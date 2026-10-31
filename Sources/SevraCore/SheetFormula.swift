import Foundation

/// A cell a worksheet formula names. Rows are one-based, as in A1.
struct SheetCell: Hashable, Sendable {
  var sheet: String?
  var column: Int
  var row: Int
  var name: String { XLSX.cellName(column: column, row: row) }
}

indirect enum SheetExpression: Sendable {
  case number(Decimal)
  case cell(SheetCell)
  case range(SheetCell, SheetCell)
  case negate(SheetExpression)
  case percent(SheetExpression)
  case arithmetic(String, SheetExpression, SheetExpression)
  case comparison(String, SheetExpression, SheetExpression)
  case call(String, [SheetExpression])
}

enum SheetValue: Equatable, Sendable {
  case blank
  case number(Decimal)
  case text(String)
  case error(String)
}

/// Why a formula keeps its saved value, in words shown to people.
struct SheetFormulaGap: Error {
  let reason: String
  init(uses what: String) { reason = "Uses \(what), which Sevra does not calculate." }
  init(reason: String) { self.reason = reason }
}

/// The declared Excel subset: numbers, percent, + - * /, cell and range references with
/// an optional sheet, and SUM, AVERAGE, MIN, MAX, COUNT, ROUND and IF. Anything else keeps
/// its saved value. This is not an Excel engine and makes no claim to match one.
enum SheetFormula {
  static let aggregates: Set<String> = ["SUM", "AVERAGE", "MIN", "MAX", "COUNT"]
  static let rangeLimit = 10_000

  static func parse(_ text: String) throws -> SheetExpression {
    try require(text.utf8.count <= 8192, "formula_limit", "Formula is too long.")
    var parser = SheetFormulaParser(tokens: try SheetFormulaToken.scan(text))
    return try parser.formula()
  }

  /// A shared formula's text for a cell the given distance from its first cell. Excel
  /// stores it once. Relative parts move, absolute parts stay, and text is left alone.
  static func shifted(_ text: String, columns: Int, rows: Int) -> String {
    let input = Array(text)
    var output = ""
    var index = 0
    while index < input.count {
      let character = input[index]
      if character == "\"" || character == "'" {
        // Doubled quotes stay inside the same literal.
        var end = index + 1
        while end < input.count {
          if input[end] == character {
            if end + 1 < input.count, input[end + 1] == character {
              end += 2
              continue
            }
            break
          }
          end += 1
        }
        let stop = min(end + 1, input.count)
        output += String(input[index..<stop])
        index = stop
      } else if SheetFormulaToken.isWord(character) {
        var end = index
        while end < input.count, SheetFormulaToken.isWord(input[end]) { end += 1 }
        let word = String(input[index..<end])
        let next = end < input.count ? input[end] : " "
        if next != "(", next != "!", let parts = SheetFormulaToken.address(word) {
          output += parts.moved(columns: columns, rows: rows)
        } else {
          output += word
        }
        index = end
      } else {
        output.append(character)
        index += 1
      }
    }
    return output
  }

  /// Excel keeps 15 significant digits, so a recalculated cell does too.
  static func text(_ number: Decimal) -> String {
    guard number != 0 else { return "0" }
    let size = Int(floor(log10(abs(NSDecimalNumber(decimal: number).doubleValue))))
    var input = number
    var output = Decimal()
    NSDecimalRound(&output, &input, max(-127, min(127, 14 - size)), .plain)
    return Numbers.string(output)
  }

  static func text(_ value: SheetValue) -> String {
    switch value {
    case .blank: return "0"
    case .number(let number): return text(number)
    case .text(let text): return text
    case .error(let code): return code
    }
  }

  /// A number as a spreadsheet saves it, with an exponent when it is very large or very small.
  static func number(_ text: String) -> Decimal? {
    if let plain = try? Numbers.decimal(text) { return plain }
    guard
      text.range(
        of: "^[+-]?(?:[0-9]+(?:\\.[0-9]*)?|\\.[0-9]+)[eE][+-]?[0-9]+\\z", options: .regularExpression)
        != nil,
      let number = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")), !number.isNaN
    else { return nil }
    return number
  }

