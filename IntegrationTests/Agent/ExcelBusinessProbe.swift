import Foundation
import SevraAI
import SevraAppUI
import SevraNativeAI

@testable import SevraCore

/// Fresh generation and conversational operations. An independent spreadsheet
/// oracle consumes saved snapshots only AFTER the model finishes.
@MainActor func runExcelBusinessProbe(
  modelsRoot: String, library: String, engine: String, output: String
) async throws {
  let root = URL(fileURLWithPath: output)
  try require(
    !FileManager.default.fileExists(atPath: root.path), "fixture", "Use a fresh directory.")
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  let fixtures = URL(fileURLWithPath: "integration/fixtures/excel-business")
  let cases = try Value.parse(
    String(contentsOf: fixtures.appendingPathComponent("cases.json"), encoding: .utf8)
  ).array
  let selected =
    ProcessInfo.processInfo.environment["SEVRA_BUSINESS_CASES"]?.components(separatedBy: "|")
    ?? cases.map { $0["slug"].text }
  try require(
    !selected.isEmpty && Set(selected).count == selected.count
      && Set(selected).isSubset(of: Set(cases.map { $0["slug"].text })), "fixture",
    "Choose distinct cases.")
  // Diagnostic-only: replay untouched programs to isolate conversation/runtime
  // changes without paying for another generation. Never qualifies a fresh cohort.
  let replay = ProcessInfo.processInfo.environment["SEVRA_BUSINESS_REPLAY_DIR"].map {
    URL(fileURLWithPath: $0)
  }
  let model = NativeWorkbookModel(
    configuration: try nativeProbeConfiguration(
      library: library, engine: engine, modelsRoot: modelsRoot,
      budget: .init(profile: .evaluation32K), reasoning: .bounded512, modelLayout: .installed))
  var results: [Value] = []
  for slug in selected {
    let example = cases.first { $0["slug"].text == slug }!
    let started = Date()
    let book = try Workbook.create(
      at: root.appendingPathComponent(slug + ".sevra"), title: example["name"].text)
    var result: [String: Value] = ["slug": .string(slug), "freshModelTrial": .bool(replay == nil)]
    var journeys: [Value] = []
    let suite = "Sevra-business-probe-" + identifier()
    let defaults = UserDefaults(suiteName: suite)!
    var session: NativeAppSession?
    var pendingBuild: (id: String, version: String)?
    defer {
      session?.stop()
      defaults.removePersistentDomain(forName: suite)
    }
    do {
      func captureReference(_ file: URL) throws -> Item {
        let job = try book.captureIntake(file, role: .reference)
        try expectEqual(try book.runIntake(job.id).state, "ready")
        return try book.item(job.sourceID)
      }
      let source = try captureReference(
        fixtures.appendingPathComponent(example["files"].array[0].text))
      var conversion = try book.beginExcelConversion(sourceID: source.id)
      conversion = try book.updateExcelConversion(
        conversion.id, expectedVersion: conversion.version,
        state: "analyzing", purpose: example["purpose"].text)
      let plan: Value
      if let replay {
        let previous = try Value.parse(
          String(contentsOf: replay.appendingPathComponent("results.json"), encoding: .utf8))
        plan = try expectValue(previous.array.first { $0["slug"] == .string(slug) })["plan"]
      } else {
        plan = try await ExcelConversionAgent.analyze(
          conversion, workbook: book, model: model,
          directory: URL(fileURLWithPath: modelsRoot), cancellation: .init(),
          progress: { print(slug + " plan: " + $0) })
      }
      result["plan"] = plan
      conversion = try book.saveExcelConversionPlan(
        conversion.id, expectedVersion: conversion.version,
        plan: plan, model: await model.identity)
      conversion = try book.importExcelConversionTables(conversion.id)
      // One changed original is visible to generation. The second stays held out.
      let reference = try captureReference(
        fixtures.appendingPathComponent(example["files"].array[1].text))
      conversion = try book.addExcelExample(
        conversion.id, sourceID: reference.id, expectedVersion: conversion.version)
      conversion = try book.updateExcelConversion(
        conversion.id, expectedVersion: conversion.version, state: "building")
      let build = try book.prepareExcelConversionBuild(conversion.id)
      pendingBuild = (conversion.id, build.conversionVersion)
      if let replay {
        var package = try NativeAppPackage.decode(
          Data(contentsOf: replay.appendingPathComponent(slug + ".sevraapp")))
        result["reusedCandidateDigest"] = .string(package.digest)
        for (index, table) in build.tables.enumerated() {
          let alias = "sheet\(index + 1)"
          package.datasets[alias] = .init(
            title: table.title, columns: table.columns,
            writable: package.datasets[alias]?.writable ?? false, datasetID: table.id)
        }
        _ = try book.installExcelConversionApp(
          package, build: build,
          check: .object(["scope": .string("Diagnostic replay; independent business checks follow")]
          ),
          token: identifier(), cancellation: .init())
      } else {
        let response = try await WorkbookAgent.run(
          build.request, workbook: book, context: build.context,
          modelDirectory: URL(fileURLWithPath: modelsRoot),
          progress: { print(slug + " build: " + $0) },
          model: model, excelConversion: build)
        result["buildAnswer"] = .string(response.answer)
        result["generationSeconds"] = .number(Date().timeIntervalSince(started))
      }
      try expectEqual(try book.excelConversion(conversion.id).state, "ready")
      pendingBuild = nil
      let space = try book.space(conversion.id)
      let package = space.definition.app!
      result["digest"] = .string(package.digest)
      result["comparison"] = try book.excelConversion(conversion.id).record.data["comparison"]
      try Data(encoded(package).json().utf8).write(
        to: root.appendingPathComponent(slug + ".sevraapp"))
      func snapshot(_ workbook: Workbook) throws -> Value {
        .array(
          try conversion.datasetIDs.map { id in
            var rows: [Value] = []
            while true {
              let page = try workbook.tablePage(id, offset: rows.count, limit: 200)
              rows.append(contentsOf: page.values.map(Value.object))
              if rows.count == page.total { return .array(rows) }
              try require(
                !page.values.isEmpty && rows.count < page.total, "test", "Invalid page boundary.")
            }
          })
      }
      func rowVersions() throws -> [[String]] {
        try conversion.datasetIDs.map { id in
          var versions: [String] = []
          while true {
            let page = try book.tablePage(id, offset: versions.count, limit: 200)
            versions += page.rows.map(\.id)
            if versions.count == page.total { return versions }
            try require(!page.rows.isEmpty, "test", "Incomplete immutable row snapshot.")
          }
        }
      }
      // Exercise held-out inputs through actual persistence, and compare every formula.
      let original = try book.excelOriginalSheets(source.id)
      let held = try ExtractionWorker().readTable(
        fixtures.appendingPathComponent(example["files"].array[2].text), format: .xlsx
      ).sheets
      let beforeHeld = try snapshot(book)
      func applyInputs(_ sheets: [ImportedSheet], comparedWith others: [ImportedSheet]) throws {
        for (index, sheet) in sheets.enumerated() {
          let rows = try book.tablePage(conversion.datasetIDs[index]).rows
          for (position, row) in sheet.rows.enumerated() {
            var changed: [String: Value] = [:]
            for (column, text) in row.enumerated() {
              let coordinate = XLSX.cellName(column: column, row: sheet.rowNumbers[position])
              if sheet.formulas[coordinate] == nil && text != others[index].rows[position][column] {
                changed["c\(column + 1)"] = .string(text)
              }
            }
            if !changed.isEmpty { _ = try book.editRow(rows[position].id, values: changed) }
          }
        }
      }
      try applyInputs(held, comparedWith: original)
      for (index, sheet) in held.enumerated() {
        let actual = try book.tablePage(conversion.datasetIDs[index]).values
        for coordinate in sheet.formulas.keys {
          let address = SheetFormulaToken.address(coordinate)!
          let position = sheet.rowNumbers.firstIndex(of: address.row)!
          try require(
            Workbook.sameExcelResult(
              actual[position]["c\(address.column + 1)"]!.text,
              sheet.rows[position][address.column]), "heldout",
            "Held-out result differs: " + sheet.name + "!" + coordinate)
        }
      }
      try applyInputs(original, comparedWith: held)
      try expectEqual(try snapshot(book), beforeHeld)
      result["heldoutPassed"] = .bool(true)
      let active = NativeAppSession(book: book, space: space, defaults: defaults)
      session = active
      // Durable human confirmation precedes execution; the model cannot grant itself access.
      let approval = try book.prepareChatApproval(
        action: "app.enable",
        arguments: .object([
          "id": .string(space.id), "expectedVersion": .number(Double(space.version)),
        ]),
        title: "Enable " + space.title, conversation: "main")
      let confirmation = try book.addMessage("Confirm", role: "user")
      try expectEqual(
        try book.claimChatApproval(conversation: "main", messageID: confirmation).id, approval)
      _ = try await active.businessCommand("enable")
      result["catalog"] = try await active.businessCommand("inspect")
      var undoExpected: Value?
      var receiptAction: Value?
      var successfulCalls: [Int: Value] = [:]
      for (step, journey) in example["journeys"].array.enumerated() {
        let before = try snapshot(book)
        let beforeVersions = try rowVersions()
        var namedCalls: [(arguments: Value, result: Value)] = []
        var request = journey["request"].text
        if let file = journey["inputFile"].string {
          let supplied = try captureReference(fixtures.appendingPathComponent(file))
          request +=
            " Supplied file: " + supplied.title + "; source ID: " + supplied.id
            + ". Read this file to obtain the prices."
        }
        let answer = try await WorkbookAgent.run(
          request, workbook: book,
          context: "Active app: " + space.title + ". Active space ID: " + space.id + "\n"
            + ChatOperations.appOperationGuidance,
          modelDirectory: URL(fileURLWithPath: modelsRoot), model: model, enableCompaction: false,
          workspaceAction: { action, arguments, readOnly, cancellation in
            _ = try ChatOperations.validate(action, arguments: arguments, readOnly: readOnly)
            let target = try book.spaceTarget(arguments["id"].text)
            try require(
              target.id == space.id && action.hasPrefix("app."), "test", "Unexpected host action.")
            if !["app.inspect", "app.browse"].contains(action) {
              try expectEqual(arguments["expectedVersion"].int, space.version)
            }
            let result = try await active.businessCommand(
              String(action.dropFirst(4)), arguments: arguments,
              readOnly: readOnly, cancellation: cancellation)
            if action == "app.run" { namedCalls.append((arguments, result)) }
            return result
          })
        let after = try snapshot(book)
        let finalMessage = try expectValue(book.messages().last { $0.role == "assistant" })
        let completion = try book.messagePayload(finalMessage.id)
        let currentApp = try book.space(space.id)
        try expectEqual(currentApp.version, space.version)
        try expectEqual(currentApp.definition.app?.digest, package.digest)
        journeys.append(
          .object([
            "step": .number(Double(step)), "request": .string(request),
            "answer": .string(answer.answer), "state": after,
            "completion": completion,
          ]))
        try Data(Value.array(journeys).json().utf8).write(
          to: root.appendingPathComponent(slug + "-journeys.json"), options: .atomic)
        if journey["unchanged"] == .bool(true) {
          try expectEqual(after, before)
          try expectEqual(try rowVersions(), beforeVersions)
          try require(
            namedCalls.allSatisfy { $0.result["changes"].array.isEmpty },
            "journey", "A refused request must not commit a write and then undo it.")
          if journey["clarification"] == .bool(true) {
            try require(
              namedCalls.isEmpty
                && !answer.answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              "journey", "Missing business values must be requested before invoking an action.")
            result["clarificationAnswer"] = .string(answer.answer)
          }
        } else {
          try require(
            completion["unresolvedActionFailure"] == .bool(false)
              && completion["arguments"]["basis"] == .string("completed_action"),
            "journey",
            "A saved action must finish with a truthful completion, without a stale failure.")
          let index = example["sheets"].array.firstIndex(of: journey["sheet"])!
          func fields(_ value: Value) -> Value {
            .object(Dictionary(uniqueKeysWithValues: value.object.map {
              ("c\(Int($0.key.utf8.first!) - 64)", $0.value)
            }))
          }
          try checkBusinessSavedEffect(
            before: before, after: after,
            expected: .object([
              "sheet": .number(Double(index)), "match": fields(journey["match"]),
              "values": fields(journey["values"]),
            ]), original: original)
          let committed = namedCalls.filter {
            $0.result["outcome"] == .string("completed")
              && !$0.result["changes"].array.isEmpty
          }
          try require(
            !committed.isEmpty, "journey", "No named app action committed the requested change.")
          try require(
            committed.count == 1 && committed[0].result["changes"].array.count == 1,
            "journey", "This scenario requires one atomic business transaction.")
          for value in journey["argumentValues"].array {
            try require(
              committed[0].arguments["inputs"].object.values.contains {
                Workbook.sameExcelResult($0.text, value.text)
              }, "journey",
              "The named action changed the requested argument convention instead of accepting the person's value."
            )
          }
          successfulCalls[step] = committed[0].arguments
          undoExpected = before
          if slug == "stock", step == 0 { receiptAction = committed[0].arguments }
          if after.array[index].array.count > before.array[index].array.count {
            // A second direct invocation must hit the SAME saved business rule.
            // A conversational refusal alone cannot prove duplicate validation.
            let repeated = try await active.businessCommand(
              "run", arguments: committed[0].arguments)
            try expectEqual(repeated["outcome"], .string("failed"))
            try expectEqual(try snapshot(book), after)
          }
        }
        try expectEqual(try snapshot(Workbook(book.url)), after)
        print(slug + " journey \(step + 1): " + answer.answer)
      }
      let undone = try await active.businessCommand("undo")
      try expectEqual(undone["outcome"], .string("completed"))
      try require(undoExpected != nil, "journey", "No business operation was saved.")
      try expectEqual(try snapshot(book), undoExpected!)
      journeys.append(.object(["step": .string("undo"), "state": try snapshot(book)]))
      try Data(Value.array(journeys).json().utf8).write(
        to: root.appendingPathComponent(slug + "-journeys.json"), options: .atomic)
      try expectEqual(try snapshot(Workbook(book.url)), try snapshot(book))
      try expectEqual(try book.space(space.id).definition.app!.digest, package.digest)
      if slug == "stock", let receiptAction {
        // Grow through the generated action itself, then challenge a duplicate
        // beyond page one. No source edits or bypass writes prepare this case.
        let before = try snapshot(book)
        let inputs = receiptAction["inputs"].object
        try require(
          inputs.values.filter { $0 == .string("TEST-R1") }.count == 1,
          "test", "Receipt input must retain the requested reference.")
        var last: Value = .null
        for index in 0..<205 {
          var arguments = receiptAction.object
          arguments["inputs"] = .object(
            inputs.mapValues { value in
              value == .string("TEST-R1") ? .string("LOAD-\(index)") : value
            })
          last = .object(arguments)
          let saved = try await active.businessCommand("run", arguments: last)
          try require(
            saved["outcome"] == .string("completed") && saved["changes"].array.count == 1,
            "journey", "The unchanged generated receipt action failed while the ledger grew.")
        }
        let after = try snapshot(book)
        try expectEqual(after.array[1].array.count, before.array[1].array.count + 205)
        let duplicate = try await active.businessCommand("run", arguments: last)
        try expectEqual(duplicate["outcome"], .string("failed"))
        try expectEqual(try snapshot(book), after)
        try expectEqual(try snapshot(Workbook(book.url)), after)
        journeys.append(.object(["step": .string("paged-growth"), "state": after]))
        try Data(Value.array(journeys).json().utf8).write(
          to: root.appendingPathComponent(slug + "-journeys.json"), options: .atomic)
        result["pagedGrowthRecords"] = .number(205)
      }
      let validation = try Value.parse(
        String(contentsOf: fixtures.appendingPathComponent("adversarial.json"), encoding: .utf8)
      )[slug].array
      try require(!validation.isEmpty, "validation_probe", "Missing business validation probes.")
      journeys += try await checkBusinessValidation(
        probes: validation, calls: successfulCalls, session: active, original: original,
        snapshot: { try snapshot(book) }, versions: rowVersions)
      try Data(Value.array(journeys).json().utf8).write(
        to: root.appendingPathComponent(slug + "-journeys.json"), options: .atomic)
      result["invalidDirectCases"] = .number(
        Double(
          validation.reduce(0) {
            $0 + $1["invalid"].array.reduce(0) { $0 + $1["values"].array.count }
          }))
      result["invalidRecoveryCases"] = result["invalidDirectCases"]
      try expectEqual(try book.space(space.id).version, space.version)
      try expectEqual(try book.space(space.id).definition.app?.digest, package.digest)
      let beforeRebuild = try snapshot(book)
      let rebuild = try book.prepareExcelConversionBuild(conversion.id)
      _ = try book.installExcelConversionApp(
        package, build: rebuild,
        check: .object([
          "scope": .string("Unchanged-source publication regression after ledger growth")
        ]),
        token: identifier(), cancellation: .init())
      try expectEqual(try snapshot(book), beforeRebuild)
      try expectEqual(try book.space(space.id).definition.app!.digest, package.digest)
      result["unchangedSourceRebuildPassed"] = .bool(true)
      let archive = root.appendingPathComponent(slug + ".sevraz")
      try book.export(to: archive)
      let copy = try Workbook.openArchive(
        archive, at: root.appendingPathComponent(slug + "-copy.sevra"))
      try expectEqual(try snapshot(copy), try snapshot(book))
      try expectEqual(try copy.verify()["ok"], .bool(true))
      result["passed"] = .bool(true)
    } catch {
      if let pendingBuild {
        _ = try? book.updateExcelConversion(
          pendingBuild.id, expectedVersion: pendingBuild.version, state: "needs_attention",
          failure: error.localizedDescription)
      }
      result["passed"] = .bool(false)
      result["error"] = .string(error.localizedDescription)
    }
    session?.stop()
    result["seconds"] = .number(Date().timeIntervalSince(started))
    results.append(.object(result))
    try Data(Value.array(results).json().utf8).write(
      to: root.appendingPathComponent("results.json"), options: .atomic)
    try Data(encoded(book.messages(limit: 1000)).json().utf8).write(
      to: root.appendingPathComponent(slug + "-messages.json"))
    print(try Value.object(result).json())
  }
  try require(
    results.allSatisfy { $0["passed"] == .bool(true) }, "business_probe",
    "Inspect retained business trial failures.")
}
