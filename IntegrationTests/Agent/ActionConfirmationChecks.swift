import Foundation
import SevraAI
import SevraCore

private actor ConfirmationModel: WorkbookInference {
  let identity = "synthetic saved-artifact confirmation"
  let lastMetrics: Value = .null
  let source: Item
  let factual: Bool
  let invalidDraft: Bool
  let retryDraft: Bool
  let differentTitle: Bool
  var step = 0
  init(
    _ source: Item, factual: Bool, invalidDraft: Bool, retryDraft: Bool = false,
    differentTitle: Bool = false
  ) {
    self.source = source
    self.factual = factual
    self.invalidDraft = invalidDraft
    self.retryDraft = retryDraft
    self.differentTitle = differentTitle
  }
  func beginRun() {}
  func endRun() {}
  func respond(
    messages: [InferenceMessage], directory: URL, cancellation: Cancellation,
    progress: @escaping @Sendable (String) -> Void, toolScope: InferenceToolScope,
    citationIDs: [String]
  ) throws -> NativeReply {
    step += 1
    let tool: String
    let args: Value
    if step == 1 {
      tool = "read"
      args = .object(["id": .string(source.id)])
    } else if [2, 3].contains(step) {
      tool = "save_space"
      args = .object([
        "title": .string("Overview"),
        "definition": .object(["version": .number(1), "components": .array([])]),
      ])
    } else if step == 4 || (step == 5 && retryDraft) {
      tool = "draft"
      args = .object([
        "title": .string(differentTitle && step == 5 ? "Other memo" : "Memo [A]"),
        "text": .string("Renamed the identifier to Alpha."),
        "inputs": .array([.string(invalidDraft && step == 4 ? "not-a-source" : source.id)]),
      ])
    } else {
      tool = "finish"
      args = .object([
        "answer": .string(
          factual
            ? "The source records ALPHA-CHECK."
            : "All requested identifiers were preserved exactly; every condition was verified. 123e4567-e89b-12d3-a456-426614174000 cost $1000."
        ),
        "basis": .string(factual ? "evidence" : "completed_action"),
        "citations": .array(factual ? [.string(source.id)] : []),
      ])
    }
    return .init(text: "", calls: [try .init(id: identifier(), operation: tool, args, scope: toolScope)])
  }
}

