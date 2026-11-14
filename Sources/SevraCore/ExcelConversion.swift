import CryptoKit
import Foundation

/// One durable draft over an immutable Excel original. Working tables are shared with the
/// workbook, never copied into app code. Every transition is a captured current-format change.
public struct ExcelConversion: Identifiable, Sendable {
  public let record: Item
  public var id: String { record.logicalID }
  public var version: String { record.id }
  public var sourceID: String { record.data["sourceID"].text }
  public var state: String { record.data["state"].text }
  public var inspection: Value { record.data["inspection"] }
  public var plan: Value { record.data["plan"] }
  public var purpose: String { record.data["purpose"].text }
  public var datasetIDs: [String] { record.data["datasets"].array.map(\.text) }
  public var appID: String? { record.data["appID"].string }
  public var failure: String? { record.data["failure"].string }
  public var appMatchesPlan: Bool {
    appID != nil && record.data["appPlan"] == plan && record.data["appPurpose"].string == purpose
      && record.data["appExamples"] == record.data["examples"]
  }
}

/// A native host captures this capability after the person requests a build. No tool
/// argument, imported text or model-produced plan can manufacture or expand it.
public struct ExcelConversionBuild: Sendable {
  let physicalID: String
  let workbookID: String
  public let conversionID: String
  public let conversionVersion: String
  public let sourceID: String
  public let tables: [Dataset]
  public let appVersion: Int?
  public let context: String
  public let request: String
  public let displayRequest: String
}

extension Workbook {
  private func excelRowIdentity(_ dataset: String) throws -> String {
    let rows = try db.execute(
      "SELECT logical_id FROM dataset_rows WHERE dataset_id=? ORDER BY ordinal",
      [.string(dataset)]
    ).map { $0["logical_id"]!.text }
    return SHA256.hash(data: Data(try encoded(rows).json().utf8)).map { String(format: "%02x", $0) }
      .joined()
  }
  private func validateExcelRows(_ conversion: ExcelConversion) throws {
    for table in conversion.datasetIDs {
      try require(
        conversion.record.data["rowIdentities"][table] == .string(excelRowIdentity(table)),
        "excel_rows",
        "The original worksheet rows changed. Restore their structure or import a new original before rebuilding."
      )
    }
  }
  public func excelConversionSummaries() throws -> [Value] {
    try synchronized {
      try db.execute(
        "SELECT i.logical_id AS id,i.title,json_extract(i.data,'$.state') AS state FROM items i JOIN heads h ON h.item_id=i.id WHERE i.kind='excel-conversion' ORDER BY i.created DESC LIMIT 100"
      ).map { .object($0) }
    }
  }

  public func excelConversion(_ id: String) throws -> ExcelConversion {
    let record = try item(id)
    try require(record.kind == "excel-conversion", "excel_conversion", "Choose an Excel import.")
    let data = record.data
    let sheets = data["inspection"]["sheets"].array
    guard case .array(let datasets) = data["datasets"],
      case .array = data["inspection"]["sheets"]
    else { throw SevraError("excel_conversion", "This saved Excel import is malformed.") }
    try require(
      data["sourceID"].string?.isEmpty == false
        && [
          "inspected", "analyzing", "review", "importing", "building", "tables", "needs_attention",
          "ready",
        ].contains(data["state"].text)
        && data["purpose"].string != nil && data["purpose"].text.utf8.count <= 4000
        && datasets.count <= 100 && datasets.allSatisfy { $0.string?.isEmpty == false }
        && Set(datasets.map(\.text)).count == datasets.count
        && sheets.count <= 100 && data["inspection"].json().utf8.count <= 256_000
        && sheets.enumerated().allSatisfy { index, sheet in
          sheet["index"].int == index && sheet["name"].string != nil
            && sheet["rows"].int.map { $0 >= 0 && $0 <= 100_000 } == true
        }
        && (data["appID"] == .null || data["appID"].string == record.logicalID),
      "excel_conversion",
      "This saved Excel import is malformed. Its original file is still available.")
    if data["plan"] != .null { try Self.validateExcelPlan(data["plan"]) }
    if data["examples"] != .null {
      guard case .array(let examples) = data["examples"] else {
        throw SevraError("excel_example", "The saved comparison examples are malformed.")
      }
      try require(
        examples.count <= 12
          && examples.allSatisfy { reference in
            guard case .object = reference["arguments"] else { return false }
            return reference["sourceID"].string?.isEmpty == false
              && reference["sourceID"].text.utf8.count <= 256
              && reference["action"].text.range(
                of: "^[a-z][a-zA-Z0-9_]{0,63}$", options: .regularExpression) != nil
              && reference["arguments"].object.count <= 32
              && (try? reference["arguments"].json().utf8.count <= 8192) == true
          }, "excel_example", "The saved comparison examples are malformed.")
    }
    return ExcelConversion(record: record)
  }

