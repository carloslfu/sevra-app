import Foundation

@testable import SevraCore

func checkWorkflowIntakes(at root: URL) {
  let worker = ExtractionWorker()
  let mapping = [
    IntakeColumnMapping(position: 0, target: "sku"), .init(position: 1, target: "qty"),
  ]
  func fixture(
    _ name: String, mode: String = "merge", text: String = "code,amount\n0012,7\n0013,5\n0014,2\n",
    linked: Bool = false, meaning: String = "estimate"
  ) throws -> (Workbook, Item, Dataset, ApplicationDefinition, WorkflowExecutionSession) {
    let book = try Workbook.create(
      at: root.appendingPathComponent("WorkflowIntake-" + name + ".sevra"), title: name)
    let basis = try book.addItem(category: "source", kind: "observation", title: "Starting values")
    try book.setOpeningBalance(
      subject: "stock", quantity: "20", effective: "2026-01-01", sourceID: basis.id)
    let table = try book.createDataset(
      title: "Parts",
      columns: [
        .init(id: "sku", title: "SKU"), .init(id: "qty", title: "Quantity", type: "decimal"),
      ],
      rows: [
        ["sku": .string("0012"), "qty": .string("4")],
        ["sku": .string("0013"), "qty": .string("5")],
      ],
      sourceID: basis.id)
    let file = root.appendingPathComponent("WorkflowIntake-" + name + ".csv")
    try Data(text.utf8).write(to: file)
    let source = try book.importFile(file, linked: linked)
    let parameter = ActionRegistry.field("file", "Incoming CSV or TSV", "item")
    let intake = try book.saveApplicationDefinition(
      logicalID: identifier(),
      content: .object([
        "kind": .string("intake"), "title": .string("Update parts"),
        "description": .string("Explicit synthetic mapping"),
        "parameters": .array([parameter]),
        "payload": .object([
          "parser": .string("native-v1"), "file": .string("file"),
          "datasetID": .string(table.id), "definitionID": .string(table.definitionID),
          "mode": .string(mode), "mapping": try encoded(mapping),
          "keys": .array(mode == "merge" ? [.string("sku")] : []), "headerRow": .number(1),
          "newRowMeaning": .string(meaning), "newRowScenario": .string("actual"),
        ]),
      ]))
    let workflow = try book.saveApplicationDefinition(
      logicalID: identifier(),
      content: .object([
        "kind": .string("workflow"), "title": .string("Update and review"),
        "description": .string("Synthetic"),
        "parameters": .array([parameter]),
        "payload": .object([
          "readPolicy": .string("latest-at-step"),
          "steps": .array([
            .object([
              "id": .string("import_rows"), "kind": .string("intake"),
              "binding": .object(["mode": .string("exact"), "versionID": .string(intake.id)]),
              "arguments": .object(["file": .object(["parameter": .string("file")])]),
            ]),
            .object([
              "id": .string("review"), "kind": .string("review"), "review": .string("import_rows"),
            ]),
          ]),
        ]),
      ]))
    let run = try book.startWorkflow(
      workflow.id, arguments: .object(["file": .string(source.id)]), token: "start")
    return (book, source, table, intake, try book.authorizeWorkflowExecution(run["id"].text))
  }
  func prepared(_ book: Workbook, _ session: WorkflowExecutionSession) throws -> (
    Value, Value, WorkflowIntakePreparation
  ) {
    let claim = try book.claimWorkflowStep(session, owner: "synthetic", leaseSeconds: 60)
    let request = try book.prepareWorkflowIntake(
      session, claim: claim, worker: worker.workflowIdentity())
    let result = try book.performWorkflowIntake(session, claim: claim, request: request)
    return (claim, request, result)
  }
  func proposal(_ book: Workbook, _ run: Value) throws -> Item {
    try book.item(run["steps"].array[0]["output"]["value"]["proposals"].array[0].text)
  }

  check(
    "structured workflow retains an exact mapped plan, tolerates unrelated revisions and applies only after review"
  ) {
    let (book, source, table, intake, session) = try fixture("Merge")
    let original = try book.rows(table.id)
    try expect(try book.items().allSatisfy { $0.kind != "table-intake-update" })
    let claim = try book.claimWorkflowStep(session, owner: "synthetic", leaseSeconds: 60)
    let request = try book.prepareWorkflowIntake(
      session, claim: claim, worker: worker.workflowIdentity())
    _ = try book.addItem(category: "source", kind: "observation", title: "Unrelated note")
    _ = try book.heartbeatWorkflowStep(session, claim: claim)
    let result = try book.performWorkflowIntake(session, claim: claim, request: request)
    try expect(result.preview.revision > request["readRevision"].int!)
    _ = try book.addItem(category: "source", kind: "observation", title: "Another unrelated note")
    let saved = try book.completeWorkflowStep(session, claim: claim, intake: result)
    let draft = try proposal(book, saved)
    try expect(draft.status == "draft" && draft.data["incoming"].array.count == 3)
    try expectInputRole(book, child: draft.id, parent: source.id, roles: 1)
    try expectInputRole(book, child: draft.id, parent: intake.sourceID, roles: 2)
    try expectInputRole(
      book, child: draft.id, parent: book.datasetDefinition(table.id).sourceID, roles: 2)
    try expectInputRole(book, child: draft.id, parent: saved["source_id"].text, roles: 4)
    for row in original { try expectInputRole(book, child: draft.id, parent: row.id, roles: 1) }
    let origins = try book.businessOrigins(inputs: [draft.id])
    try expect(origins["items"].array.contains { $0["id"] == .string(source.id) })
    for row in original {
      try expect(origins["items"].array.contains { $0["id"] == .string(row.id) })
    }
    try expect(origins["automaticProducers"].array.isEmpty)
    try expect(!origins["items"].array.contains { $0["id"] == .string(intake.sourceID) })
    try expect(draft.data["incoming"].array[0]["sku"] == .string("0012"))
    try expect(draft.data["additionRecords"] == .array([.number(4)]))
    try expect(try book.rows(table.id).map(\.id) == original.map(\.id))
    try expect(saved["steps"].array[0]["output"]["readRevision"] == request["readRevision"])
    try expect(try book.completeWorkflowStep(session, claim: claim, intake: result) == saved)
    try expect(
      try book.advanceWorkflow(session, owner: "review")["state"] == .string("waiting_review"))
    let inert = try book.reconstruct(to: root.appendingPathComponent("WorkflowIntake-Inert.sevra"))
    try expect(try inert.rows(table.id).map(\.id) == original.map(\.id))
    try expect(try inert.workflowRun(session.runID)["state"] == .string("waiting_review"))
    let accepted = try book.accept(
      draft.id, token: "accept-mapped", actor: .human("synthetic-review"))
    let rows = try book.rows(table.id)
    try expect(rows.map { $0.data["qty"].text } == ["7", "5", "2"])
    try expect(rows[0].meaning == "actual" && rows[2].meaning == "estimate")
    try expectInputRole(book, child: rows[2].id, parent: source.id, roles: 1)
    try expectInputRole(
      book, child: rows[2].id, parent: book.datasetDefinition(table.id).sourceID, roles: 2)
    try expect(
      try book.lineage(rows[2].id).contains {
        $0["parent"] == .string(source.id) && $0["transformation"].text.contains("source-record=4")
      })
    let done = try book.advanceWorkflow(session, owner: "review")
    try expect(done["state"] == .string("completed"))
    try expect(try book.balance(subject: "stock")["quantity"] == .string("20"))
    try expect(try book.workflowAcceptedVersion(draft, accepted))
    let copy = try book.reconstruct(to: root.appendingPathComponent("WorkflowIntake-Done.sevra"))
    try expect(
      try copy.workflowRun(session.runID) == done && copy.rows(table.id).map(\.id) == rows.map(\.id)
    )
    try expect(try copy.verify()["ok"] == .bool(true) && book.verify()["ok"] == .bool(true))
  }
  check("workflow append discloses duplicates while replace preserves removal consequences") {
    for mode in ["append", "replace"] {
      let (book, _, table, _, session) = try fixture(
        mode, mode: mode, text: "code,amount\n0012,4\n0012,4\n")
      let (claim, _, result) = try prepared(book, session)
      try expect(result.preview.repeatedIncomingRows == 1 && result.preview.rowsMatchingTarget == 2)
      try expect(result.preview.removed == (mode == "replace" ? 2 : 0))
      let saved = try book.completeWorkflowStep(session, claim: claim, intake: result)
      let draft = try proposal(book, saved)
      _ = try book.accept(draft.id)
      try expect(try book.dataset(table.id).rowCount == (mode == "append" ? 4 : 2))
      try expect(
        try book.advanceWorkflow(session, owner: "review")["state"] == .string("completed"))
      try expect(try book.verify()["ok"] == .bool(true))
    }
  }
  check(
    "retained parser input plans without reopening files and preserves lexical source coordinates"
  ) {
    let (book, source, table, _, _) = try fixture("Parsed")
    let input = try book.tableUpdateInput(source.id, headerRow: 1, cancellation: .init())
    let file = try book.assetURL(source.assetID!)
    let bytes = try Data(contentsOf: file)
    try FileManager.default.removeItem(at: file)
    defer { try? bytes.write(to: file) }
    let plan = try book.tableUpdatePlan(
      input: input, datasetID: table.id, mode: .merge, mapping: mapping, keys: ["sku"],
      cancellation: .init())
    try expect(plan.incoming[0]["sku"] == .string("0012") && plan.additionRecords == [4])
    try expect(plan.preview.changed == 1 && plan.preview.unchanged == 1)
  }
  check("changed target, schema, original and forged intake requests cannot publish stale plans") {
    for mode in ["target", "schema", "original", "request"] {
      let (book, source, table, _, session) = try fixture("Stale-" + mode)
      let (claim, request, result) = try prepared(book, session)
      let code: String
      switch mode {
      case "target":
        let row = try book.rows(table.id)[0]
        _ = try book.editRow(row.id, values: ["sku": .string("0012"), "qty": .string("99")])
        code = "stale_revision"
      case "schema":
        try book.setColumns(
          table.id,
          columns: [
            .init(id: "sku", title: "Identifier"),
            .init(id: "qty", title: "Quantity", type: "decimal"),
          ])
        code = "stale_schema"
      case "original":
        let url = try book.assetURL(source.assetID!)
        try Data("Different source".utf8).write(to: url)
        code = "changed_asset"
      default:
        var changed = request.object
        changed["fingerprint"] = .string(String(repeating: "a", count: 64))
        try refuses("workflow_intake_request") {
          _ = try book.performWorkflowIntake(session, claim: claim, request: .object(changed))
        }
        continue
      }
      try refuses(code) { _ = try book.completeWorkflowStep(session, claim: claim, intake: result) }
      try expect(try book.items().allSatisfy { $0.kind != "table-intake-update" })
      if mode == "original" {
        try Data("code,amount\n0012,7\n0013,5\n0014,2\n".utf8).write(
          to: book.assetURL(source.assetID!))
      }
      try expect(try book.verify()["ok"] == .bool(true))
    }
  }
  check("intake publication fault and cancellation preserve rows, checkpoints and exact retry") {
    let (book, _, table, _, session) = try fixture("Rollback")
    let (claim, _, result) = try prepared(book, session)
    let before = try book.revision()
    let rows = try book.rows(table.id)
    try book.db.execute(
      "CREATE TEMP TRIGGER intake_fault BEFORE INSERT ON workflow_outbox BEGIN SELECT RAISE(ABORT,'intake_fault'); END"
    )
    try refuses("database") {
      _ = try book.completeWorkflowStep(session, claim: claim, intake: result)
    }
    try book.db.execute("DROP TRIGGER intake_fault")
    try expect(try book.revision() == before && book.rows(table.id).map(\.id) == rows.map(\.id))
    try expect(try book.items().allSatisfy { $0.kind != "table-intake-update" })
    let cancelled = Cancellation()
    cancelled.cancel()
    try refuses("cancelled") {
      _ = try book.completeWorkflowStep(
        session, claim: claim, intake: result, cancellation: cancelled)
    }
    let saved = try book.completeWorkflowStep(session, claim: claim, intake: result)
    try expect(try book.completeWorkflowStep(session, claim: claim, intake: result) == saved)
    try expect(try book.items().filter { $0.kind == "table-intake-update" }.count == 1)
    try expect(try book.verify()["ok"] == .bool(true))
  }
  check("committed intake retry needs no source file and cannot reuse another step preparation") {
    let (book, source, _, _, session) = try fixture("Retry")
    let (claim, _, result) = try prepared(book, session)
    let saved = try book.completeWorkflowStep(session, claim: claim, intake: result)
    let url = try book.assetURL(source.assetID!)
    let bytes = try Data(contentsOf: url)
    try FileManager.default.removeItem(at: url)
    defer { try? bytes.write(to: url) }
    let before = try book.revision()
    try expect(try book.completeWorkflowStep(session, claim: claim, intake: result) == saved)
    try expect(try book.revision() == before)
    try bytes.write(to: url)
    let review = try book.claimWorkflowStep(session, owner: "review")
    try refuses("workflow_intake") {
      _ = try book.completeWorkflowStep(session, claim: review, intake: result)
    }
  }
  check("actual SQLite busy and full refuse intake checkpoint atomically") {
    for mode in ["busy", "full"] {
      let text =
        "code,amount\n"
        + (0..<900).map { "item\($0)-" + String(repeating: "x", count: 600) + ",2\n" }.joined()
      let (book, _, table, _, session) = try fixture(mode, mode: "append", text: text)
      let (claim, _, result) = try prepared(book, session)
      let revision = try book.revision()
      let other = try Database(book.url.appendingPathComponent("workbook.sqlite"))
      let maximum = try book.db.scalar("PRAGMA max_page_count").int!
      if mode == "busy" {
        try other.execute("BEGIN IMMEDIATE")
      } else {
        try book.db.execute("PRAGMA max_page_count=\(try book.db.scalar("PRAGMA page_count").int!)")
      }
      defer {
        _ = try? other.execute("ROLLBACK")
        _ = try? book.db.execute("PRAGMA max_page_count=\(maximum)")
      }
      do {
        _ = try book.completeWorkflowStep(session, claim: claim, intake: result)
        throw SevraError("test", "Page/lock pressure did not refuse")
      } catch let error as SevraError {
        try expect(
          error.code == "database" && error.message.contains(mode == "busy" ? "locked" : "full"),
          "Expected real SQLite \(mode): \(error)")
      }
      try expect(try book.revision() == revision && book.dataset(table.id).rowCount == 2)
      try expect(try book.items().allSatisfy { $0.kind != "table-intake-update" })
      if mode == "busy" {
        try other.execute("ROLLBACK")
      } else {
        try book.db.execute("PRAGMA max_page_count=\(maximum)")
      }
      let saved = try book.completeWorkflowStep(session, claim: claim, intake: result)
      try expect(try proposal(book, saved).data["incoming"].array.count == 900)
      try expect(try saved["steps"].array[0]["output"].json().utf8.count < 524_288)
      try expect(try book.verify()["ok"] == .bool(true))
    }
  }
  check("undone or copied-looking table acceptance cannot satisfy the old review") {
    let (book, _, _, _, session) = try fixture("UndoReview")
    let (claim, _, result) = try prepared(book, session)
    let saved = try book.completeWorkflowStep(session, claim: claim, intake: result)
    let draft = try proposal(book, saved)
    let accepted = try book.accept(draft.id)
    try expect(try book.workflowAcceptedVersion(draft, accepted))
    var forged = try encoded(accepted).object
    var applied = accepted.data.object
    applied["acceptanceOperationID"] = .string("unrelated-receipt")
    forged["data"] = .object(applied)
    let fake = try JSONDecoder().decode(Item.self, from: Data(Value.object(forged).json().utf8))
    try expect(try !book.workflowAcceptedVersion(draft, fake))
    // A real undo changes the head and adds compensating versions, rather than
    // treating the once-accepted plan as permission for this earlier review.
    _ = try book.undoItem(accepted.id)
    try refuses("workflow_stale_review") { _ = try book.advanceWorkflow(session, owner: "review") }
    try expect(try book.workflowRun(session.runID)["state"] == .string("needs_attention"))
    try expect(try book.verify()["ok"] == .bool(true))
  }
  check("intake scope, whole-input limits and exact schemas refuse before any row proposal") {
    for mode in ["linked", "limit", "duplicate", "schema"] {
      let text =
        mode == "limit"
        ? "code,amount\n" + String(repeating: "0014,2\n", count: 1001)
        : mode == "duplicate" ? "code,amount\n0012,2\n0012,3\n" : "code,amount\n0014,2\n"
      let (book, _, table, _, session) = try fixture(
        "Refuse-" + mode, text: text, linked: mode == "linked")
      if mode == "schema" {
        _ = try book.updateDatasetDefinition(
          table.id, expectedVersion: table.version, expectedDefinitionID: table.definitionID,
          title: "Changed target")
      }
      let claim = try book.claimWorkflowStep(session, owner: "synthetic", leaseSeconds: 60)
      if mode == "linked" || mode == "schema" {
        try refuses(mode == "linked" ? "workflow_intake_scope" : "stale_schema") {
          _ = try book.prepareWorkflowIntake(
            session, claim: claim, worker: worker.workflowIdentity())
        }
      } else {
        let request = try book.prepareWorkflowIntake(
          session, claim: claim, worker: worker.workflowIdentity())
        try refuses(mode == "limit" ? "update_limit" : "update_key_duplicate") {
          _ = try book.performWorkflowIntake(session, claim: claim, request: request)
        }
      }
      try expect(
        try book.dataset(table.id).rowCount == 2
          && book.items().allSatisfy { $0.kind != "table-intake-update" })
    }
  }
  check(
    "workflow intake form queues inertly with recoverable exact inputs and one submission receipt"
  ) {
    let (book, source, table, _, session) = try fixture("Form")
    let workflow = try book.applicationDefinition(
      book.workflowRun(session.runID)["definition_id"].text)
    let form = try book.saveApplicationDefinition(
      logicalID: identifier(), content: ActionRegistry.formDefinition(target: workflow))
    var state = try book.newFormDraft(form.id)
    state.arguments = .object(["file": .string(source.id)])
    _ = try book.saveFormDraft("intake-form", state: state, expected: nil)
    let preview = try book.previewFormDraft(state)
    try expect(preview["steps"].array[0]["kind"] == .string("intake"))
    let receipt = try book.submitFormDraft(state, preview: preview, actor: .human("synthetic-form"))
    try expect(receipt["state"] == .string("queued"))
    let revision = try book.revision()
    try expect(
      try book.submitFormDraft(state, preview: preview, actor: .human("synthetic-form")) == receipt)
    let opened = try Workbook(book.url)
    try expect(try opened.formDraft("intake-form")?.arguments == state.arguments)
    try expect(try opened.revision() == revision && opened.dataset(table.id).rowCount == 2)
    try expect(try opened.items().allSatisfy { $0.kind != "table-intake-update" })
    try expect(try opened.verify()["ok"] == .bool(true))
  }
  check(
    "reusable intake definitions reject missing semantics, ambiguous mappings and unreviewed workflow steps"
  ) {
    let (book, _, _, intake, session) = try fixture("Definitions")
    for field in ["newRowMeaning", "newRowScenario", "mapping", "keys"] {
      var content = intake.content.object
      var payload = intake.payload.object
      payload.removeValue(forKey: field)
      content["payload"] = .object(payload)
      try refuses {
        _ = try book.saveApplicationDefinition(logicalID: identifier(), content: .object(content))
      }
    }
    var content = intake.content.object
    var payload = intake.payload.object
    payload["mapping"] = .array([
      .object(["position": .number(0), "target": .string("sku")]),
      .object(["position": .number(1), "target": .string("sku")]),
    ])
    content["payload"] = .object(payload)
    try refuses("update_mapping") {
      _ = try book.saveApplicationDefinition(logicalID: identifier(), content: .object(content))
    }
    let workflow = try book.applicationDefinition(
      book.workflowRun(session.runID)["definition_id"].text)
    var unreviewed = workflow.content.object
    var steps = workflow.payload.object
    steps["steps"] = .array([workflow.payload["steps"].array[0]])
    unreviewed["payload"] = .object(steps)
    try refuses("workflow_definition") {
      _ = try book.saveApplicationDefinition(logicalID: identifier(), content: .object(unreviewed))
    }
    let dependencies = try book.applicationDefinitionDependencies(intake.id)
    try expect(dependencies.count == 1 && dependencies[0]["mode"] == .string("exact"))
    try expect(try book.verify()["ok"] == .bool(true))
  }
}