  /// Binary and decimal arithmetic can differ in the last places of a long chain.
  static func same(_ value: SheetValue, as saved: String) -> Bool {
    guard case .number(let number) = value else { return text(value) == saved }
    guard let other = Self.number(saved) else { return false }
    let gap = abs(number - other)
    return gap <= max(abs(number), abs(other)) * Decimal(string: "0.00000000000005")!
  }
}

extension SheetValue {
  /// Spreadsheets sort numbers before text and ignore case in text. A blank reads as the other
  /// side's empty value, so it equals zero and empty text alike.
  static func order(_ left: SheetValue, _ right: SheetValue) -> Int {
    switch (left, right) {
    case (.blank, .blank): return 0
    case (.blank, .number(let number)): return order(.number(0), .number(number))
    case (.number(let number), .blank): return order(.number(number), .number(0))
    case (.blank, .text(let text)): return order(.text(""), .text(text))
    case (.text(let text), .blank): return order(.text(text), .text(""))
    case (.number(let a), .number(let b)): return a == b ? 0 : a < b ? -1 : 1
    case (.number, .text): return -1
    case (.text, .number): return 1
    case (.text(let a), .text(let b)):
      switch a.caseInsensitiveCompare(b) {
      case .orderedSame: return 0
      case .orderedAscending: return -1
      case .orderedDescending: return 1
      }
    default: return 0
    }
  }
}

struct SheetAddress {
  var column: Int
  var row: Int
  var absoluteColumn: Bool
  var absoluteRow: Bool
  func moved(columns: Int, rows: Int) -> String {
    let x = absoluteColumn ? column : column + columns
    let y = absoluteRow ? row : row + rows
    guard x >= 0, x < 500, y >= 1, y <= 1_048_576 else { return "#REF!" }
    let name = XLSX.cellName(column: x, row: y)
    let letters = name.prefix { $0.isLetter }
    return (absoluteColumn ? "$" : "") + letters + (absoluteRow ? "$" : "") + name.dropFirst(letters.count)
  }
}

enum SheetFormulaToken: Equatable {
  case number(Decimal)
  case cell(SheetCellToken)
  case function(String)
  case symbol(String)
  case end

  struct SheetCellToken: Equatable {
    var sheet: String?
    var column: Int
    var row: Int
  }

  static func isWord(_ c: Character) -> Bool {
    c.isLetter || c.isNumber || c == "_" || c == "." || c == "$"
  }

  static func address(_ word: String) -> SheetAddress? {
    let characters = Array(word.uppercased())
    var index = 0
    let absoluteColumn = index < characters.count && characters[index] == "$"
    if absoluteColumn { index += 1 }
    let lettersStart = index
    var column = 0
    while index < characters.count, let value = characters[index].asciiValue, (65...90).contains(value) {
      column = column * 26 + Int(value) - 64
      index += 1
      if index - lettersStart > 3 { return nil }
    }
    guard index > lettersStart else { return nil }
    let absoluteRow = index < characters.count && characters[index] == "$"
    if absoluteRow { index += 1 }
    let digits = String(characters[index...])
    guard !digits.isEmpty, digits.allSatisfy({ $0.isASCII && $0.isNumber }), digits.count <= 7,
      let row = Int(digits), (1...1_048_576).contains(row), column <= 500
    else { return nil }
    return SheetAddress(
      column: column - 1, row: row, absoluteColumn: absoluteColumn, absoluteRow: absoluteRow)
  }