  public func excelConversions() throws -> [ExcelConversion] {
    try synchronized {
      try db.execute(
        "SELECT i.id FROM items i JOIN heads h ON h.item_id=i.id WHERE i.kind='excel-conversion' ORDER BY i.created DESC LIMIT 100"
      ).map { try excelConversion($0["id"]!.text) }
    }
  }

  public func beginExcelConversion(
    sourceID: String, cancellation: Cancellation = .init()
  ) throws -> ExcelConversion {
    try cancellation.check()
    let source = try item(sourceID)
    guard source.category == "source", let assetID = source.assetID else {
      throw SevraError("excel_source", "Choose an included Excel file.")
    }
    let original = try asset(assetID)
    try require(
      ["xlsx", "xlsm"].contains(URL(fileURLWithPath: original.name).pathExtension.lowercased()),
      "excel_format",
      "Choose an .xlsx or .xlsm workbook. Original macro source is inspected, never executed."
    )
    // Re-adding identical bytes resumes their conversion, even if capture created another
    // evidence Source. Changed files have a different hash and a separate review.
    if let id = try synchronized({
      try db.scalar(
        "SELECT i.id FROM items i JOIN heads h ON h.item_id=i.id WHERE i.kind='excel-conversion' AND json_extract(i.data,'$.originalHash')=? LIMIT 1",
        [.string(original.hash)]
      ).string
    }) {
      return try excelConversion(id)
    }
    let sheets = try ExtractionWorker().readTable(
      assetURL(assetID, verify: true, cancellation: cancellation), format: .xlsx,
      cancellation: cancellation
    ).sheets
    _ = try assetURL(assetID, verify: true, cancellation: cancellation)
    var inspectionFields = Self.excelInspection(sheets).object
    let evidence = try excelSourceEvidence(source.id, cancellation: cancellation)
    inspectionFields["evidence"] = .array(
      evidence.map {
        .object([
          "id": .string($0.id), "kind": .string($0.kind), "complete": .bool($0.complete),
          "characters": .number(Double($0.text.count)),
        ])
      })
    let inspection = Value.object(inspectionFields)
    try cancellation.check()
    let saved = try addHostOwnedItem(
      category: "record", kind: "excel-conversion", title: source.title,
      text: "Excel import: original preserved; workflow interpretation awaits review.",
      data: .object([
        "sourceID": .string(source.id), "originalHash": .string(original.hash),
        "state": .string("inspected"), "inspection": inspection,
        "plan": .null, "purpose": .string(""), "datasets": .array([]),
      ]), status: "accepted", inputs: [source.id], transformation: "excel-conversion-v1",
      token: "excel-conversion:" + original.hash)
    return ExcelConversion(record: saved)
  }

  private static func excelInspection(_ sheets: [ImportedSheet]) -> Value {
    var budget = 32_000
    var noteBudget = 16_000
    func text(_ value: String, limit: Int = 600) -> Value {
      let result = String(value.prefix(min(limit, max(0, budget))))
      budget -= result.utf8.count
      return .string(result)
    }
    let summaries: [Value] = sheets.enumerated().map { index, sheet in
      var notes: [Value] = []
      for note in sheet.notes {
        if noteBudget <= 0 {
          notes.append(
            .string("More structure details exist in the original; this inspection is bounded."))
          break
        }
        let bounded = String(note.prefix(min(700, noteBudget)))
        noteBudget -= bounded.utf8.count
        notes.append(.string(bounded))
      }
      let sample: [Value] = sheet.rows.prefix(8).enumerated().map { offset, cells in
        .object([
          "row": .number(Double(sheet.rowNumbers[offset])),
          "cells": .array(cells.prefix(16).map { text($0, limit: 160) }),
        ])
      }
      return .object([
        "index": .number(Double(index)), "name": text(sheet.name),
        "rows": .number(Double(sheet.rows.count)),
        "columns": .number(Double(sheet.rows.map(\.count).max() ?? 0)),
        "formulaCount": .number(Double(sheet.formulas.count)),
        "formulas": .array(
          sheet.formulas.sorted { $0.key < $1.key }.prefix(12).map {
            .object(["cell": .string($0.key), "expression": text($0.value)])
          }),
        "unsettledCells": .number(Double(sheet.unsettled.count)),
        "sample": .array(sample), "notes": .array(notes),
      ])
    }
    return .object([
      "sheets": .array(summaries), "sampled": .bool(true),
      "notice": .string(
        "Samples are bounded. The original includes deeper evidence of formulas, layout, validation, charts and macro source when readable. Recreated behavior is compared with saved original results; untested rules and external services need explicit review."
      ),
    ])
  }

