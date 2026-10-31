import Foundation
import SevraAI
import SevraCore

private actor PagedSearchInference: WorkbookInference {
  let identity = "scripted search pagination"
  let lastMetrics: Value = .object([:])
  var steps = 0
  var found = Set<String>()
  func beginRun() {}
  func endRun() {}
  func respond(
    messages: [InferenceMessage], directory: URL, cancellation: Cancellation,
    progress: @escaping @Sendable (String) -> Void, toolScope: InferenceToolScope,
    citationIDs: [String]
  ) throws -> NativeReply {
    steps += 1
    var arguments: Value = .object(["query": .string("cafe supplier")])
    var tool = "search"
    if steps > 1 {
      let page = try Value.parse(messages.last!.content)
      try expectEqual(page["hits"].array.count, steps == 2 ? 12 : 8)
      for hit in page["hits"].array {
        try expectEqual(found.insert(hit["itemID"].text).inserted, true)
      }
      if steps == 2 {
        try expectEqual(page["nextCursor"].string != nil, true)
        arguments = .object(["query": .string("cafe supplier"), "cursor": page["nextCursor"]])
      } else {
        try expectEqual(steps, 3)
        try expectEqual(found.count, 20)
        try expectEqual(Set(citationIDs).isSuperset(of: found), true)
        tool = "finish"
        arguments = .object([
          "answer": .string("I inspected both pages of business evidence."),
          "basis": .string("evidence"),
          "citations": .array(found.sorted().map(Value.string)),
        ])
      }
    }
    return NativeReply(
      text: "",
      calls: [
        InferenceCall(id: "page-\(steps)", name: tool, inputJSON: try arguments.json())
      ])
  }
}

