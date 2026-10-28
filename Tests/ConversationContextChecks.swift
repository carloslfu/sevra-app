import Foundation
import SevraCore

private func sql(_ file: URL, _ script: String) throws -> String {
  let process = Process()
  let input = Pipe()
  let output = Pipe()
  process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
  process.arguments = [file.path]
  process.standardInput = input
  process.standardOutput = output
  try process.run()
  try input.fileHandleForWriting.write(contentsOf: Data(script.utf8))
  try input.fileHandleForWriting.close()
  let result = output.fileHandleForReading.readDataToEndOfFile()
  process.waitUntilExit()
  try expect(process.terminationStatus == 0, "Fixture SQL failed")
  return String(decoding: result, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
}

private func legacyBook(_ root: URL, name: String, version: Int = 1) throws -> URL {
  let path = root.appendingPathComponent(name + ".sevra")
  for folder in [
    path, path.appendingPathComponent("assets"), path.appendingPathComponent("staging"),
  ] {
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
  }
  try Data(
    "{\"format\":\"sevra\",\"version\":1,\"id\":\"legacy-fixture\",\"title\":\"Legacy\"}".utf8
  )
  .write(to: path.appendingPathComponent("manifest.json"))
  let fixture = Bundle.module.url(
    forResource: "schema-v\(version)", withExtension: "sql", subdirectory: "Fixtures")!
  let schema = try String(contentsOf: fixture, encoding: .utf8)
  _ = try sql(
    path.appendingPathComponent("workbook.sqlite"),
    schema + """
      INSERT INTO messages VALUES('old-user','main','user','Keep purchase code P-27 and do not invent a currency','complete','2026-10-25T10:00:00Z');
      INSERT INTO messages VALUES('old-answer','main','assistant','The code is P-27','complete','2026-10-25T10:01:00Z');
      INSERT INTO chapters VALUES('old-chapter','Purchasing','old-user');
      UPDATE meta SET value='5' WHERE key='revision';
      """)
  return path
}

func checkConversationContext(at root: URL) {
  check("unsupported development formats are refused without changing their bytes") {
    for version in 1...6 {
      let path = try legacyBook(root, name: "UnsupportedV\(version)", version: version)
      let database = path.appendingPathComponent("workbook.sqlite")
      let before = try Data(contentsOf: database)
      try refuses("schema") { _ = try Workbook(path) }
      try expect(
        try Data(contentsOf: database) == before, "Refusal changed an unsupported workbook")
    }
  }
  check("future and untrusted current schemas are refused without changing data") {
    for mode in ["future", "trigger", "references"] {
      let path = root.appendingPathComponent("Refuse-" + mode + ".sevra")
      _ = try Workbook.create(at: path, title: "Refusal")
      let database = path.appendingPathComponent("workbook.sqlite")
      let alteration: String
      switch mode {
      case "future": alteration = "PRAGMA user_version=99;"
      case "trigger":
        alteration =
          "CREATE TRIGGER unexpected AFTER INSERT ON messages BEGIN DELETE FROM items; END;"
      default:
        alteration =
          "INSERT INTO lineage VALUES('missing-child','missing-parent','derives-from','fixture');"
      }
      _ = try sql(database, alteration)
      let before = try Data(contentsOf: database)
      try refuses(mode == "references" ? "integrity" : "schema") { _ = try Workbook(path) }
      try expect(try Data(contentsOf: database) == before, "Refusal changed original bytes")
    }
  }
  check("history paging preserves Unicode, NUL, payloads and conversation scope") {
    let book = try Workbook.create(
      at: root.appendingPathComponent("History.sevra"), title: "History")
    let first = try book.addMessage("Café\0one", role: "user")
    let tangent = try book.tangent(title: "Other", parentMessage: first)
    _ = try book.addMessage("Private tangent code", role: "user", conversation: tangent)
    let metadata: Value = .object([
      "callID": .string("call-1"), "arguments": .object(["quantity": .string("0.10")]),
    ])
    let second = try book.addMessage("Recorded", role: "assistant", payload: metadata)
    let third = try book.addMessage(String(repeating: "x", count: 100_000), role: "user")
    _ = try book.addMessage(String(repeating: "y", count: 100_000), role: "assistant")
    let page = try book.historySlice(limit: 2)
    try expect(page.messages.map(\.id) == [first, second] && page.hasMore)
    try expect(page.payloads[second] == metadata)
    try expect(try book.historyMessage(first).body == "Café\0one")
    let next = try book.historySlice(after: second, byteLimit: 128_000)
    try expect(next.messages.map(\.id) == [third] && next.hasMore)
    try expect(try book.historySlice(through: second).digest == page.digest)
    try refuses("history_scope") { _ = try book.historyMessage(first, conversation: tangent) }
    try refuses("history_scope") { _ = try book.historySlice(conversation: tangent, after: first) }
    try refuses("history_range") { _ = try book.historySlice(after: third, through: first) }
    try expect(try book.historySlice(after: next.messages.last!.id).messages.count == 1)
  }
  check("conversation FTS uses bounded scoped cursors and supports rebuilding") {
    let book = try Workbook.create(
      at: root.appendingPathComponent("HistorySearch.sevra"), title: "History search")
    var ids: [String] = []
    for n in 0..<8 { ids.append(try book.addMessage("Supplier café note \(n)", role: "user")) }
    let tangent = try book.tangent(title: "Tangent", parentMessage: ids[0])
    _ = try book.addMessage("supplier secret", role: "user", conversation: tangent)
    let page = try book.searchHistory("cafe", limit: 3)
    try expect(page["hits"].array.map { $0["id"].text } == Array(ids.suffix(3).reversed()))
    let cursor = page["nextCursor"].text
    let next = try book.searchHistory("cafe", cursor: cursor, limit: 3)
    try expect(next["hits"].array.map { $0["id"].text } == [ids[4], ids[3], ids[2]])
    try expect(try book.searchHistory("secret")["hits"].array.isEmpty)
    try refuses("stale_cursor") {
      _ = try book.searchHistory("cafe", conversation: tangent, cursor: cursor)
    }
    let cancel = Cancellation()
    cancel.cancel()
    try refuses("cancelled") { _ = try book.searchHistory("cafe", cancellation: cancel) }
    _ = try book.addMessage("new", role: "assistant")
    try expect(try book.searchHistory("cafe", cursor: cursor)["hits"].array.count == 5)
    try book.rebuildSearch()
    try expect(try book.searchHistory("cafe")["hits"].array.count == 8)
    try expect(try book.verify()["ok"] == .bool(true))
  }
  check("checkpoint publication validates range, revision, cancellation and exact inputs") {
    let book = try Workbook.create(
      at: root.appendingPathComponent("CheckpointGuards.sevra"), title: "Guards")
    let source = try book.addItem(
      category: "source", kind: "note", title: "Constraint", text: "No currency specified")
    let user = try book.addMessage("Compare suppliers", role: "user")
    let incomplete = try book.historySlice()
    try refuses("checkpoint_boundary") {
      _ = try book.saveContextCheckpoint(
        incomplete, summary: "Pending", model: "fixture", template: "v1")
    }
    let end = try book.addMessage("No evidence yet", role: "assistant", state: "failed")
    let history = try book.historySlice()
    let before = try book.revision()
    try refuses("checkpoint_input") {
      _ = try book.saveContextCheckpoint(
        history, summary: "Closed", model: "fixture", template: "v1",
        evidenceIDs: [source.logicalID])
    }
    let cancel = Cancellation()
    cancel.cancel()
    try refuses("cancelled") {
      _ = try book.saveContextCheckpoint(
        history, summary: "Closed", model: "fixture", template: "v1", cancellation: cancel)
    }
    let skip = try book.historySlice(after: user)
    try refuses("checkpoint_chain") {
      _ = try book.saveContextCheckpoint(
        skip, summary: "Skipped request", model: "fixture", template: "v1")
    }
    var forged = try encoded(history).object
    forged["digest"] = .string(String(repeating: "0", count: 64))
    let changed = try JSONDecoder().decode(
      HistorySlice.self, from: Data(Value.object(forged).json().utf8))
    try refuses("checkpoint_history") {
      _ = try book.saveContextCheckpoint(
        changed, summary: "Forged", model: "fixture", template: "v1")
    }
    try expect(try book.contextCheckpoints().isEmpty && book.revision() == before)
    _ = try book.addMessage("New request", role: "user")
    try refuses("stale_revision") {
      _ = try book.saveContextCheckpoint(
        history, summary: "Stale", model: "fixture", template: "v1")
    }
    let fresh = try book.historySlice(through: end)
    let id = try book.saveContextCheckpoint(
      fresh, summary: "Closed failed request", model: "fixture", template: "v1",
      evidenceIDs: [source.id], token: "once")
    try expect(
      try book.saveContextCheckpoint(
        fresh, summary: "Closed failed request", model: "fixture", template: "v1",
        evidenceIDs: [source.id], token: "once") == id)
    try expect(try book.contextCheckpoints().count == 1)
  }
  check("checkpoint chain retains originals and derives current meaning/acceptance") {
    let book = try Workbook.create(
      at: root.appendingPathComponent("ContextChain.sevra"), title: "Chain")
    let source = try book.addItem(
      category: "source", kind: "assumption", title: "Estimate", text: "Five units",
      meaning: "estimate")
    _ = try book.addMessage("Forecast five units", role: "user")
    let end = try book.addMessage(
      "Ready to review", role: "assistant", state: "needs_review",
      payload: .object(["exact": .string(source.id)]))
    let history = try book.historySlice()
    let first = try book.saveContextCheckpoint(
      history, summary: "The forecast was accepted", model: "fixture", template: "v1",
      evidenceIDs: [source.id])
    try expect(try book.item(source.id).status == "draft", "Digest accidentally accepted an item")
    let accepted = try book.accept(source.id)
    let projection = try book.contextCheckpoint(first)
    try expect(projection["inputs"].array[0]["originalStatus"].text == "draft")
    try expect(projection["inputs"].array[0]["currentStatus"].text == "accepted")
    try expect(projection["inputs"].array[0]["currentMeaning"].text == "estimate")
    try expect(projection["inputs"].array[0]["currentVersionID"].text == accepted.id)
    _ = try book.addMessage("Return later", role: "user")
    _ = try book.addMessage("Cancelled", role: "assistant", state: "cancelled")
    let second = try book.saveContextCheckpoint(
      book.historySlice(after: end), summary: "Second request closed", model: "fixture",
      template: "v2", parentID: first)
    try expect(try book.contextCheckpoints().first?["id"].text == second)
    try expect(try book.historySlice(through: end).digest == history.digest)
    let archive = root.appendingPathComponent("ContextChain.sevraz")
    try book.export(to: archive)
    let reopened = try Workbook.openArchive(
      archive, at: root.appendingPathComponent("ContextCopy.sevra"))
    try expect(try reopened.contextCheckpoints().count == 2)
    try expect(try reopened.historySlice(through: end).digest == history.digest)
    try expect(try reopened.messagePayload(end)["exact"].text == source.id)
    try expect(try reopened.verify()["ok"] == .bool(true))
    _ = try sql(
      reopened.url.appendingPathComponent("workbook.sqlite"),
      "UPDATE message_payloads SET payload='{}' WHERE message_id='\(end)';")
    try refuses("integrity") { _ = try reopened.verify() }
    try refuses("integrity") { _ = try reopened.contextCheckpoint(first) }
  }
  check("run request linkage is scoped and preserved across reopen") {
    let book = try Workbook.create(
      at: root.appendingPathComponent("RunRequests.sevra"), title: "Runs")
    let message = try book.addMessage("Find a source", role: "user")
    let tangent = try book.tangent(title: "Other", parentMessage: message)
    try refuses("run_request") {
      _ = try book.startAgentRun(conversation: tangent, model: "fixture", requestMessageID: message)
    }
    try expect(try book.agentRuns().isEmpty)
    let run = try book.startAgentRun(
      conversation: "main", model: "fixture", requestMessageID: message)
    try book.finishAgentRun(run, status: "cancelled", steps: 0, metrics: .array([]))
    try expect(try Workbook(book.url).agentRuns().first?["request_message_id"].text == message)
  }
  check("mid-run checkpoint retains a complete tool group and refuses an invented boundary") {
    let book = try Workbook.create(
      at: root.appendingPathComponent("MidRun.sevra"), title: "Mid-run")
    let request = try book.addMessage("Compare both costs and then explain", role: "user")
    let run = try book.startAgentRun(
      conversation: "main", model: "fixture", requestMessageID: request)
    var forged = try encoded(book.historySlice()).object
    var messages = forged["messages"]!.array
    var message = messages[0].object
    message["role"] = .string("assistant")
    messages[0] = .object(message)
    forged["messages"] = .array(messages)
    let fake = try JSONDecoder().decode(
      HistorySlice.self, from: Data(Value.object(forged).json().utf8))
    try refuses("checkpoint_boundary") {
      _ = try book.saveContextCheckpoint(
        fake, summary: "False boundary", model: "fixture", template: "v1")
    }
    let receipt: Value = .object([
      "receiptVersion": .number(1), "runID": .string(run), "callID": .string("calc-1"),
      "tool": .string("calculate"), "arguments": .object(["expression": .string("12.40*2")]),
      "result": .object(["result": .string("24.8")]), "assistantText": .string(""),
    ])
    let end = try book.addMessage(receipt.json(), role: "tool")
    let id = try book.saveContextCheckpoint(
      book.historySlice(), summary: "First cost is computed; explanation remains pending",
      model: "fixture", template: "v1", runID: run)
    try expect(try book.contextCheckpoint(id)["last_message"].text == end)
    try expect(try book.agentRuns().first?["status"].text == "running")
    try expect(try book.historyMessage(request).body == "Compare both costs and then explain")
    try expect(try book.verify()["ok"] == .bool(true))
  }
}
