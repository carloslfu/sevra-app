import Foundation
import SevraAI
import SevraCore

/// A chat request stops when it stops getting anywhere, and closes with the model's own
/// account. A count of steps is only a backstop.
func checkProgressStop() async throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(
    "sevra-progress-" + identifier())
  defer { try? FileManager.default.removeItem(at: root) }
  func book(_ name: String) throws -> Workbook {
    try Workbook.create(at: root.appendingPathComponent(name + ".sevra"), title: name)
  }
  func missing(_ id: String) -> ScriptedCalls.Step {
    call("read_definition", .object(["id": .string(id)]))
  }
  func query(_ statement: String) -> ScriptedCalls.Step {
    call("sql", .object(["statements": .array([.string(statement)])]))
  }

  // The failure this was built for: one action, the same error, different arguments. The
  // second failure brings help in place of the general advice, and the third closes the
  // request with an answer instead of a failed run.
  let stuck = ScriptedCalls([
    missing("one"), missing("two"), missing("three"),
    finish("I could not find that definition.", basis: "unresolved"),
  ])
  let closed = try await WorkbookAgent.run(
    "Open the reorder rule.", workbook: try book("Stuck"), model: stuck, conversationInput: true)
  try expectEqual(closed.state, "complete")
  try expectEqual(closed.steps, 4)
  let prompts = await stuck.prompts
  try expectEqual(prompts[1].last?.content.contains("same error as the last attempt"), false)
  try expectEqual(prompts[2].last?.content.contains("same error as the last attempt"), true)
  try expectEqual(prompts[3].last?.content.contains("Host stop:"), true)
  try expectEqual(prompts[3].first?.content.contains("Host stop: The same error came back"), true)
  try expectEqual(prompts[3].first?.conversationInput, false)

  // A closed request whose writes failed still ends in the model's account. The host names
  // the unfinished task once after it, in place of the raw errors.
  func move(_ id: String) -> ScriptedCalls.Step {
    call(
      "edit_space",
      .object([
        "id": .string("home"), "expectedVersion": .number(1),
        "edits": .array([
          .object(["operation": .string("move"), "componentID": .string(id)])
        ]),
      ]))
  }
  let account = "I could not move the cards on Home. Reply “continue” to try again."
  let unsaved = try await WorkbookAgent.run(
    "Tidy my Home.", workbook: try book("Unsaved"),
    model: ScriptedCalls([
      move("attention"), move("continue"), move("shortcuts"), finish(account, basis: "unresolved"),
    ]), conversationInput: true)
  try expectEqual(unsaved.state, "complete")
  try expectEqual(unsaved.answer, account + "\n\nCouldn’t finish saving the space.")

  // Once it is closing, the only call left is the answer.
  do {
    _ = try await WorkbookAgent.run(
      "Open the reorder rule.", workbook: try book("Closing"),
      model: ScriptedCalls([missing("one"), missing("two"), missing("three"), missing("four")]))
    throw SevraError("fixture", "A closing request ran another tool.")
  } catch let error as SevraError where error.code == "tool_scope" {}

  // Counterexample: failures that differ are attempts, not a loop. The request stays open.
  let trying = ScriptedCalls([
    missing("one"), query("SELECT * FROM nowhere"), query("SELEC 1"), query("SELECT 1 AS one"),
    finish("Hello.", basis: "general"),
  ])
  let open = try await WorkbookAgent.run(
    "Say hello.", workbook: try book("Trying"), model: trying)
  try expectEqual(open.state, "complete")
  try expectEqual(open.steps, 5)
  try expectEqual(await trying.prompts.last?.first?.content.contains("Host stop:"), false)

  // The backstop is far from where ordinary work ends, and its last steps belong to the
  // answer: a request that only ever reads is closed, not failed.
  try expectEqual(WorkbookAgent.chatStepBackstop >= 48, true)
  let reads = WorkbookAgent.chatStepBackstop - 3
  let endless = ScriptedCalls(
    (1...reads).map { query("SELECT \($0) AS n") } + [finish("Still counting.", basis: "general")])
  let backstopped = try await WorkbookAgent.run(
    "Count for me.", workbook: try book("Endless"), model: endless)
  try expectEqual(backstopped.state, "complete")
  try expectEqual(backstopped.steps, reads + 1)
  try expectEqual(
    await endless.prompts.last?.first?.content.contains(
      "Host stop: This request has taken \(reads) steps"), true)
  print("PASS progress stop: repeated error help and close, differing failures stay open, backstop closes")
}