private func checkRefusedRepeats() throws {
  let memo: Value = .object(["title": .string("Memo")])
  let refusal =
    "A draft titled Memo was already saved for this work. Do not save it again. Finish, and say plainly what it still needs."
  var repeated = ActionConfirmations()
  repeated.record(
    tool: "draft", arguments: memo,
    result: .object(["id": .string("d"), "status": .string("draft"), "title": .string("Memo")]),
    receiptID: "first")
  repeated.recordFailure(
    tool: "draft", arguments: memo, result: .object(["error": .string(refusal)]),
    receiptID: "second")
  try expectEqual(repeated.hasUnresolvedFailure, false)
  try expectEqual(repeated.rendered, "Saved draft [Memo](sevra://item/d).")
  // With no earlier save in this request the refusal stands, in words meant for a person.
  var elsewhere = ActionConfirmations()
  elsewhere.recordFailure(
    tool: "save_space", arguments: .object(["title": .string("Overview")]),
    result: .object([
      "error": .string(
        "A space titled Overview already exists. Do not save it again. Use edit_space to change it."
      )
    ]), receiptID: "only")
  try expectEqual(elsewhere.hasUnresolvedFailure, true)
  try expectEqual(
    elsewhere.rendered, "Couldn’t finish saving the space. A space titled Overview already exists.")
  // After an account that already said why, each unfinished task is named once.
  var twice = elsewhere
  twice.recordFailure(
    tool: "edit_space", arguments: .object(["id": .string("o")]),
    result: .object(["error": .string("Unknown layout edit.")]), receiptID: "again")
  try expectEqual(
    twice.rendered(excluding: nil, brief: true), "Couldn’t finish saving the space.")
  // Editing that view afterwards is the outcome, and it settles the refused save.
  elsewhere.record(
    tool: "edit_space", arguments: .object(["id": .string("o")]),
    result: .object(["spaceID": .string("o"), "title": .string("Overview")]), receiptID: "next")
  try expectEqual(elsewhere.hasUnresolvedFailure, false)
  try expectEqual(elsewhere.rendered, "Updated space “Overview”.")

  // Every write can fail, and a later success on the same target settles it.
  let bad: Value = .object(["error": .string("Column total is missing.")])
  let table: Value = .object(["title": .string("Quotes")])
  var proposals = ActionConfirmations()
  proposals.recordFailure(tool: "propose_record", arguments: table, result: bad, receiptID: "a")
  proposals.recordFailure(
    tool: "include_archive_members", arguments: .object(["id": .string("zip")]), result: bad,
    receiptID: "b")
  proposals.recordFailure(tool: "read", arguments: table, result: bad, receiptID: "c")
  try expectEqual(proposals.evidence.array.count, 2)
  try expectEqual(
    proposals.rendered,
    "Couldn’t finish preparing the proposal. Column total is missing.\n"
      + "Couldn’t finish including the archive files. Column total is missing.")
  proposals.record(
    tool: "propose_record", arguments: .object(["title": .string("Other")]),
    result: .object(["id": .string("t")]), receiptID: "d")
  try expectEqual(proposals.rendered?.contains("preparing the proposal"), true)
  proposals.record(
    tool: "propose_record", arguments: table, result: .object(["id": .string("t")]), receiptID: "e")
  proposals.record(
    tool: "include_archive_members", arguments: .object(["id": .string("zip")]),
    result: .object(["included": .array([])]), receiptID: "f")
  try expectEqual(proposals.hasUnresolvedFailure, false)
  try expectEqual(proposals.rendered, nil)
  var layout = ActionConfirmations()
  let edit: Value = .object(["id": .string("home"), "expectedVersion": .number(1)])
  layout.recordFailure(tool: "edit_space", arguments: edit, result: bad, receiptID: "g")
  layout.record(
    tool: "edit_space", arguments: edit,
    result: .object(["spaceID": .string("home"), "title": .string("Home")]), receiptID: "h")
  try expectEqual(layout.hasUnresolvedFailure, false)
  try expectEqual(layout.rendered, "Updated space “Home”.")
  try expectEqual(layout.rendered(excluding: "h"), nil)
  // Whatever saved keeps the model's summary, a view or a draft alike, and so does a refused
  // repeat whose first save stands. A failed write, even one a later write of the same target
  // settles for the host's lines, a change waiting for approval and a request that saved
  // nothing do not.
  try expectEqual(repeated.keepsSummary, true)
  try expectEqual(elsewhere.keepsSummary, true)
  try expectEqual(layout.keepsSummary, false)
  try expectEqual(twice.keepsSummary, false)
  try expectEqual(ActionConfirmations().keepsSummary, false)
  var waiting = ActionConfirmations()
  waiting.record(
    tool: "workspace_action", arguments: .object(["action": .string("table.update")]),
    result: .object([
      "status": .string("confirmation_required"), "preview": .string("Change 2 rows."),
    ]), receiptID: "approval")
  try expectEqual(waiting.keepsSummary, false)
  // A failed edit of Home that a later edit of Home settles for the host's own lines does not
  // let the model's summary describe both: the failed part may be in it.
  var partly = ActionConfirmations()
  partly.recordFailure(
    tool: "edit_space", arguments: edit, result: .object(["error": .string("No saved tool is named x.")]),
    receiptID: "button")
  partly.record(
    tool: "edit_space", arguments: edit,
    result: .object(["spaceID": .string("home"), "title": .string("Home")]), receiptID: "metric")
  try expectEqual(partly.hasUnresolvedFailure, false)
  try expectEqual(partly.keepsSummary, false)
  // A failed call the model fixed and made again, with the same intent, keeps the summary: the
  // same table created, the same kind of component put into the same view. The same tool with
  // another intent, another table or another component, does not.
  func sql(_ statements: String...) -> Value {
    .object(["statements": .array(statements.map(Value.string))])
  }
  func insert(_ type: String) -> Value {
    .object([
      "id": .string("home"), "expectedVersion": .number(1),
      "edits": .array([
        .object([
          "operation": .string("insert"), "at": .string("last"),
          "component": .object(["id": .string(type + "1"), "type": .string(type)]),
        ])
      ]),
    ])
  }
  let homeSaved: Value = .object(["spaceID": .string("home"), "title": .string("Home")])
  let created: Value = .object([
    "results": .array([.object(["done": .bool(true)])]),
    "shape": .array([.object(["change": .string("created"), "table": .string("visits")])]),
  ])
  func summary(
    failed: (String, Value), then: (String, Value), result: Value
  ) -> Bool {
    var confirmations = ActionConfirmations()
    confirmations.recordFailure(
      tool: failed.0, arguments: failed.1, result: .object(["error": .string("Refused.")]),
      receiptID: "failed")
    confirmations.record(tool: then.0, arguments: then.1, result: result, receiptID: "fixed")
    confirmations.record(
      tool: "edit_space", arguments: insert("button"), result: homeSaved, receiptID: "view")
    return confirmations.keepsSummary
  }
  try expectEqual(
    summary(
      failed: ("sql", sql("CREATE TABLE visits (id INTEGER PRIMARY KEY AUTOINCREMENT, at TEXT)")),
      then: ("sql", sql("create table \"Visits\" (id INTEGER PRIMARY KEY, at TEXT)")),
      result: created), true)
  try expectEqual(
    summary(
      failed: ("sql", sql("INSERT INTO visits (at) VALUES ('x')")),
      then: ("sql", sql("CREATE TABLE visits (id INTEGER PRIMARY KEY, at TEXT)")),
      result: created), false)
  // A refused change to a table's shape that the model moved past is its own dead end: the
  // summary stands and the refusal, written for the model, is not shown as the outcome.
  var detour = ActionConfirmations()
  detour.record(
    tool: "sql", arguments: sql("CREATE TABLE counters (id INTEGER PRIMARY KEY, name TEXT)"),
    result: created, receiptID: "table")
  detour.recordFailure(
    tool: "sql", arguments: sql("CREATE UNIQUE INDEX counter_names ON counters (name)"),
    result: .object(["error": .string("Remove UNIQUE. Nothing was changed.")]),
    receiptID: "unique")
  try expectEqual(detour.hasUnresolvedFailure, true)
  detour.record(
    tool: "edit_space", arguments: insert("button"), result: homeSaved, receiptID: "view")
  try expectEqual(detour.hasUnresolvedFailure, false)
  try expectEqual(detour.keepsSummary, true)
  // The table it made is the host's own line, by the table's title.
  try expectEqual(detour.rendered, "Created table “visits”.\nUpdated space “Home”.")
  try expectEqual(
    summary(
      failed: ("sql", sql("ALTER TABLE counters ADD COLUMN label TEXT UNIQUE")),
      then: ("save", .object(["kind": .string("tool"), "name": .string("add_click")])),
      result: .object([:])), true)
  try expectEqual(
    summary(failed: ("edit_space", insert("metric")), then: ("edit_space", insert("metric")), result: homeSaved),
    true)
  try expectEqual(
    summary(failed: ("edit_space", insert("metric")), then: ("edit_space", insert("table")), result: homeSaved),
    false)
  // A view saved again with the same kinds of component in another order did the same work.
  func view(_ types: [String]) -> Value {
    .object([
      "title": .string("Alerts"),
      "definition": .object([
        "version": .number(1),
        "components": .array(types.map { .object(["id": .string($0 + "1"), "type": .string($0)]) }),
      ]),
    ])
  }
  let alerts: Value = .object(["spaceID": .string("alerts"), "title": .string("Alerts")])
  try expectEqual(
    summary(failed: ("save_space", view(["table", "button"])), then: ("save_space", view(["button", "table"])), result: alerts),
    true)
  // An edit that failed after the view was saved is a later change that did not apply, not the
  // whole view unsaved.
  var later = ActionConfirmations()
  later.record(tool: "edit_space", arguments: insert("chart"), result: homeSaved, receiptID: "chart")
  later.recordFailure(
    tool: "edit_space", arguments: insert("chart"),
    result: .object(["error": .string("Component id chart1 is used twice.")]), receiptID: "again")
  try expectEqual(
    later.rendered,
    "Updated space “Home”.\nCouldn’t finish a later change to “Home”. Component id chart1 is used twice.")
  // What a statement writes, read from its text: a quoted value and an upsert's own UPDATE are
  // not writes of their own.
  try expectEqual(
    ActionConfirmations.writes([
      "INSERT OR REPLACE INTO [Counts] (n) VALUES ('update visits set n = 1')",
      "INSERT INTO totals (k, n) VALUES ('a', 1) ON CONFLICT(k) DO UPDATE SET n = n + 1",
      "DELETE FROM old_rows WHERE 1", "drop table if exists scratch",
    ]), ["delete old_rows", "drop scratch", "insert counts", "insert totals"])
  // A failed read changed nothing, so it is not a failed write. A failed write, a WITH that
  // writes, and a statement that cannot be read as a SELECT still are.
  var read = ActionConfirmations()
  read.recordFailure(
    tool: "sql", arguments: .object(["statements": .array([.string("SELEC 1")])]),
    result: .object(["error": .string("syntax error")]), receiptID: "typo")
  try expectEqual(read.evidence.array.count, 1)
  var lookup = ActionConfirmations()
  lookup.recordFailure(
    tool: "sql", arguments: .object(["statements": .array([.string("SELECT * FROM nowhere")])]),
    result: .object(["error": .string("no such table")]), receiptID: "read")
  lookup.recordFailure(
    tool: "sql",
    arguments: .object([
      "statements": .array([.string("WITH t AS (SELECT 1) SELECT * FROM t")])
    ]), result: .object(["error": .string("no such table")]), receiptID: "with")
  try expectEqual(lookup.evidence.array.count, 0)
  var writing = ActionConfirmations()
  writing.recordFailure(
    tool: "sql",
    arguments: .object([
      "statements": .array([.string("WITH t AS (SELECT 1) INSERT INTO items SELECT * FROM t")])
    ]), result: .object(["error": .string("no such table")]), receiptID: "write")
  try expectEqual(writing.evidence.array.count, 1)
  // A claim about content is refused; an honest summary, "Perfect!" and all, is not.
  for claim in [
    "Saved every detail perfectly.", "I copied the clause verbatim.",
    "All requested identifiers were preserved exactly; every condition was verified.",
  ] {
    try expectEqual(FidelityClaim.overstates(claim), true)
  }
  for honest in [
    "Perfect! I added a large count to Home.", "Each press is recorded exactly once.",
    "I placed it exactly where you asked.", "All values you type are checked against their types.",
  ] {
    try expectEqual(FidelityClaim.overstates(honest), false)
  }
  var app = ActionConfirmations()
  for (tool, args) in [
    ("edit_space", Value.object(["id": .string("stock-id")])),
    ("save_space", .object(["title": .string("Stock")])),
    (
      "save_native_app",
      .object([
        "id": .string("incorrect-id"), "package": .object(["name": .string("Stock")]),
      ])
    ),
  ] {
    app.recordFailure(tool: tool, arguments: args, result: bad, receiptID: identifier())
  }
  let saved: Value = .object([
    "spaceID": .string("stock-id"), "title": .string("Stock"),
    "check": .object(["assertions": .number(3)]),
  ])
  app.record(
    tool: "save_native_app", arguments: .object(["id": .string("stock-id")]),
    result: saved, receiptID: "app")
  try expectEqual(app.hasUnresolvedFailure, false)
  try expectEqual(app.rendered?.contains("Couldn’t"), false)
  // Another app and an explicitly requested snapshot are not settled by this edit.
  for (tool, args) in [
    ("save_native_app", Value.object(["package": .object(["name": .string("Other")])])),
    ("pin_space", .object(["id": .string("stock-id")])),
  ] {
    var separate = ActionConfirmations()
    separate.recordFailure(tool: tool, arguments: args, result: bad, receiptID: "failed")
    separate.record(
      tool: "save_native_app", arguments: .object(["id": .string("stock-id")]),
      result: saved, receiptID: "saved")
    try expectEqual(separate.hasUnresolvedFailure, true)
    try expectEqual(separate.rendered?.contains("Couldn’t"), true)
  }
}

