import Foundation

/// Unicode scalar coordinates address the exact string in an immutable read
/// receipt. They never address a mutable search-index row or the current head.
public struct DocumentCopyReference: Codable, Equatable, Sendable {
  public let receiptID: String
  public let path: [String]
  public let startScalar: Int
  public let scalarCount: Int
  public let sha256: String
  public init(
    receiptID: String, path: [String], startScalar: Int, scalarCount: Int, sha256: String
  ) {
    self.receiptID = receiptID
    self.path = path
    self.startScalar = startScalar
    self.scalarCount = scalarCount
    self.sha256 = sha256
  }
}

public struct DocumentCopy: Codable, Equatable, Sendable {
  public let reference: DocumentCopyReference
  public let text: String
  public let sourceVersionID: String
  public let locator: String
  public let resultHash: String
}

public struct DocumentPart: Codable, Equatable, Sendable {
  public let text: String?
  public let copy: DocumentCopyReference?
  public init(text: String) {
    self.text = text
    copy = nil
  }
  public init(copy: DocumentCopyReference) {
    text = nil
    self.copy = copy
  }

  /// New prose and copies sent together. A copy takes the place of its own words in the prose,
  /// so a line retyped beside its copy is saved once, where the prose put it. Every other part
  /// follows the prose in the order sent, unless the prose already says it.
  static func placed(_ parts: [(part: DocumentPart, words: String?)], in prose: String)
    -> [DocumentPart]
  {
    guard !prose.isEmpty else { return parts.map(\.part) }
    var anchors: [(range: Range<String.Index>, part: DocumentPart, words: String)] = []
    var following: [DocumentPart] = []
    for (part, words) in parts {
      if let text = part.text, !trimmed(text).isEmpty, says(trimmed(text), in: prose) { continue }
      if let words,
        let range = free(words, in: prose, avoiding: anchors.map(\.range))
          ?? free(trimmed(words), in: prose, avoiding: anchors.map(\.range))
      {
        anchors.append((range, part, words))
      } else {
        following.append(part)
      }
    }
    var result: [DocumentPart] = []
    var start = prose.startIndex
    var tail = ""
    for anchor in anchors.sorted(by: { $0.range.lowerBound < $1.range.lowerBound }) {
      if start < anchor.range.lowerBound {
        result.append(.init(text: String(prose[start..<anchor.range.lowerBound])))
      }
      result.append(anchor.part)
      tail = anchor.words
      start = anchor.range.upperBound
    }
    if start < prose.endIndex {
      tail = String(prose[start...])
      result.append(.init(text: tail))
    }
    // Copies that follow start on their own line, not on the end of the last sentence.
    if !result.isEmpty, !following.isEmpty, !tail.hasSuffix("\n") {
      result.append(.init(text: "\n\n"))
    }
    return result + following
  }

  /// A copied line often ends in a newline that the last line of the prose does not have.
  private static func trimmed(_ words: String) -> String {
    var words = Substring(words)
    while let last = words.last, last.isNewline { words.removeLast() }
    return String(words)
  }

  private static func free(
    _ words: String, in prose: String, avoiding taken: [Range<String.Index>]
  ) -> Range<String.Index>? {
    guard !words.isEmpty else { return nil }
    var start = prose.startIndex
    while let found = prose.range(of: words, options: .literal, range: start..<prose.endIndex) {
      if !taken.contains(where: { $0.overlaps(found) }), wholeWords(found, in: prose) { return found }
      start = found.upperBound
    }
    return nil
  }

  /// MAPLE-2 is not found inside MAPLE-27, and 12 is not found inside 120.
  private static func wholeWords(_ range: Range<String.Index>, in prose: String) -> Bool {
    func word(_ character: Character) -> Bool { character.isLetter || character.isNumber }
    let splitsStart =
      range.lowerBound > prose.startIndex && word(prose[range.lowerBound])
      && word(prose[prose.index(before: range.lowerBound)])
    let splitsEnd =
      range.upperBound < prose.endIndex && word(prose[range.upperBound])
      && word(prose[prose.index(before: range.upperBound)])
    return !splitsStart && !splitsEnd
  }

  /// Prose repeats a text part only as a whole line or sentence. A heading such as Notes is not
  /// said by a sentence that starts with the same word.
  private static func says(_ words: String, in prose: String) -> Bool {
    var start = prose.startIndex
    while let found = prose.range(of: words, options: .literal, range: start..<prose.endIndex) {
      let opens =
        found.lowerBound == prose.startIndex
        || prose[prose.index(before: found.lowerBound)].isWhitespace
      let closes =
        found.upperBound == prose.endIndex || prose[found.upperBound].isNewline
        || words.last.map { ".!?:".contains($0) } == true
      if opens && closes { return true }
      start = found.upperBound
    }
    return false
  }
}

