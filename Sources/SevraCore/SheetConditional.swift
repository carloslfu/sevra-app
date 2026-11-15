import Foundation

/// Bounded conditional sums. The parser normalizes SUMIF's top-left sum reference so
/// dependency discovery and evaluation see exactly the same cells, including blank tails.
enum SheetConditional {
  static func bounds(_ expression: SheetExpression) -> (SheetCell, SheetCell)? {
    switch expression {
    case .cell(let cell): return (cell, cell)
    case .range(let first, let last): return (first, last)
    default: return nil
    }
  }

  static func arguments(_ name: String, _ input: [SheetExpression]) throws -> [SheetExpression] {
    var result = input
    if name == "SUMIF" {
      guard (2...3).contains(input.count), let (first, last) = bounds(input[0]),
        let (sum, _) = bounds(input.count == 3 ? input[2] : input[0])
      else {
        throw SheetFormulaGap(uses: "SUMIF without a range, criterion and optional sum range")
      }
      let end = SheetCell(
        sheet: sum.sheet, column: sum.column + last.column - first.column,
        row: sum.row + last.row - first.row)
      guard end.column < 500, end.row <= 1_048_576 else {
        throw SheetFormulaGap(uses: "a conditional sum past the worksheet bounds")
      }
      result = [input[0], input[1], .range(sum, end)]
    } else {
      guard input.count >= 3, input.count <= 255, input.count % 2 == 1 else {
        throw SheetFormulaGap(uses: "SUMIFS without a sum range and range/criterion pairs")
      }
      for index in [0] + Array(stride(from: 1, to: input.count, by: 2)) {
        guard bounds(input[index]) != nil else {
          throw SheetFormulaGap(uses: "SUMIFS with a non-range argument")
        }
      }
    }
    return result
  }

  static func evaluate(
    _ name: String, _ arguments: [SheetExpression], budget: SheetFormulaBudget,
    _ read: (SheetCell) throws -> SheetValue
  ) rethrows -> SheetValue {
    let sum = bounds(arguments[name == "SUMIF" ? 2 : 0])!
    let pairs = name == "SUMIF" ? [0] : Array(stride(from: 1, to: arguments.count, by: 2))
    var criteria: [(SheetCell, Criterion)] = []
    for index in pairs {
      let range = bounds(arguments[index])!
      guard range.1.row - range.0.row == sum.1.row - sum.0.row,
        range.1.column - range.0.column == sum.1.column - sum.0.column
      else { return .error("#VALUE!") }
      let value = try arguments[index + 1].evaluate(budget: budget, read)
      if case .error = value { return value }
      guard let criterion = Criterion(value) else { return .error("#VALUE!") }
      criteria.append((range.0, criterion))
    }
    var total = Decimal(0)
    for row in 0...(sum.1.row - sum.0.row) {
      for column in 0...(sum.1.column - sum.0.column) {
        var matches = true
        for (first, criterion) in criteria {
          let cell = SheetCell(
            sheet: first.sheet, column: first.column + column, row: first.row + row)
          let candidate = try read(cell)
          // The native evaluator must remain bounded even for hostile long text
          // and wildcard criteria. A visible calculation error never fabricates a sum.
          let bytes: Int
          if case .text(let text) = candidate { bytes = max(1, text.utf8.count) } else { bytes = 1 }
          let cost = max(1, criterion.pattern?.count ?? 1)
          guard budget.consume(bytes, multiplier: cost) else { return .error("#CALC!") }
          if !criterion.matches(candidate) {
            matches = false
            break
          }
        }
        if !matches { continue }
        switch try read(
          .init(sheet: sum.0.sheet, column: sum.0.column + column, row: sum.0.row + row))
        {
        case .number(let value):
          guard let next = try? Numbers.binary(total, value, op: "+") else {
            return .error("#NUM!")
          }
          total = next
        case .error(let error): return .error(error)
        default: break
        }
      }
    }
    return .number(total)
  }

  struct Criterion {
    let op: String
    let value: SheetValue
    let pattern: [Pattern]?

    init?(_ source: SheetValue) {
      if case .text(var text) = source {
        guard text.utf16.count <= 255 else { return nil }
        var comparison = "="
        for prefix in ["<=", ">=", "<>", "=", "<", ">"] where text.hasPrefix(prefix) {
          comparison = prefix
          text = String(text.dropFirst(prefix.count))
          break
        }
        op = comparison
        if let number = SheetFormula.number(text) {
          value = .number(number)
          pattern = nil
        } else {
          value = .text(text)
          pattern =
            (comparison == "=" || comparison == "<>")
              && text.contains(where: { "*?~".contains($0) })
            ? Self.pattern(text) : nil
        }
      } else {
        op = "="
        value = source == .blank ? .number(0) : source
        pattern = nil
      }
    }

    func matches(_ candidate: SheetValue) -> Bool {
      let order: Int
      switch value {
      case .number(let expected):
        let actual: Decimal?
        switch candidate {
        case .blank: return op == "<>"
        case .number(let number): actual = number
        case .text(let text):
          if op == "<>" { return true }
          guard op == "=" else { return false }
          actual = SheetFormula.number(text)
        default: actual = nil
        }
        guard let actual else { return op == "<>" }
        order = actual == expected ? 0 : actual < expected ? -1 : 1
      case .text(let expected):
        let actual: String
        switch candidate {
        case .text(let text): actual = text
        case .blank:
          return op == "=" ? expected.isEmpty : op == "<>" && !expected.isEmpty
        case .error(let error):
          guard expected.hasPrefix("#"), pattern == nil else { return op == "<>" }
          actual = error
        default: return op == "<>"
        }
        if let pattern {
          let match = Self.matches(pattern, actual)
          return op == "<>" ? !match : match
        }
        order = SheetValue.order(.text(actual), .text(expected))
      default: return false
      }
      switch op {
      case "=": return order == 0
      case "<>": return order != 0
      case "<": return order < 0
      case "<=": return order <= 0
      case ">": return order > 0
      default: return order >= 0
      }
    }

    enum Pattern: Equatable {
      case literal(Character)
      case one
      case many
    }
    static func pattern(_ text: String) -> [Pattern] {
      let characters = Array(text.lowercased())
      var tokens: [Pattern] = []
      var index = 0
      while index < characters.count {
        let character = characters[index]
        if character == "~", index + 1 < characters.count,
          "*?~".contains(characters[index + 1])
        {
          index += 1
          tokens.append(.literal(characters[index]))
        } else if character == "*" {
          if tokens.last != .many { tokens.append(.many) }
        } else if character == "?" {
          tokens.append(.one)
        } else {
          tokens.append(.literal(character))
        }
        index += 1
      }
      return tokens
    }

    /// Iterative automaton: no regular-expression backtracking or recursive wildcard expansion.
    static func matches(_ pattern: [Pattern], _ text: String) -> Bool {
      var states = Array(repeating: false, count: pattern.count + 1)
      states[0] = true
      for index in pattern.indices where pattern[index] == .many {
        states[index + 1] = states[index]
      }
      for character in text.lowercased() {
        var next = Array(repeating: false, count: states.count)
        for index in pattern.indices {
          switch pattern[index] {
          case .many: next[index + 1] = next[index] || states[index + 1]
          case .one: next[index + 1] = states[index]
          case .literal(let literal): next[index + 1] = states[index] && literal == character
          }
        }
        states = next
      }
      return states[pattern.count]
    }
  }
}
