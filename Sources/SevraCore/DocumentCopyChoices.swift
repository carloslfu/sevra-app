import Foundation

/// Small, exact passages published with a source read. IDs are opaque to users;
/// the host owns scalar coordinates and the original receipt binding.
public enum DocumentCopyChoices {
  public static func entries(_ value: Value) -> [Value] {
    value["documentCopies"]["entries"].array
  }

  public static func adding(
    to result: Value, receiptID: String, offset: Int = 0, cancellation: Cancellation = .init()
  ) throws -> Value {
    try cancellation.check()
    try require(
      UUID(uuidString: receiptID) != nil && offset >= 0 && offset <= 10000,
      "document_copy_range", "Choose a valid source-copy page.")
    var entries: [Value] = []
    var seen = Set<String>()
    var candidate = 0
    var omitted = false
    var nextOffset: Int?
    var budget = 0
    // Never publish an ID which the bounded receipt resolver cannot inspect.
    // Read fewer chunks for unusually wide Unicode or structured results.
    if try result.json().utf8.count > 124000 { return result }
    chunks: for (index, chunk) in result["chunks"].array.enumerated() {
      try cancellation.check()
      guard let text = chunk["body"].string, text.utf8.count <= 128000 else { continue }
      let scalars = Array(text.unicodeScalars)
      var start = 0
      while start < scalars.count {
        try cancellation.check()
        var end = start
        while end < scalars.count && scalars[end].value != 10 && scalars[end].value != 13 {
          end += 1
        }
        if end < scalars.count {
          if scalars[end].value == 13 && end + 1 < scalars.count && scalars[end + 1].value == 10 {
            end += 1
          }
          end += 1
        }
        // Long lines are explicit adjacent fragments; the model chooses IDs,
        // never character counts. Keep a single displayed entry below the
        // ordinary receipt-page field limit.
        var fragmentEnd = start
        var fragmentBytes = 0
        while fragmentEnd < end {
          let scalar = scalars[fragmentEnd]
          let bytes =
            scalar.value < 32 || scalar.value == 0x2028 || scalar.value == 0x2029
            ? 6 : scalar.value == 34 || scalar.value == 92 ? 2 : scalar.utf8.count
          if fragmentBytes + bytes > 1024 { break }
          fragmentBytes += bytes
          fragmentEnd += 1
        }
        end = fragmentEnd
        let passage = String(String.UnicodeScalarView(scalars[start..<end]))
        defer { start = end }
        let locator = chunk["locator"].text
        var position = "\(index):\(start):\(end)"
        if let marker = locator.range(of: "; offset=", options: .backwards),
          let origin = Int(locator[marker.upperBound...]), origin >= 0,
          origin <= Int.max - scalars.count
        {
          let first = String(String.UnicodeScalarView(scalars[..<start])).count
          let last = String(String.UnicodeScalarView(scalars[..<end])).count
          position = String(locator[..<marker.lowerBound]) + ":\(origin + first):\(origin + last)"
        }
        // Suppress the same source coordinates repeated by overlapping chunks,
        // while preserving identical lines at different original positions.
        guard !passage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
          seen.insert(position + ":" + ToolResultProjection.digest(passage)).inserted
        else { continue }
        candidate += 1
        guard candidate > offset else { continue }
        let id = "copy:\(receiptID):\(index):\(start):\(end - start)"
        let entry: Value = .object([
          "id": .string(id), "text": .string(passage),
          "sourceVersionID": result["item"]["id"], "locator": chunk["locator"],
        ])
        let bytes = try entry.json().utf8.count
        guard end - start <= 16000 && passage.utf8.count <= 16000,
          entries.count < 8, bytes <= 2000 - budget
        else {
          omitted = true
          nextOffset = entries.isEmpty ? candidate : candidate - 1
          break chunks
        }
        entries.append(entry)
        budget += bytes
      }
    }
    var fields = result.object
    fields["documentCopies"] = .object([
      "entries": .array(entries), "offset": .number(Double(offset)),
      "hasMore": .bool(omitted),
      "nextOffset": nextOffset.map { .number(Double($0)) } ?? .null,
      "notice": .string(
        "Exact original passages for draft parts. Use a passage ID as copy, without retyping its text. New prose uses text. These passages do not establish current acceptance or complete coverage. Use read with copyOffset for later passage candidates; source chunks may have partial first/last lines."
      ),
    ])
    return .object(fields)
  }
}

extension Workbook {
  public func documentCopyChoice(
    _ id: String, runID: String, conversation: String = "main", cancellation: Cancellation = .init()
  ) throws -> DocumentCopy {
    try require(id.utf8.count <= 128, "document_copy_scope", "Choose a published source passage.")
    let fields = id.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
    guard fields.count == 5, fields[0] == "copy", UUID(uuidString: fields[1]) != nil,
      let index = Int(fields[2]), index >= 0, String(index) == fields[2],
      let start = Int(fields[3]), String(start) == fields[3],
      let count = Int(fields[4]), String(count) == fields[4]
    else { throw SevraError("document_copy_scope", "Choose a published source passage.") }
    return try synchronized(cancellation: cancellation) {
      try db.readTransaction {
        let copy = try documentCopy(
          receiptID: fields[1], path: ["chunks", String(index), "body"],
          startScalar: start, scalarCount: count, runID: runID, conversation: conversation,
          cancellation: cancellation)
        let result = try Value.parse(
          db.scalar("SELECT result FROM tool_calls WHERE id=?", [.string(fields[1])]).text)
        guard
          let published = DocumentCopyChoices.entries(result).first(where: { $0["id"].text == id }),
          published["sourceVersionID"].text == copy.sourceVersionID,
          let text = published["text"].string, Data(text.utf8) == Data(copy.text.utf8)
        else {
          throw SevraError(
            "document_copy_scope", "This passage was not published by that source read.")
        }
        return copy
      }
    }
  }
}
