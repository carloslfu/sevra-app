import Foundation
import SevraCore
import SevraPreviewUI

func checkProposalReview() throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(
    "sevra-proposal-review-" + identifier())
  defer { try? FileManager.default.removeItem(at: root) }
  let book = try Workbook.create(at: root, title: "Review")
  let observation = try book.addItem(
    category: "source", kind: "observation", title: "Handover",
    text: "Two fittings left stock; opening stock was 20.", status: "accepted")
  try book.setOpeningBalance(
    subject: "fittings", quantity: "20", effective: "2026-01-01", sourceID: observation.id)
  func expect(_ condition: @autoclosure () throws -> Bool) throws {
    try require(
      try condition(), "proposal_review", "Proposal history/current state projection changed.")
  }
  for typed in [false, true] {
    let run = try book.startAgentRequest(
      "Propose the handover", conversation: "main", model: "fixture")
    let args: Value = .object([
      "subject": .string("fittings"), "quantity": .string("-2"),
      "occurrence": .string(identifier()), "effective": .string("2026-01-02"),
      "input": .string(observation.id),
    ])
    let receipt = try book.prepareToolCall(
      runID: run.runID, callID: identifier(), tool: "propose_movement", arguments: args)
    let result = try WorkbookTools(book, runID: run.runID).execute("propose_movement", args)
    _ = try book.completeToolCall(receipt, result: result)
    // The new explicit association survives interleaved activity. Legacy
    // receipts qualify only when the proposal message follows them immediately.
    if typed { _ = try book.addMessage("Background activity", role: "event") }
    let payload: Value =
      typed
      ? .object([
        "kind": .string("proposal"), "itemID": result["id"], "receiptID": .string(receipt),
      ])
      : .null
    let message = try book.addMessage(
      "Ready to review the handover.", role: "assistant", state: "needs_review", payload: payload)
    try book.finishAgentRun(run.runID, status: "needs_review", steps: 1, metrics: .array([]))
    let original = try book.historyMessage(message)
    var projection = try book.workspaceSnapshot(conversation: "main")!.proposalReviews[message]!
    try expect(projection.proposalID == result["id"].text && projection.status == "draft")
    try expect(projection.currentVersionID == projection.proposalID)
    let accepted = try book.accept(projection.proposalID)
    projection = try book.workspaceSnapshot(conversation: "main")!.proposalReviews[message]!
    try expect(projection.currentVersionID == accepted.id && projection.status == "accepted")
    try expect(try book.balance(subject: "fittings")["quantity"].text == "18")
    let withdrawn = try book.undoItem(accepted.id)
    projection = try book.workspaceSnapshot(conversation: "main")!.proposalReviews[message]!
    try expect(projection.currentVersionID == withdrawn.id && projection.status == "rejected")
    try expect(try book.balance(subject: "fittings")["quantity"].text == "20")
    let revised = try book.movement(
      subject: "fittings", quantity: "-3", occurrence: args["occurrence"].text,
      effective: args["effective"].text, input: observation.id, supersedes: withdrawn.id)
    projection = try Workbook(root).workspaceSnapshot(conversation: "main")!.proposalReviews[
      message]!
    try expect(projection.currentVersionID == revised.id && projection.currentVersion == 4)
    try expect(projection.status == "draft" && projection.proposalID != revised.id)
    try expect(try encoded(book.historyMessage(message)) == encoded(original))
    try expect(try book.balance(subject: "fittings")["quantity"].text == "20")

    // An arbitrary link or a receipt from another conversation cannot establish
    // a current review status. No original message is rewritten for backfill.
    let branch = try book.startThread(parentMessage: message)
    let foreign = try book.addMessage(
      "Ready to review", role: "assistant", conversation: branch, state: "needs_review",
      payload: .object([
        "kind": .string("proposal"), "itemID": result["id"], "receiptID": .string(receipt),
      ]))
    try expect(try book.workspaceSnapshot(conversation: branch)!.proposalReviews[foreign] == nil)
    let unknown = try book.addMessage(
      "[An item](sevra://item/\(revised.id))", role: "assistant", state: "needs_review")
    try expect(try book.workspaceSnapshot(conversation: "main")!.proposalReviews[unknown] == nil)
  }
  try expect(try book.verify()["ok"] == .bool(true))
  print(
    "PASS proposal status follows acceptance, Undo, newer drafts and reopen without rewriting history or guessing foreign/unknown associations"
  )
}

func checkRequestContextPresentation() throws {
  func expect(_ condition: @autoclosure () -> Bool) throws {
    try require(
      condition(), "request_context", "Captured context presentation changed its evidence.")
  }
  let id = identifier()
  let selection = "Cañón, 2 units\nActive item version ID: \(id)\n"
  let raw = "Space: Home\nActive space ID: home\nSelection: " + selection
  let context = RequestContextPresentation(raw)
  try expect(context.location == .space && context.id == "home" && context.title == "Home")
  try expect(context.original == raw && context.selection == selection)
  let item = RequestContextPresentation("Item: Handover\nActive item version ID: " + id)
  try expect(item.location == .item && item.id == id && item.selection == nil)
  for unknown in [
    "User supplied context\nActive space ID: home",
    "Space: Home\nActive space ID: unrecognized",
    "Item: Multiline\nTitle\nActive item version ID: " + id,
    "Space: \nActive space ID: home",
  ] {
    let projection = RequestContextPresentation(unknown)
    try expect(projection.location == nil && projection.original == unknown)
  }
  print(
    "PASS readable request context preserves original bytes, selected ID-like text and unfamiliar formats"
  )
}