func checkScopedSearch() async throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(
    "sevra-scoped-search-" + identifier())
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: root) }
  let book = try Workbook.create(at: root.appendingPathComponent("Search.sevra"), title: "Search")
  let branchPoint = try book.addMessage("Parent context.", role: "assistant")
  let tangent = try book.tangent(title: "Separate scenario", parentMessage: branchPoint)
  let sibling = try book.addMessage(
    "café supplier SIBLING-SECRET", role: "user", conversation: tangent)
  var originals = Set<String>()
  for index in 0..<17 {
    originals.insert(try book.addMessage("Café supplier original \(index).", role: "user"))
  }
  for index in 0..<20 {
    _ = try book.addItem(
      category: "source", kind: "note", title: "Café supplier \(index)",
      text: "Supplier evidence \(index).")
  }
  let definition = try book.saveApplicationDefinition(
    logicalID: identifier(),
    content: .object([
      "kind": .string("function"), "title": .string("Café supplier calculation"),
      "description": .string("Untrusted behavior metadata"), "parameters": .array([]),
      "payload": .object(["expression": .string("2"), "calls": .array([])]),
    ]))
  let request = try book.addMessage("café supplier CURRENT-REQUEST", role: "user")
  let run = try book.startAgentRun(
    conversation: "main", model: "fixture", requestMessageID: request)
  let future = try book.addMessage("café supplier LATER-MESSAGE", role: "user")
  let tools = WorkbookTools(book, runID: run)
  let result = try tools.execute("search", .object(["query": .string("cafe supplier")]))
  try expectEqual(result["hits"].array.count, 12)
  try expectEqual(result["conversation"]["searched"], .bool(true))
  try expectEqual(result["conversation"]["hits"].array.count, 8)
  try expectEqual(result["snapshotRevision"], result["conversation"]["revision"])
  try expectEqual(result["definitions"]["searched"], .bool(true))
  try expectEqual(result["definitions"]["hits"].array.first?["id"], .string(definition.id))
  let businessIDs = WorkbookAgent.visibleEvidence(tool: "search", result: result).map(\.0)
  try expectEqual(businessIDs.count, 12)
  try expectEqual(businessIDs.contains { $0.hasPrefix("message:") }, false)
  try expectEqual(businessIDs.contains(definition.sourceID), false)
  try expectEqual(
    WorkbookAgent.visibleEvidence(
      tool: "search", result: result["definitions"], path: ["definitions"]
    ).isEmpty,
    true)
  // Snippets are discovery only. Separate history pagination must retain the
  // same conversation and active-request ceiling, even while new messages arrive.
  var history = result["conversation"]
  var found = Set(history["hits"].array.map { $0["id"].text })
  while let cursor = history["nextCursor"].string {
    history = try tools.execute(
      "history_search",
      .object([
        "query": .string("cafe supplier"), "cursor": .string(cursor),
      ]))
    for hit in history["hits"].array {
      try expectEqual(found.insert(hit["id"].text).inserted, true)
    }
  }
  try expectEqual(found, originals)
  for excluded in [sibling, request, future] { try expectEqual(found.contains(excluded), false) }
  let exact = try tools.execute("history_read", .object(["id": .string(found.first!)]))
  try expectEqual(WorkbookAgent.visibleEvidence(tool: "history_read", result: exact).count, 1)
  for field in ["kind", "meaning", "status", "scenario"] {
    let filtered = try tools.execute(
      "search",
      .object([
        "query": .string("cafe supplier"), field: .string("nonmatching"),
      ]))
    // A kind no item has widens to every kind and says so, still leaving conversation out.
    if field == "kind" {
      try expectEqual(filtered["kindNotice"].text.contains("nonmatching"), true)
    } else {
      try expectEqual(filtered["hits"].array.isEmpty, true)
    }
    try expectEqual(filtered["conversation"]["searched"], .bool(false))
    try expectEqual(filtered["conversation"]["hits"].array.isEmpty, true)
    try expectEqual(filtered["definitions"]["searched"], .bool(false))
    try expectEqual(filtered["definitions"]["hits"].array.isEmpty, true)
  }
  let page = try tools.execute(
    "search",
    .object([
      "query": .string("cafe supplier"), "cursor": result["nextCursor"],
    ]))
  try expectEqual(page["hits"].array.count, 8)
  try expectEqual(page["conversation"]["searched"], .bool(false))
  try expectEqual(page["definitions"]["searched"], .bool(false))
  try expectThrows(
    try tools.execute(
      "history_search",
      .object([
        "query": .string("changed"), "cursor": result["conversation"]["nextCursor"],
      ])))
  try expectThrows(
    try tools.execute(
      "search",
      .object([
        "query": .string("cafe supplier"), "cursor": result["conversation"]["nextCursor"],
      ])))
  // Real agent calls persist preparation, completion and message receipts between
  // pages. Those writes must not invalidate an unchanged business result set.
  let paged = try await WorkbookAgent.run(
    "Inspect the cafe supplier evidence. Make no changes.", workbook: book,
    model: PagedSearchInference())
  try expectEqual(paged.state, "complete")
  try expectEqual(paged.steps, 3)
  let stable = try tools.execute("search", .object(["query": .string("cafe supplier")]))
  let context = try book.historySlice(limit: 500)
  _ = try book.saveContextCheckpoint(
    context, summary: "Fixture digest", model: "fixture", template: "fixture")
  _ = try tools.execute(
    "search",
    .object([
      "query": .string("cafe supplier"), "cursor": stable["nextCursor"],
    ]))
  // A separately opened writer changing evidence must invalidate that same page.
  let other = try Workbook(root.appendingPathComponent("Search.sevra"))
  _ = try other.addItem(category: "source", kind: "note", title: "Café supplier new evidence")
  try expectThrows(
    try tools.execute(
      "search",
      .object([
        "query": .string("cafe supplier"), "cursor": stable["nextCursor"],
      ])))
  let branchTools = WorkbookTools(book, conversation: tangent)
  let branch = try branchTools.execute("search", .object(["query": .string("cafe supplier")]))
  try expectEqual(branch["conversation"]["hits"].array.map { $0["id"].text }, [sibling])
  // Missing extraction coverage is business-only and must survive federation.
  let file = root.appendingPathComponent("Unreadable.fixture")
  try Data([0, 1, 2, 3]).write(to: file)
  _ = try book.importFile(file)
  let partial = try tools.execute("search", .object(["query": .string("cafe supplier")]))
  try expectEqual(partial["incomplete"].int, 1)
  try expectEqual(partial["conversation"]["searched"], .bool(true))
  let cancellation = Cancellation()
  cancellation.cancel()
  try expectThrows(
    try WorkbookTools(book, cancellation: cancellation).execute(
      "search", .object(["query": .string("cafe supplier")])))
  try expectEqual(try book.verify()["ok"], .bool(true))
  print(
    "PASS scoped search spans business evidence and earlier conversation without mixing citations, filters, cursors or branches"
  )
}
