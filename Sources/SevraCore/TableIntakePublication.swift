import Foundation

extension Workbook {
  public func proposeTableUpdate(
    sourceID: String, datasetID: String, mode: TableUpdateMode,
    mapping: [IntakeColumnMapping], keys: [String] = [], headerRow: Int = 1, sheet: String? = nil,
    newRowMeaning: String, newRowScenario: String,
    expectedRevision: Int, expectedFingerprint: String,
    intakeID: String? = nil,
    token: String = UUID().uuidString, cancellation: Cancellation = .init()
  ) throws -> Item {
    var fields: [String: Value] = [
      "source": .string(sourceID), "dataset": .string(datasetID), "mode": .string(mode.rawValue),
      "mapping": try encoded(mapping), "keys": .array(keys.map(Value.string)),
      "headerRow": .number(Double(headerRow)), "meaning": .string(newRowMeaning),
      "scenario": .string(newRowScenario), "revision": .number(Double(expectedRevision)),
      "fingerprint": .string(expectedFingerprint),
      "intakeID": intakeID.map(Value.string) ?? .null,
    ]
    if let sheet { fields["sheet"] = .string(sheet) }
    let request: Value = .object(fields)
    // Receipt lookup precedes parsing: retry must work after an original disappears
    // or after acceptance changes the target. The transactional check repeats below.
    if let prior = try synchronized({
      try db.execute("SELECT kind,request,result FROM operations WHERE id=?", [.string(token)])
        .first
    }) {
      try require(
        prior["kind"]?.text == "propose_table_update" && prior["request"]?.text == request.json(),
        "idempotency", "The operation identifier was reused with different arguments.")
      return try item(Value.parse(prior["result"]!.text).text)
    }
    try require(
      ["actual", "estimate", "plan", "commitment", "assumption", "rule"].contains(newRowMeaning)
        && !newRowScenario.isEmpty && newRowScenario.utf8.count <= 256,
      "update_meaning", "Choose the meaning and scenario for new rows explicitly.")
    let plan = try tableUpdatePlan(
      sourceID: sourceID, datasetID: datasetID, mode: mode,
      mapping: mapping, keys: keys, headerRow: headerRow, sheet: sheet,
      cancellation: cancellation)
    try require(
      plan.preview.revision == expectedRevision && plan.preview.fingerprint == expectedFingerprint,
      "stale_revision", "The target or workbook changed after preview. Review a fresh preview.")
    try require(
      plan.preview.added + plan.preview.changed + plan.preview.removed > 0,
      "update_unchanged", "The reviewed input makes no working changes.")
    return try mutation(
      "propose_table_update", token: token, request: request,
      expected: expectedRevision, cancellation: cancellation,
      reading: { try item($0.text) }
    ) {
      try require(
        try tableFingerprint(datasetID) == expectedFingerprint, "stale_revision",
        "The target changed. Review it again.")
      if let intakeID {
        let job = try intakeJob(intakeID)
        try require(
          job.sourceID == sourceID && job.role == .update && job.state == "awaiting_update",
          "intake_update", "Choose a pending update intake for this original.")
      }
      let proposal = try insertTableUpdatePlan(
        plan, newRowMeaning: newRowMeaning, newRowScenario: newRowScenario,
        cancellation: cancellation)
      try removeTableUpdateDraft(sourceID)
      if let intakeID {
        var report = try intakeJob(intakeID).report.object
        report["conversion"] = .string("proposed_update")
        report["proposalID"] = .string(proposal)
        try db.execute(
          "UPDATE intake_jobs SET state='ready',attempt=NULL,report=?,dataset_ids=?,detail=?,updated=? WHERE id=?",
          [
            .string(try Value.object(report).json()),
            .string(try Value.array([.string(datasetID)]).json()),
            .string("Update draft created for review. No working table changes have been applied."),
            .string(timestamp()), .string(intakeID),
          ])
      }
      return .string(proposal)
    }
  }

