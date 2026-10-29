import Foundation
import SevraCore
import SevraPreviewUI

@MainActor func checkWorkflowFormDrafts() async throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(
    "sevra-workflow-form-" + identifier())
  defer { try? FileManager.default.removeItem(at: root) }
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  let book = try Workbook.create(
    at: root.appendingPathComponent("Forms.sevra"), title: "Synthetic forms")
  let source = try book.addItem(
    category: "source", kind: "observation", title: "Synthetic receipt", status: "accepted")
  let action = try book.saveApplicationDefinition(
    logicalID: identifier(), content: ActionRegistry.receivingDefinition())
  let workflow = try book.saveApplicationDefinition(
    logicalID: identifier(),
    content: .object([
      "kind": .string("workflow"), "title": .string("Receive and review"),
      "description": .string("Synthetic"),
      "parameters": action.parameters,
      "payload": .object([
        "readPolicy": .string("latest-at-step"),
        "steps": .array([
          .object([
            "id": .string("receive"), "kind": .string("action"),
            "binding": .object(["mode": .string("exact"), "versionID": .string(action.id)]),
            "arguments": .object(
              Dictionary(
                uniqueKeysWithValues: action.parameters.array.map {
                  ($0["id"].text, Value.object(["parameter": $0["id"]]))
                })),
          ]),
          .object([
            "id": .string("review"), "kind": .string("review"), "review": .string("receive"),
          ]),
        ]),
      ]),
    ]))
  let form = try book.saveApplicationDefinition(
    logicalID: identifier(), content: ActionRegistry.formDefinition(target: workflow))
  let arguments: Value = .object([
    "delivery": .string("synthetic-1"), "effective": .string("2026-10-28"),
    "evidence": .string(source.id),
    "lines": .array([
      .object(["line": .string("1"), "subject": .string("bolts"), "quantity": .string("5")])
    ]),
  ])
  let session = FormDraftSession(workbook: book, key: "workflow")
  await session.open(form.id)
  session.update(arguments)
  let saved = await session.flush()
  try require(saved, "workflow_form_check", session.failure ?? "Inputs were not saved")
  await session.prepare()
  try require(
    session.preview?["kind"] == .string("workflow"), "workflow_form_check",
    session.failure ?? "No workflow preview")
  await session.submit()
  let receipt = session.state?.lastReceipt
  try require(
    receipt?["workflowRunID"].string != nil, "workflow_form_check",
    session.failure ?? "No workflow receipt")
  let revision = try book.revision()
  let recovered = FormDraftSession(workbook: try Workbook(book.url), key: "workflow")
  await recovered.open(form.id)
  await recovered.submit()
  try require(
    recovered.state?.lastReceipt == receipt && book.revision() == revision, "workflow_form_check",
    "Reopening submitted the form twice")

  let crash = FormDraftSession(workbook: book, key: "before-presentation-save")
  await crash.open(form.id)
  crash.update(arguments)
  let persisted = await crash.flush()
  try require(persisted, "workflow_form_check", "Missing saved submission identity")
  let state = crash.state!
  let committed = try book.submitFormDraft(
    state, preview: book.previewFormDraft(state), actor: .human("SevraNativeForm"))
  try require(
    try book.formDraft("before-presentation-save")?.lastReceipt == nil, "workflow_form_check",
    "Fixture did not stop before presentation save")
  let afterCrash = FormDraftSession(
    workbook: try Workbook(book.url), key: "before-presentation-save")
  await afterCrash.open(form.id)
  try require(
    afterCrash.state?.lastReceipt == committed, "workflow_form_check",
    afterCrash.failure ?? "Committed run was not reconciled")
  let runs = try book.workflowRuns()
  try require(
    runs.count == 2 && runs.allSatisfy { $0["state"] == .string("queued") }, "workflow_form_check",
    "Recovery started a worker or created a duplicate run")
  try require(
    try book.counts()["records"].int == 0 && book.verify()["ok"] == .bool(true),
    "workflow_form_check", "Preview/recovery changed business data")
  print("PASS workflow form input ownership, exact submission recovery and inert queued runs")
}