  static func scan(_ text: String) throws -> [SheetFormulaToken] {
    let input = Array(text.hasPrefix("=") ? String(text.dropFirst()) : text)
    var output: [SheetFormulaToken] = []
    var index = 0

    func word(from start: Int) -> (String, Int) {
      var end = start
      while end < input.count, isWord(input[end]) { end += 1 }
      return (String(input[start..<end]), end)
    }
    func cell(_ name: String, sheet: String?) throws -> SheetFormulaToken {
      guard let address = address(name) else {
        throw SheetFormulaGap(uses: "whole-column or whole-row references")
      }
      return .cell(.init(sheet: sheet, column: address.column, row: address.row))
    }

    while index < input.count {
      let character = input[index]
      if character.isWhitespace {
        index += 1
      } else if character == "." || (character.isASCII && character.isNumber) {
        var end = index
        while end < input.count, input[end] == "." || (input[end].isASCII && input[end].isNumber) {
          end += 1
        }
        if end < input.count, input[end] == "e" || input[end] == "E" {
          var exponent = end + 1
          if exponent < input.count, input[exponent] == "+" || input[exponent] == "-" {
            exponent += 1
          }
          let digits = exponent
          while exponent < input.count, input[exponent].isASCII, input[exponent].isNumber {
            exponent += 1
          }
          if exponent > digits { end = exponent }
        }
        guard
          let number = Decimal(
            string: String(input[index..<end]), locale: Locale(identifier: "en_US_POSIX"))
        else { throw SheetFormulaGap(uses: "a number it cannot read") }
        output.append(.number(number))
        index = end
      } else if character == "\"" {
        throw SheetFormulaGap(uses: "text values")
      } else if character == "'" {
        var name = ""
        var end = index + 1
        while end < input.count {
          if input[end] == "'" {
            guard end + 1 < input.count, input[end + 1] == "'" else { break }
            end += 1
          }
          name.append(input[end])
          end += 1
        }
        guard !name.hasPrefix("[") else { throw SheetFormulaGap(uses: "a reference to another file") }
        guard end + 1 < input.count, input[end + 1] == "!" else {
          throw SheetFormulaGap(uses: "a sheet reference it cannot read")
        }
        let (reference, stop) = word(from: end + 2)
        output.append(try cell(reference, sheet: name))
        index = stop
      } else if isWord(character) {
        let (name, end) = word(from: index)
        let next: Character? = end < input.count ? input[end] : nil
        if next == "!" {
          let (reference, stop) = word(from: end + 1)
          output.append(try cell(reference, sheet: name))
          index = stop
        } else if next == "(" {
          // Name an unsupported function before anything inside it.
          let function = name.uppercased().replacingOccurrences(of: "_XLFN.", with: "")
          guard SheetFormula.aggregates.contains(function) || ["ROUND", "IF"].contains(function)
          else { throw SheetFormulaGap(uses: function) }
          output.append(.function(function))
          index = end
        } else if address(name) != nil {
          output.append(try cell(name, sheet: nil))
          index = end
        } else if next == ":" {
          throw SheetFormulaGap(uses: "whole-column or whole-row references")
        } else if ["TRUE", "FALSE"].contains(name.uppercased()) {
          throw SheetFormulaGap(uses: "TRUE and FALSE values")
        } else {
          throw SheetFormulaGap(uses: "the name \(name)")
        }
      } else if character == "<" || character == ">" {
        let next: Character? = index + 1 < input.count ? input[index + 1] : nil
        if next == "=" || (character == "<" && next == ">") {
          output.append(.symbol(String([character, next!])))
          index += 2
        } else {
          output.append(.symbol(String(character)))
          index += 1
        }
      } else if "+-*/%(),:=".contains(character) {
        output.append(.symbol(String(character)))
        index += 1
      } else if character == "[" {
        throw SheetFormulaGap(uses: "a reference to another file")
      } else if character == "#" {
        throw SheetFormulaGap(reason: "Reads a cell Excel reports as missing.")
      } else if character == "^" {
        throw SheetFormulaGap(uses: "powers")
      } else if character == "&" {
        throw SheetFormulaGap(uses: "joined text")
      } else {
        throw SheetFormulaGap(uses: "the symbol \(character)")
      }
      if output.count > 1024 { throw SheetFormulaGap(reason: "The formula is too long to calculate.") }
    }
    return output + [.end]
  }
}

struct SheetFormulaParser {
  var tokens: [SheetFormulaToken]
  var position = 0
  /// One formula may not read more cells than one range may hold.
  var cellsRead = 0

  mutating func formula() throws -> SheetExpression {
    let result = try comparison(0)
    guard tokens[position] == .end else {
      throw SheetFormulaGap(uses: "syntax it cannot read")
    }
    try check(result)
    return result
  }