  /// Shared insertion body. The caller owns the transaction, exact retry receipt
  /// and final cancellation/lease guard. No parser or file I/O occurs here.
  func insertTableUpdatePlan(
    _ plan: TableUpdatePlan, newRowMeaning: String, newRowScenario: String,
    workflow: Value? = nil, additionalInputs: [String] = [], controlInputs: [String] = [],
    producerInputs: [String] = [], cancellation: Cancellation
  ) throws -> String {
    try cancellation.check()
    let preview = plan.preview
    try require(
      ["actual", "estimate", "plan", "commitment", "assumption", "rule"].contains(newRowMeaning)
        && !newRowScenario.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && newRowScenario.utf8.count <= 256,
      "update_meaning", "Choose the meaning and scenario for new rows explicitly.")
    try require(
      try tableFingerprint(preview.datasetID) == preview.fingerprint, "stale_revision",
      "The target changed. Review it again.")
    try require(
      preview.added + preview.changed + preview.removed > 0,
      "update_unchanged", "The reviewed input makes no working changes.")
    let table = try dataset(preview.datasetID)
    var data: [String: Value] = [
      "version": .number(1), "sourceID": .string(preview.sourceID),
      "datasetID": .string(preview.datasetID), "mode": .string(preview.mode.rawValue),
      "preview": try encoded(preview), "changes": try encoded(plan.changes),
      "additions": .array(plan.additions.map(Value.object)),
      "changeRecords": try encoded(plan.changeRecords),
      "additionRecords": try encoded(plan.additionRecords),
      "newRowMeaning": .string(newRowMeaning), "newRowScenario": .string(newRowScenario),
    ]
    if let workflow {
      data["workflow"] = workflow
      // Retain all mapped rows, including exact matches that cause no edits.
      // Original bytes and explicit mappings preserve ignored source columns.
      data["incoming"] = .array(plan.incoming.map(Value.object))
    }
    let text =
      "\(preview.mode.rawValue.capitalized) into \(table.title): \(preview.added) added, \(preview.changed) changed, \(preview.removed) removed, \(preview.unchanged) matched rows unchanged.\n"
      + "\(preview.repeatedIncomingRows) repeated incoming rows; \(preview.rowsMatchingTarget) incoming rows exactly match existing values.\n"
      + "New rows: \(newRowMeaning), scenario \(newRowScenario).\n"
      + preview.limitations.joined(separator: "\n")
    return try insertItem(
      category: "record", kind: "table-intake-update",
      title: "Review \(preview.mode.rawValue): \(table.title)", text: text,
      data: .object(data), meaning: "plan", status: "draft", scenario: "actual",
      inputs: [preview.sourceID] + plan.membership.map { $0["item_id"].text } + additionalInputs,
      transformation: "proposed-table-intake-v1",
      controlInputs: [try datasetDefinition(preview.datasetID).sourceID] + controlInputs,
      producerInputs: producerInputs)
  }

