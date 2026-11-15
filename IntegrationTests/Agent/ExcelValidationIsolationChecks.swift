import Foundation
import SevraAppUI

@testable import SevraCore

@MainActor func checkExcelValidationIsolation() async throws {
  let original = ImportedSheet(
    name: "Values", rows: [["R1", "2", "4"], ["R2", "3", "6"]], rowNumbers: [1, 2],
    notes: [], formulas: ["C1": "B1*2", "C2": "B2*2"])
  let before: Value = .array([.array([
    .object(["c1": .string("R1"), "c2": .string("2"), "c3": .string("4")]),
    .object(["c1": .string("R2"), "c2": .string("3"), "c3": .string("6")]),
  ])])
  let expected: Value = .object([
    "sheet": .number(0), "match": .object(["c1": .string("R1")]),
    "values": .object(["c2": .string("1.5")]),
  ])
  func changed(_ amount: String, unrelated: String = "3") -> Value {
    .array([.array([
      .object(["c1": .string("R1"), "c2": .string(amount), "c3": .string("3")]),
      .object(["c1": .string("R2"), "c2": .string(unrelated), "c3": .string("6")]),
    ])])
  }
  try checkBusinessSavedEffect(
    before: before, after: changed("1.50"), expected: expected, original: [original])
  for wrong in [changed("1"), changed("1.50000000000001"), changed("1.5", unrelated: "4")] {
    try expectThrows(try checkBusinessSavedEffect(
      before: before, after: wrong, expected: expected, original: [original]))
  }
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(identifier())
  defer { try? FileManager.default.removeItem(at: root) }
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  for mode in ["poisoned", "coerced", "valid"] {
    let poisoned = mode == "poisoned"
    let book = try Workbook.create(
      at: root.appendingPathComponent("\(mode).sevra"), title: "Isolation")
    let source = """
      let blocked=false;
      Sevra.action('add',{title:'Add',inputs:{reference:{type:'text'},month:{type:'number'}}},async a=>{
        if(blocked)throw Error('Blocked');
        if(a.month<1||a.month>3){\(poisoned ? "blocked=true;" : "")throw Error('Invalid month');}
        return await Sevra.data.transaction([{op:'insert',table:'entries',values:{c1:a.reference,c2:String(\(mode == "coerced" ? "Math.trunc(a.month)" : "a.month"))}}]);
      });
      Sevra.mount(Sevra.h(Sevra.Text,{text:'Entries'}));
      """
    let space = try book.installNativeAppContents(
      NativeAppPackage(
        name: "Isolation", source: source,
        datasets: [
          "entries": .init(
            title: "Entries",
            columns: [
              .init(id: "c1", title: "Reference"), .init(id: "c2", title: "Value"),
            ], writable: true)
        ]))
    let suite = "Sevra-validation-isolation-" + identifier()
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let session = NativeAppSession(book: book, space: space, defaults: defaults)
    defer { session.stop() }
    _ = try await session.converse("enable")
    let table = space.definition.app!.datasets["entries"]!.datasetID!
    let call: Value = .object([
      "action": .string("add"),
      "inputs": .object(["reference": .string("BASE"), "month": .number(2)]),
    ])
    let probe: Value = .object([
      "journey": .number(0), "reference": .string("BASE"),
      "valid": .object(["2": .string("1.5")]),
      "expected": .object([
        "sheet": .number(0), "match": .object(["c1": .string("CONTROL-0")]),
        "values": .object(["c2": .string("1.5")]),
      ]),
      "invalid": .array([
        .object(["original": .string("2"), "values": .array([.string("0"), .string("4")])])
      ]),
    ])
    do {
      _ = try await checkBusinessValidation(
        probes: [probe], calls: [0: call], session: session,
        original: [.init(name: "Entries", rows: [], rowNumbers: [], notes: [], formulas: [:])],
        snapshot: { .array([.array(try book.tablePage(table).values.map(Value.object))]) },
        versions: { [try book.rows(table).map(\.id)] })
      try expectEqual(mode, "valid")
    } catch let error as SevraError {
      try expectEqual(mode != "valid", true)
      try expectEqual(error.code, poisoned ? "validation_probe" : "journey")
      try expectEqual(
        error.message.contains(poisoned ? "valid correction failed" : "Wrong saved"), true)
    }
  }
  print(
    "PASS business validation isolation: coerced valid inputs and poisoned refusals rejected; exact saved effects, correction and Undo required"
  )
}
