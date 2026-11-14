import Foundation
import SevraAI
import SevraAppProtocol
import SevraNativeAI

@testable import SevraCore

/// Real local inference receives the original and user workflow, never the reference translation.
func runExcelBehaviorProbe(modelsRoot: String, library: String, engine: String, output: String)
  async throws
{
  let root = URL(fileURLWithPath: output)
  try require(
    !FileManager.default.fileExists(atPath: root.path), "fixture", "Use a fresh output directory.")
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  let fixtures = URL(fileURLWithPath: "integration/fixtures/excel-behavior")
  let cases = try Value.parse(
    String(contentsOf: fixtures.appendingPathComponent("cases.json"), encoding: .utf8)
  ).array
  let selected = Set(
    (ProcessInfo.processInfo.environment["SEVRA_EXCEL_CASES"] ?? "Inventory|Loan|Lookup quotes")
      .components(separatedBy: "|"))
  let replay = ProcessInfo.processInfo.environment["SEVRA_EXCEL_REPLAY_DIR"].map {
    URL(fileURLWithPath: $0)
  }
  let model = NativeWorkbookModel(
    configuration: try nativeProbeConfiguration(
      library: library, engine: engine,
      modelsRoot: modelsRoot, budget: .init(profile: .evaluation32K), reasoning: .bounded512,
      modelLayout: .installed))
  var results: [Value] = []
  for example in cases where selected.contains(example["name"].text) {
    let name = example["name"].text
    let started = Date()
    let book = try Workbook.create(at: root.appendingPathComponent(name + ".sevra"), title: name)
    var result: [String: Value] = ["name": .string(name), "freshModelTrial": .bool(replay == nil)]
    do {
      let source = try book.importFile(
        fixtures.appendingPathComponent(example["files"].array[0].text))
      var draft = try book.beginExcelConversion(sourceID: source.id)
      let purpose =
        name == "Inventory"
        ? "Recreate the stock workbook, including its ShipStock VBA business action as a native Ship stock button with a Quantity input. Preserve its validation and recalculation. Show the worksheet in a native table labeled Records. The original macro must never execute."
        : name == "Loan"
          ? "Recreate the Loan workbook so I can select a data row in a native table labeled Records, edit Principal in an input labeled Principal, and use Save changes. Keep its calculations live after edits; don't edit headers or insert/delete rows."
          : "Recreate the Lookup quotes workbook so I can select a quote in a native table labeled Records, edit SKU and Quantity in inputs with those labels, and use Save changes. Keep calculations live, including zero quantities and unknown SKUs. Don't edit headers or insert/delete rows."
      draft = try book.updateExcelConversion(
        draft.id, expectedVersion: draft.version, state: "analyzing", purpose: purpose)
      let plan: Value
      if replay != nil {
        plan = .object([
          "name": .string(name), "purpose": .string(purpose),
          "workflows": .array([.string("Recheck the retained candidate")]),
          "questions": .array([]),
        ])
      } else {
        plan = try await ExcelConversionAgent.analyze(
          draft, workbook: book, model: model,
          directory: URL(fileURLWithPath: modelsRoot), cancellation: .init(),
          progress: { fputs("Plan: " + $0 + "\n", stderr) })
      }
      result["plan"] = plan
      draft = try book.saveExcelConversionPlan(
        draft.id, expectedVersion: draft.version, plan: plan, model: await model.identity)
      draft = try book.importExcelConversionTables(draft.id)
      for file in example["files"].array.dropFirst() {
        let reference = try book.importFile(fixtures.appendingPathComponent(file.text))
        draft = try book.addExcelExample(
          draft.id, sourceID: reference.id, expectedVersion: draft.version)
      }
      let build = try book.prepareExcelConversionBuild(draft.id)
      if let replay {
        let candidate = replay.appendingPathComponent(name + ".sevraapp")
        var package = try JSONDecoder().decode(
          NativeAppPackage.self, from: Data(contentsOf: candidate))
        let digest = package.digest
        for (index, table) in build.tables.enumerated() {
          let alias = "sheet\(index + 1)"
          package.datasets[alias] = .init(
            title: table.title, columns: table.columns,
            writable: package.datasets[alias]?.writable ?? false, datasetID: table.id)
        }
        _ = try book.installExcelConversionApp(
          package, build: build,
          check: .object([
            "scope": .string("Replayed retained candidate source; independent checks follow"),
            "priorDigest": .string(digest),
          ]), token: identifier(), cancellation: .init())
        result["reusedCandidateDigest"] = .string(digest)
      } else {
        let response = try await WorkbookAgent.run(
          build.request, workbook: book, context: build.context,
          modelDirectory: URL(fileURLWithPath: modelsRoot),
          progress: { fputs("Build: " + $0 + "\n", stderr) },
          model: model, excelConversion: build)
        result["answer"] = .string(response.answer)
      }
      let ready = try book.excelConversion(draft.id)
      try expectEqual(ready.state, "ready")
      let package = try book.space(draft.id).definition.app!
      try require(
        package.excelBehavior != nil, "probe",
        "This case needs reconstructed behavior, not a saved-value viewer.")
      result["comparison"] = ready.record.data["comparison"]
      let table = draft.datasetIDs[0]
      let seeded: Value = .object([
        "sheet1": .array(try book.tablePage(table).values.map(Value.object))
      ])
      let changed = try ExtractionWorker().readTable(
        fixtures.appendingPathComponent(example["files"].array[1].text), format: .xlsx
      ).sheets
      let expected = try Workbook.excelCells(changed)
      var steps: [Value]
      if name == "Inventory" {
        steps = [
          .object(["kind": .string("select"), "target": .string("Records"), "value": .number(1)]),
          .object(["kind": .string("change"), "target": .string("Quantity"), "value": .string("2")]
          ),
          .object(["kind": .string("click"), "target": .string("Ship stock")]),
          .object([
            "kind": .string("expect_rows"), "table": .string("sheet1"), "count": .number(1),
            "values": .object(["c2": .string("6"), "c4": .string("6")]),
          ]),
          .object(["kind": .string("select"), "target": .string("Records"), "value": .number(1)]),
          .object([
            "kind": .string("change"), "target": .string("Quantity"), "value": .string("999"),
          ]),
          .object(["kind": .string("click"), "target": .string("Ship stock")]),
          .object([
            "kind": .string("expect_rows"), "table": .string("sheet1"), "count": .number(1),
            "values": .object(["c2": .string("6"), "c4": .string("6")]),
          ]),
        ]
      } else {
        // The first lookup candidate visibly labels the SKU editor separately from its Input section.
        // Recheck the actual business control; retain that earlier literal-label failure separately.
        let inputLabel = name == "Lookup quotes" ? "SKU" : "Principal"
        result["inputControl"] = .string(inputLabel)
        steps = [
          .object(["kind": .string("select"), "target": .string("Records"), "value": .number(1)]),
          .object([
            "kind": .string("change"), "target": .string(inputLabel),
            "value": .string(expected["sheet1!B2"]!),
          ]),
          .object(["kind": .string("click"), "target": .string("Save changes")]),
          .object([
            "kind": .string("expect_rows"), "table": .string("sheet1"), "count": .number(1),
            "values": .object([
              "c2": .string(expected["sheet1!B2"]!), "c4": .string(expected["sheet1!D2"]!),
            ]),
          ]),
        ]
      }
      if name == "Inventory" {
        for invalid in ["0", "-1", "not a number"] {
          steps += [
            .object(["kind": .string("select"), "target": .string("Records"), "value": .number(1)]),
            .object([
              "kind": .string("change"), "target": .string("Quantity"), "value": .string(invalid),
            ]),
            .object(["kind": .string("click"), "target": .string("Ship stock")]),
            .object([
              "kind": .string("expect_rows"), "table": .string("sheet1"), "count": .number(1),
              "values": .object(["c2": .string("6"), "c4": .string("6")]),
            ]),
          ]
        }
      }
      if name == "Lookup quotes" {
        steps += [
          .object(["kind": .string("select"), "target": .string("Records"), "value": .number(1)]),
          .object(["kind": .string("change"), "target": .string("Quantity"), "value": .string("0")]
          ),
          .object(["kind": .string("click"), "target": .string("Save changes")]),
          .object([
            "kind": .string("expect_rows"), "table": .string("sheet1"), "count": .number(1),
            "values": .object(["c3": .string("0"), "c4": .string("0")]),
          ]),
          .object(["kind": .string("select"), "target": .string("Records"), "value": .number(1)]),
          .object([
            "kind": .string("change"), "target": .string("SKU"), "value": .string("Missing"),
          ]),
          .object(["kind": .string("click"), "target": .string("Save changes")]),
          .object([
            "kind": .string("expect_rows"), "table": .string("sheet1"), "count": .number(1),
            "values": .object(["c2": .string("Missing"), "c4": .string("#N/A")]),
          ]),
        ]
      }
      if name != "Inventory" {
        steps += [
          .object(["kind": .string("select"), "target": .string("Records"), "value": .number(1)]),
          .object(["kind": .string("select"), "target": .string("Records"), "value": .number(0)]),
          .object([
            "kind": .string("expect_value"),
            "target": .string(name == "Loan" ? "Principal" : "SKU"), "value": .string(""),
          ]),
        ]
      }
      result["independentUI"] = try await NativeAppCheck.run(
        package: package, steps: steps, fixtures: seeded,
        excelCoordinates: book.excelCheckCoordinates(draft.id))
      try expectEqual(try book.verify()["ok"], .bool(true))
      result["passed"] = .bool(true)
      try Data(encoded(package).json().utf8).write(
        to: root.appendingPathComponent(name + ".sevraapp"))
    } catch {
      result["passed"] = .bool(false)
      result["error"] = .string(error.localizedDescription)
    }
    result["seconds"] = .number(Date().timeIntervalSince(started))
    results.append(.object(result))
    try Data(Value.array(results).json().utf8).write(
      to: root.appendingPathComponent("results.json"), options: .atomic)
    try Data(encoded(book.messages()).json().utf8).write(
      to: root.appendingPathComponent(name + "-messages.json"))
    print(try Value.object(result).json())
  }
  try require(
    !results.isEmpty && results.allSatisfy { $0["passed"] == .bool(true) }, "excel_probe",
    "Inspect retained reconstruction trial results.")
}
