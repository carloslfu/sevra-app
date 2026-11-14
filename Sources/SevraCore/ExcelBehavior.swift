import CryptoKit
import Foundation

/// A pure translation of workbook behavior. It has cell values, not database or OS authority.
public struct ExcelBehavior: Codable, Equatable, Sendable {
  public struct Action: Codable, Equatable, Sendable {
    public struct Input: Codable, Equatable, Sendable {
      public var id: String
      public var title: String
      public init(id: String, title: String) {
        self.id = id
        self.title = title
      }
    }
    public var id: String
    public var title: String
    public var writes: [String]
    public var inputs: [Input]?
    public init(id: String, title: String, writes: [String], inputs: [Input] = []) {
      self.id = id
      self.title = title
      self.writes = writes
      self.inputs = inputs
    }
  }
  public var source: String
  public var outputs: [String]
  public var actions: [Action]
  public var gaps: [String]
  public init(source: String, outputs: [String], actions: [Action] = [], gaps: [String] = []) {
    self.source = source
    self.outputs = outputs
    self.actions = actions
    self.gaps = gaps
  }
  public var digest: String {
    SHA256.hash(data: Data(((try? encoded(self).json()) ?? "").utf8))
      .map { String(format: "%02x", $0) }.joined()
  }
  static let identifierPattern = "^[A-Za-z][A-Za-z0-9_]{0,63}$"
  static func validIdentifier(_ value: String) -> Bool {
    value.utf8.count <= 64
      && value.range(of: identifierPattern, options: .regularExpression) == value
        .startIndex..<value.endIndex
  }

