import Foundation
import SevraCore

func checkToolReceipts(at root: URL) {
  check("journal preserves large exact results with valid bounded Unicode pages") {
    let book = try Workbook.create(
      at: root.appendingPathComponent("Receipts.sevra"), title: "Receipts")
    let request = try book.addMessage("Read this table", role: "user")
    let run = try book.startAgentRun(
      conversation: "main", model: "fixture", requestMessageID: request)
    let text = String(repeating: "café\0👩🏽‍💻\n", count: 12_000)
    let large: Value = .object([
      "id": .string("exact"), "text": .string(text),
      "data": .array(
        (0..<300).map { .object(["decimal": .string("0.10"), "index": .number(Double($0))]) }),
    ])
    let id = try book.prepareToolCall(
      runID: run, callID: "read-1", tool: "rows", arguments: .object([:])
    )
    let projected = try book.completeToolCall(id, result: large)
    try expect(try projected.json().utf8.count <= 16_000)
    try expect(try Value.parse(projected.json()) == projected)
    try expect(projected["complete"] == .bool(false))
    let before = try book.revision()
    try expect(try book.completeToolCall(id, result: large) == projected)
    try expect(try book.revision() == before)
    try refuses("idempotency") { _ = try book.completeToolCall(id, result: .null) }
    try refuses("tool_duplicate") {
      _ = try book.prepareToolCall(
        runID: run, callID: "read-1", tool: "rows", arguments: .object([:]))
    }
    var rebuilt = ""
    var offset = 0
    while true {
      let page = try book.toolResultPage(id, path: ["text"], offset: offset)
      try expect(try page.json().utf8.count <= 16_000)
      rebuilt += page["textSegment"].text
      guard let next = page["nextOffset"].int else { break }
      try expect(next > offset)
      offset = next
    }
    try expect(rebuilt == text)
    let cell = try book.toolResultPage(id, path: ["data", "299", "decimal"])
    try expect(cell["value"] == .string("0.10"))
    try refuses("result_path") { _ = try book.toolResultPage(id, path: ["data", "-1"]) }
    try refuses("result_offset") { _ = try book.toolResultPage(id, offset: -1) }
    let cancel = Cancellation()
    cancel.cancel()
    try refuses("cancelled") { _ = try book.toolResultPage(id, cancellation: cancel) }
    let tangent = try book.tangent(title: "Other", parentMessage: request)
    try refuses("tool_scope") { _ = try book.toolResultPage(id, conversation: tangent) }
    let saved = try book.historyMessage(book.toolCall(id)["message_id"].text)
    try expect(saved.body.utf8.count <= 128_000 && saved.body.contains(id))
    try expect(try book.unresolvedToolCalls().isEmpty)
    try expect(try book.verify()["ok"] == .bool(true))
    _ = try book.saveContextCheckpoint(
      book.historySlice(), summary: "Read-only result is saved.", model: "fixture", template: "v1",
      runID: run)
    let archive = root.appendingPathComponent("Receipts.sevraz")
    try book.export(to: archive)
    if let fixture = ProcessInfo.processInfo.environment["SEVRA_RECEIPT_FIXTURE"] {
      try FileManager.default.copyItem(at: archive, to: URL(fileURLWithPath: fixture))
    }
    let restored = try Workbook.openArchive(
      archive, at: root.appendingPathComponent("RestoredReceipts.sevra"))
    try expect(
      try restored.toolResultPage(id, path: ["data", "299"])
        == book.toolResultPage(id, path: ["data", "299"]))
    let tamper = Process()
    tamper.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
    tamper.arguments = [
      book.url.appendingPathComponent("workbook.sqlite").path,
      "UPDATE tool_calls SET result='{}' WHERE id='\(id)';",
    ]
    try tamper.run()
    tamper.waitUntilExit()
    try expect(tamper.terminationStatus == 0)
    try refuses("integrity") { _ = try book.toolResultPage(id) }
    try refuses("integrity") { _ = try book.verify() }
  }
  check("free-form writers cannot forge what the table and inventory pipelines own") {
    let book = try Workbook.create(
      at: root.appendingPathComponent("ForgedKinds.sevra"), title: "Forged")
    let request = try book.addMessage("Tidy the formatting", role: "user")
    let run = try book.startAgentRun(
      conversation: "main", model: "fixture", requestMessageID: request)
    let source = try book.addItem(category: "source", kind: "request", title: "Request")
    let tools = WorkbookTools(book, runID: run, requestSourceID: source.id)
    let table = try book.createDataset(
      title: "Stock", columns: [.init(id: "qty", title: "Qty", type: "decimal")],
      rows: [["qty": .string("10")]], sourceID: source.id)
    let row = try book.rows(table.id)[0]
    let edits = try encoded([RowEdit(id: row.id, values: ["qty": .string("999")])])
    for kind in [
      "table-change", "table-creation", "table-intake-update", "movement", "row", "decision",
      "calculation", "request", "annotation", "workflow_authorization", "excel-formulas",
    ] {
      try refuses("proposal_tool") {
        _ = try tools.execute(
          "propose_record",
          .object([
            "title": .string("Tidy formatting"), "text": .string("No values change."),
            "kind": .string(kind), "meaning": .string("plan"),
            "data": .object(["datasetID": .string(table.id), "edits": edits]),
          ]))
      }
    }
    try refuses("proposal_tool") {
      _ = try tools.execute(
        "draft",
        .object([
          "title": .string("Forged"), "text": .string("Body"),
          "data": .object(["documentComposition": .object(["version": .number(9)])]),
        ]))
    }
    let movement = try book.movement(
      subject: "bolts", quantity: "2", occurrence: "one", effective: "2026-01-01",
      input: source.id)
    for (kind, subject) in [("row", row), ("movement", movement)] {
      try refuses("proposal_tool") {
        _ = try book.addItem(
          category: "record", kind: kind, title: subject.title, data: .object([:]),
          meaning: subject.meaning, inputs: [subject.id], supersedes: subject.id)
      }
    }
    try expect(try book.rows(table.id)[0].data["qty"] == .string("10"))
    // The pipelines themselves and ordinary domain kinds keep working.
    let reviewed = try book.proposeTableEdit(
      table.id, edits: [RowEdit(id: row.id, values: ["qty": .string("12")])])
    _ = try book.accept(reviewed.id)
    try expect(try book.rows(table.id)[0].data["qty"] == .string("12"))
    let created = try book.proposeTable(
      title: "New", columns: [.init(id: "a", title: "A", type: "text")],
      rows: [["a": .string("x")]], inputs: [source.id])
    _ = try book.accept(created.id)
    let forecast = try tools.execute(
      "propose_record",
      .object([
        "title": .string("Forecast"), "text": .string("Five units"), "kind": .string("forecast"),
        "meaning": .string("estimate"),
      ]))
    try expect(try book.item(forecast["id"].text).status == "draft")
    try expect(try book.verify()["ok"] == .bool(true))
  }
  check("prepared call survives mutation gap without replay or false acceptance") {
    let path = root.appendingPathComponent("InterruptedCall.sevra")
    let book = try Workbook.create(at: path, title: "Interrupted")
    let request = try book.addMessage("Draft a forecast", role: "user")
    let run = try book.startAgentRun(
      conversation: "main", model: "fixture", requestMessageID: request)
    let source = try book.addItem(category: "source", kind: "request", title: "Forecast")
    let tools = WorkbookTools(book, runID: run, requestSourceID: source.id)
    let arguments: Value = .object([
      "title": .string("Forecast"), "text": .string("Five units"), "kind": .string("forecast"),
      "meaning": .string("estimate"),
    ])
    let id = try book.prepareToolCall(
      runID: run, callID: "draft-1", tool: "propose_record", arguments: arguments)
    let result = try tools.execute("propose_record", arguments)
    // Deliberately omit completeToolCall: this is the durable state at process death.
    let reopened = try Workbook(path)
    let before = try reopened.revision()
    let pending = try reopened.unresolvedToolCalls()
    try expect(pending.count == 1 && pending[0]["state"].text == "prepared")
    try expect(pending[0]["committedOperation"]["result"].text == result["id"].text)
    try expect(try reopened.revision() == before, "Inspecting recovery performed a mutation")
    try expect(try reopened.item(result["id"].text).status == "draft")
    try expect(try reopened.item(result["id"].text).meaning == "estimate")
    try expect(try reopened.toolResultPage(id)["state"].text == "prepared")
    let original = try reopened.completeToolCall(id, result: result)
    try expect(original == result)
    try expect(try reopened.messages().count == 2)
    try expect(try reopened.verify()["ok"] == .bool(true))
  }
  check("oversized keys have lossless raw JSON recovery and failed calls retain receipts") {
    let book = try Workbook.create(at: root.appendingPathComponent("RawResult.sevra"), title: "Raw")
    let message = try book.addMessage("Explore", role: "user")
    let run = try book.startAgentRun(
      conversation: "main", model: "fixture", requestMessageID: message)
    let id = try book.prepareToolCall(
      runID: run, callID: "unusual", tool: "fixture", arguments: .object([:]))
    let value: Value = .object([String(repeating: "k", count: 18_000): .string("0.10")])
    let view = try book.completeToolCall(id, result: value, failed: true)
    try expect(view["notice"].text.contains("rawJSON"))
    var text = ""
    var offset = 0
    while true {
      let page = try book.toolResultPage(id, offset: offset, rawJSON: true)
      text += page["textSegment"].text
      guard let next = page["nextOffset"].int else { break }
      offset = next
    }
    try expect(try Value.parse(text) == value)
    try expect(try book.toolCall(id)["state"].text == "failed")
    try expect(try book.verify()["ok"] == .bool(true))
  }
  check("agent history tools find old originals and exclude tangent messages") {
    let book = try Workbook.create(
      at: root.appendingPathComponent("HistoryTools.sevra"), title: "History")
    let old = try book.addMessage("Purchase code MAPLE-27. Do not assume a currency.", role: "user")
    for index in 0..<105 { _ = try book.addMessage("Closed note \(index)", role: "assistant") }
    let other = try book.tangent(title: "Separate", parentMessage: old)
    let secret = try book.addMessage("MAPLE private tangent", role: "user", conversation: other)
    let tools = WorkbookTools(book)
    let result = try tools.execute("history_search", .object(["query": .string("MAPLE")]))
    try expect(result["hits"].array.map { $0["id"].text } == [old])
    let read = try tools.execute("history_read", .object(["id": .string(old)]))
    try expect(read["message"]["body"].text.contains("MAPLE-27"))
    try refuses("history_scope") {
      _ = try tools.execute("history_read", .object(["id": .string(secret)]))
    }
  }
}
