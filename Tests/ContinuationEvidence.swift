import Foundation
import SevraCore

func checkContinuationEvidence(at root: URL) {
  check("one request saves one space per title, however its components are named") {
    let book = try Workbook.create(at: root.appendingPathComponent("Spaces.sevra"), title: "Spaces")
    let request = try book.addMessage("Save one review", role: "user")
    let run = try book.startAgentRun(
      conversation: "main", model: "fixture", requestMessageID: request)
    func save(_ title: String, component: String) throws -> Value {
      let definition = SpaceDefinition(components: [
        .init(id: component, type: "text", title: title, text: "In progress")
      ])
      let args: Value = .object(["title": .string(title), "definition": try encoded(definition)])
      let id = try book.prepareToolCall(
        runID: run, callID: identifier(), tool: "save_space", arguments: args)
      let result = try WorkbookTools(book, runID: run).execute("save_space", args)
      _ = try book.completeToolCall(id, result: result)
      return result
    }
    let first = try save("Receiving review", component: "one")
    try expect(try save("Receiving review", component: "one") == first)
    try refuses("space_duplicate") { _ = try save("Receiving review", component: "two") }
    try refuses("space_duplicate") { _ = try save("RECEIVING REVIEW", component: "three") }
    _ = try save("Another view", component: "two")
    try expect(try book.spaces().filter { $0.title == "Receiving review" }.count == 1)
    try expect(try book.spaces().count == 3)
    // A later request cannot save it again either, and it hears what the stopped one finished.
    try book.finishAgentRun(run, status: "cancelled", steps: 3, metrics: .array([]))
    let next = try book.startAgentRun(
      conversation: "main", model: "fixture",
      requestMessageID: try book.addMessage("Please continue", role: "user"))
    let stopped = try book.continuationState(conversation: "main", runID: next, messageIDs: [])[
      "stoppedRequest"]
    try expect(stopped["messageID"].text == request && stopped["status"].text == "cancelled")
    try expect(stopped["saved"].array.map { $0["title"].text } == ["Receiving review", "Another view"])
    try expect(stopped["text"] == .null)
    try refuses("space_duplicate") {
      _ = try WorkbookTools(book, runID: next).execute(
        "save_space",
        .object([
          "title": .string("Receiving review"),
          "definition": try encoded(
            SpaceDefinition(components: [.init(type: "text", title: "Later", text: "Again")])),
        ]))
    }
    try book.finishAgentRun(next, status: "complete", steps: 1, metrics: .array([]))
    let after = try book.startAgentRun(
      conversation: "main", model: "fixture",
      requestMessageID: try book.addMessage("Something else", role: "user"))
    try expect(
      try book.continuationState(conversation: "main", runID: after, messageIDs: [])[
        "stoppedRequest"] == .null)
  }
  check("a stopped request's text stays once read, across another stop, and only then") {
    let book = try Workbook.create(
      at: root.appendingPathComponent("Stopped.sevra"), title: "Stopped")
    func start(_ words: String) throws -> (run: String, message: String) {
      let message = try book.addMessage(words, role: "user")
      return (
        try book.startAgentRun(conversation: "main", model: "fixture", requestMessageID: message),
        message
      )
    }
    func call(_ run: String, _ name: String, _ args: Value) throws {
      let id = try book.prepareToolCall(
        runID: run, callID: identifier(), tool: name, arguments: args)
      let result = try WorkbookTools(book, runID: run).execute(name, args)
      _ = try book.completeToolCall(id, result: result)
    }
    func stopped(_ run: String) throws -> Value {
      try book.continuationState(conversation: "main", runID: run, messageIDs: [])["stoppedRequest"]
    }
    func space(_ title: String) throws -> Value {
      .object([
        "title": .string(title),
        "definition": try encoded(
          SpaceDefinition(components: [.init(type: "text", title: title, text: "Open")])),
      ])
    }
    let source = try book.addItem(
      category: "source", kind: "document", title: "Report", text: "Line one.\n", meaning: "estimate")
    let first = try start("Save a review, read the report, then save a memo.")
    try call(first.run, "save_space", try space("Review"))
    try call(first.run, "read", .object(["id": .string(source.id)]))
    try book.finishAgentRun(first.run, status: "cancelled", steps: 2, metrics: .array([]))

    // Reads do not carry over, so they are not listed as finished work.
    let second = try start("Please continue")
    var state = try stopped(second.run)
    try expect(state["messageID"].text == first.message && state["text"] == .null)
    try expect(state["saved"].array.map { $0["tool"].text } == ["save_space"])
    try expect(state["notice"].text.contains("history_read"))
    try expect(state["notice"].text.contains("Earlier reads do not carry over"))

    // Reading another message keeps nothing. Reading this one keeps its words.
    let unrelated = try book.addMessage("Something unrelated", role: "user")
    try call(second.run, "history_read", .object(["id": .string(unrelated)]))
    try expect(try stopped(second.run)["text"] == .null)
    try call(second.run, "history_read", .object(["id": .string(first.message)]))
    state = try stopped(second.run)
    try expect(state["text"].text == "Save a review, read the report, then save a memo.")
    try expect(state["notice"].text.contains("applies only if the current request asks"))
    try call(second.run, "save_space", try space("Second view"))
    try book.finishAgentRun(second.run, status: "failed", steps: 2, metrics: .array([]))

    // The next follow-up points at the first request, not at "Please continue".
    let third = try start("Continue again")
    state = try stopped(third.run)
    try expect(state["messageID"].text == first.message && state["status"].text == "failed")
    try expect(state["saved"].array.map { $0["title"].text } == ["Review", "Second view"])
    try expect(state["text"] == .null && state["earlier"] == .null)
    // Reading that request says what is done, right beside its words.
    let history = try WorkbookTools(book, runID: third.run).execute(
      "history_read", .object(["id": .string(first.message)]))
    try expect(history["message"]["body"].text.contains("Save a review"))
    try expect(history["stoppedRequest"]["saved"].array.count == 2)
    try expect(history["stoppedRequest"]["notice"].text.contains("do not repeat"))
    let plain = try WorkbookTools(book, runID: third.run).execute(
      "history_read", .object(["id": .string(unrelated)]))
    try expect(plain["stoppedRequest"] == .null)
    try book.finishAgentRun(third.run, status: "complete", steps: 0, metrics: .array([]))
    let newWork = try start("New work")
    try expect(try stopped(newWork.run) == .null)
    try book.finishAgentRun(newWork.run, status: "complete", steps: 0, metrics: .array([]))

    // A follow-up that stopped without reading its request leaves that request findable.
    let job = try start("Save a second review.")
    try call(job.run, "save_space", try space("Third view"))
    try book.finishAgentRun(job.run, status: "cancelled", steps: 1, metrics: .array([]))
    let lost = try start("Please continue")
    try book.finishAgentRun(lost.run, status: "cancelled", steps: 0, metrics: .array([]))
    let again = try start("Continue")
    state = try stopped(again.run)
    try expect(state["messageID"].text == lost.message)
    try expect(state["earlier"].array == [.string(job.message)])
    try expect(state["saved"].array.map { $0["title"].text } == ["Third view"])
    try expect(state["notice"].text.contains("earlier lists older stopped requests"))
    try call(again.run, "history_read", .object(["id": .string(job.message)]))
    state = try stopped(again.run)
    try expect(state["text"].text == "Save a second review.")
    try book.finishAgentRun(again.run, status: "complete", steps: 0, metrics: .array([]))

    // A very long request stays behind history_read instead of filling the context.
    let long = try start(String(repeating: "long ", count: 2000))
    try book.finishAgentRun(long.run, status: "interrupted", steps: 0, metrics: .array([]))
    let afterLong = try start("Continue")
    try call(afterLong.run, "history_read", .object(["id": .string(long.message)]))
    state = try stopped(afterLong.run)
    try expect(state["text"] == .null && state["notice"].text.contains("history_read"))
  }
  check("continuation preserves exact source bindings and saved spaces, with live version status") {
    let book = try Workbook.create(
      at: root.appendingPathComponent("Continuing.sevra"), title: "Continue")
    let request = try book.addMessage("Read both and save one review", role: "user")
    let run = try book.startAgentRun(
      conversation: "main", model: "fixture", requestMessageID: request)
    func call(_ name: String, _ args: Value) throws -> Value {
      let id = try book.prepareToolCall(
        runID: run, callID: identifier(), tool: name, arguments: args)
      let result = try WorkbookTools(book, runID: run).execute(name, args)
      _ = try book.completeToolCall(id, result: result)
      return result
    }
    var originals: [Item] = []
    for (name, value) in [("Cedar", "0.31"), ("Iris", "0.32")] {
      let text = "\(name): \(value) mm. HOLD.\n\0" + String(repeating: "🌱", count: 500)
      let source = try book.addItem(
        category: "source", kind: "document", title: name, text: text, meaning: "estimate")
      originals.append(source)
      _ = try call("read", .object(["id": .string(source.id)]))
    }
    let definition = SpaceDefinition(components: [
      .init(type: "text", title: "Review", text: "In progress")
    ])
    let space = try call(
      "save_space",
      .object(["title": .string("Receiving review"), "definition": try encoded(definition)]))[
        "spaceID"
      ].text
    let accepted = try book.accept(originals[0].id)
    _ = try book.saveSpace(
      id: space, title: "Renamed by user", definition: definition, expectedVersion: 1)
    let revision = try book.revision()
    let state = try book.continuationState(conversation: "main", runID: run, messageIDs: [])
    let entries = state["readEvidence"]["entries"].array
    try expect(entries.map { $0["versionID"].text } == originals.map(\.id))
    for (entry, original) in zip(entries, originals) {
      try expect(entry["textPrefix"].text == String(original.text.unicodeScalars.prefix(256)))
      try expect(entry["title"].text == original.title && entry["resultHash"].text.count == 64)
      try expect(try book.toolCall(entry["receiptID"].text)["tool"].text == "read")
    }
    try expect(entries[0]["originalStatus"].text == "draft")
    try expect(
      entries[0]["currentStatus"].text == "accepted"
        && entries[0]["currentMeaning"].text == "estimate")
    try expect(
      entries[0]["currentVersionID"].text == accepted.id
        && entries[0]["isCurrentVersion"] == .bool(false))
    try expect(state["savedSpaces"].array.count == 1)
    try expect(state["savedSpaces"].array[0]["spaceID"].text == space)
    try expect(state["savedSpaces"].array[0]["savedTitle"].text == "Receiving review")
    try expect(state["savedSpaces"].array[0]["currentTitle"].text == "Renamed by user")
    try expect(state["savedSpaces"].array[0]["currentVersion"].int == 2)
    try expect(try book.revision() == revision && book.verify()["ok"] == .bool(true))
    let archive = root.appendingPathComponent("Continuing.sevraz")
    try book.export(to: archive)
    let copy = try Workbook.openArchive(
      archive, at: root.appendingPathComponent("ContinuingCopy.sevra"))
    let recovered = try copy.continuationState(conversation: "main", runID: run, messageIDs: [])
    try expect(
      recovered["readEvidence"] == state["readEvidence"]
        && recovered["savedSpaces"] == state["savedSpaces"])
  }
  check(
    "continuation evidence is bounded, deduplicated and isolated from old, failed and foreign calls"
  ) {
    let book = try Workbook.create(
      at: root.appendingPathComponent("EvidenceScopes.sevra"), title: "Scopes")
    func run(_ text: String, conversation: String = "main") throws -> String {
      let request = try book.addMessage(text, role: "user", conversation: conversation)
      return try book.startAgentRun(
        conversation: conversation, model: "fixture", requestMessageID: request)
    }
    func read(_ item: Item, run: String, failed: Bool = false) throws -> String {
      let args: Value = .object(["id": .string(item.id)])
      let receipt = try book.prepareToolCall(
        runID: run, callID: identifier(), tool: "read", arguments: args)
      _ = try book.completeToolCall(
        receipt, result: WorkbookTools(book, runID: run).execute("read", args), failed: failed)
      return try book.toolCall(receipt)["message_id"].text
    }
    let old = try book.addItem(
      category: "source", kind: "document", title: "Old run only", text: "Old run evidence")
    let previous = try run("Old request")
    let oldMessage = try read(old, run: previous)
    try book.finishAgentRun(previous, status: "complete", steps: 1, metrics: .array([]))
    let current = try run("New request")
    var ids: [String] = []
    for index in 0..<10 {
      let source = try book.addItem(
        category: "source", kind: "document", title: "Report \(index)",
        text: "Value \(index). " + String(repeating: "x", count: 1600))
      ids.append(source.id)
      _ = try read(source, run: current)
    }
    _ = try read(book.item(ids.last!), run: current)
    _ = try read(old, run: current, failed: true)
    // A projected omission is not a newly observed item, even when its original
    // journal contains text. Only fields actually shown to this run are retained.
    let omitted = try book.prepareToolCall(
      runID: current, callID: "omitted", tool: "read", arguments: .object(["id": .string(old.id)]))
    _ = try book.completeToolCall(
      omitted,
      result: .object([
        "item": .object([
          "id": .string(old.id), "text": .string(old.text),
          "data": .string(String(repeating: "x", count: 30_000)),
        ])
      ]))
    _ = try book.prepareToolCall(
      runID: current, callID: "pending", tool: "read", arguments: .object(["id": .string(old.id)]))
    let state = try book.continuationState(
      conversation: "main", runID: current, messageIDs: [oldMessage])
    let entries = state["readEvidence"]["entries"].array
    try expect(entries.map { $0["versionID"].text } == Array(ids.suffix(8)))
    try expect(state["readEvidence"]["omittedVersions"].int == 2)
    try expect(try Value.array(entries).json().utf8.count <= 8192)
    try expect(!entries.contains { $0["versionID"].text == old.id })
    let branch = try book.tangent(title: "Other", parentMessage: oldMessage)
    let other = try run("Other request", conversation: branch)
    try expect(
      try book.continuationState(conversation: branch, runID: other, messageIDs: [])[
        "readEvidence"]["entries"].array.isEmpty)
    try refuses("context_scope") {
      _ = try book.continuationState(conversation: branch, runID: current, messageIDs: [])
    }
    try expect(try book.verify()["ok"] == .bool(true))
  }
  check("continuation refuses a read excerpt that differs from the immutable source") {
    let book = try Workbook.create(
      at: root.appendingPathComponent("ForgedRead.sevra"), title: "Read")
    let source = try book.addItem(
      category: "source", kind: "document", title: "Cedar", text: "0.31 mm")
    let request = try book.addMessage("Inspect", role: "user")
    let run = try book.startAgentRun(
      conversation: "main", model: "fixture", requestMessageID: request)
    let receipt = try book.prepareToolCall(
      runID: run, callID: "wrong-value", tool: "read",
      arguments: .object(["id": .string(source.id)]))
    _ = try book.completeToolCall(
      receipt,
      result: .object([
        "item": .object(["id": .string(source.id), "text": .string("0.35 mm")])
      ]))
    try refuses("integrity") {
      _ = try book.continuationState(conversation: "main", runID: run, messageIDs: [])
    }
    try expect(try book.item(source.id).text == "0.31 mm")
  }
}