  /// Called only within the acceptance transaction. No parser or external effect runs here.
  func applyTableIntake(_ proposal: Item, decision: String, cancellation: Cancellation) throws
    -> Value
  {
    let data = proposal.data
    guard data["version"].int == 1, let mode = TableUpdateMode(rawValue: data["mode"].text) else {
      throw SevraError("update_definition", "Unsupported table-update definition.")
    }
    let datasetID = data["datasetID"].text
    try require(
      try tableFingerprint(datasetID) == data["preview"]["fingerprint"].text,
      "stale_revision", "The table changed after review. Create a fresh update proposal.")
    let table = try dataset(datasetID)
    let changes = try JSONDecoder().decode([RowEdit].self, from: Data(data["changes"].json().utf8))
    let additions = data["additions"].array.map(\.object)
    let additionRecords = try JSONDecoder().decode(
      [Int].self, from: Data(data["additionRecords"].json().utf8))
    let changeRecords = try JSONDecoder().decode(
      [String: Int].self, from: Data(data["changeRecords"].json().utf8))
    try require(
      additionRecords.count == additions.count && additionRecords.allSatisfy { $0 > 0 }
        && Set(changeRecords.keys) == Set(changes.map(\.id))
        && changeRecords.values.allSatisfy { $0 > 0 },
      "update_definition", "Missing source record coordinates.")
    try require(
      changes.count + additions.count <= 1000 && Set(changes.map(\.id)).count == changes.count
        && (mode == .merge || changes.isEmpty), "update_definition",
      "Invalid table-update row plan.")
    let stored = Set(table.columns.filter { $0.formula == nil }.map(\.id))
    let meaning = data["newRowMeaning"].text
    let scenario = data["newRowScenario"].text
    try require(
      ["actual", "estimate", "plan", "commitment", "assumption", "rule"].contains(meaning)
        && !scenario.isEmpty && scenario.utf8.count <= 256,
      "update_meaning", "Invalid meaning or scenario for incoming rows.")
    let source = try item(data["sourceID"].text)
    try require(
      source.category == "source" && source.assetID != nil, "intake_source",
      "The captured source is missing.")
    let before = try tableMembership(datasetID)
    let currentIDs = Set(before.map { $0["item_id"].text })
    var versions: [Value] = []
    let inputs = [source.id, proposal.id, decision]
    try prepareManagedRowEdits(datasetID, exactIDs: changes.map(\.id))
    for edit in changes {
      try cancellation.check()
      try require(
        currentIDs.contains(edit.id), "stale_revision",
        "A changed row is not in the reviewed table.")
      let old = try item(edit.id)
      try require(
        Set(edit.values.keys).isSuperset(of: stored), "update_mapping",
        "Every stored column must have a reviewed value.")
      try validateValues(edit.values, columns: table.columns)
      for column in table.columns where column.formula != nil {
        try require(
          edit.values[column.id] == old.data.object[column.id], "calculated_cell",
          "Calculated cells cannot be overwritten.")
      }
      let next = try intakeRowVersion(
        old, values: .object(edit.values), status: old.status,
        inputs: inputs,
        transformation: "table-intake-merge-v1;source-record=\(changeRecords[edit.id]!)")
      versions.append(.object(["before": .string(old.id), "after": .string(next)]))
    }
    if mode == .replace {
      for member in before {
        try cancellation.check()
        let old = try item(member["item_id"].text)
        let next = try intakeRowVersion(
          old, values: old.data, status: "rejected", inputs: inputs,
          transformation: "table-intake-replace-v1")
        versions.append(.object(["before": .string(old.id), "after": .string(next)]))
      }
      try clearDatasetMembers(datasetID)
    }
    var ordinal =
      (try db.scalar(
        "SELECT max(ordinal) FROM dataset_rows WHERE dataset_id=?", [.string(datasetID)]
      ).int ?? -1) + 1
    for (index, values) in additions.enumerated() {
      try cancellation.check()
      try require(
        Set(values.keys) == stored, "update_mapping", "Incoming rows must map every stored column.")
      try validateValues(values, columns: table.columns)
      let id = try insertItem(
        category: "record", kind: "row",
        title: "\(table.title.prefix(500)), imported row \(ordinal + 1)",
        text: rowDescription(values), data: .object(values), meaning: meaning,
        status: "accepted", scenario: scenario,
        inputs: inputs,
        transformation: "table-intake-add-v1;source-record=\(additionRecords[index])",
        controlInputs: [try datasetDefinition(datasetID).sourceID])
      try insertDatasetMember(datasetID, ordinal: ordinal, logicalID: try item(id).logicalID)
      versions.append(.object(["before": .null, "after": .string(id)]))
      ordinal += 1
    }
    var accepted = data.object
    accepted["beforeMembership"] = .array(before)
    accepted["afterMembership"] = .array(try tableMembership(datasetID))
    accepted["rowVersions"] = .array(versions)
    accepted["afterFingerprint"] = .string(try tableFingerprint(datasetID))
    return .object(accepted)
  }

  func rowDescription(_ values: [String: Value]) -> String {
    values.sorted { $0.key < $1.key }.map { "\($0.key): \($0.value.text)" }.joined(separator: "\n")
  }

  func intakeRowVersion(
    _ old: Item, values: Value, status: String, inputs: [String], transformation: String
  ) throws -> String {
    try insertItem(
      category: "record", kind: old.kind, title: old.title,
      text: rowDescription(values.object), data: values, meaning: old.meaning,
      status: status, scenario: old.scenario, inputs: [old.id] + inputs,
      transformation: transformation, supersedes: old.id)
  }
}
