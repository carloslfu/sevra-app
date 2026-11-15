import Foundation
import SevraAppUI

@testable import SevraCore

@MainActor func checkExcelValidationIsolation() async throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(identifier())
  defer { try? FileManager.default.removeItem(at: root) }
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  for poisoned in [true, false] {
    let book = try Workbook.create(
      at: root.appendingPathComponent("\(poisoned).sevra"), title: "Isolation")
    let source = """
      let blocked=false;
      Sevra.action('add',{title:'Add',inputs:{reference:{type:'text'},month:{type:'number'}}},async a=>{
        if(blocked)throw Error('Blocked');
        if(a.month<1||a.month>3){\(poisoned ? "blocked=true;" : "")throw Error('Invalid month');}
        return await Sevra.data.transaction([{op:'insert',table:'entries',values:{reference:a.reference,month:String(a.month)}}]);
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
              .init(id: "reference", title: "Reference"), .init(id: "month", title: "Month"),
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
      "journey": .number(0), "reference": .string("BASE"), "valid": .object([:]),
      "invalid": .array([
        .object(["original": .string("2"), "values": .array([.string("0"), .string("4")])])
      ]),
    ])
    do {
      _ = try await checkBusinessValidation(
        probes: [probe], calls: [0: call], session: session,
        snapshot: { .array(try book.tablePage(table).values.map(Value.object)) },
        versions: { [try book.rows(table).map(\.id)] })
      try expectEqual(poisoned, false)
    } catch let error as SevraError {
      try expectEqual(poisoned, true)
      try expectEqual(error.code, "validation_probe")
      try expectEqual(error.message.contains("valid correction failed"), true)
    }
  }
  print(
    "PASS business validation isolation: poisoned refusals rejected; valid correction and Undo required after each invalid input"
  )
}