func checkActionConfirmations() async throws {
  try await checkReplyTruth()
  try checkRefusedRepeats()
  try await checkRecordMeaningRefusal()
  try checkNestedActionRecovery()
  try checkMisplacedActionRecovery()
  try checkMisnamedHostActionRecovery()
  // Repairing a malformed call can expose a genuine business refusal. Show the
  // refusal, retain both receipts, and never mark the requested action successful.
  for sameTarget in [true, false] {
    var confirmations = ActionConfirmations()
    let malformed: Value = .object([
      "action": .string("app.run"),
      "arguments": .object([
        "id": .string("invoice-app"), "expectedVersion": .number(1),
        "action": .string("createInvoice"), "arguments": .object([:]),
      ]),
    ])
    let valid: Value = .object([
      "action": .string("app.run"),
      "arguments": .object([
        "id": .string(sameTarget ? "invoice-app" : "other-app"),
        "expectedVersion": .number(1), "action": .string("createInvoice"),
        "inputs": .object(["reference": .string("INV-1")]),
      ]),
    ])
    confirmations.recordFailure(
      tool: "workspace_action", arguments: malformed,
      result: .object(["error": .string("Missing fields: inputs")]), receiptID: "envelope")
    confirmations.recordFailure(
      tool: "workspace_action", arguments: valid,
      result: .object(["error": .string("Duplicate reference")]), receiptID: "business")
    try expectEqual(confirmations.evidence.array.count, 2)
    try expectEqual(confirmations.hasUnresolvedFailure, true)
    try expectEqual(confirmations.rendered?.contains("Duplicate reference"), true)
    try expectEqual(confirmations.rendered?.contains("Missing fields"), !sameTarget)
  }
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(
    "confirmation-" + identifier())
  defer { try? FileManager.default.removeItem(at: root) }
  for mode in ["saved", "evidence", "failed-draft", "retry", "different"] {
    let book = try Workbook.create(at: root.appendingPathComponent(mode + ".sevra"), title: mode)
    let source = try book.addItem(
      category: "source", kind: "note", title: "Input", text: "ALPHA-CHECK")
    let invalid = mode == "failed-draft"
    let retry = mode == "retry" || mode == "different"
    let result = try await WorkbookAgent.run(
      "Save Overview and a memo using the input.", workbook: book,
      context: "Input: \(source.id)",
      model: ConfirmationModel(
        source, factual: mode == "evidence", invalidDraft: invalid || retry, retryDraft: retry,
        differentTitle: mode == "different"))
    try expectEqual(result.state, "complete")
    let last = try expectValue(book.messages().last { $0.role == "assistant" })
    let payload = try book.messagePayload(last.id)
    try expectEqual(payload["unresolvedActionFailure"], .bool(invalid || mode == "different"))
    try expectEqual(try book.spaces().filter { $0.title == "Overview" }.count, 1)
    try expectEqual(result.answer.contains("every condition was verified"), false)
    try expectEqual(result.answer.contains("All requested identifiers"), false)
    try expectEqual(result.answer.contains("123e4567"), false)
    try expectEqual(result.answer.contains("$1000"), false)
    if mode == "evidence" {
      try expectEqual(result.answer.hasPrefix("The source records ALPHA-CHECK."), true)
      try expectEqual(payload["presentation"].text, "answer")
    } else {
      try expectEqual(result.answer.components(separatedBy: "Saved space").count, 2)
      try expectEqual(result.answer.contains("Saved draft"), !invalid)
      try expectEqual(payload["presentation"].text, "host_actions")
      try expectEqual(payload["actionConfirmations"].array.count, retry ? 4 : 3)
      try expectEqual(
        result.answer.contains("Couldn’t finish saving the draft."), invalid || mode == "different")
      try expectEqual(
        payload["arguments"]["answer"].text.contains("every condition was verified"), true)
    }
    if !invalid {
      let draft = try expectValue(book.items(kind: "document").first)
      try expectEqual(draft.text, "Renamed the identifier to Alpha.")
      try expectEqual(draft.status, "draft")
      if mode == "saved" { try expectEqual(result.answer.contains(draft.id), true) }
    }
    try expectEqual(try book.verify()["ok"], .bool(true))
  }
  print(
    "PASS receipt-based saved-artifact confirmations, idempotent rendering, failed-write exclusion and intact cited answers"
  )
  // A changed view keeps the model's summary above the host's line, because only the summary
  // says what was chosen. A summary the host refuses twice is dropped, and the request still
  // completes on the host's line alone.
  func addNote(_ answer: String, finishes: Int) -> ScriptedCalls {
    let note: Value = .object([
      "id": .string("note"), "type": .string("text"), "title": .string("Note"),
      "text": .string("Hello"),
    ])
    let edit: Value = .object([
      "operation": .string("insert"), "at": .string("last"), "component": note,
    ])
    return ScriptedCalls(
      [
        call(
          "edit_space",
          .object([
            "id": .string("home"), "expectedVersion": .number(1), "edits": .array([edit]),
          ]))
      ] + (0..<finishes).map { _ in finish(answer, basis: "completed_action") })
  }
  let summary = "I added a Note card at the bottom of Home. Say where else you want it."
  let summarized = try await WorkbookAgent.run(
    "Add a note to my Home.",
    workbook: try Workbook.create(
      at: root.appendingPathComponent("summary.sevra"), title: "Summary"),
    model: addNote(summary, finishes: 1))
  try expectEqual(summarized.answer, summary + "\n\nUpdated space “Home”.")
  let dropped = try await WorkbookAgent.run(
    "Add a note to my Home.",
    workbook: try Workbook.create(
      at: root.appendingPathComponent("dropped.sevra"), title: "Dropped"),
    model: addNote("I added a note that cost $1000.", finishes: 3))
  try expectEqual(dropped.state, "complete")
  try expectEqual(dropped.steps, 4)
  try expectEqual(dropped.answer, "Updated space “Home”.")
  // The same holds for every save, a draft too. A claim the receipt cannot prove, that the
  // content is perfect, is sent back, and a summary that keeps making it is dropped.
  func memo(_ answer: String, finishes: Int) -> ScriptedCalls {
    ScriptedCalls(
      [
        call(
          "draft",
          .object(["title": .string("Memo"), "text": .string("Order more bolts."), "inputs": .array([])]))
      ] + (0..<finishes).map { _ in finish(answer, basis: "completed_action") })
  }
  let drafted = try await WorkbookAgent.run(
    "Draft a memo about bolts.",
    workbook: try Workbook.create(at: root.appendingPathComponent("memo.sevra"), title: "Memo"),
    model: memo("I drafted a short memo asking to order more bolts.", finishes: 1))
  try expectEqual(drafted.answer.hasPrefix("I drafted a short memo asking to order more bolts.\n\nSaved draft [Memo]"), true)
  let overclaimed = ScriptedCalls(
    [
      call(
        "draft",
        .object(["title": .string("Memo"), "text": .string("Order more bolts."), "inputs": .array([])])),
      finish("I saved every detail perfectly.", basis: "completed_action"),
      finish("I drafted the memo.", basis: "completed_action"),
    ])
  let corrected = try await WorkbookAgent.run(
    "Draft a memo about bolts.",
    workbook: try Workbook.create(at: root.appendingPathComponent("claim.sevra"), title: "Claim"),
    model: overclaimed)
  try expectEqual(await overclaimed.refusals.first?.contains("not how faithful its content is"), true)
  try expectEqual(corrected.answer.hasPrefix("I drafted the memo.\n\nSaved draft [Memo]"), true)
  // A summary states no number nothing gave: "42" was never read.
  let counted = ScriptedCalls(
    [
      call(
        "draft",
        .object(["title": .string("Memo"), "text": .string("Order more bolts."), "inputs": .array([])])),
      finish("I drafted a memo for the 42 open orders.", basis: "completed_action"),
      finish("I drafted a memo about the open orders.", basis: "completed_action"),
    ])
  let grounded = try await WorkbookAgent.run(
    "Draft a memo about bolts.",
    workbook: try Workbook.create(at: root.appendingPathComponent("count.sevra"), title: "Count"),
    model: counted)
  try expectEqual(await counted.refusals.first?.contains("The summary states 42"), true)
  try expectEqual(grounded.answer.hasPrefix("I drafted a memo about the open orders."), true)
  print("PASS every save keeps the model's summary; unprovable claims and twice-refused summaries are dropped")
  for basis in ["general", "current_request", "unresolved", "completed_action", "evidence"] {
    let book = try Workbook.create(
      at: root.appendingPathComponent("failed-" + basis + ".sevra"), title: basis)
    let source = try book.addItem(
      category: "source", kind: "note", title: "Input", text: "ALPHA-CHECK")
    let result: AgentResult
    do {
      result = try await WorkbookAgent.run(
        "Save reusable behavior.", workbook: book, context: "Input: \(source.id)",
        model: FailedDefinitionConfirmationModel(basis: basis, source: source))
    } catch {
      throw SevraError(
        "confirmation_check",
        "Failed basis \(basis): \(error). Last messages: \(try book.messages().suffix(3).map(\.body))"
      )
    }
    try expectEqual(result.answer.contains("saved successfully"), false)
    try expectEqual(result.answer.contains("Couldn’t finish saving reusable behavior."), true)
    try expectEqual(try book.searchApplicationDefinitions("")["hits"].array.isEmpty, true)
    let last = try expectValue(book.messages().last { $0.role == "assistant" })
    let payload = try book.messagePayload(last.id)
    try expectEqual(payload["actionConfirmations"].array.count, 1)
    if basis == "evidence" {
      try expectEqual(result.answer.hasPrefix("The source records ALPHA-CHECK."), true)
      try expectEqual(result.citations, [source.id])
    } else {
      try expectEqual(payload["presentation"].text, "host_actions")
    }
    try expectEqual(try book.verify()["ok"], .bool(true))
  }
  print(
    "PASS failed definition receipts cannot become success by relabeling finish basis; cited facts retain explicit failure outcomes"
  )
  let book = try Workbook.create(
    at: root.appendingPathComponent("failed-queue.sevra"), title: "Queue failure")
  let source = try book.addItem(
    category: "source", kind: "note", title: "Input", text: "ALPHA-CHECK")
  let queueFailure = try await WorkbookAgent.run(
    "Queue a workflow.", workbook: book,
    model: FailedDefinitionConfirmationModel(basis: "general", source: source, queue: true))
  try expectEqual(queueFailure.answer.contains("Couldn’t finish queueing the workflow."), true)
  try expectEqual(queueFailure.answer.contains("saved successfully"), false)
  try expectEqual(try book.workflowActivity()["runs"].array.isEmpty, true)
  try expectEqual(try book.verify()["ok"], .bool(true))
}

