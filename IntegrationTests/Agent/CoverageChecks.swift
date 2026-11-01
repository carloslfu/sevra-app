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
          "citations": .array([]), "counts": coverage,
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
      if mode == "legacy" || mode == "legacy_mixed" {
        var arguments: [String: Value] = [
          "answer": .string("The scoped count follows."), "basis": .string("evidence"),
          "citations": .array([]), "coverage": .array([.string(receipt)]),
        ]
        if mode == "legacy_mixed" {
          arguments["counts"] = .array([.string(receipt)])
          arguments["coverage"] = .null
        }
        return try call("finish", .object(arguments))
      }
      if mode == "stale" {
        let source = try book.addItem(category: "source", kind: "note", title: "Handover")
        _ = try book.addHostOwnedItem(
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
    if mode.hasPrefix("legacy") && step == 3 {
      try expectEqual(messages.last!.content.contains("active finish field is counts"), true)
    }
    if ["forged", "malformed", "legacy"].contains(mode) && step == 3 {
      try expectEqual(toolScope, .inspection)
      return try count()
    }
    if ["forged", "malformed", "legacy"].contains(mode) {
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
  let first = try book.addHostOwnedItem(
    category: "record", kind: "movement", title: "Dispatch", meaning: "estimate",
    inputs: [source.id])
  let current = try book.addHostOwnedItem(
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
    "legacy", "legacy_mixed",
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
  try await checkRequestEvidenceBoundary(root)
}

/// Reproduces the W1 path: empty searches, read the current request Source,
/// then cite that Source while reporting unresolved external evidence.
private actor RequestEvidenceInference: WorkbookInference {
  let identity = "synthetic current-request evidence boundary"
  let lastMetrics: Value = .null
  let book: Workbook
  let mode: String
  let independent: String
  var step = 0
  var request = ""
  init(_ book: Workbook, mode: String, independent: String) {
    self.book = book
    self.mode = mode
    self.independent = independent
  }
  func beginRun() {}
  func endRun() {}
  func respond(
    messages: [InferenceMessage], directory: URL, cancellation: Cancellation,
    progress: @escaping @Sendable (String) -> Void, toolScope: InferenceToolScope,
    citationIDs: [String]
  ) throws -> NativeReply {
    step += 1
    func call(_ name: String, _ arguments: Value) throws -> NativeReply {
      NativeReply(
        text: "",
        calls: [
          .init(id: identifier(), name: name, inputJSON: try arguments.json())
        ])
    }
    if step == 1 {
      request = try expectValue(book.items(kind: "request").first?.id)
      return try call(
        "search",
        .object([
          "query": .string(
            ["independent", "mixed"].contains(mode) ? "quotation" : "Lakehouse contract")
        ]))
    }
    if step == 2 {
      return try call(
        "read", .object(["id": .string(mode == "independent" ? independent : request)]))
    }
    if mode == "mixed", step == 3 {
      return try call("read", .object(["id": .string(independent)]))
    }
    if (mode == "independent" && step == 3) || (mode == "mixed" && step == 4) {
      return try call("search", .object(["query": .string("Lakehouse contract")]))
    }
    var basis = "unresolved"
    var answer = "Indexing may be incomplete. I cannot establish the contract's renewal price."
    var citations = [request]
    if mode == "supplied" {
      basis = "current_request"
      answer = "Your supplied purchase code is MAPLE-27."
    } else if mode == "independent" || mode == "mixed" {
      basis = "evidence"
      answer = "The quotation still needs a signature."
      citations = mode == "mixed" ? [request, independent] : [independent]
    } else if mode == "evidence", step == 3 {
      basis = "evidence"
      answer = "The signed contract specifies a renewal price of 125."
    } else if mode == "evidence" {
      try expectEqual(step, 4)
      try expectEqual(messages.last!.content.contains("current request"), true)
    } else if mode == "unknown", step == 3 {
      citations += ["not-inspected-evidence"]
    } else if mode == "unknown" {
      try expectEqual(step, 4)
      try expectEqual(messages.last!.content.contains("Citations must be inspected"), true)
    }
    return try call(
      "finish",
      .object([
        "answer": .string(answer), "basis": .string(basis),
        "citations": .array(citations.map(Value.string)),
      ]))
  }
}

private func checkRequestEvidenceBoundary(_ root: URL) async throws {
  for mode in ["gap", "evidence", "supplied", "independent", "mixed", "unknown"] {
    let book = try Workbook.create(
      at: root.appendingPathComponent("request-\(mode).sevra"), title: "Request evidence")
    let attachment = try book.addItem(
      category: "source", kind: "file", title: "Unreadable attachment")
    try book.index(
      attachment.id, chunks: [], state: "unsupported", detail: "Synthetic unsupported file")
    let independent = try book.addItem(
      category: "source", kind: "note", title: "Quotation status",
      text: "The quotation still needs a signature.")
    let reply: AgentResult
    do {
      reply = try await WorkbookAgent.run(
        "My purchase code is MAPLE-27. Find the signed Lakehouse contract and renewal price; do not guess.",
        workbook: book,
        model: RequestEvidenceInference(book, mode: mode, independent: independent.id))
    } catch {
      let refusals = try book.messages(limit: 100).compactMap { message -> String? in
        guard message.role == "tool", let payload = try? Value.parse(message.body) else {
          return nil
        }
        return payload["validation"].string
      }
      throw SevraError("test", "Request evidence mode \(mode): \(error); \(refusals)")
    }
    try expectEqual(reply.state, "complete")
    let request = try expectValue(book.items(kind: "request").first?.id)
    let final = try expectValue(book.messages(limit: 100).last { $0.role == "assistant" })
    let payload = try book.messagePayload(final.id)
    if ["gap", "evidence", "unknown"].contains(mode) {
      try expectEqual(reply.answer.contains("1 incomplete source"), true)
      try expectEqual(
        reply.answer.contains("These searches do not establish the requested facts"), true)
      try expectEqual(reply.answer.contains("125"), false)
      try expectEqual(reply.citations, [])
      try expectEqual(payload["presentation"].text, "host_search")
      try expectEqual(payload["searchEvidence"]["incomplete"].int, 1)
      try expectEqual(payload["arguments"]["citations"], .array([.string(request)]))
    } else {
      try expectEqual(payload["presentation"].text, "answer")
      try expectEqual(reply.answer.contains("These searches do not establish"), false)
      if mode == "supplied" {
        try expectEqual(reply.answer.contains("MAPLE-27"), true)
        try expectEqual(reply.citations, [request])
      } else {
        try expectEqual(reply.answer.contains("quotation still needs a signature"), true)
        try expectEqual(reply.citations.contains(independent.id), true)
      }
    }
    try expectEqual(try book.verify()["ok"], .bool(true))
  }
  print(
    "PASS current-request citations cannot replace missing external evidence; supplied and independently cited facts remain available"
  )
}