  public func validate() throws {
    try require(
      !source.isEmpty && source.utf8.count <= 131_072 && !source.contains("\0"),
      "excel_behavior", "Use JavaScript behavior source up to 128 KiB.")
    try require(
      outputs.count <= 2000 && Set(outputs).count == outputs.count && actions.count <= 24
        && Set(actions.map(\.id)).count == actions.count && gaps.count <= 24
        && gaps.allSatisfy { !$0.isEmpty && $0.utf8.count <= 800 },
      "excel_behavior", "Behavior declarations exceed their bounds or contain duplicates.")
    for action in actions {
      let inputs = action.inputs ?? []
      try require(
        inputs.count <= 16 && Set(inputs.map(\.id)).count == inputs.count
          && inputs.allSatisfy {
            Self.validIdentifier($0.id)
              && !$0.title.isEmpty && $0.title.utf8.count <= 160
          }, "excel_action",
        "Use up to 16 unique named inputs. IDs start with an ASCII letter, contain only letters, digits or underscores, and have at most 64 characters; titles need 1 to 160 UTF-8 bytes."
      )
      try require(
        action.id != "recalculate"
          && Self.validIdentifier(action.id),
        "excel_behavior",
        "Action ID '" + String(action.id.prefix(80))
          + "' must start with an ASCII letter, contain only letters, digits or underscores, and have at most 64 characters. The ID recalculate is reserved."
      )
      try require(
        !action.title.isEmpty && action.title.utf8.count <= 160,
        "excel_behavior", "Action titles need 1 to 160 UTF-8 bytes.")
      try require(
        (1...64).contains(action.writes.count)
          && Set(action.writes).count == action.writes.count,
        "excel_behavior", "Each action needs 1 to 64 distinct non-formula write cells.")
      let overlap = Set(action.writes).intersection(outputs)
      try require(
        overlap.isEmpty, "excel_behavior",
        "Action writes overlap calculated outputs: "
          + overlap.sorted().prefix(12).map { String($0.prefix(100)) }.joined(separator: ", ")
          + ". outputs must contain only original formula cells; keep editable input cells only in actions[].writes. "
          + "For an action event, return only its changed write cells. For recalculate, return every formula output; the host recalculates after the action."
      )
    }
    for cell in outputs + actions.flatMap(\.writes) { _ = try Self.address(cell) }
  }
  static func address(_ key: String) throws -> (sheet: Int, column: Int, row: Int) {
    let parts = key.split(separator: "!", omittingEmptySubsequences: false)
    guard parts.count == 2, parts[0].hasPrefix("sheet"),
      let sheet = Int(parts[0].dropFirst(5)), (1...12).contains(sheet),
      String(parts[0]) == "sheet\(sheet)",
      let cell = SheetFormulaToken.address(String(parts[1])),
      String(parts[1]) == XLSX.cellName(column: cell.column, row: cell.row),
      cell.column < 500, (1...1_048_576).contains(cell.row)
    else { throw SevraError("excel_behavior", "Use exact cell keys such as sheet1!D2.") }
    return (sheet - 1, cell.column, cell.row)
  }
  public func evaluate(
    cells: [String: String], action: String = "recalculate",
    arguments: Value = .object([:]), cancellation: Cancellation = .init()
  ) throws -> [String: String] {
    try validate()
    try require(
      cells.count <= 100_000
        && cells.reduce(0) { $0 + $1.key.utf8.count + $1.value.utf8.count } <= 2_000_000,
      "excel_behavior_limit", "Calculation inputs exceed their cell budget.")
    let writes: Set<String>
    if action == "recalculate" {
      writes = Set(outputs)
    } else {
      guard let definition = actions.first(where: { $0.id == action }) else {
        throw SevraError("excel_action", "That workbook action is not declared.")
      }
      writes = Set(definition.writes)
      try require(
        Set(arguments.object.keys).isSubset(of: Set((definition.inputs ?? []).map(\.id))),
        "excel_action", "Use the declared inputs for this action.")
    }
    try require(
      writes.isSubset(of: Set(cells.keys)), "excel_behavior", "A declared cell no longer exists.")
    guard case .object = arguments else {
      throw SevraError("excel_action", "Action inputs must be an object.")
    }
    try require(
      arguments.object.count <= 32 && arguments.json().utf8.count <= 8192,
      "excel_action", "Action inputs exceed their bounds.")
    var input = cells
    // A translator cannot pass original-result checks by reading the expected derived values.
    if action == "recalculate" {
      for key in outputs { input.removeValue(forKey: key) }
    } else if !outputs.isEmpty {
      // An action receives freshly computed starting outputs, never expected results from a reference file.
      input.merge(try evaluate(cells: cells, cancellation: cancellation)) { _, value in value }
    }
    let result = try ExtractionWorker(timeout: 4, maximumMemoryBytes: 256 * 1024 * 1024)
      .excelBehavior(
        .object([
          "source": .string(source),
          "hiddenOutputs": .array(action == "recalculate" ? outputs.map(Value.string) : []),
          "input": .object([
            "event": .string(action), "cells": .object(input.mapValues(Value.string)),
            "arguments": arguments,
          ]),
        ]), cancellation: cancellation)
    guard case .object(let values) = result else {
      throw SevraError("excel_behavior_result", "The behavior must return a cell-value object.")
    }
    try require(
      action == "recalculate" ? Set(values.keys) == writes : Set(values.keys).isSubset(of: writes),
      "excel_behavior_result",
      "Fix excelBehavior.source, inside recreate(input), for event '" + action
        + "'. Its return object contains undeclared or missing cell keys. Allowed keys: "
        + writes.sorted().prefix(12).joined(separator: ", ") + "; received: "
        + values.keys.sorted().prefix(12).map { String($0.prefix(100)) }.joined(separator: ", ")
        + ". Return a new object with only the declared result cells; NEVER return input.cells or the whole worksheet. "
        + "For an action, return only its changed writes; the host recalculates formula outputs afterward. "
        + "This error is about the behavior function's return value. Keep fixtures and expect_rows using table column IDs such as c2. "
        + "Only recreate(input) is called; dispatch actions inside it using input.event."
    )
    try require(
      values.allSatisfy { $0.value.string != nil && $0.value.text.utf8.count <= 32_000 },
      "excel_behavior_result",
      "Return string values for every cell, each at most 32 KB. Wrap numeric results in String(...)."
    )
    var changes = values.mapValues(\.text)
    if action != "recalculate", !outputs.isEmpty {
      changes.merge(
        try evaluate(
          cells: cells.merging(changes) { _, value in value }, cancellation: cancellation)
      ) { _, value in value }
    }
    return changes
  }
}

extension NativeAppPackage {
  public func validateExcelBehaviorBindings() throws {
    guard let excelBehavior else { return }
    try excelBehavior.validate()
    let count = datasets.count
    try require(
      Set(datasets.keys) == Set((1...max(1, count)).map { "sheet\($0)" }),
      "excel_behavior", "Workbook behavior needs the exact worksheet aliases.")
    for cell in excelBehavior.outputs + excelBehavior.actions.flatMap(\.writes) {
      let address = try ExcelBehavior.address(cell)
      try require(
        address.sheet < count
          && address.column < datasets["sheet\(address.sheet + 1)"]!.columns.count,
        "excel_behavior", "Behavior refers to an unbound worksheet cell.")
    }
  }
}