private func checkNestedActionRecovery() throws {
  let inputs: Value = .object([
    "principal": .string("12000"), "annualRate": .string("0"), "months": .string("12"),
  ])
  let correct: Value = .object([
    "id": .string("cash-app"), "expectedVersion": .number(1),
    "action": .string("updateLoan"), "inputs": inputs,
  ])
  let nested: Value = .object([
    "action": .string("updateLoan"),
    "arguments": .object(correct.object.merging(["annualRate": .string("0")]) { $1 }),
  ])
  for mode in [
    "saved", "refused", "other-id", "other-action", "other-version", "other-input", "conflict",
    "outer-conflict", "outer-other-input", "conflicting-extra-input",
  ] {
    var confirmations = ActionConfirmations()
    var malformed = nested.object
    if mode == "conflict" { malformed["id"] = .string("other-app") }
    if mode.hasPrefix("outer-") { malformed["id"] = .string("cash-app") }
    if mode == "outer-conflict" {
      malformed["arguments"] = .object(correct.object.merging(["id": .string("other-app")]) { $1 })
    }
    if mode == "conflicting-extra-input" {
      malformed["arguments"] = .object(correct.object.merging(["annualRate": .string("1")]) { $1 })
    }
    confirmations.recordFailure(
      tool: "workspace_action",
      arguments: .object(["action": .string("app.run"), "arguments": .object(malformed)]),
      result: .object(["error": .string("Missing fields: expectedVersion, id, inputs")]),
      receiptID: "envelope")
    var repaired = correct.object
    if mode == "other-id" { repaired["id"] = .string("other-app") }
    if mode == "other-action" { repaired["action"] = .string("otherAction") }
    if mode == "other-version" { repaired["expectedVersion"] = .number(2) }
    if ["other-input", "outer-other-input"].contains(mode) {
      repaired["inputs"] = .object(["months": .string("24")])
    }
    let arguments: Value = .object([
      "action": .string("app.run"), "arguments": .object(repaired),
    ])
    if mode == "refused" {
      confirmations.recordFailure(
        tool: "workspace_action", arguments: arguments,
        result: .object(["error": .string("Loan is closed")]), receiptID: "handler")
    } else {
      confirmations.record(
        tool: "workspace_action", arguments: arguments,
        result: .object(["outcome": .string("completed")]), receiptID: "handler")
    }
    try expectEqual(confirmations.evidence.array.count, 2)
    try expectEqual(confirmations.hasUnresolvedFailure, mode != "saved")
    try expectEqual(
      confirmations.rendered?.contains("Missing fields") ?? false,
      !["saved", "refused"].contains(mode))
    if mode == "refused" {
      try expectEqual(confirmations.rendered, "Couldn’t finish that action. Loan is closed")
    }
  }
  // Two requested transactions can use the same action. A different successful
  // transaction must not erase the first one's actual business refusal.
  for changedInput in [false, true] {
    var confirmations = ActionConfirmations()
    var malformed = correct.object
    malformed.removeValue(forKey: "expectedVersion")
    confirmations.recordFailure(
      tool: "workspace_action",
      arguments: .object(["action": .string("app.run"), "arguments": .object(malformed)]),
      result: .object(["error": .string("Missing fields: expectedVersion")]), receiptID: "envelope")
    var repaired = correct.object
    if changedInput { repaired["inputs"] = .object(["months": .string("24")]) }
    confirmations.record(
      tool: "workspace_action",
      arguments: .object(["action": .string("app.run"), "arguments": .object(repaired)]),
      result: .object(["outcome": .string("completed")]), receiptID: "handler")
    try expectEqual(confirmations.hasUnresolvedFailure, changedInput)
  }
  for changedInput in [false, true] {
    var confirmations = ActionConfirmations()
    let failed: Value = .object(["action": .string("app.run"), "arguments": correct])
    confirmations.recordFailure(
      tool: "workspace_action", arguments: failed,
      result: .object(["error": .string("Loan is closed")]), receiptID: "first")
    var next = correct.object
    next["expectedVersion"] = .number(2)
    if changedInput { next["inputs"] = .object(["months": .string("24")]) }
    confirmations.record(
      tool: "workspace_action",
      arguments: .object(["action": .string("app.run"), "arguments": .object(next)]),
      result: .object(["outcome": .string("completed")]), receiptID: "second")
    try expectEqual(confirmations.hasUnresolvedFailure, changedInput)
  }
  for mode in [
    "missing", "mistyped", "blank", "blank-record", "optional-blank", "nonblank-unicode",
    "different-value", "partial-write",
  ] {
    var confirmations = ActionConfirmations()
    var incomplete = inputs.object
    incomplete["months"] = mode == "mistyped" ? .number(12) : nil
    if ["blank", "blank-record", "optional-blank"].contains(mode) {
      incomplete["months"] = .string(" \t\n\u{00A0}\u{FEFF}")
    }
    if mode == "nonblank-unicode" { incomplete["months"] = .string("\u{0085}") }
    var arguments = correct.object
    arguments["inputs"] = .object(incomplete)
    let contract = Value.object(
      inputs.object.mapValues { _ in
        .object([
          "required": .bool(mode != "optional-blank"), "valueType": .string("string"),
          "type": .string(mode == "blank-record" ? "record" : "text"),
        ])
      })
    confirmations.recordFailure(
      tool: "workspace_action",
      arguments: .object(["action": .string("app.run"), "arguments": .object(arguments)]),
      result: .object([
        "errors": .array([.string("Supply months as a string")]),
        "invocationInputContract": contract,
        "changes": .array(mode == "partial-write" ? [.object(["saved": .bool(true)])] : []),
      ]), receiptID: "incomplete")
    var repaired = correct.object
    if mode == "different-value" {
      repaired["inputs"] = .object(inputs.object.merging(["principal": .string("24000")]) { $1 })
    }
    confirmations.record(
      tool: "workspace_action",
      arguments: .object(["action": .string("app.run"), "arguments": .object(repaired)]),
      result: .object(["outcome": .string("completed")]), receiptID: "repaired")
    try expectEqual(
      confirmations.hasUnresolvedFailure,
      ["different-value", "partial-write", "optional-blank", "nonblank-unicode"].contains(mode))
  }
}