extension Workbook {
  /// This is an explicit read of original receipt text, including a field which
  /// may have been omitted from the model's earlier bounded projection.
  public func documentCopy(
    receiptID: String, path: [String], startScalar: Int, scalarCount: Int,
    runID: String, conversation: String = "main", cancellation: Cancellation = .init()
  ) throws -> DocumentCopy {
    try synchronized(cancellation: cancellation) {
      try db.readTransaction {
        try cancellation.check()
        try require(
          receiptID.utf8.count <= 256 && runID.utf8.count <= 256
            && conversation.utf8.count <= 256 && path.count <= 3
            && path.allSatisfy { $0.utf8.count <= 64 },
          "document_copy_scope", "Choose a bounded original read reference.")
        try require(
          startScalar >= 0 && scalarCount > 0 && scalarCount <= 16000,
          "document_copy_range", "Choose a nonempty bounded source span.")
        let call = try toolCall(receiptID, conversation: conversation)
        try require(
          call["run_id"].text == runID && call["tool"].text == "read"
            && call["state"].text == "completed",
          "document_copy_scope", "Copying requires a completed source read in this request.")
        let row = try db.execute(
          "SELECT length(CAST(result AS BLOB)) AS result_bytes,result_hash FROM tool_calls WHERE id=?",
          [.string(receiptID)]
        ).first!
        try require(
          (row["result_bytes"]?.int ?? Int.max) <= 128000, "document_copy_limit",
          "This receipt exceeds the document-copy read bound. Read a smaller source page.")
        let json = try db.scalar("SELECT result FROM tool_calls WHERE id=?", [.string(receiptID)])
          .text
        try require(
          ToolResultProjection.digest(json) == row["result_hash"]!.text,
          "integrity", "The original source read changed.")
        let result = try Value.parse(json)
        let source = try item(result["item"]["id"].text)
        try require(
          source.id == result["item"]["id"].text, "document_copy_scope",
          "The original source read must identify an exact item version.")
        let original: String
        let locator: String
        if path == ["item", "text"], let text = result["item"]["text"].string {
          original = text
          locator = "item text"
        } else if path.count == 3, path[0] == "chunks", path[2] == "body",
          let index = Int(path[1]), index >= 0, String(index) == path[1],
          result["chunks"].array.indices.contains(index),
          let text = result["chunks"].array[index]["body"].string
        {
          original = text
          locator = result["chunks"].array[index]["locator"].text
        } else {
          throw SevraError(
            "document_copy_path", "Choose original item text or a source chunk body.")
        }
        let scalars = Array(original.unicodeScalars)
        try require(
          startScalar <= scalars.count && scalarCount <= scalars.count - startScalar,
          "document_copy_range", "The source span is outside the selected original text.")
        let text = String(
          String.UnicodeScalarView(scalars[startScalar..<(startScalar + scalarCount)]))
        try require(
          text.utf8.count <= 16000, "document_copy_limit", "The selected source span is too large.")
        try cancellation.check()
        return DocumentCopy(
          reference: .init(
            receiptID: receiptID, path: path, startScalar: startScalar, scalarCount: scalarCount,
            sha256: ToolResultProjection.digest(text)),
          text: text, sourceVersionID: source.id, locator: locator,
          resultHash: row["result_hash"]!.text)
      }
    }
  }

