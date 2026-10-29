import Foundation
import SevraCore
import SevraPreviewUI

private func expectClarification(_ condition: Bool, _ message: String) throws {
  try require(condition, "clarification_input_check", message)
}

private func clarificationFault(_ book: Workbook, _ sql: String) throws {
  let process = Process()
  process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
  process.arguments = [book.url.appendingPathComponent("workbook.sqlite").path, sql]
  process.standardOutput = Pipe()
  process.standardError = Pipe()
  try process.run()
  process.waitUntilExit()
  try require(
    process.terminationStatus == 0, "clarification_input_check",
    "Cannot prepare synthetic presentation fault.")
}

@MainActor func checkWorkflowClarificationDrafts() async throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(
    "clarification-inputs-" + identifier())
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: root) }
  let book = try Workbook.create(
    at: root.appendingPathComponent("Inputs.sevra"), title: "Synthetic missing count")
  let evidence = try book.addItem(
    category: "source", kind: "observation", title: "Synthetic receipt",
    text: "The received count was not recorded.")
  let other = try book.addItem(
    category: "source", kind: "observation", title: "Unrelated synthetic evidence")
  let parameters: Value = .array([
    .object([
      "id": .string("evidence"), "label": .string("Evidence"), "type": .string("item"),
      "required": .bool(true),
    ])
  ])
  let interpretation = try book.saveApplicationDefinition(
    logicalID: identifier(),
    content: .object([
      "kind": .string("interpretation"), "title": .string("Read received count"),
      "description": .string("Synthetic missing information"), "parameters": parameters,
      "payload": .object([
        "instruction": .string("Ask if the received count is missing."),
        "evidence": .array([.string("evidence")]),
        "outputs": .array([
          .object([
            "id": .string("quantity"), "label": .string("Received count"),
            "type": .string("decimal"), "unit": .string("items"), "required": .bool(true),
          ]),
          .object([
            "id": .string("confirmed"), "label": .string("Confirmed"), "type": .string("boolean"),
            "required": .bool(false),
          ]),
          .object([
            "id": .string("original"), "label": .string("Original"), "type": .string("item"),
            "required": .bool(false),
          ]),
        ]), "meaning": .string("actual"), "scenario": .string("actual"),
      ]),
    ]))
  let function = try book.saveApplicationDefinition(
    logicalID: identifier(),
    content: .object([
      "kind": .string("function"), "title": .string("Double"),
      "description": .string("Synthetic calculation"),
      "parameters": .array([
        .object([
          "id": .string("quantity"), "label": .string("Count"), "type": .string("decimal"),
          "required": .bool(true), "unit": .string("items"),
        ])
      ]),
      "payload": .object(["expression": .string("quantity * 2"), "unit": .string("items")]),
    ]))
  let workflow = try book.saveApplicationDefinition(
    logicalID: identifier(),
    content: .object([
      "kind": .string("workflow"), "title": .string("Read and double"),
      "description": .string("Synthetic clarification journey"), "parameters": parameters,
      "payload": .object([
        "readPolicy": .string("latest-at-step"),
        "steps": .array([
          .object([
            "id": .string("read"), "kind": .string("interpret"),
            "binding": .object(["mode": .string("exact"), "versionID": .string(interpretation.id)]),
            "arguments": .object(["evidence": .object(["parameter": .string("evidence")])]),
          ]),
          .object([
            "id": .string("double"), "kind": .string("evaluate"),
            "binding": .object(["mode": .string("exact"), "versionID": .string(function.id)]),
            "arguments": .object([
              "quantity": .object([
                "step": .string("read"), "field": .string("quantity"), "unit": .string("items"),
              ])
            ]),
          ]),
        ]),
      ]),
    ]))
  func pause(_ runID: String) throws {
    let local = try book.authorizeWorkflowExecution(runID)
    let claim = try book.claimWorkflowStep(local, owner: "Synthetic input fixture")
    let request = try book.prepareWorkflowInterpretation(
      local, claim: claim, model: "Synthetic, no inference")
    let response: Value = .object([
      "request": request,
      "response": .object([
        "state": .string("needs_input"), "values": .object([:]), "citations": .array([]),
        "issues": .array([.string("Supply the missing count.")]),
      ]), "metrics": .object(["synthetic": .bool(true)]),
    ])
    _ = try book.completeWorkflowStep(local, claim: claim, interpretation: response)
  }
  func start() throws -> String {
    let run = try book.startWorkflow(
      workflow.id, arguments: .object(["evidence": .string(evidence.id)]), token: identifier())
    try pause(run["id"].text)
    return run["id"].text
  }
  func values(_ count: String) -> Value {
    .object(["quantity": .string(count), "confirmed": .bool(false)])
  }
  let runID = try start()
  let scope = WorkflowClarificationScope()
  try expectClarification(await scope.open(book), "Cannot open clarification scope")
  let first = scope.session(runID)!
  await first.open()
  let original = try book.workflowRun(runID)
  let revision = try book.revision()
  let history = try book.committedHistory()
  first.update(values: values("not a number yet"), reason: "Unsent café 日本語")
  try expectClarification(await scope.flush(), "Cannot save incomplete answer")
  try expectClarification(
    try book.revision() == revision && book.committedHistory() == history,
    "Keystrokes changed business history")
  let rebuilt = try book.reconstruct(to: root.appendingPathComponent("Unsent.sevra"))
  try expectClarification(
    try rebuilt.workflowClarificationDraft(runID) == first.state, "Reconstruction lost raw draft")
  let second = WorkflowClarificationSession(workbook: try Workbook(book.url), runID: runID)
  await second.open()
  try expectClarification(second.state == first.state, "Reopen lost unsent input")
  await second.prepare()
  try expectClarification(
    second.preview == nil && second.failure != nil && second.state == first.state,
    "Invalid preview dropped inputs")
  second.update(
    values: .object(["quantity": .string("0"), "original": .string(other.id)]),
    reason: "Synthetic supply")
  await second.prepare()
  try expectClarification(
    second.preview == nil && second.failure != nil, "Unrelated evidence entered the answer")
  second.update(values: values("0"), reason: "Synthetic zero, deliberately supplied")
  await second.prepare()
  try expectClarification(
    second.preview?["values"]["quantity"] == .string("0")
      && second.preview?["values"]["confirmed"] == .bool(false),
    "Zero/false were defaulted or discarded")
  first.update(values: values("5"), reason: "First synthetic window")
  try expectClarification(await first.flush(), "First window save failed")
  second.update(values: values("6"), reason: "Second synthetic window")
  try expectClarification(
    !(await second.flush()) && second.conflict, "Concurrent writer silently overwrote answer")
  await second.keepBoth()
  try expectClarification(
    !second.conflict
      && second.state?.alternatives.contains(where: { $0.values == values("5") }) == true,
    "Keep both lost first answer")
  try expectClarification(
    second.state?.entry.token != first.state?.entry.token, "Divergent answer reused retry identity")
  await second.prepare()
  let prepared = second.state!
  let preview = second.preview!
  try expectClarification(try book.workflowRun(runID) == original, "Preview advanced the workflow")
  // Deliberately stop between durable submission and presentation confirmation.
  let receipt = try book.submitWorkflowClarificationDraft(prepared, preview: preview)
  let afterSubmission = try book.revision()
  let recovered = WorkflowClarificationSession(workbook: try Workbook(book.url), runID: runID)
  await recovered.open()
  try expectClarification(
    recovered.state?.entry.receipt == receipt,
    "Saved operation did not recover missing presentation receipt")
  await recovered.submit()
  try expectClarification(
    try book.revision() == afterSubmission, "Reopen repeated the business operation")
  let submittedRun = try book.workflowRun(runID)
  let output = submittedRun["steps"].array[0]["output"]["value"]
  let supplied = try book.item(output["clarification"]["sourceID"].text)
  try expectClarification(
    output["response"]["values"] == .object([:])
      && supplied.data["actor"]["kind"] == .string("human"),
    "Native submission lost original/human provenance")
  try expectClarification(
    receipt["state"] == .string("queued")
      && submittedRun["steps"].array[1]["state"] == .string("pending")
      && receipt["steps"] == .null && receipt["operationID"] == .string(prepared.entry.token)
      && (try receipt.json().utf8.count) < 2048,
    "Submission implicitly continued or cached a full run"
  )
  let copy = try book.reconstruct(to: root.appendingPathComponent("Submitted.sevra"))
  try expectClarification(
    try copy.workflowClarificationDraft(runID) == recovered.state,
    "Submitted presentation receipt did not reconstruct")
  _ = try copy.verify()

  // A third window may retain an older unsent variant of an entry that another
  // window subsequently edited and submitted under its shared retry identity.
  let collisionID = try start()
  let writer = WorkflowClarificationSession(workbook: book, runID: collisionID)
  let competing = WorkflowClarificationSession(workbook: try Workbook(book.url), runID: collisionID)
  await writer.open()
  await competing.open()
  writer.update(values: values("1"), reason: "First pending variant")
  try expectClarification(await writer.flush(), "Cannot save first variant")
  competing.update(values: values("2"), reason: "Second pending variant")
  _ = await competing.flush()
  await competing.keepBoth()
  let third = WorkflowClarificationSession(workbook: try Workbook(book.url), runID: collisionID)
  await third.open()
  let retained = third.state!.alternatives.first(where: { $0.values == values("1") })!
  competing.update(values: values("5"), reason: "Edited and explicitly submitted variant")
  await competing.prepare()
  await competing.submit()
  try expectClarification(competing.state?.entry.receipt != nil, "Competing submission failed")
  await third.restoreAlternative(retained.id)
  try expectClarification(third.conflict, "Restoring an old window ignored newer submission")
  await third.keepBoth()
  try expectClarification(
    !third.conflict && !third.dirty, "Submitted-versus-unsent conflict could not retain both")
  try expectClarification(
    third.state?.alternatives.contains(where: { $0.values == values("5") && $0.receipt != nil })
      == true
      && third.state?.alternatives.contains(where: { $0.values == values("2") && $0.receipt == nil }
      ) == true, "Keep both confused saved receipt with older unsent values")

  let staleID = try start()
  let stale = scope.session(staleID)!
  await stale.open()
  stale.update(values: values("7"), reason: "Unsent before retry")
  try expectClarification(await stale.flush(), "Cannot save before retry")
  let old = stale.state!
  _ = try book.retryWorkflow(book.authorizeWorkflowExecution(staleID), token: identifier())
  await stale.prepare()
  try expectClarification(
    stale.preview == nil && stale.state == old && stale.failure != nil,
    "Retry silently rebound or discarded answer")
  try pause(staleID)
  await stale.useCurrent()
  try expectClarification(
    stale.state?.entry.target != old.entry.target && stale.state?.entry.values == old.entry.values
      && stale.state?.alternatives.contains(old.entry) == true
      && stale.state?.entry.token != old.entry.token,
    "Explicit rebind lost old draft or reused token")
  await stale.restoreAlternative(old.entry.id)
  try expectClarification(
    stale.state?.entry == old.entry, "Restoring alternative lost exact target")
  await stale.prepare()
  try expectClarification(stale.preview == nil, "Old target submitted to new attempt")
  let staleCopy = try book.reconstruct(to: root.appendingPathComponent("Stale.sevra"))
  try expectClarification(
    try staleCopy.workflowClarificationDraft(staleID) == stale.state,
    "Stale draft became unreadable after reconstruction")
  let oldDraft = stale.state!
  var forged = oldDraft
  var target = forged.entry.target.object
  target["meaning"] = .string("estimate")
  forged.entry = .init(target: .object(target))
  do {
    _ = try book.saveWorkflowClarificationDraft(staleID, draft: forged, expected: oldDraft)
    throw SevraError("test", "Forged original target saved")
  } catch let error as SevraError {
    try expectClarification(error.code != "test", "Forged target accepted")
  }
  stale.update(values: values("8"), reason: "Unsent during write fault")
  try clarificationFault(
    book,
    "CREATE TRIGGER fail_clarification_draft BEFORE UPDATE ON meta WHEN NEW.key LIKE 'workflow-clarification-draft:%' BEGIN SELECT RAISE(ABORT,'synthetic presentation write fault'); END"
  )
  try expectClarification(
    !(await scope.flush()) && stale.dirty && stale.failure != nil, "Failed save discarded input")
  let unrelated = try Workbook.create(
    at: root.appendingPathComponent("Other.sevra"), title: "Other")
  try expectClarification(
    !(await scope.open(unrelated)) && scope.session(staleID) === stale,
    "Workbook switch abandoned unsaved answer")
  try expectClarification(
    !(await WorkflowClarificationScope.flushAll()), "Quit gate ignored failed save")
  try clarificationFault(book, "DROP TRIGGER fail_clarification_draft")
  try expectClarification(await scope.flush(), "Retry did not save retained input")
  _ = try book.verify()
  print(
    "PASS native clarification inputs: incomplete/stale/reconstructed drafts, scoped evidence, zero/false, conflict/keep-both, exact receipt recovery, separate continuation, failed save/switch/quit gates"
  )
}