  private func check(_ node: SheetExpression, condition: Bool = false) throws {
    switch node {
    case .number, .cell: break
    case .range(let first, let last):
      throw SheetFormulaGap(uses: "the range \(first.name):\(last.name) outside a function")
    case .negate(let inner), .percent(let inner): try check(inner)
    case .arithmetic(_, let lhs, let rhs):
      try check(lhs)
      try check(rhs)
    case .comparison(_, let lhs, let rhs):
      guard condition else { throw SheetFormulaGap(uses: "TRUE and FALSE values") }
      try check(lhs)
      try check(rhs)
    case .call(let name, let arguments):
      for (index, argument) in arguments.enumerated() {
        if case .range = argument, SheetFormula.aggregates.contains(name) { continue }
        try check(argument, condition: name == "IF" && index == 0)
      }
    }
  }

  private mutating func take(_ symbols: Set<String>) -> String? {
    if case .symbol(let symbol) = tokens[position], symbols.contains(symbol) {
      position += 1
      return symbol
    }
    return nil
  }

  private mutating func comparison(_ depth: Int) throws -> SheetExpression {
    var node = try sum(depth)
    while let op = take(["=", "<>", "<", ">", "<=", ">="]) {
      node = .comparison(op, node, try sum(depth))
    }
    return node
  }

  private mutating func sum(_ depth: Int) throws -> SheetExpression {
    var node = try product(depth)
    while let op = take(["+", "-"]) { node = .arithmetic(op, node, try product(depth)) }
    return node
  }

  private mutating func product(_ depth: Int) throws -> SheetExpression {
    var node = try unary(depth)
    while let op = take(["*", "/"]) { node = .arithmetic(op, node, try unary(depth)) }
    return node
  }

  private mutating func unary(_ depth: Int) throws -> SheetExpression {
    guard depth < 32 else { throw SheetFormulaGap(reason: "The formula is nested too deeply.") }
    if take(["-"]) != nil { return .negate(try unary(depth + 1)) }
    if take(["+"]) != nil { return try unary(depth + 1) }
    var node = try primary(depth)
    while take(["%"]) != nil { node = .percent(node) }
    return node
  }

  private mutating func primary(_ depth: Int) throws -> SheetExpression {
    let token = tokens[position]
    position += 1
    switch token {
    case .number(let number): return .number(number)
    case .cell(let first):
      let start = SheetCell(sheet: first.sheet, column: first.column, row: first.row)
      guard take([":"]) != nil else { return .cell(start) }
      guard case .cell(let last) = tokens[position], last.sheet == nil || last.sheet == first.sheet
      else { throw SheetFormulaGap(uses: "a range it cannot read") }
      position += 1
      let end = SheetCell(sheet: first.sheet, column: last.column, row: last.row)
      guard end.column >= start.column, end.row >= start.row else {
        throw SheetFormulaGap(uses: "a range it cannot read")
      }
      cellsRead += (end.column - start.column + 1) * (end.row - start.row + 1)
      guard cellsRead <= SheetFormula.rangeLimit else {
        throw SheetFormulaGap(uses: "more than \(SheetFormula.rangeLimit.formatted()) cells")
      }
      return .range(start, end)
    case .function(let name):
      guard take(["("]) != nil else { throw SheetFormulaGap(uses: "syntax it cannot read") }
      var arguments: [SheetExpression] = []
      repeat { arguments.append(try comparison(depth + 1)) } while take([","]) != nil
      guard take([")"]) != nil else { throw SheetFormulaGap(uses: "syntax it cannot read") }
      if name == "IF", arguments.count != 3 { throw SheetFormulaGap(uses: "IF without both results") }
      if name == "ROUND", arguments.count != 2 { throw SheetFormulaGap(uses: "syntax it cannot read") }
      return .call(name, arguments)
    case .symbol("("):
      let inner = try comparison(depth + 1)
      guard take([")"]) != nil else { throw SheetFormulaGap(uses: "syntax it cannot read") }
      return inner
    default:
      throw SheetFormulaGap(uses: "syntax it cannot read")
    }
  }
}