  public func readExcelConversionRange(
    _ id: String, sheet: Int, offset: Int, limit: Int, cancellation: Cancellation = .init()
  ) throws -> Value {
    try require(
      sheet >= 0 && offset >= 0 && (1...30).contains(limit), "excel_range",
      "Choose a worksheet and 1 to 30 rows.")
    let conversion = try excelConversion(id)
    let original = try item(conversion.sourceID)
    guard let assetID = original.assetID else {
      throw SevraError("excel_source", "The Excel original is unavailable.")
    }
    let sheets = try ExtractionWorker().readTable(
      assetURL(assetID, verify: true, cancellation: cancellation), format: .xlsx,
      cancellation: cancellation
    ).sheets
    _ = try assetURL(assetID, verify: true, cancellation: cancellation)
    try require(sheets.indices.contains(sheet), "excel_range", "That worksheet does not exist.")
    let selected = sheets[sheet]
    let start = min(offset, selected.rows.count)
    let end = min(selected.rows.count, start + limit)
    var remaining = 20_000
    let rows: [Value] = (start..<end).map { index in
      .object([
        "row": .number(Double(selected.rowNumbers[index])),
        "cells": .array(
          selected.rows[index].prefix(24).map {
            let value = String($0.prefix(min(400, max(0, remaining))))
            remaining -= value.utf8.count
            return .string(value)
          }),
      ])
    }
    let rowNumbers = Set(selected.rowNumbers[start..<end])
    let formulas = selected.formulas.filter { entry in
      let row = Int(entry.key.drop(while: { $0.isLetter }))
      return row.map { rowNumbers.contains($0) } ?? false
    }.sorted { $0.key < $1.key }.prefix(30)
    return .object([
      "sheet": .string(selected.name), "offset": .number(Double(start)),
      "totalRows": .number(Double(selected.rows.count)),
      "rows": .array(rows),
      "formulas": .object(
        Dictionary(
          uniqueKeysWithValues: formulas.map { ($0.key, .string(String($0.value.prefix(600)))) })),
      "bounded": .bool(true),
    ])
  }

  @discardableResult public func updateExcelConversion(
    _ id: String, expectedVersion: String, state: String, purpose: String? = nil,
    plan: Value? = nil, failure: String? = nil
  ) throws -> ExcelConversion {
    try require(
      ["inspected", "analyzing", "review", "importing", "building", "tables", "needs_attention"]
        .contains(state),
      "excel_state", "Invalid Excel import transition.")
    return try synchronized {
      let previous = try excelConversion(id)
      try require(
        previous.version == expectedVersion, "stale_revision",
        "This import changed. Refresh before continuing.")
      var data = previous.record.data.object
      data["state"] = .string(state)
      data["failure"] = failure.map { .string(String($0.prefix(2000))) } ?? .null
      if let purpose {
        try require(
          purpose.utf8.count <= 4000, "excel_purpose", "Please shorten the workflow description.")
        data["purpose"] = .string(purpose)
      }
      if let plan {
        try Self.validateExcelPlan(plan)
        data["plan"] = plan
      }
      let saved = try addHostOwnedItem(
        category: "record", kind: "excel-conversion", title: previous.record.title,
        text: "Excel import: " + state, data: .object(data), status: "accepted",
        inputs: [previous.record.id, previous.sourceID], transformation: "excel-conversion-v1",
        supersedes: previous.version)
      return ExcelConversion(record: saved)
    }
  }

