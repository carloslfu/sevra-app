import Foundation
import SevraAI
import SevraCore

private actor HistoryToolInference: WorkbookInference {
  let identity = "scripted history retrieval"
  let lastMetrics: Value = .object([:])
  let large: Bool
  var steps = 0
  init(large: Bool) { self.large = large }
  func beginRun() {}
  func endRun() {}
  func respond(
    messages: [InferenceMessage], directory: URL, cancellation: Cancellation,
    progress: @escaping @Sendable (String) -> Void, finishOnly: Bool, citationIDs: [String]
  ) throws -> NativeReply {
    steps += 1
    let tool: String
    let args: Value
    if steps == 1 {
      try expectEqual(messages.contains { $0.content.contains("MAPLE-27") }, false)
      tool = large ? "datasets" : "history_search"
      args = large ? .object([:]) : .object(["query": .string("purchase code")])
    } else if steps == 2 {
      let result = try Value.parse(messages.last!.content)
      try expectEqual(messages.last!.content.utf8.count <= 16_000, true)
      if large {
        try expectEqual(result["complete"], .bool(false))
        try expectEqual(result["receiptID"].text.isEmpty, false)
        tool = "tool_result"
        args = .object([
          "id": result["receiptID"], "path": .array([.string("0"), .string("title")]),
        ])
      } else {
        let hit = try expectValue(result["hits"].array.first)
        tool = "history_read"
        args = .object(["id": hit["id"]])
      }
    } else {
      try expectEqual(steps, 3)
      let result = try Value.parse(messages.last!.content)
      if large {
        try expectEqual(result["value"].text, "Large table")
      } else {
        try expectEqual(result["message"]["body"].text.contains("MAPLE-27"), true)
        try expectEqual(citationIDs.contains(result["citation"].text), true)
      }
      tool = "finish"
      args = .object([
        "answer": .string(
          large
            ? "The table is named Large table."
            : "You supplied purchase code MAPLE-27 and did not specify a currency."),
        "citations": .array(large ? [] : [result["citation"]]),
      ])
    }
    return NativeReply(
      text: "",
      calls: [InferenceCall(id: "history-\(steps)", name: tool, inputJSON: try args.json())])
  }
}

func checkHistoryTools() async throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(
    "sevra-history-tools-" + identifier())
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: root) }
  for large in [false, true] {
    let book = try Workbook.create(
      at: root.appendingPathComponent("\(large).sevra"), title: "History")
    if large {
      let source = try book.addItem(category: "source", kind: "note", title: "Table input")
      _ = try book.createDataset(
        title: "Large table",
        columns: (0..<400).map {
          Column(id: "field\($0)", title: "Field \($0)", type: "text")
        }, rows: [], sourceID: source.id)
    } else {
      _ = try book.addMessage(
        "Our purchase code is MAPLE-27. Do not invent a currency.", role: "user")
      for index in 0..<110 { _ = try book.addMessage("Closed note \(index)", role: "assistant") }
    }
    let model = HistoryToolInference(large: large)
    let result = try await WorkbookAgent.run(
      large ? "Find the name of the table." : "What purchase code did I supply earlier?",
      workbook: book, model: model)
    try expectEqual(result.state, "complete")
    try expectEqual(result.steps, 3)
    if !large {
      try expectEqual(result.citations.first?.hasPrefix("message:"), true)
      try expectEqual(result.answer.contains("sevra://conversation/main?message="), true)
      try expectThrows(
        try book.addItem(
          category: "record", kind: "analysis", title: "Invalid business lineage",
          inputs: result.citations))
      let run = try book.agentRuns().first!
      let current = try WorkbookTools(book, runID: run["id"].text).execute(
        "history_read", .object(["id": run["request_message_id"]]))
      try expectEqual(current["citation"], .null)
      try expectEqual(WorkbookAgent.visibleEvidence(tool: "history_read", result: current).count, 0)
    }
    try expectEqual(try book.unresolvedToolCalls().isEmpty, true)
    try expectEqual(try book.verify()["ok"], .bool(true))
    let receipts = try book.messages().filter { $0.role == "tool" }
    try expectEqual(receipts.count, 2)
    for receipt in receipts {
      let body = try Value.parse(receipt.body)
      try expectEqual(try book.toolCall(body["receiptID"].text)["state"].text, "completed")
    }
  }
  let hit: Value = .object([
    "itemID": .string("observed"), "snippet": .string("Five units"), "locator": .string("page 1"),
  ])
  let omitted: Value = .object([
    "omitted": .bool(true), "path": .array([.string("hits"), .string("1")]),
  ])
  let page: Value = .object([
    "complete": .bool(false), "type": .string("array"),
    "entries": .array([
      .object(["index": .number(0), "value": hit]),
      .object(["index": .number(1), "value": omitted]),
    ]),
  ])
  let observed = WorkbookAgent.visibleEvidence(
    tool: "search", result: ToolResultProjection.visibleValue(page), path: ["hits"])
  try expectEqual(observed.map { $0.0 }, ["observed"])
  try expectEqual(WorkbookAgent.visibleEvidence(tool: "history_read", result: hit).count, 0)
  try expectEqual(
    WorkbookAgent.visibleEvidence(
      tool: "search", result: .object(["itemID": .string("unseen")]), path: ["hits", "1"]
    ).count, 0)
  print("PASS shared agent retrieves old originals and pages oversized saved results")
}
