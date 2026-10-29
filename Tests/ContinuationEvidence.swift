import Foundation
import SevraCore

func checkContinuationEvidence(at root: URL) {
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