  public static func validateExcelPlan(_ plan: Value) throws {
    try require(
      Set(plan.object.keys) == ["name", "purpose", "workflows", "questions"], "excel_plan",
      "The workflow description was incomplete. Try again.")
    for key in ["name", "purpose"] {
      try require(
        plan[key].string != nil
          && !plan[key].text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
          && plan[key].text.utf8.count <= (key == "name" ? 160 : 2400), "excel_plan",
        "The workflow description is missing or too long.")
    }
    for key in ["workflows", "questions"] {
      guard case .array(let values) = plan[key] else {
        throw SevraError("excel_plan", "Expected a workflow or question list.")
      }
      try require(
        values.count <= (key == "questions" ? 3 : 6)
          && values.allSatisfy { $0.string != nil && !$0.text.isEmpty && $0.text.utf8.count <= 800 },
        "excel_plan", "The workflow list exceeds its bounds.")
    }
  }

  public func saveExcelConversionPlan(
    _ id: String, expectedVersion: String, plan: Value, model: String
  ) throws -> ExcelConversion {
    let policyText =
      "Sevra Excel planning policy v1. The local model may propose an inferred workflow and questions from an immutable source and the person's clarification. This does not authorize business changes, execution, device access or claims of complete Excel equivalence. The person reviews the proposal before requesting a native workspace."
    let policy = try mutation(
      "excel_planning_policy", token: "sevra-excel-planning-policy-v1",
      request: .string(policyText), actor: .programmatic("Sevra.excelPlanningPolicy"),
      readBack: { value in
        let rule = try self.item(value.text)
        try require(
          rule.id == value.text && self.item(rule.logicalID).id == rule.id
            && rule.text == policyText && rule.status == "accepted" && rule.kind == "rule",
          "excel_policy", "The Excel planning policy changed.")
      },
      {
        .string(
          try insertItem(
            category: "source", kind: "rule", title: "Excel planning policy", text: policyText,
            data: .object([:]), meaning: "rule", status: "accepted", scenario: "actual", inputs: [],
            transformation: "excel-planning-policy-v1"))
      })
    return try ChangeAttribution.$actor.withValue(
      .ai("Sevra.excelPlanning", model: model, policy: policy.text)
    ) {
      try updateExcelConversion(id, expectedVersion: expectedVersion, state: "review", plan: plan)
    }
  }

  /// The deterministic intake token shares one set of tables across retry and both UI choices.
  @discardableResult public func importExcelConversionTables(
    _ id: String, cancellation: Cancellation = .init(),
    progress: (Int, Int) -> Void = { _, _ in }
  ) throws -> ExcelConversion {
    try cancellation.check()
    let conversion = try excelConversion(id)
    let token = "excel-values:" + conversion.sourceID
    let job = try beginIntake(sourceID: conversion.sourceID, role: .values, token: token)
    let result =
      job.state == "ready"
      ? job : try runIntake(job.id, cancellation: cancellation, progress: progress)
    try require(
      result.state == "ready", "excel_import",
      "The data import is incomplete. Resume it before building a workspace.")
    try cancellation.check()
    return try synchronized {
      let current = try excelConversion(id)
      if current.datasetIDs == result.datasetIDs
        && current.record.data["valuesImported"] == .bool(true)
      {
        return current
      }
      var data = current.record.data.object
      data["datasets"] = .array(result.datasetIDs.map(Value.string))
      data["valuesImported"] = .bool(true)
      data["failure"] = .null
      let nonempty = current.inspection["sheets"].array.enumerated().filter {
        ($0.element["rows"].int ?? 0) > 0
      }
      try require(
        nonempty.count == result.datasetIDs.count, "excel_binding",
        "The imported worksheets do not match their inspection. Reopen the original file.")
      data["sheetBindings"] = .object(
        Dictionary(
          uniqueKeysWithValues: zip(nonempty, result.datasetIDs).map {
            (String($0.0.offset), .string($0.1))
          }))
      data["formulaReport"] = result.report["formulas"]
      data["rowIdentities"] = .object(
        try Dictionary(
          uniqueKeysWithValues: result.datasetIDs.map {
            ($0, .string(try excelRowIdentity($0)))
          }))
      data["state"] = .string("tables")
      let saved = try addHostOwnedItem(
        category: "record", kind: "excel-conversion", title: current.record.title,
        text: "Excel data imported; original and formula limitations retained.",
        data: .object(data),
        status: "accepted", inputs: [current.version, current.sourceID],
        transformation: "excel-conversion-v1", supersedes: current.version)
      return ExcelConversion(record: saved)
    }
  }

