import Foundation

/// SUMPRODUCT evaluates bounded arrays before aggregating them. Arithmetic broadcasts
/// scalars; separate arguments must have identical dimensions. Comparisons stay logical
/// until arithmetic coerces them, so SUMPRODUCT(A1:A3="x") does not count booleans.
enum SheetProduct {
  private struct Element {
    var value: SheetValue
    var logical = false
    func numeric(_ budget: SheetFormulaBudget) -> SheetValue {
      switch value {
      case .blank: return .number(0)
      case .text(let text):
        guard budget.consume(max(1, text.utf8.count)) else { return .error("#CALC!") }
        return SheetFormula.number(text).map(SheetValue.number) ?? .error("#VALUE!")
      default: return value
      }
    }
  }

  private struct ArrayValue {
    var rows: Int
    var columns: Int
    var elements: [Element]
    var scalar: Bool { rows == 1 && columns == 1 }
    init(_ value: SheetValue) {
      rows = 1
      columns = 1
      elements = [Element(value: value)]
    }
    init(rows: Int, columns: Int, elements: [Element]) {
      self.rows = rows
      self.columns = columns
      self.elements = elements
    }
  }

  static func evaluate(
    _ arguments: [SheetExpression], budget: SheetFormulaBudget,
    _ read: (SheetCell) throws -> SheetValue
  ) rethrows -> SheetValue {
    var arrays: [ArrayValue] = []
    for argument in arguments {
      let array = try expand(argument, budget: budget, read)
      // An expression failure precedes a subsequent dimension mismatch.
      if array.scalar, case .error = array.elements[0].value { return array.elements[0].value }
      if let first = arrays.first,
        first.rows != array.rows || first.columns != array.columns
      {
        return .error("#VALUE!")
      }
      arrays.append(array)
    }
    guard let first = arrays.first else { return .error("#VALUE!") }
    var total = Decimal(0)
    for index in first.elements.indices {
      var product = Decimal(1)
      for array in arrays {
        guard budget.consume() else { return .error("#CALC!") }
        let element = array.elements[index]
        if case .error = element.value { return element.value }
        let number: Decimal
        if case .number(let value) = element.value, !element.logical {
          number = value
        } else {
          number = 0
        }
        guard let next = try? Numbers.binary(product, number, op: "*") else {
          return .error("#NUM!")
        }
        product = next
      }
      guard let next = try? Numbers.binary(total, product, op: "+") else { return .error("#NUM!") }
      total = next
    }
    return .number(total)
  }

  private static func expand(
    _ expression: SheetExpression, budget: SheetFormulaBudget,
    _ read: (SheetCell) throws -> SheetValue
  ) rethrows -> ArrayValue {
    guard budget.consume() else { return ArrayValue(.error("#CALC!")) }
    switch expression {
    case .range(let first, let last):
      let rows = last.row - first.row + 1
      let columns = last.column - first.column + 1
      guard budget.consume(rows, multiplier: columns) else { return ArrayValue(.error("#CALC!")) }
      var elements: [Element] = []
      for row in first.row...last.row {
        for column in first.column...last.column {
          elements.append(
            Element(value: try read(.init(sheet: first.sheet, column: column, row: row))))
        }
      }
      return ArrayValue(rows: rows, columns: columns, elements: elements)
    case .negate(let inner), .percent(let inner):
      var array = try expand(inner, budget: budget, read)
      guard budget.consume(array.elements.count) else { return ArrayValue(.error("#CALC!")) }
      array.elements = array.elements.map { element in
        let numeric = element.numeric(budget)
        guard case .number(let number) = numeric else { return Element(value: numeric) }
        if case .negate = expression { return Element(value: .number(-number)) }
        return Element(
          value: (try? Numbers.binary(number, 100, op: "/")).map(SheetValue.number)
            ?? .error("#NUM!"))
      }
      return array
    case .arithmetic(let op, let lhs, let rhs), .comparison(let op, let lhs, let rhs):
      let left = try expand(lhs, budget: budget, read)
      let right = try expand(rhs, budget: budget, read)
      guard
        left.scalar || right.scalar || (left.rows == right.rows && left.columns == right.columns)
      else { return ArrayValue(.error("#VALUE!")) }
      let shape = left.scalar ? right : left
      guard budget.consume(shape.elements.count) else { return ArrayValue(.error("#CALC!")) }
      var elements: [Element] = []
      for index in shape.elements.indices {
        let a = left.elements[left.scalar ? 0 : index]
        let b = right.elements[right.scalar ? 0 : index]
        if case .error = a.value {
          elements.append(a)
          continue
        }
        if case .error = b.value {
          elements.append(b)
          continue
        }
        if case .comparison = expression {
          // Bound text collation as well as the number of array entries.
          func cost(_ value: SheetValue) -> Int {
            if case .text(let text) = value { return max(1, text.utf8.count) }
            return 1
          }
          guard budget.consume(cost(a.value)), budget.consume(cost(b.value)) else {
            return ArrayValue(.error("#CALC!"))
          }
          let order = SheetValue.order(a.value, b.value)
          let matches: Bool
          switch op {
          case "=": matches = order == 0
          case "<>": matches = order != 0
          case "<": matches = order < 0
          case "<=": matches = order <= 0
          case ">": matches = order > 0
          default: matches = order >= 0
          }
          elements.append(Element(value: .number(matches ? 1 : 0), logical: true))
        } else {
          let x = a.numeric(budget)
          let y = b.numeric(budget)
          guard case .number(let first) = x else {
            elements.append(Element(value: x))
            continue
          }
          guard case .number(let second) = y else {
            elements.append(Element(value: y))
            continue
          }
          if op == "/", second == 0 {
            elements.append(Element(value: .error("#DIV/0!")))
          } else {
            elements.append(
              Element(
                value: (try? Numbers.binary(first, second, op: op)).map(SheetValue.number)
                  ?? .error("#NUM!")))
          }
        }
      }
      return ArrayValue(rows: shape.rows, columns: shape.columns, elements: elements)
    default:
      // Nested ordinary functions retain their scalar semantics. Array-valued
      // function calls are refused by the parser instead of silently scalarized.
      return ArrayValue(try expression.evaluate(budget: budget, read))
    }
  }
}
