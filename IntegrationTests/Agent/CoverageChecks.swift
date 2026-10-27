import Foundation
import SevraAI
import SevraCore

private actor CoverageInference: WorkbookInference {
  let identity = "synthetic search coverage"
  let lastMetrics: Value = .null
  let book: Workbook
  let mode: String
  var step = 0
  var receipt = ""
  init(_ book: Workbook, _ mode: String) {
    self.book = book
    self.mode = mode
  }
  func beginRun() {}
  func endRun() {}
  func respond(
    messages: [InferenceMessage], directory: URL, cancellation: Cancellation,
    progress: @escaping @Sendable (String) -> Void, toolScope: InferenceToolScope,
    citationIDs: [String]
  ) async throws -> NativeReply {
    step += 1
    func call(_ name: String, _ input: Value) throws -> NativeReply {
      NativeReply(
        text: "", calls: [.init(id: identifier(), name: name, inputJSON: try input.json())])
    }
    func count() throws -> NativeReply {
      try call(
        "count_records", .object(["category": .string("record"), "kind": .string("movement")]))
    }
    func finish(_ answer: String, _ basis: String, coverage: Value = .array([])) throws
      -> NativeReply
    {
      try call(
        "finish",
        .object([
          "answer": .string(answer), "basis": .string(basis),
          "citations": .array([]), "coverage": coverage,
        ]))
    }
    if mode == "overclaim" || mode == "general" || mode == "gap" {
      if step == 1 {
        return try call(
          "search",
          .object([
            "query": .string(
              mode == "gap"
                ? "no invoices 10% [claim](https://example.test)" : "movement")
          ]))
      }
      if step == 2 {
        return try finish(
          "There are no inventory movements recorded in the workbook.",
          mode == "general" ? "general" : "unresolved")
      }
      try expectEqual(step, 3)
      try expectEqual(messages.last!.content.contains("Do not infer absence"), true)
      return try finish(
        "The search for ‘movement’ returned no matches. That does not establish the inventory state.",
        "unresolved")
    }
    if mode == "count_after_search" && step == 1 {
      return try call("search", .object(["query": .string("missing contract")]))
    }
    if mode == "count_after_search" && step == 2 { return try count() }
    if mode == "count_after_search" {
      receipt = try Value.parse(messages.last!.content)["receiptID"].text
      return try finish(
        "The contract was signed and paid.", "evidence", coverage: .array([.string(receipt)]))
    }
    if step == 1 { return try count() }
    if step == 2 {
      receipt = try Value.parse(messages.last!.content)["receiptID"].text
      try expectEqual(receipt.isEmpty, false)
      if mode == "stale" {
        let source = try book.addItem(category: "source", kind: "note", title: "Handover")
        _ = try book.addItem(
          category: "record", kind: "movement", title: "Dispatch", inputs: [source.id])
      }
      let value: Value =
        mode == "malformed"
        ? .array([.number(1)]) : .array([.string(mode == "forged" ? "unknown-receipt" : receipt)])
      return try finish("The invoice was paid and cash is 999.", "evidence", coverage: value)
    }
    if mode == "stale" && step == 3 {
      try expectEqual(messages.last!.content.contains("count changed"), true)
      return try count()
    }
    if mode == "stale" && step == 4 {
      receipt = try Value.parse(messages.last!.content)["receiptID"].text
    }
    // Evidence failure forces one inspection before another finish.
    if (mode == "forged" || mode == "malformed") && step == 3 {
      try expectEqual(toolScope, .inspection)
      return try count()
    }
    if mode == "forged" || mode == "malformed" {
      receipt = try Value.parse(messages.last!.content)["receiptID"].text
    }
    return try finish("The scoped count follows.", "evidence", coverage: .array([.string(receipt)]))
  }
}