private actor FailedDefinitionConfirmationModel: WorkbookInference {
  let identity = "synthetic failed definition confirmation"
  let lastMetrics: Value = .null
  let basis: String
  let source: Item
  let queue: Bool
  var step = 0
  init(basis: String, source: Item, queue: Bool = false) {
    self.basis = basis
    self.source = source
    self.queue = queue
  }
  func beginRun() {}
  func endRun() {}
  func respond(
    messages: [InferenceMessage], directory: URL, cancellation: Cancellation,
    progress: @escaping @Sendable (String) -> Void, toolScope: InferenceToolScope,
    citationIDs: [String]
  ) throws -> NativeReply {
    step += 1
    let name: String
    let arguments: Value
    if step == 1 {
      name = queue ? "start_workflow" : "save_definition"
      arguments =
        queue
        ? .object(["id": .string(identifier()), "arguments": .object([:])])
        : .object(["logicalID": .string(identifier()), "content": .object([:])])
    } else if step == 2 && basis == "evidence" {
      name = "read"
      arguments = .object(["id": .string(source.id)])
    } else {
      name = "finish"
      arguments = .object([
        "basis": .string(basis),
        "answer": .string(
          basis == "evidence"
            ? "The source records ALPHA-CHECK." : "The reusable behavior was saved successfully."),
        "citations": .array(basis == "evidence" ? [.string(source.id)] : []),
      ])
    }
    return .init(
      text: "", calls: [try .init(id: identifier(), operation: name, arguments, scope: toolScope)])
  }
}