  public func prepareExcelConversionBuild(_ id: String) throws -> ExcelConversionBuild {
    try synchronized {
      let conversion = try excelConversion(id)
      try Self.validateExcelPlan(conversion.plan)
      try validateExcelRows(conversion)
      let tables = try conversion.datasetIDs.map { try dataset($0) }
      try require(
        !tables.isEmpty && tables.count <= 12 && tables.allSatisfy { !$0.archived }, "excel_build",
        "Import 1 to 12 nonempty worksheets before building. Larger files remain available as tables."
      )
      let current = try spaceIfPresent(conversion.id)
      var logicBudget = 16_000
      let logic: [Value] = try excelSourceEvidence(conversion.sourceID, cancellation: .init())
        .filter { $0.kind == "vba" || !$0.complete }.map { part in
          let text = String(part.text.prefix(max(0, logicBudget)))
          logicBudget -= text.utf8.count
          return .object([
            "id": .string(part.id), "text": .string(text),
            "complete": .bool(part.complete && text == part.text),
          ])
        }
      let bindings = Value.object(
        Dictionary(
          uniqueKeysWithValues: tables.indices.map {
            ("sheet\($0 + 1)", Value.object(["writable": .bool(false)]))
          }))
      let context: Value = .object([
        "original": conversion.inspection, "inferredPlan": conversion.plan,
        "originalLogic": .array(logic),
        "calculationEvidence": try Self.excelCalculationEvidence(
          excelOriginalSheets(conversion.sourceID)),
        "fixtureRowCounts": .object(
          Dictionary(
            uniqueKeysWithValues: tables.enumerated().map {
              ("sheet\($0.offset + 1)", .number(Double($0.element.rowCount)))
            })),
        "userClarification": .string(conversion.purpose),
        "tables": try encoded(tables), "formulaReport": conversion.record.data["formulaReport"],
        "originalResultExamples": conversion.record.data["examples"],
        "packageDatasetTemplate": try encoded(bindings),
        "dataLayout": .string(
          "Rows preserve Excel coordinates, including header rows. Columns c1,c2,… correspond to A,B,…; infer visible field labels from the original cells, but keep the binding schema unchanged. packageDatasetTemplate contains only short aliases with writable flags. Copy it and set writable:true only where requested controls edit inputs. The host fills exact datasetIDs, titles and columns; do not supply these binding fields. Table.table and data.page/transaction use the short sheet1/sheet2 aliases, not dataset IDs. Editing existing input cells recalculates supported formulas; adding rows does not automatically extend Excel formulas."
        ),
        "appID": current.map { .string($0.id) } ?? .null,
        "appVersion": current.map { .number(Double($0.version)) } ?? .null,
      ])
      try require(
        context.json().utf8.count <= 64_000, "excel_build",
        "This workbook has too much structure for one local-model build. Use its imported tables, or import a smaller workbook for the workspace."
      )
      return .init(
        physicalID: try NativeAppAccess.physicalIdentity(self), workbookID: self.id,
        conversionID: conversion.id, conversionVersion: conversion.version,
        sourceID: conversion.sourceID, tables: tables, appVersion: current?.version,
        context: try context.json(),
        request:
          "Create a native workspace for this imported Excel workbook. Copy the supplied packageDatasetTemplate into package.datasets, using short aliases such as sheet1 with ONLY writable flags. The host supplies each exact datasetID, title and columns, so do not supply those fields yourself. Enable writable only for requested input editing. Provide a searchable native table for each sheet, clear workflow labels, and useful controls for the described workflow. Understand and recreate the business application: inputs, calculations, buttons/macros, validations and useful native views. Reuse working built-in formulas; inspect original evidence and translate missing calculations/actions into package.excelBehavior using native_app_sdk. Compare with the original using compare_excel_behavior and repair differences. Do not embed business values or original answers in code. List concrete unresolved behavior in gaps. Do not offer row insertion/deletion on formula worksheets: new rows do not automatically inherit Excel formulas. The native host displays the original and conversion limitations outside the generated interface; do not duplicate that notice in the app. Do not create new datasets, duplicate rows, execute macros or claim full Excel equivalence. Save a checked app for my review. Reviewed inferred workflow: "
          + conversion.plan["purpose"].text + " "
          + conversion.plan["workflows"].array.map(\.text).joined(separator: "; ")
          + ". My clarification: " + conversion.purpose,
        displayRequest: "Build a native workspace from " + conversion.record.title + ".\n"
          + conversion.plan["purpose"].text
          + "\n" + conversion.plan["workflows"].array.map { "• " + $0.text }.joined(separator: "\n")
          + (conversion.purpose.isEmpty ? "" : "\nMy workflow: " + conversion.purpose))
    }
  }

