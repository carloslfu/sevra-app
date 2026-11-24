import Foundation
import SevraAI
import SevraCore
import SevraSplashGrammar

/// The grammar fixes the order an object's fields are written in, and a model that passes a
/// field cannot go back for it. So everything the model is shown has to list fields in that
/// order. This holds it for every tool, every nested shape and every hand-written example.
func checkFieldOrder() throws {
  func any(_ value: Value) throws -> Any {
    try JSONSerialization.jsonObject(with: Data(value.json().utf8), options: [.fragmentsAllowed])
  }
  /// Every object schema with properties, at any depth.
  func objects(_ value: Value) -> [Value] {
    var found: [Value] = []
    func walk(_ value: Value) {
      switch value {
      case .object(let fields):
        if case .object = value["properties"] { found.append(value) }
        fields.values.forEach(walk)
      case .array(let items): items.forEach(walk)
      default: break
      }
    }
    walk(value)
    return found
  }
  let grammar = try NativeTools.referenceDefinitions(toolScope: .all, display: false)
  let shown = try NativeTools.referenceDefinitions(
    toolScope: .all, conversationInput: true, display: true)
  // Each schema with the order the grammar writes it in: a tool's own parameters by name,
  // every object inside them by `propertyOrder`.
  var schemas: [(schema: Value, order: [String])] = []
  for definition in grammar + shown {
    let top = definition.parameters
    schemas.append((top, SplashToolPolicy.parameterOrder(try any(top) as! [String: Any])))
    for schema in objects(top).dropFirst() {
      // The order the model is told is the order the grammar enforces.
      let rule = NativeTools.fieldOrder(schema)
      let enforced = SplashToolPolicy.propertyOrder(try any(schema) as! [String: Any])
      guard rule == enforced else {
        throw SevraError(
          "field_order",
          "\(definition.name): shown \(rule.joined(separator: ", ")) but the grammar writes \(enforced.joined(separator: ", ")).")
      }
      schemas.append((schema, enforced))
    }
  }
  // The component order the view description and guide state is the grammar's.
  try expectEqual(
    SpaceDefinition.componentFieldOrder,
    NativeTools.fieldOrder(NativeTools.componentSchema(depth: 0)))
  // The order an edit's refusal names is the grammar's.
  let edit = try expectValue(
    schemas.first { Set($0.schema["properties"].object.keys).isSuperset(of: ["operation", "componentID"]) })
  try expectEqual(
    Workbook.editFieldOrder.filter { edit.schema["properties"][$0] != .null }, edit.order)

  /// The fields a hand-written shape such as {id, type: "table", title} names, in order.
  func shapes(_ text: String) -> [[String]] {
    var found: [[String]] = []
    let characters = Array(text)
    var opened: [Int] = []
    for (index, character) in characters.enumerated() {
      if character == "{" {
        opened.append(index)
      } else if character == "}", let start = opened.popLast() {
        var parts: [String] = []
        var current = ""
        var depth = 0
        var quoted = false
        for c in characters[(start + 1)..<index] {
          if c == "\"" { quoted.toggle() }
          if !quoted, "{[(".contains(c) { depth += 1 }
          if !quoted, "}])".contains(c) { depth -= 1 }
          if c == ",", depth == 0, !quoted {
            parts.append(current)
            current = ""
          } else {
            current.append(c)
          }
        }
        parts.append(current)
        found.append(
          parts.compactMap { part in
            let key = part.split(separator: ":", maxSplits: 1).first.map {
              $0.trimmingCharacters(in: .whitespacesAndNewlines)
            } ?? ""
            let name = key.hasSuffix("?") ? String(key.dropLast()) : key
            return name.range(of: "^[A-Za-z][A-Za-z0-9]*$", options: .regularExpression) != nil
              ? name : nil
          })
      }
    }
    // Prose lists say the order too: "aggregation, datasetID, unit and y, in that order" and
    // "in this order: operation, at, beforeID, component".
    let word = "[A-Za-z][A-Za-z0-9]*"
    let list = "(\(word)(?:, \(word))*,? and \(word)|\(word)(?:, \(word))+)"
    for pattern in [list + ", in that order", "in this order: " + list] {
      let expression = try! NSRegularExpression(pattern: pattern)
      for match in expression.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
        let names = String(text[Range(match.range(at: 1), in: text)!])
          .replacingOccurrences(of: " and ", with: ", ").split(separator: ",")
          .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        found.append(names)
      }
    }
    return found
  }
  func inOrder(_ keys: [String], _ order: [String]) -> Bool {
    var remaining = order[...]
    for key in keys {
      guard let at = remaining.firstIndex(of: key) else { return false }
      remaining = remaining[(at + 1)...]
    }
    return true
  }
  // The host's own refusals show shapes too. Make one and read it.
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(
    "field-order-" + identifier())
  defer { try? FileManager.default.removeItem(at: root) }
  let book = try Workbook.create(at: root.appendingPathComponent("a.sevra"), title: "Order")
  let empty: Value = .object(["version": .number(1), "components": .array([])])
  _ = try WorkbookTools(book).execute(
    "save_space", .object(["title": .string("Overview"), "definition": empty]))
  var refusals: [String] = []
  do {
    _ = try WorkbookTools(book).execute(
      "save_space", .object(["title": .string("Overview"), "definition": empty]))
  } catch let error as SevraError { refusals.append(error.message) }
  do {
    _ = try book.editSpace(
      "home", expectedVersion: 1,
      edits: [
        SpaceEdit(
          operation: "insert", component: Component(id: "n", type: "text", title: "N", text: "x"),
          text: "first")
      ])
  } catch let error as SevraError { refusals.append(error.message) }
  try expectEqual(refusals.count, 2)
  let texts =
    [GeneralTools.instructions] + refusals + shown.map(\.description)
    + shown.flatMap { objects($0.parameters).compactMap { $0["description"].string } }
    + shown.flatMap { definition in
      definition.parameters["properties"].object.values.compactMap { $0["description"].string }
    }
    + Array(WorkbookTools.guides.values)
  /// Nil when the shape names no schema's fields, or names them in the grammar's order.
  func problem(_ keys: [String]) -> String?? {
    let candidates = schemas.filter {
      Set($0.schema["properties"].object.keys).isSuperset(of: keys)
    }
    guard !candidates.isEmpty else { return nil }
    // The closest schemas, those with the fewest other fields, are the ones a shape means.
    let closest = candidates.map { $0.schema["properties"].object.count }.min()!
    let meant = candidates.filter { $0.schema["properties"].object.count == closest }
    if meant.contains(where: { inOrder(keys, $0.order) }) { return .some(nil) }
    return "The shape {\(keys.joined(separator: ", "))} is not in the order the grammar writes: "
      + meant[0].order.joined(separator: ", ") + "."
  }
  // Counterexamples: a shape and a prose list in the wrong order are both caught.
  for wrong in ["{id, title, type}", "metric: y, datasetID and aggregation, in that order."] {
    guard let keys = shapes(wrong).first, case .some(.some) = problem(keys) else {
      throw SevraError("field_order", "The check missed a wrong order in: " + wrong)
    }
  }
  var checked = 0
  for text in texts {
    for keys in shapes(text) where keys.count >= 2 {
      guard let found = problem(keys) else { continue }
      checked += 1
      if let found { throw SevraError("field_order", found) }
    }
  }
  try expectEqual(checked >= 30, true)
  print("PASS every shape the model is shown lists its fields in the grammar's order (\(checked) examples)")
}