extension SheetExpression {
  /// Blank counts as zero in arithmetic. Ranges and cell references passed to an aggregate
  /// skip text and blanks, as Excel does. The first error wins and IF reads one branch.
  func evaluate(_ read: (SheetCell) throws -> SheetValue) rethrows -> SheetValue {
    func numeric(_ node: SheetExpression) throws -> SheetValue {
      switch try node.evaluate(read) {
      case .blank: return .number(0)
      case .text: return .error("#VALUE!")
      case let value: return value
      }
    }
    switch self {
    case .number(let number): return .number(number)
    case .cell(let cell): return try read(cell)
    case .range: return .error("#VALUE!")
    case .negate(let node):
      let value = try numeric(node)
      guard case .number(let number) = value else { return value }
      return .number(-number)
    case .percent(let node):
      let value = try numeric(node)
      guard case .number(let number) = value else { return value }
      return .number(number / 100)
    case .arithmetic(let op, let lhs, let rhs):
      let left = try numeric(lhs)
      guard case .number(let x) = left else { return left }
      let right = try numeric(rhs)
      guard case .number(let y) = right else { return right }
      if op == "/", y == 0 { return .error("#DIV/0!") }
      guard let result = try? Numbers.binary(x, y, op: op) else { return .error("#NUM!") }
      return .number(result)
    case .comparison(let op, let lhs, let rhs):
      let left = try lhs.evaluate(read)
      if case .error = left { return left }
      let right = try rhs.evaluate(read)
      if case .error = right { return right }
      let order = SheetValue.order(left, right)
      switch op {
      case "=": return .number(order == 0 ? 1 : 0)
      case "<>": return .number(order != 0 ? 1 : 0)
      case "<": return .number(order < 0 ? 1 : 0)
      case "<=": return .number(order <= 0 ? 1 : 0)
      case ">": return .number(order > 0 ? 1 : 0)
      default: return .number(order >= 0 ? 1 : 0)
      }
    case .call("IF", let arguments):
      let test = try numeric(arguments[0])
      guard case .number(let number) = test else { return test }
      return try (number != 0 ? arguments[1] : arguments[2]).evaluate(read)
    case .call("ROUND", let arguments):
      let value = try numeric(arguments[0])
      guard case .number(var number) = value else { return value }
      let digits = try numeric(arguments[1])
      guard case .number(let places) = digits else { return digits }
      let whole = NSDecimalNumber(decimal: places).intValue
      guard Decimal(whole) == places, (-28...28).contains(whole) else { return .error("#NUM!") }
      var output = Decimal()
      NSDecimalRound(&output, &number, whole, .plain)
      return .number(output)
    case .call(let name, let arguments):
      var numbers: [Decimal] = []
      for argument in arguments {
        var cells: [SheetCell] = []
        switch argument {
        case .cell(let cell): cells = [cell]
        case .range(let first, let last):
          for row in first.row...last.row {
            for column in first.column...last.column {
              cells.append(.init(sheet: first.sheet, column: column, row: row))
            }
          }
        default:
          switch try numeric(argument) {
          case .number(let number): numbers.append(number)
          case let failure: return failure
          }
        }
        for cell in cells {
          switch try read(cell) {
          case .number(let number): numbers.append(number)
          case .error(let code): if name != "COUNT" { return .error(code) }
          default: break
          }
        }
      }
      switch name {
      case "COUNT": return .number(Decimal(numbers.count))
      case "MIN": return .number(numbers.min() ?? 0)
      case "MAX": return .number(numbers.max() ?? 0)
      default:
        var total = Decimal(0)
        for number in numbers {
          guard let next = try? Numbers.binary(total, number, op: "+") else { return .error("#NUM!") }
          total = next
        }
        if name == "SUM" { return .number(total) }
        guard !numbers.isEmpty else { return .error("#DIV/0!") }
        return .number(total / Decimal(numbers.count))
      }
    }
  }

  /// Every cell the formula could read, for dependency order and bounds.
  var references: [SheetCell] {
    switch self {
    case .number: return []
    case .cell(let cell): return [cell]
    case .range(let first, let last):
      var cells: [SheetCell] = []
      for row in first.row...last.row {
        for column in first.column...last.column {
          cells.append(.init(sheet: first.sheet, column: column, row: row))
        }
      }
      return cells
    case .negate(let node), .percent(let node): return node.references
    case .arithmetic(_, let lhs, let rhs), .comparison(_, let lhs, let rhs):
      return lhs.references + rhs.references
    case .call(_, let arguments): return arguments.flatMap(\.references)
    }
  }
}
