import Darwin
import Foundation

public enum Numbers {
  public static func decimal(_ text: String) throws -> Decimal {
    try require(
      text.range(of: "^[+-]?(?:[0-9]+(?:\\.[0-9]*)?|\\.[0-9]+)\\z", options: .regularExpression)
        != nil,
      "number",
      "Expected an unambiguous decimal number, received ‘\(text)’. Use a period for decimals.")
    let digits = text.filter(\.isNumber).drop(while: { $0 == "0" }).reversed().drop(while: {
      $0 == "0"
    })
    try require(
      digits.count <= 38, "precision", "A decimal may have at most 38 significant digits.")
    guard let d = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")), !d.isNaN else {
      throw SevraError("number", "Number is out of range.")
    }
    return d
  }
  public static func string(_ number: Decimal) -> String {
    NSDecimalNumber(decimal: number).stringValue
  }
  public static func calculate(
    _ expression: String, values: [String: Value] = [:],
    resolve: ((String) throws -> Decimal)? = nil
  ) throws -> String {
    var parser = try Formula(expression)
    let tree = try parser.parse()
    return string(try tree.evaluate(values: values, resolve: resolve))
  }
  static func binary(_ lhs: Decimal, _ rhs: Decimal, op: String) throws -> Decimal {
    if ["=", "<>", "<", ">", "<=", ">="].contains(op) {
      let result: Bool
      switch op {
      case "=": result = lhs == rhs
      case "<>": result = lhs != rhs
      case "<": result = lhs < rhs
      case ">": result = lhs > rhs
      case "<=": result = lhs <= rhs
      default: result = lhs >= rhs
      }
      return result ? 1 : 0
    }
    var a = lhs
    var b = rhs
    var out = Decimal()
    let error: Decimal.CalculationError
    switch op {
    case "+": error = NSDecimalAdd(&out, &a, &b, .plain)
    case "-": error = NSDecimalSubtract(&out, &a, &b, .plain)
    case "*": error = NSDecimalMultiply(&out, &a, &b, .plain)
    default:
      try require(b != 0, "division_by_zero", "Cannot divide by zero.")
      error = NSDecimalDivide(&out, &a, &b, .plain)
    }
    try require(
      error == .noError || error == .lossOfPrecision, "number",
      "Calculation exceeded decimal range.")
    return out
  }
}
indirect enum Expression {
  case number(Decimal)
  case name(String)
  case range(String, String)
  case negate(Expression)
  case binary(String, Expression, Expression)
  case call(String, [Expression])
  /// A formula can read a cell or column whose formula reads the next, each one up to the depth
  /// limit below. Those multiply, so only the thread's own stack bounds them, and a worker's is
  /// 512 KiB. Leave room for the parsing and storage reads that one more level needs.
  private static var stackHasRoom: Bool {
    let thread = pthread_self()
    var here = 0
    let position = withUnsafePointer(to: &here) { UInt(bitPattern: $0) }
    let top = UInt(bitPattern: pthread_get_stackaddr_np(thread))
    return position > top - UInt(pthread_get_stacksize_np(thread)) + 256 * 1024
  }
  func evaluate(values: [String: Value], resolve: ((String) throws -> Decimal)?, depth: Int = 0)
    throws -> Decimal
  {
    try require(
      depth < 64 && Self.stackHasRoom, "formula_limit",
      "Formula evaluation exceeds its depth budget.")
    func eval(_ node: Expression) throws -> Decimal {
      try node.evaluate(values: values, resolve: resolve, depth: depth + 1)
    }
    switch self {
    case .number(let n): return n
    case .name(let name):
      if let value = values[name], value != .null, !value.text.isEmpty {
        return try Numbers.decimal(value.text)
      }
      if let resolve { return try resolve(name) }
      throw SevraError("missing_value", "No value for \(name).")
    case .range: throw SevraError("range", "Use a range inside an aggregate such as SUM.")
    case .negate(let node): return -(try eval(node))
    case .binary(let op, let a, let b): return try Numbers.binary(eval(a), eval(b), op: op)
    case .call(let name, let nodes):
      if name == "IF" {
        try require(
          nodes.count == 3, "formula", "IF takes a condition, true value and false value.")
        return try eval(nodes[0]) == 0 ? eval(nodes[2]) : eval(nodes[1])
      }
      var args: [Decimal] = []
      for node in nodes {
        if case .range(let first, let last) = node {
          let (x1, y1) = try CellReference.parse(first)
          let (x2, y2) = try CellReference.parse(last)
          try require(
            x2 >= x1 && y2 >= y1 && (x2 - x1 + 1) * (y2 - y1 + 1) <= 10_000, "range",
            "Use a forward range of at most 10,000 cells.")
          for y in y1...y2 {
            for x in x1...x2 {
              args.append(try eval(.name(Workbook.spreadsheetColumn(x) + String(y + 1))))
            }
          }
        } else {
          args.append(try eval(node))
        }
      }
      switch name {
      case "COUNT": return Decimal(args.count)
      case "SUM": return try args.reduce(0) { try Numbers.binary($0, $1, op: "+") }
      case "AVERAGE":
        try require(!args.isEmpty, "formula", "AVERAGE needs values.")
        return try Numbers.binary(
          args.reduce(0) { try Numbers.binary($0, $1, op: "+") }, Decimal(args.count), op: "/")
      case "MIN":
        guard let n = args.min() else { throw SevraError("formula", "MIN needs values.") }
        return n
      case "MAX":
        guard let n = args.max() else { throw SevraError("formula", "MAX needs values.") }
        return n
      case "ROUND":
        try require(args.count == 2, "formula", "ROUND takes a value and decimal places.")
        let places = NSDecimalNumber(decimal: args[1]).intValue
        try require(
          Decimal(places) == args[1] && (-28...28).contains(places), "rounding",
          "ROUND supports -28 to 28 places.")
        var input = args[0]
        var output = Decimal()
        NSDecimalRound(&output, &input, places, .plain)
        return output
      default: throw SevraError("formula", "Unknown function: \(name)")
      }
    }
  }
}
public enum CellReference {
  public static func parse(_ text: String) throws -> (Int, Int) {
    let cleaned = text.replacingOccurrences(of: "$", with: "").uppercased()
    let letters = cleaned.prefix(while: { $0.isLetter })
    let digits = cleaned.dropFirst(letters.count)
    try require(
      !letters.isEmpty && !digits.isEmpty && digits.allSatisfy(\.isNumber), "cell",
      "Use a cell address such as A1.")
    var column = 0
    for char in letters.unicodeScalars {
      try require(
        (65...90).contains(Int(char.value)) && column < 500, "cell",
        "Column is outside the 500-column limit.")
      column = column * 26 + Int(char.value) - 64
    }
    guard let row = Int(digits), row > 0, row <= 100_000, column > 0, column <= 500 else {
      throw SevraError("cell", "Cell is outside the supported table bounds.")
    }
    return (column - 1, row - 1)
  }
}
struct Formula {
  enum Token: Equatable {
    case number(String)
    case name(String)
    case symbol(String)
    case end
  }
  var tokens: [Token] = [], position = 0
  init(_ expression: String) throws {
    try require(expression.utf8.count <= 4096, "formula_limit", "Formula is too long.")
    let input = expression.hasPrefix("=") ? String(expression.dropFirst()) : expression
    let chars = Array(input)
    var i = 0
    while i < chars.count {
      let c = chars[i]
      if c.isWhitespace {
        i += 1
        continue
      }
      if c.isNumber || c == "." {
        let start = i
        while i < chars.count && (chars[i].isNumber || chars[i] == ".") { i += 1 }
        tokens.append(.number(String(chars[start..<i])))
      } else if c.isLetter || c == "_" || c == "$" {
        let start = i
        while i < chars.count
          && (chars[i].isLetter || chars[i].isNumber || chars[i] == "_" || chars[i] == "$")
        { i += 1 }
        tokens.append(.name(String(chars[start..<i])))
      } else if c == "[" {
        i += 1
        let start = i
        while i < chars.count && chars[i] != "]" { i += 1 }
        try require(i < chars.count, "formula", "Unclosed column reference.")
        tokens.append(.name(String(chars[start..<i])))
        i += 1
      } else {
        try require("+-*/(),:<>= ".contains(c), "formula", "Unsupported formula character: \(c)")
        var op = String(c)
        i += 1
        if i < chars.count && ["<", ">"].contains(op)
          && (chars[i] == "=" || op == "<" && chars[i] == ">")
        {
          op.append(chars[i])
          i += 1
        }
        tokens.append(.symbol(op))
      }
    }
    try require(tokens.count <= 256, "formula_limit", "Formula has too many operations.")
    tokens.append(.end)
  }
  mutating func parse() throws -> Expression {
    let result = try expression()
    try require(tokens[position] == .end, "formula", "Unexpected formula suffix.")
    return result
  }
  mutating func expression(_ depth: Int = 0) throws -> Expression {
    try require(depth < 32, "formula_limit", "Formula nesting exceeds 32 levels.")
    var node = try sum(depth + 1)
    while case .symbol(let op) = tokens[position], ["=", "<>", "<", ">", "<=", ">="].contains(op) {
      position += 1
      node = .binary(op, node, try sum(depth + 1))
    }
    return node
  }
  mutating func sum(_ depth: Int) throws -> Expression {
    var node = try term(depth)
    while case .symbol(let op) = tokens[position], ["+", "-"].contains(op) {
      position += 1
      node = .binary(op, node, try term(depth))
    }
    return node
  }
  mutating func term(_ depth: Int) throws -> Expression {
    var node = try atom(depth)
    while case .symbol(let op) = tokens[position], ["*", "/"].contains(op) {
      position += 1
      node = .binary(op, node, try atom(depth))
    }
    return node
  }
  mutating func atom(_ depth: Int) throws -> Expression {
    try require(depth < 32, "formula_limit", "Formula nesting exceeds 32 levels.")
    let token = tokens[position]
    position += 1
    switch token {
    case .number(let n): return .number(try Numbers.decimal(n))
    case .symbol("-"): return .negate(try atom(depth + 1))
    case .symbol("+"): return try atom(depth + 1)
    case .symbol("("):
      let result = try expression(depth + 1)
      try require(tokens[position] == .symbol(")"), "formula", "Missing closing parenthesis.")
      position += 1
      return result
    case .name(let name):
      if tokens[position] == .symbol("(") {
        position += 1
        var args: [Expression] = []
        if tokens[position] != .symbol(")") {
          args.append(try expression(depth + 1))
          while tokens[position] == .symbol(",") {
            position += 1
            args.append(try expression(depth + 1))
          }
        }
        try require(tokens[position] == .symbol(")"), "formula", "Missing closing parenthesis.")
        position += 1
        return .call(name.uppercased(), args)
      }
      if tokens[position] == .symbol(":") {
        position += 1
        guard case .name(let end) = tokens[position] else {
          throw SevraError("range", "Missing range end.")
        }
        position += 1
        return .range(name, end)
      }
      return .name(name)
    default: throw SevraError("formula", "Expected a value.")
    }
  }
}
