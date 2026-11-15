import Foundation
import SevraAI
import SevraAppUI
import SevraCore
import SevraNativeAI

@MainActor func runChatOperationProbe(
  modelsRoot: String, library: String, engine: String, output: String
) async throws {
  let root = URL(fileURLWithPath: output)
  try require(
    !FileManager.default.fileExists(atPath: root.path), "fixture", "Use a new output directory.")
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  let model = NativeWorkbookModel(
    configuration: try nativeProbeConfiguration(
      library: library, engine: engine, modelsRoot: modelsRoot,
      budget: .init(profile: .evaluation32K), reasoning: .bounded512, modelLayout: .installed))
  let book = try Workbook.create(
    at: root.appendingPathComponent("Stock.sevra"), title: "Synthetic stock")
  let package = try NativeAppPackage.decode(
    Data(contentsOf: URL(fileURLWithPath: "examples/apps/inventory/app.sevraapp")))
  let space = try book.installNativeAppContents(package)
  let suite = "Sevra-chat-probe-" + identifier()
  let defaults = UserDefaults(suiteName: suite)!
  defer { defaults.removePersistentDomain(forName: suite) }
  let session = NativeAppSession(book: book, space: space, defaults: defaults)
  defer { session.stop() }
  _ = try await session.converse("enable")
  let table = space.definition.app!.datasets["stock"]!.datasetID!
  var results: [Value] = []
  func ask(_ name: String, _ request: String) async throws -> AgentResult {
    let started = Date()
    let result = try await WorkbookAgent.run(
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
          try require(
            arguments["expectedVersion"].int == space.version, "stale_app",
            "Inspect current version.")
        }
        return try await session.converse(
          String(action.dropFirst(4)), arguments: arguments, readOnly: readOnly,
          cancellation: cancellation)
      })
    results.append(
      .object([
        "case": .string(name), "request": .string(request), "answer": .string(result.answer),
        "state": .string(result.state), "steps": .number(Double(result.steps)),
        "seconds": .number(Date().timeIntervalSince(started)),
        "rows": try encoded(book.rows(table)),
      ]))
    try Data(Value.array(results).json().utf8).write(
      to: root.appendingPathComponent("results.json"), options: .atomic)
    try Data(encoded(book.messages(limit: 500)).json().utf8).write(
      to: root.appendingPathComponent("messages.json"), options: .atomic)
    print("CHAT PROBE " + name + ": " + result.answer)
    return result
  }
  let added = try await ask(
    "add", "In the Stock room app, add Pencils with quantity 3. Do it here in chat.")
  try expectEqual(added.answer.contains("Couldn’t finish"), false)
  try expectEqual(try book.rows(table).count, 1)
  try expectEqual(try book.rows(table)[0].data["name"].text, "Pencils")
  try expectEqual(try book.rows(table)[0].data["quantity"].text, "3")
  let edited = try await ask("edit", "Change Pencils to quantity 5 in the Stock room app.")
  try expectEqual(edited.answer.contains("Couldn’t finish"), false)
  try expectEqual(try book.rows(table).count, 1)
  try expectEqual(try book.rows(table)[0].data["quantity"].text, "5")
  let namedWrites = try book.messages(limit: 500).filter { message in
    guard message.role == "tool", let receipt = try? Value.parse(message.body) else { return false }
    return receipt["tool"] == .string("workspace_action")
      && receipt["arguments"]["action"] == .string("app.run")
      && receipt["result"]["outcome"] == .string("completed")
      && !receipt["result"]["changes"].array.isEmpty
  }
  try expectEqual(namedWrites.count, 2)
  let question = try await ask("missing-input", "Add Notebooks in the Stock room app.")
  try expectEqual(try book.rows(table).count, 1)
  try expectEqual(
    question.answer.lowercased().contains("quantity")
      || question.answer.lowercased().contains("how many"), true)
  _ = try await ask("undo", "Undo the last saved change in the Stock room app.")
  try expectEqual(try book.rows(table)[0].data["quantity"].text, "3")
  try expectEqual(try Workbook(book.url).rows(table).count, 1)
  print(
    "PASS live chat: named insert, edit, missing-input clarification, Undo and reopen without a renderer"
  )
}