/// Proposes a record with a meaning the items table refuses, then either a corrected
/// retry under another title or an answer.
private actor MeaningModel: WorkbookInference {
  let identity = "synthetic record meaning refusal"
  let lastMetrics: Value = .null
  let retry: Bool
  var step = 0
  var refusal = ""
  init(retry: Bool) { self.retry = retry }
  func beginRun() {}
  func endRun() {}
  func respond(
    messages: [InferenceMessage], directory: URL, cancellation: Cancellation,
    progress: @escaping @Sendable (String) -> Void, toolScope: InferenceToolScope,
    citationIDs: [String]
  ) throws -> NativeReply {
    step += 1
    if step == 2 { refusal = messages.last?.content ?? "" }
    let tool: String
    let args: Value
    if step == 1 || (step == 2 && retry) {
      tool = "propose_record"
      args = .object([
        "title": .string(step == 1 ? "User Presence Record" : "User Retention Request"),
        "text": .string("The user asked to be kept."), "kind": .string("user_status"),
        "meaning": .string(step == 1 ? "Record of user request to be kept." : "commitment"),
        "inputs": .array([]),
      ])
    } else {
      tool = "finish"
      args = .object([
        "answer": .string("I could not save that record."), "basis": .string("general"),
        "citations": .array([]),
      ])
    }
    return .init(text: "", calls: [try .init(id: identifier(), operation: tool, args, scope: toolScope)])
  }
}

/// A meaning outside the set is refused in words the model can act on and saves nothing.
/// A corrected retry, even under another title, leaves no stale failure in its receipt.
func checkRecordMeaningRefusal() async throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(
    "meaning-" + identifier())
  defer { try? FileManager.default.removeItem(at: root) }
  for retry in [true, false] {
    let book = try Workbook.create(
      at: root.appendingPathComponent("\(retry).sevra"), title: "Meaning")
    let model = MeaningModel(retry: retry)
    let result = try await WorkbookAgent.run("Keep me.", workbook: book, model: model)
    let refusal = await model.refusal
    try expectEqual(refusal.contains(Item.meaningRefusal), true)
    try expectEqual(refusal.contains("CHECK constraint"), false)
    let records = try book.items().filter { $0.category == "record" }
    let last = try expectValue(book.messages().last { $0.role == "assistant" })
    if retry {
      try expectEqual(records.map(\.title), ["User Retention Request"])
      try expectEqual(result.state, "needs_review")
      try expectEqual(last.body.contains("Couldn’t"), false)
    } else {
      try expectEqual(records.isEmpty, true)
      try expectEqual(result.state == "needs_review", false)
      try expectEqual(last.body.contains("Couldn’t finish preparing the proposal"), true)
    }
  }
}
