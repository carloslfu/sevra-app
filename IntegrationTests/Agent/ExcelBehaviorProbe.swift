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
  let selected =
    (ProcessInfo.processInfo.environment["SEVRA_EXCEL_CASES"]
    ?? cases.map { $0["name"].text }.joined(separator: "|"))
    .components(separatedBy: "|")
  try require(
    !selected.isEmpty && Set(selected).count == selected.count
      && Set(selected).isSubset(of: Set(cases.map { $0["name"].text })),
    "fixture", "Select distinct known Excel business cases.")
  let orderedCases = selected.map { name in cases.first { $0["name"].text == name }! }
  let replay = ProcessInfo.processInfo.environment["SEVRA_EXCEL_REPLAY_DIR"].map {
    URL(fileURLWithPath: $0)
  }
  let model = NativeWorkbookModel(
    configuration: try nativeProbeConfiguration(
      library: library, engine: engine,
      modelsRoot: modelsRoot, budget: .init(profile: .evaluation32K), reasoning: .bounded512,
      modelLayout: .installed))
  var results: [Value] = []
  for example in orderedCases {
    let name = example["name"].text
    let started = Date()
    let book = try Workbook.create(at: root.appendingPathComponent(name + ".sevra"), title: name)
    var result: [String: Value] = ["name": .string(name), "freshModelTrial": .bool(replay == nil)]
    do {
      let source = try book.importFile(
        fixtures.appendingPathComponent(example["files"].array[0].text))
      let originalCells = try Workbook.excelCells(book.excelOriginalSheets(source.id))
      let inputLabel = originalCells["sheet1!B1"] ?? "Input"
      var draft = try book.beginExcelConversion(sourceID: source.id)
      let purpose =
        name == "Inventory"
        ? "Recreate the stock workbook, including its ShipStock VBA business action as a native Ship stock button with a Quantity input. Preserve its validation and recalculation. Show the worksheet in a native table labeled Records. The original macro must never execute."
        : name == "Lookup quotes"
          ? "Recreate the Lookup quotes workbook so I can select a quote in a native table labeled Records, edit SKU and Quantity in inputs with those labels, and use Save changes. Keep calculations live, including zero quantities, unknown SKUs, blank cells and original error results. Preserve exact entered cell text unless the original validates it. Don't edit headers or insert/delete rows."
          : "Recreate the \(name) workbook so I can select a data row in a native table labeled Records, edit \(inputLabel) in an input labeled \(inputLabel), and use Save changes. Keep its calculations live after edits, including zero values, blank cells and original errors; preserve exact entered cell text unless the original validates it; don't edit headers or insert/delete rows."
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
      // UI assertions use exact stored strings. A translation may preserve a different
      // numeric format (0.00 versus 0); anchor its output to the independent original
      // before using that presentation in the exact UI assertion. Inputs stay exact.
      func expectedOutput(_ original: [String: String]) throws -> String {
        let saved = original["sheet1!D2"] ?? ""
        guard let behavior = package.excelBehavior else { return saved }
        let output = try behavior.evaluate(cells: original)["sheet1!D2"] ?? ""
        try expectEqual(Workbook.sameExcelResult(output, saved), true)
        return output
      }
      if ["Inventory", "Loan", "Lookup quotes"].contains(name) {
        try require(
          package.excelBehavior != nil, "probe", "This workflow needs recreated behavior.")
      }
      let originalComparison = ready.record.data["comparison"]
      try expectEqual(originalComparison["status"], .string("matched"))
      result["comparison"] = ready.record.data["comparison"]
      let table = draft.datasetIDs[0]
      let seeded: Value = .object([
        "sheet1": .array(try book.tablePage(table).values.map(Value.object))
      ])
      // Accept the two ordinary labels for this action, then run the same independent
      // saved-state assertions. Discover controls from the rendered app, not its tests
      // or source, and never retry a failing action with a different button.
      var shipTarget = "Ship stock"
      if name == "Inventory" {
        var matches: [String] = []
        for title in ["Ship stock", "Ship"] {
          do {
            _ = try await NativeAppCheck.run(
              package: package,
              steps: [.object(["kind": .string("expect_control"), "target": .string(title)])],
              fixtures: seeded, excelCoordinates: book.excelCheckCoordinates(draft.id))
            matches.append(title)
          } catch {
            guard (error as? SevraError)?.code == "app_check_assertion",
              error.localizedDescription.contains("Target must match one control")
            else { throw error }
          }
        }
        try require(matches.count == 1, "probe", "Expected one unambiguous shipping control.")
        shipTarget = matches[0]
        result["actionControl"] = .string(shipTarget)
      }
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
          .object(["kind": .string("click"), "target": .string(shipTarget)]),
          .object([
            "kind": .string("expect_rows"), "table": .string("sheet1"), "count": .number(1),
            "values": .object(["c2": .string("6"), "c4": .string(try expectedOutput(expected))]),
          ]),
          .object(["kind": .string("select"), "target": .string("Records"), "value": .number(1)]),
          .object([
            "kind": .string("change"), "target": .string("Quantity"), "value": .string("999"),
          ]),
          .object(["kind": .string("click"), "target": .string(shipTarget)]),
          .object([
            "kind": .string("expect_rows"), "table": .string("sheet1"), "count": .number(1),
            "values": .object(["c2": .string("6"), "c4": .string(try expectedOutput(expected))]),
          ]),
        ]
      } else {
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
              "c2": .string(expected["sheet1!B2"]!), "c4": .string(try expectedOutput(expected)),
            ]),
          ]),
        ]
      }
      if name == "Inventory" {
        steps.append(
          .object([
            "kind": .string("expect_value"), "target": .string("Quantity"), "value": .string("999"),
          ]))
        for invalid in ["0", "-1", "not a number", "2abc"] {
          steps += [
            .object(["kind": .string("select"), "target": .string("Records"), "value": .number(1)]),
            .object([
              "kind": .string("change"), "target": .string("Quantity"), "value": .string(invalid),
            ]),
            .object(["kind": .string("click"), "target": .string(shipTarget)]),
            .object([
              "kind": .string("expect_rows"), "table": .string("sheet1"), "count": .number(1),
              "values": .object([
                "c2": .string("6"), "c4": .string(try expectedOutput(expected)),
              ]),
            ]),
            .object([
              "kind": .string("expect_value"), "target": .string("Quantity"),
              "value": .string(invalid),
            ]),
          ]
        }
        var secondShipment = expected
        secondShipment["sheet1!B2"] = "4"
        secondShipment["sheet1!D2"] = "8"
        steps += [
          .object(["kind": .string("change"), "target": .string("Quantity"), "value": .string("2")]
          ),
          .object(["kind": .string("click"), "target": .string(shipTarget)]),
          .object([
            "kind": .string("expect_rows"), "table": .string("sheet1"), "count": .number(1),
            "values": .object([
              "c2": .string("4"), "c4": .string(try expectedOutput(secondShipment)),
            ]),
          ]),
          .object([
            "kind": .string("expect_value"), "target": .string("Quantity"), "value": .string(""),
          ]),
        ]
      }
      if name == "Lookup quotes" {
        var zeroQuantity = expected
        zeroQuantity["sheet1!C2"] = "0"
        zeroQuantity["sheet1!D2"] = "0"
        var missingSKU = zeroQuantity
        missingSKU["sheet1!B2"] = "Missing"
        missingSKU["sheet1!D2"] = "#N/A"
        steps += [
          .object(["kind": .string("select"), "target": .string("Records"), "value": .number(1)]),
          .object(["kind": .string("change"), "target": .string("Quantity"), "value": .string("0")]
          ),
          .object(["kind": .string("click"), "target": .string("Save changes")]),
          .object([
            "kind": .string("expect_rows"), "table": .string("sheet1"), "count": .number(1),
            "values": .object([
              "c3": .string("0"), "c4": .string(try expectedOutput(zeroQuantity)),
            ]),
          ]),
          .object(["kind": .string("select"), "target": .string("Records"), "value": .number(1)]),
          .object([
            "kind": .string("change"), "target": .string("SKU"), "value": .string("Missing"),
          ]),
          .object(["kind": .string("click"), "target": .string("Save changes")]),
          .object([
            "kind": .string("expect_rows"), "table": .string("sheet1"), "count": .number(1),
            "values": .object([
              "c2": .string("Missing"), "c4": .string(try expectedOutput(missingSKU)),
            ]),
          ]),
        ]
      }
      if name != "Inventory" && name != "Lookup quotes" {
        steps.append(
          .object([
            "kind": .string("expect_value"), "target": .string(inputLabel), "value": .string(""),
          ]))
        for file in example["files"].array.dropFirst(2).prefix(2) {
          let scenario = try ExtractionWorker().readTable(
            fixtures.appendingPathComponent(file.text), format: .xlsx
          ).sheets
          let values = try Workbook.excelCells(scenario)
          steps += [
            .object(["kind": .string("select"), "target": .string("Records"), "value": .number(1)]),
            .object([
              "kind": .string("change"), "target": .string(inputLabel),
              "value": .string(values["sheet1!B2"]!),
            ]),
            .object(["kind": .string("click"), "target": .string("Save changes")]),
            .object([
              "kind": .string("expect_rows"), "table": .string("sheet1"), "count": .number(1),
              "values": .object([
                "c2": .string(values["sheet1!B2"]!), "c4": .string(try expectedOutput(values)),
              ]),
            ]),
            .object([
              "kind": .string("expect_value"), "target": .string(inputLabel), "value": .string(""),
            ]),
          ]
        }
      }
      if name != "Inventory" {
        steps += [
          .object(["kind": .string("select"), "target": .string("Records"), "value": .number(1)]),
          .object(["kind": .string("select"), "target": .string("Records"), "value": .number(0)]),
          .object([
            "kind": .string("expect_value"),
            "target": .string(inputLabel), "value": .string(""),
          ]),
        ]
      }
      // Synthetic UI checks have no original formula plan when the app reuses the host engine.
      // Check the input writes here and separately exercise real saved calculations below.
      // Never inject the fixture's reference JavaScript into a generated package.
      if package.excelBehavior == nil {
        steps = steps.map { step in
          guard step["kind"] == .string("expect_rows") else { return step }
          var fields = step.object
          var values = step["values"].object
          values.removeValue(forKey: "c4")
          fields["values"] = .object(values)
          return .object(fields)
        }
      }
      if name == "Inventory" {
        steps.removeAll { $0["kind"] == .string("select") }
        steps.insert(
          .object([
            "kind": .string("expect_enabled"), "target": .string("Quantity"), "value": .bool(true),
          ]), at: 0)
      }
      result["independentUI"] = try await NativeAppCheck.run(
        package: package, steps: steps, fixtures: seeded,
        excelCoordinates: book.excelCheckCoordinates(draft.id))
      var boundarySteps: [Value] = []
      for file in example["uiBoundaryFiles"].array {
        let scenario = try ExtractionWorker().readTable(
          fixtures.appendingPathComponent(file.text), format: .xlsx
        ).sheets
        let values = try Workbook.excelCells(scenario)
        var savedValues: [String: Value] = ["c2": .string(values["sheet1!B2"] ?? "")]
        if package.excelBehavior != nil { savedValues["c4"] = .string(try expectedOutput(values)) }
        boundarySteps += [
          .object(["kind": .string("select"), "target": .string("Records"), "value": .number(1)]),
          .object([
            "kind": .string("change"), "target": .string(inputLabel),
            "value": .string(values["sheet1!B2"] ?? ""),
          ]),
          .object(["kind": .string("click"), "target": .string("Save changes")]),
          .object([
            "kind": .string("expect_rows"), "table": .string("sheet1"), "count": .number(1),
            "values": .object(savedValues),
          ]),
          .object([
            "kind": .string("expect_value"), "target": .string(inputLabel), "value": .string(""),
          ]),
        ]
      }
      if !boundarySteps.isEmpty {
        result["boundaryUI"] = try await NativeAppCheck.run(
          package: package, steps: boundarySteps, fixtures: seeded,
          excelCoordinates: book.excelCheckCoordinates(draft.id))
      }
      let access = try NativeAppAccess(workbook: book, space: book.space(draft.id))
      defer { access.revoke() }
      var savedChecks = 0
      // Held-out originals never enter the model's workbook or comparison examples.
      // Exercise them only after publication through actual saved edits and Undo.
      let holdouts = example["holdoutFiles"].array
      result["heldOutOriginalFiles"] = .array(holdouts)
      for file in Array(example["files"].array.dropFirst()) + holdouts {
        let sheets = try ExtractionWorker().readTable(
          fixtures.appendingPathComponent(file.text), format: .xlsx
        ).sheets
        let expected = try Workbook.excelCells(sheets)
        let row = try book.tablePage(table).rows[1]
        let before = try book.tablePage(table).values
        var inputs: [String: Value] = [
          "c2": .string(expected["sheet1!B2"]!), "c3": .string(expected["sheet1!C2"]!),
        ]
        if name == "Loan" { inputs["c5"] = .string(expected["sheet1!E2"]!) }
        if name == "Lookup quotes" {
          inputs["c6"] = .string(expected["sheet1!F2"]!)
          inputs["c7"] = .string(expected["sheet1!G2"]!)
        }
        let token = identifier()
        _ = try book.nativeAppTransaction(
          access,
          operations: [
            .object([
              "op": .string("update"), "table": .string("sheet1"), "id": .string(row.id),
              "values": .object(inputs),
            ])
          ], expectedRevision: book.revision(), token: token)
        let actual = try book.tablePage(table).values[1]["c4"]!.text
        try require(
          Workbook.sameExcelResult(actual, expected["sheet1!D2"]!), "probe",
          "Saved calculation differs from original " + file.text + ": original “"
            + expected["sheet1!D2"]! + "”; recreated “" + actual + "”.")
        let reopened = try Workbook(book.url)
        try expectEqual(try reopened.tablePage(table).values, try book.tablePage(table).values)
        _ = try book.nativeAppTransaction(
          access, operations: [], expectedRevision: book.revision(), token: identifier(),
          undo: token)
        try expectEqual(try book.tablePage(table).values, before)
        savedChecks += 1
      }
      let archive = root.appendingPathComponent(name + ".sevraz")
      try book.export(to: archive)
      let copy = try Workbook.openArchive(
        archive, at: root.appendingPathComponent(name + " copy.sevra"))
      try expectEqual(try copy.tablePage(table).values, try book.tablePage(table).values)
      try expectEqual(try copy.verify()["ok"], .bool(true))
      result["savedEditReopenUndoCases"] = .number(Double(savedChecks))
      result["portableCopyVerified"] = .bool(true)
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