func checkSearchCoverage() async throws {
  for text in [
    "There are no inventory movements recorded in the workbook.",
    "The workbook contains no invoices.", "No purchase records exist.",
    "I reviewed every document.", "This is an exhaustive search.",
    "No hay movimientos registrados.", "Revisé todos los documentos.",
  ] { try expectEqual(SearchCoverage.overstates(text), true) }
  for text in [
    "The search for ‘movement’ returned no matches.", "No currency was specified.",
    "The forecast is an accepted estimate, not actual stock.",
    "I cannot determine whether a payment happened from the retrieved evidence.",
  ] { try expectEqual(SearchCoverage.overstates(text), false) }
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(
    "sevra-coverage-" + identifier())
  defer { try? FileManager.default.removeItem(at: root) }
  let book = try Workbook.create(at: root.appendingPathComponent("Count.sevra"), title: "Scope")
  let source = try book.addItem(category: "source", kind: "note", title: "Handover")
  let first = try book.addItem(
    category: "record", kind: "movement", title: "Dispatch", meaning: "estimate",
    inputs: [source.id])
  let current = try book.addItem(
    category: "record", kind: "movement", title: "Dispatch", meaning: "estimate",
    status: "accepted", inputs: [source.id], supersedes: first.id)
  let filters: Value = .object(["category": .string("record"), "kind": .string("movement")])
  try expectEqual(try book.search("movement").hits.count, 0)
  try expectEqual(try book.countRecords(filters)["count"].int, 1)
  for (meaning, expected) in [("actual", 0), ("estimate", 1)] {
    var f = filters.object
    f["meaning"] = .string(meaning)
    f["status"] = .string("accepted")
    try expectEqual(try book.countRecords(.object(f))["count"].int, expected)
  }
  for invalid: Value in [
    .object(["category": .string("record"), "status": .string("acceptd")]),
    .object(["category": .string("record"), "meaning": .string("fact")]),
    .object(["category": .string("record"), "query": .string("anything")]),
    .object(["category": .string("record"), "kind": .number(1)]),
  ] { try expectThrows(try book.countRecords(invalid)) }
  let cancel = Cancellation()
  cancel.cancel()
  try expectThrows(try book.countRecords(filters, cancellation: cancel))
  let unindexed = root.appendingPathComponent("Unreadable.fixture")
  try Data([0, 1, 2]).write(to: unindexed)
  _ = try book.importFile(unindexed)
  try expectEqual(try book.countRecords(.object(["category": .string("source")]))["count"].int, 2)
  try expectEqual(try book.countRecords(filters)["count"].int, 1)
  try expectEqual(try book.item(current.id).meaning, "estimate")
  for mode in [
    "overclaim", "general", "valid", "forged", "malformed", "stale", "gap", "count_after_search",
  ] {
    let scenario = try Workbook.create(
      at: root.appendingPathComponent(mode + ".sevra"), title: mode)
    if mode == "gap" || mode == "count_after_search" { _ = try scenario.importFile(unindexed) }
    let reply = try await WorkbookAgent.run(
      "Check the workbook without making changes.", workbook: scenario,
      model: CoverageInference(scenario, mode))
    try expectEqual(reply.state, "complete")
    try expectEqual(reply.answer.contains("There are no inventory"), false)
    if mode == "gap" || mode == "count_after_search" {
      try expectEqual(reply.answer.hasPrefix("I found no matches for these searches:"), true)
      try expectEqual(reply.answer.contains("1 incomplete source"), true)
      try expectEqual(
        reply.answer.contains("These searches do not establish the requested facts"), true)
      try expectEqual(reply.answer.contains("contract was signed"), false)
      if mode == "gap" { try expectEqual(reply.answer.contains("\\[claim\\]"), true) }
      let message = try scenario.messages(limit: 100).last { $0.role == "assistant" }!
      try expectEqual(
        try scenario.messagePayload(message.id)["searchEvidence"]["incomplete"].int, 1)
      if mode == "count_after_search" {
        try expectEqual(reply.answer.contains("Current workbook Records: 0"), true)
      }
    } else if mode != "overclaim" && mode != "general" {
      try expectEqual(
        reply.answer.contains("Current workbook Records: " + (mode == "stale" ? "1" : "0") + " ("),
        true)
      try expectEqual(
        reply.answer.contains("kind: movement, status: any, meaning: any, scenario: any"), true)
      let answer = try scenario.messages(limit: 100).last { $0.role == "assistant" }!
      try expectEqual(try scenario.messagePayload(answer.id)["coverageEvidence"].array.count, 1)
      try expectEqual(try scenario.messagePayload(answer.id)["presentation"].text, "host_counts")
      try expectEqual(reply.answer.contains("invoice was paid"), false)
      try expectEqual(reply.answer.hasPrefix("Current workbook Records:"), true)
    }
    try expectEqual(try scenario.verify()["ok"], .bool(true))
  }
  print(
    "PASS scoped current-record counts, hidden lexical matches, validation, stale/forged receipts and overclaim recovery"
  )
}
