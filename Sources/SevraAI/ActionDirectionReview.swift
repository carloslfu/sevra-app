import Foundation
import SevraCore

/// Bounded isolated groups cover the complete resolved batch before writing. Saved
/// action names, mappings and proposed signs are deliberately absent.
package enum ActionDirectionReview {
  package static func excerpt(_ parts: [String], maximumBytes: Int) -> String {
    var scalars = String.UnicodeScalarView()
    var used = 0
    outer: for (index, part) in parts.enumerated() {
      let separated = index == 0 ? part : "\n" + part
      for scalar in separated.unicodeScalars {
        let bytes = scalar.utf8.count
        if used + bytes > maximumBytes { break outer }
        scalars.append(scalar)
        used += bytes
      }
    }
    return String(scalars)
  }
  package static let definition = WorkbookToolDefinition(
    name: "review_action_directions",
    description: "Classify each indexed movement from original inputs only; no write authority.",
    parameters: NativeTools.object(
      [
        "directions": .object([
          "type": .string("array"), "minItems": .number(1), "maxItems": .number(10),
          "items": NativeTools.object(
            [
              "index": NativeTools.schema(
                "integer", "Exact movement index from the input; once each."),
              "direction": .object([
                "type": .string("string"),
                "enum": .array(["incoming", "outgoing", "unclear"].map(Value.string)),
              ]),
              "basis": .object([
                "type": .string("string"),
                "enum": .array(["request", "evidence", "none"].map(Value.string)),
              ]),
              "quote": NativeTools.schema(
                "string",
                "Exact contiguous words in this movement's request or evidence; empty when unclear."
              ),
            ], required: ["index", "direction", "basis", "quote"]),
        ])
      ], required: ["directions"]))

  package static func check(
    request: String, plan: Value, workbook: Workbook,
    model: any WorkbookInference, directory: URL, cancellation: Cancellation,
    progress: @escaping @Sendable (String) -> Void
  ) async throws -> (matches: Bool, receipt: Value, metrics: [Value]) {
    let movements = plan["movements"].array
    try require(
      (1...50).contains(movements.count), "movement_review",
      "The inventory batch is outside the review limit.")
    let ids = Array(Set(movements.map { $0["input"].text })).sorted()
    var originals: [String: String] = [:]
    var excerpts: [Value] = []
    let perSource = 16_000 / ids.count
    for id in ids {
      try cancellation.check()
      let source = try workbook.item(id)
      try require(source.id == id, "movement_review", "Review exact local evidence versions.")
      let chunks =
        source.category == "source" && source.isBusinessEvidence
        ? try workbook.readChunks(id, limit: 9) : []
      let parts =
        source.category == "source" && source.isBusinessEvidence
        ? [source.text] + chunks.prefix(8).map { $0["body"].text } : []
      let excerpt = excerpt(parts, maximumBytes: perSource)
      let originalBytes = parts.reduce(0) { $0 + $1.utf8.count } + max(0, parts.count - 1)
      originals[id] = excerpt
      excerpts.append(
        .object([
          "id": .string(id), "text": .string(excerpt),
          "truncated": .bool(excerpt.utf8.count < originalBytes || chunks.count > 8),
          "notice": .string(
            "Bounded original Source excerpt only. Derived Records do not establish original direction; omitted material proves nothing."
          ),
        ]))
    }
    let policy =
      MovementDirectionReview.policy.replacingOccurrences(
        of: "Return only review_movement_direction.", with: "Return only review_action_directions.")
      + "\nReturn exactly one indexed verdict per supplied movement. Keep its original index. Check each subject independently. A quote from another subject or evidence source is insufficient. Never skip or combine indexes. Use only that movement's evidenceID excerpt or the current request."
    var inputs: [Value] = []
    var receipts: [Value] = []
    var metrics: [Value] = []
    for start in stride(from: 0, to: movements.count, by: 10) {
      try cancellation.check()
      let indexes = Array(start..<min(start + 10, movements.count))
      let sourceIDs = Set(indexes.map { movements[$0]["input"].text })
      let input: Value = .object([
        "request": .string(request),
        "evidence": .array(excerpts.filter { sourceIDs.contains($0["id"].text) }),
        "movements": .array(
          indexes.map { index in
            .object([
              "index": .number(Double(index)), "subject": movements[index]["subject"],
              "evidenceID": movements[index]["input"],
            ])
          }),
      ])
      inputs.append(input)
      progress(
        "Checking inventory directions \(start + 1)–\(indexes.last! + 1) of \(movements.count)…")
      let response = try await model.respond(
        messages: [
          .init(role: "system", content: policy), .init(role: "user", content: try input.json()),
        ],
        directory: directory, cancellation: cancellation, progress: progress,
        toolScope: .actionDirection, citationIDs: [])
      metrics.append(await model.lastMetrics)
      try cancellation.check()
      try require(
        response.calls.count == 1 && response.calls[0].name == definition.name, "movement_review",
        "The batch direction check returned no complete result. No proposals were saved.")
      try require(
        response.calls[0].inputJSON.utf8.count <= 64_000, "movement_review",
        "The batch direction check exceeded its result budget. No proposals were saved.")
      let verdict = try Value.parse(response.calls[0].inputJSON)
      let directions = verdict["directions"].array
      try require(
        Set(verdict.object.keys) == ["directions"] && directions.count == indexes.count,
        "movement_review", "The direction check must cover each supplied movement exactly once.")
      var seen = Set<Int>()
      for value in directions {
        guard let index = value["index"].int, value["index"] == .number(Double(index)),
          indexes.contains(index), seen.insert(index).inserted,
          Set(value.object.keys) == ["index", "direction", "basis", "quote"],
          ["incoming", "outgoing", "unclear"].contains(value["direction"].text),
          ["request", "evidence", "none"].contains(value["basis"].text),
          let quote = value["quote"].string
        else {
          throw SevraError(
            "movement_review",
            "The batch direction check was malformed or incomplete. No proposals were saved.")
        }
        let movement = movements[index]
        let original =
          value["basis"].text == "request"
          ? request : value["basis"].text == "evidence" ? originals[movement["input"].text]! : ""
        let supported =
          !quote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
          && Data(original.utf8).range(of: Data(quote.utf8)) != nil
        let number = try Numbers.decimal(movement["quantity"].text)
        let matches =
          supported
          && ((value["direction"].text == "incoming" && number > 0)
            || (value["direction"].text == "outgoing" && number < 0))
        receipts.append(
          .object([
            "index": .number(Double(index)), "evidenceID": movement["input"], "verdict": value,
            "quoteVerified": .bool(supported), "matches": .bool(matches),
          ]))
      }
      if !receipts.allSatisfy({ $0["matches"] == .bool(true) }) { break }
    }
    let complete = receipts.count == movements.count
    let matches = complete && receipts.allSatisfy { $0["matches"] == .bool(true) }
    return (
      matches,
      .object([
        "version": .number(1), "inputs": .array(inputs),
        "directions": .array(receipts.sorted { $0["index"].int! < $1["index"].int! }),
        "expectedCount": .number(Double(movements.count)),
        "reviewedCount": .number(Double(receipts.count)),
        "complete": .bool(complete), "matches": .bool(matches),
      ]), metrics
    )
  }
}