  public func validateExcelConversionPackage(
    _ package: NativeAppPackage, build: ExcelConversionBuild
  ) throws {
    try validateExcelConversionBuild(build)
    let bindings = Array(package.datasets.values)
    try require(
      bindings.count == build.tables.count
        && Set(bindings.compactMap(\.datasetID)) == Set(build.tables.map(\.id)), "excel_binding",
      "Use each imported table exactly once, with its original datasetID. No new or unrelated tables are permitted."
    )
    for table in build.tables {
      let actual = try dataset(table.id)
      try require(
        !actual.archived && actual.definitionID == table.definitionID
          && actual.columns == table.columns
          && bindings.first { $0.datasetID == table.id }?.columns == table.columns, "excel_binding",
        "An imported table schema changed. Refresh the conversion before building.")
    }
    for (index, table) in build.tables.enumerated() {
      try require(
        package.datasets["sheet\(index + 1)"]?.datasetID == table.id,
        "excel_binding", "Preserve the exact worksheet alias order from the host.")
    }
  }

  func validateExcelConversionBuild(_ build: ExcelConversionBuild) throws {
    try require(
      build.workbookID == id && NativeAppAccess.physicalIdentity(self) == build.physicalID,
      "excel_workbook",
      "This build belongs to a different workbook. Start a build in this workbook.")
    let current = try excelConversion(build.conversionID)
    try validateExcelRows(current)
    try require(
      current.version == build.conversionVersion && current.sourceID == build.sourceID,
      "stale_revision", "The Excel conversion changed. Start a fresh build from its current plan.")
  }

  package func installExcelConversionApp(
    _ package: NativeAppPackage, build: ExcelConversionBuild, check: Value,
    token: String, cancellation: Cancellation
  ) throws -> Space {
    let comparison = try compareExcelApplication(
      package, conversionID: build.conversionID, cancellation: cancellation)
    try require(
      comparison["status"] == .string("matched"), "excel_comparison",
      Self.excelComparisonFailure(comparison))
    return try mutation(
      "excel_conversion_app", token: token + ":conversion",
      request: .object([
        "conversion": .string(build.conversionVersion), "package": try encoded(package),
        "check": check,
      ]), cancellation: cancellation, reading: { try space($0.text) },
      {
        try validateExcelConversionPackage(package, build: build)
        try insertNativeApp(package, spaceID: build.conversionID, expectedVersion: build.appVersion)
        let saved = try space(build.conversionID)
        let old = try excelConversion(build.conversionID)
        if let behavior = package.excelBehavior {
          try attachExcelBehavior(behavior, conversion: old)
        }
        var data = old.record.data.object
        data["state"] = .string("ready")
        data["appID"] = .string(saved.id)
        data["appVersion"] = .number(Double(saved.version))
        data["appDigest"] = .string(package.digest)
        data["appPlan"] = old.plan
        data["appPurpose"] = .string(old.purpose)
        data["appExamples"] = old.record.data["examples"]
        data["comparison"] = comparison
        data["check"] = check
        data["failure"] = .null
        _ = try insertItem(
          category: "record", kind: "excel-conversion", title: old.record.title,
          text: "Native workspace saved for access review. Checks cover the reported cases only.",
          data: .object(data), meaning: "actual", status: "accepted", scenario: "actual",
          inputs: [old.version, old.sourceID], transformation: "excel-conversion-v1",
          supersedes: old.version)
        return .string(saved.id)
      })
  }
}