  /// Resolve every copy again inside the write transaction. Neither submitted
  /// quote text nor arbitrary metadata can replace its original receipt bytes.
  public func saveComposedDraft(
    title: String, parts: [DocumentPart], inputs: [String] = [], runID: String,
    conversation: String = "main", token: String = identifier(), expectedRevision: Int? = nil,
    cancellation: Cancellation = .init()
  ) throws -> Item {
    try cancellation.check()
    try require(
      !parts.isEmpty && parts.count <= 64, "document_parts", "Use one to 64 document parts.")
    try require(
      !title.isEmpty && title.utf8.count <= 4096 && inputs.count <= 128
        && inputs.allSatisfy { !$0.isEmpty && $0.utf8.count <= 256 }
        && !runID.isEmpty && runID.utf8.count <= 256
        && !conversation.isEmpty && conversation.utf8.count <= 256,
      "document_parts", "Document metadata exceeds its supported bounds.")
    var generatedBytes = 0
    for part in parts {
      if let text = part.text, part.copy == nil {
        try require(
          text.utf8.count <= 64000 - generatedBytes, "document_parts",
          "The composed draft exceeds its 64,000-byte bound.")
        generatedBytes += text.utf8.count
      } else if let copy = part.copy, part.text == nil {
        try require(
          copy.receiptID.utf8.count <= 256 && copy.path.count <= 3
            && copy.path.allSatisfy { $0.utf8.count <= 64 }
            && copy.sha256.utf8.count == 64,
          "document_parts", "Use a bounded source-copy reference.")
      } else {
        throw SevraError(
          "document_parts", "Each document part is either new prose or one source copy.")
      }
    }
    let request: Value = .object([
      "title": .string(title), "parts": try encoded(parts),
      "inputs": .array(inputs.map(Value.string)),
      "runID": .string(runID), "conversation": .string(conversation),
    ])
    let result = try mutation(
      "composed_document", token: token, request: request, expected: expectedRevision,
      cancellation: cancellation
    ) {
      try require(
        try db.scalar(
          "SELECT count(*) FROM agent_runs a JOIN run_requests r ON r.run_id=a.id WHERE a.id=? AND a.conversation_id=? AND a.status='running'",
          [.string(runID), .string(conversation)]
        ).int == 1,
        "document_copy_scope", "A new composed draft requires the active user request.")
      var body = ""
      var snapshots: [Value] = []
      var lineage = Set(inputs)
      for part in parts {
        try cancellation.check()
        let text: String
        if let generated = part.text, part.copy == nil {
          text = generated
        } else if let reference = part.copy, part.text == nil {
          let copy = try documentCopy(
            receiptID: reference.receiptID, path: reference.path,
            startScalar: reference.startScalar, scalarCount: reference.scalarCount,
            runID: runID, conversation: conversation, cancellation: cancellation)
          try require(
            copy.reference.sha256 == reference.sha256, "document_copy_hash",
            "The selected source copy does not match its expected bytes.")
          text = copy.text
          var snapshot = try encoded(copy).object
          snapshot["outputStartScalar"] = .number(Double(body.unicodeScalars.count))
          snapshots.append(.object(snapshot))
          lineage.insert(copy.sourceVersionID)
        } else {
          throw SevraError(
            "document_parts", "Each document part is either new prose or one source copy.")
        }
        try require(
          text.utf8.count <= 64000 && body.utf8.count <= 64000 - text.utf8.count,
          "document_parts", "The composed draft exceeds its 64,000-byte bound.")
        body += text
      }
      try cancellation.check()
      return .string(
        try insertItem(
          category: "record", kind: "document", title: title, text: body,
          data: .object([
            "documentComposition": .object([
              "version": .number(1), "runID": .string(runID),
              "conversation": .string(conversation), "copies": .array(snapshots),
            ])
          ]), meaning: "estimate", status: "draft", scenario: "actual",
          inputs: lineage.sorted(), transformation: "source-bound-document-v1; run=" + runID))
    }
    return try item(result.text)
  }

  /// Acceptance, withdrawal and Undo preserve the same composition metadata.
  /// Verification reads original receipts even after their run has ended.
  func verifyDocumentCompositions() throws {
    for row in try db.execute(
      "SELECT id FROM items WHERE category='record' AND kind='document' AND json_type(data,'$.documentComposition') IS NOT NULL"
    ) {
      let draft = try item(row["id"]!.text)
      let composition = draft.data["documentComposition"]
      guard case .array(let copies) = composition["copies"],
        composition["version"].int == 1, copies.count <= 64,
        let run = composition["runID"].string,
        let conversation = composition["conversation"].string,
        draft.category == "record", draft.kind == "document", draft.text.utf8.count <= 64000
      else { throw SevraError("integrity", "Invalid document-copy provenance.") }
      try require(
        try db.scalar(
          "SELECT count(*) FROM agent_runs a JOIN run_requests r ON r.run_id=a.id WHERE a.id=? AND a.conversation_id=?",
          [.string(run), .string(conversation)]
        ).int == 1,
        "integrity", "The document's originating request is missing.")
      let scalars = Array(draft.text.unicodeScalars)
      var previousEnd = 0
      for snapshot in copies {
        let saved = try JSONDecoder().decode(DocumentCopy.self, from: Data(snapshot.json().utf8))
        let original = try documentCopy(
          receiptID: saved.reference.receiptID, path: saved.reference.path,
          startScalar: saved.reference.startScalar, scalarCount: saved.reference.scalarCount,
          runID: run, conversation: conversation)
        guard let start = snapshot["outputStartScalar"].int,
          start >= previousEnd, start <= scalars.count,
          saved.reference.scalarCount <= scalars.count - start
        else { throw SevraError("integrity", "Invalid copied passage position.") }
        let end = start + saved.reference.scalarCount
        let text = String(String.UnicodeScalarView(scalars[start..<end]))
        try require(
          original.reference == saved.reference && original.sourceVersionID == saved.sourceVersionID
            && original.resultHash == saved.resultHash && original.locator == saved.locator
            && Data(original.text.utf8) == Data(saved.text.utf8)
            && Data(text.utf8) == Data(saved.text.utf8),
          "integrity", "A copied passage no longer matches its original source read.")
        previousEnd = end
      }
    }
  }
}
