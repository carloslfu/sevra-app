import Foundation

/// Saved descriptors are descriptive data. Only a host submission can answer
/// one, and only the current question in the exact conversation is actionable.
public struct ConversationSurface: Codable, Equatable, Identifiable, Sendable {
  public enum Kind: String, Codable, Sendable { case question, input, review, result }

  public struct Field: Codable, Equatable, Identifiable, Sendable {
    public enum Kind: String, Codable, CaseIterable, Sendable {
      case text, boolean, decimal, date, record
    }

    public struct RecordOptions: Codable, Equatable, Sendable {
      public let datasetID: String
      public let definitionID: String
      public let labelColumn: String
      public let rowIDs: [String]
      public var labels: [String: String]?
    }
    public let id: String
    public let label: String
    public let type: Kind
    public let required: Bool
    public var records: RecordOptions?

    fileprivate func validate(_ value: Value) throws {
      if type == .boolean {
        guard case .bool = value else {
          throw SevraError("conversation_input", "Choose a value for “\(label)”.")
        }
        return
      }
      guard let text = value.string, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
        text.utf8.count <= 1024
      else { throw SevraError("conversation_input", "Enter a value for “\(label)”.") }
      switch type {
      case .text, .boolean: break
      case .record:
        try require(
          records?.rowIDs.contains(text) == true, "conversation_input",
          "Choose a listed record for “\(label)”.")
      case .decimal: _ = try Numbers.decimal(text)
      case .date:
        let format = Date.ISO8601FormatStyle().year().month().day().dateSeparator(.dash)
        try require(
          (try? format.parse(text).formatted(format)) == text,
          "conversation_input", "Enter “\(label)” as YYYY-MM-DD.")
      }
    }
  }

  public struct Choice: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let label: String
    public let values: [String: Value]
  }

  public struct Input: Codable, Equatable, Sendable {
    public let kind: Kind
    public let purpose: String
    public let question: String
    public var fields: [Field]
    public let choices: [Choice]
    public let allowTextReply: Bool

    package static func parse(_ value: Value, resolved: Bool = false) throws -> Self {
      let shape: Set<String> = [
        "kind", "purpose", "question", "fields", "choices", "allowTextReply",
      ]
      let fieldShape: Set<String> = ["id", "label", "type", "required"]
      let choiceShape: Set<String> = ["id", "label", "values"]
      try require(
        Set(value.object.keys) == shape
          && value["fields"].array.allSatisfy {
            Set($0.object.keys).subtracting(["records"]) == fieldShape
              && Set($0["records"].object.keys).isSubset(
                of:
                  resolved
                  ? ["datasetID", "definitionID", "labelColumn", "rowIDs", "labels"]
                  : ["datasetID", "definitionID", "labelColumn", "rowIDs"])
          }
          && value["choices"].array.allSatisfy { Set($0.object.keys) == choiceShape }
          && value.json().utf8.count <= 8192,
        "conversation_input", "The input request has unsupported fields or exceeds its size limit.")
      let input = try JSONDecoder().decode(Self.self, from: Data(value.json().utf8))
      try require(
        [.question, .input].contains(input.kind)
          && Self.validText(input.purpose, maximum: 120)
          && Self.validText(input.question, maximum: 640)
          && (1...5).contains(input.fields.count) && input.choices.count <= 6,
        "conversation_input", "Use a short question and one to five fields.")
      let ids = input.fields.map { $0.id.lowercased() }
      let choiceIDs = input.choices.map { $0.id.lowercased() }
      try require(
        Set(ids).count == ids.count && Set(choiceIDs).count == choiceIDs.count
          && input.fields.allSatisfy {
            Self.validID($0.id) && Self.validText($0.label, maximum: 120)
          }
          && input.fields.allSatisfy { field in
            guard let records = field.records else { return field.type != .record }
            return field.type == .record && (1...12).contains(records.rowIDs.count)
              && Set(records.rowIDs).count == records.rowIDs.count
              && records.rowIDs.allSatisfy { Self.validText($0, maximum: 128) }
              && [records.datasetID, records.definitionID, records.labelColumn].allSatisfy {
                Self.validText($0, maximum: 128)
              }
              && (!resolved || Set(records.labels?.keys.map { $0 } ?? []) == Set(records.rowIDs))
          }
          && input.choices.allSatisfy {
            Self.validID($0.id) && Self.validText($0.label, maximum: 120)
          },
        "conversation_input", "Fields and choices need distinct IDs and short labels.")
      for choice in input.choices {
        try input.validate(choice.values)
      }
      return input
    }

    private static func validText(_ text: String, maximum: Int) -> Bool {
      !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && text.utf8.count <= maximum
        && !text.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
    }

    private static func validID(_ id: String) -> Bool {
      !id.isEmpty && id.utf8.count <= 40
        && id.utf8.allSatisfy {
          (97...122).contains($0) || (65...90).contains($0) || (48...57).contains($0)
            || $0 == 95 || $0 == 45
        }
    }

    fileprivate func validate(_ values: [String: Value]) throws {
      let ids = Set(fields.map(\.id))
      try require(Set(values.keys).isSubset(of: ids), "conversation_input", "Unknown answer field.")
      for field in fields {
        if let value = values[field.id] {
          try field.validate(value)
        } else if field.required {
          throw SevraError("conversation_input", "Supply “\(field.label)”.")
        }
      }
    }

    fileprivate func values(forText text: String, dateContext: ConversationDateContext)
      -> [String: Value]
    {
      let reply = text.trimmingCharacters(in: .whitespacesAndNewlines)
      func normalizedChoice(_ text: String) -> String {
        // Ignore a final sentence mark in a literal choice. Keep the original
        // reply verbatim, including custom conditions and qualifications.
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.last.map { ".!?".contains($0) } == true
          ? String(trimmed.dropLast()) : trimmed
      }
      let matches = choices.filter {
        $0.id.caseInsensitiveCompare(reply) == .orderedSame
          || normalizedChoice($0.label).caseInsensitiveCompare(normalizedChoice(reply))
            == .orderedSame
      }
      if matches.count == 1 { return matches[0].values }
      guard matches.isEmpty else { return [:] }
      if fields.count == 1, let field = fields.first, choices.isEmpty || field.type == .boolean {
        return typedValue(reply, field: field, dateContext: dateContext).map { [field.id: $0] }
          ?? [:]
      }
      var result: [String: Value] = [:]
      for line in reply.split(whereSeparator: \.isNewline) {
        let parts = line.split(separator: ":", maxSplits: 1)
        guard parts.count == 2 else { return [:] }
        let key = parts[0].trimmingCharacters(in: .whitespaces)
        let matches = fields.filter {
          $0.id.caseInsensitiveCompare(key) == .orderedSame
            || $0.label.caseInsensitiveCompare(key) == .orderedSame
        }
        guard matches.count == 1, let field = matches.first, result[field.id] == nil,
          let value = typedValue(
            parts[1].trimmingCharacters(in: .whitespaces), field: field, dateContext: dateContext)
        else { return [:] }
        result[field.id] = value
      }
      return result
    }

    private func typedValue(_ text: String, field: Field, dateContext: ConversationDateContext)
      -> Value?
    {
      let value: Value
      switch field.type {
      case .boolean:
        switch text.lowercased() {
        case "true", "yes": value = .bool(true)
        case "false", "no": value = .bool(false)
        default: return nil
        }
      case .record:
        guard let records = field.records else { return nil }
        let matches = records.rowIDs.filter {
          $0 == text || records.labels?[$0]?.caseInsensitiveCompare(text) == .orderedSame
        }
        guard matches.count == 1 else { return nil }
        value = .string(matches[0])
      case .date: value = .string(dateContext.resolveDay(text))
      case .decimal, .text: value = .string(text)
      }
      return (try? field.validate(value)) != nil ? value : nil
    }

    fileprivate var fallback: String {
      var lines = [question]
      if !choices.isEmpty {
        lines += choices.map { "• " + $0.label }
      } else {
        lines += fields.map { field in
          let labels = field.records?.rowIDs.compactMap { field.records?.labels?[$0] } ?? []
          return "• " + field.label + (field.type == .date ? " (YYYY-MM-DD)" : "")
            + (labels.isEmpty ? "" : " (" + labels.joined(separator: ", ") + ")")
        }
      }
      if allowTextReply { lines.append(ConversationSurface.textReplyHint) }
      return lines.joined(separator: "\n")
    }
  }

  /// The last line of an open question's text. Once the question is answered, skipped or
  /// cancelled the line no longer applies, and the app leaves it out.
  public static let textReplyHint = "You can also reply with Answer: followed by your response."

  public let id: String
  public let version: Int
  public let revision: Int
  public let kind: Kind
  public let conversation: String
  public let runID: String
  public let requestID: String
  public let readOnly: Bool
  public let input: Input?
  package let requestDateContext: ConversationDateContext?
}

public enum ConversationInputResponse: Sendable {
  case choice(String)
  case fields([String: Value])
  case text(String)
  case decline
  case cancel
}

public struct ConversationInputReference: Identifiable, Sendable {
  public let id: String
  public let purpose: String
}

package struct ConversationContinuation: Sendable {
  package let request: AgentRequest
  package let questionID: String
  package let originalRequestID: String
  package let originalTask: String
  package let question: String
  package let answer: String
  package let values: Value
  package let priorAnswers: Value
  package let requestDateContext: ConversationDateContext?
  package let answerDateContext: ConversationDateContext?
  package let declined: Bool
  package let readOnly: Bool
}

extension Workbook {
  package func publishConversationInput(
    _ descriptor: ConversationSurface.Input, runID: String, conversation: String, readOnly: Bool,
    steps: Int, metrics: Value, cancellation: Cancellation,
    requestDateContext: ConversationDateContext? = nil
  ) throws -> (id: String, body: String) {
    let id = identifier()
    var body = ""
    let saved = try mutation(
      "conversation_input", token: runID + "-input", request: try encoded(descriptor),
      cancellation: cancellation, commitGuard: { try cancellation.check() },
      {
        guard
          let request = try db.execute(
            """
            SELECT a.status,r.message_id FROM agent_runs a JOIN run_requests r ON r.run_id=a.id
            WHERE a.id=? AND a.conversation_id=? AND a.status='running'
            """, [.string(runID), .string(conversation)]
          ).first
        else {
          throw SevraError("conversation_input", "This request is no longer running.")
        }
        try require(
          try pendingConversationInputReferences(conversation: conversation).count < 8,
          "conversation_input_limit", "This conversation already has eight open questions.")
        var input = descriptor
        for index in input.fields.indices {
          guard var records = input.fields[index].records else { continue }
          var labels: [String: String] = [:]
          for rowID in records.rowIDs {
            let row = try validateInputRecord(records, rowID: rowID)
            let label = row.data[records.labelColumn].text
            try require(
              !label.isEmpty && label.utf8.count <= 120
                && !label.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains),
              "conversation_input", "Choose a short label field for the listed records.")
            labels[rowID] = label
          }
          records.labels = labels
          input.fields[index].records = records
        }
        _ = try ConversationSurface.Input.parse(encoded(input), resolved: true)
        body = input.fallback
        let surface = ConversationSurface(
          id: id, version: 1, revision: 1, kind: input.kind, conversation: conversation,
          runID: runID, requestID: request["message_id"]!.text, readOnly: readOnly, input: input,
          requestDateContext: requestDateContext)
        try insertSurfaceMessage(
          id, conversation: conversation, role: "assistant", body: body, state: "needs_input",
          payload: .object([
            "kind": .string("conversation_surface"), "surface": try encoded(surface),
          ]))
        try db.execute(
          "UPDATE agent_runs SET status='needs_input',steps=?,metrics=?,updated=? WHERE id=?",
          [
            .number(Double(steps)), .string(try metrics.json()), .string(timestamp()),
            .string(runID),
          ])
        return .string(id)
      })
    if body.isEmpty { body = try historyMessage(saved.text, conversation: conversation).body }
    return (saved.text, body)
  }

  private func validateInputRecord(
    _ records: ConversationSurface.Field.RecordOptions, rowID: String
  ) throws -> Item {
    let dataset = try dataset(records.datasetID)
    let row = try item(rowID)
    try require(
      !dataset.archived && dataset.definitionID == records.definitionID
        && dataset.columns.contains { $0.id == records.labelColumn }
        && row.id == rowID && row.status == "accepted" && item(row.logicalID).id == rowID
        && db.scalar(
          "SELECT count(*) FROM dataset_rows WHERE dataset_id=? AND logical_id=?",
          [.string(records.datasetID), .string(row.logicalID)]
        ).int == 1,
      "conversation_input_record", "A listed record has changed. Ask for new record choices.")
    return row
  }

  public func pendingConversationInput(conversation: String) throws -> ConversationSurface? {
    try pendingConversationInputs(conversation: conversation).first
  }

  public func pendingConversationInputs(conversation: String) throws -> [ConversationSurface] {
    try synchronized {
      try pendingConversationInputReferences(conversation: conversation)
        .compactMap { try readInput($0.id, conversation: conversation) }
    }
  }

  func pendingConversationInputReferences(conversation: String) throws
    -> [ConversationInputReference]
  {
    try synchronized {
      try db.execute(
        """
        SELECT q.id,substr(json_extract(qp.payload,'$.surface.input.purpose'),1,120) AS purpose
        FROM messages q JOIN message_payloads qp ON qp.message_id=q.id
        WHERE q.conversation_id=? AND q.role='assistant' AND q.state='needs_input'
          AND length(CAST(qp.payload AS BLOB))<=16384
          AND json_extract(qp.payload,'$.kind')='conversation_surface'
          AND json_extract(qp.payload,'$.surface.version')=1
          AND NOT EXISTS (
            SELECT 1 FROM messages m JOIN message_payloads p ON p.message_id=m.id
            WHERE m.conversation_id=q.conversation_id AND m.role='user' AND m.rowid>q.rowid
              AND json_extract(p.payload,'$.surfaceID')=q.id
              AND json_extract(p.payload,'$.kind') IN ('conversation_input_answer','conversation_input_cancel')
          )
        ORDER BY q.rowid DESC LIMIT 8
        """, [.string(conversation)]
      ).map { .init(id: $0["id"]!.text, purpose: $0["purpose"]?.string ?? "View question") }
    }
  }

  func isPendingConversationInput(_ surface: ConversationSurface) throws -> Bool {
    try readInput(surface.id, conversation: surface.conversation) == surface
      && inputAnswerID(surface.id, conversation: surface.conversation) == nil
  }

  func readInput(_ id: String, conversation: String) throws -> ConversationSurface? {
    guard
      let payload = try db.scalar(
        """
        SELECT p.payload FROM messages m JOIN message_payloads p ON p.message_id=m.id
        WHERE m.id=? AND m.conversation_id=? AND m.role='assistant' AND m.state='needs_input'
          AND length(CAST(p.payload AS BLOB))<=16384
        """, [.string(id), .string(conversation)]
      ).string
    else { return nil }
    let envelope = try Value.parse(payload)
    guard envelope["kind"] == .string("conversation_surface"),
      envelope["surface"]["version"] == .number(1)
    else { return nil }
    guard
      let surface = try? JSONDecoder().decode(
        ConversationSurface.self, from: Data(envelope["surface"].json().utf8)),
      surface.id == id, surface.conversation == conversation, surface.revision == 1,
      let input = surface.input, input.kind == surface.kind
    else { return nil }
    guard (try? ConversationSurface.Input.parse(encoded(input), resolved: true)) != nil else {
      return nil
    }
    return surface
  }

  private func inputAnswerID(_ id: String, conversation: String) throws -> String? {
    try db.scalar(
      """
      SELECT m.id FROM messages m JOIN message_payloads p ON p.message_id=m.id
      WHERE m.conversation_id=? AND json_extract(p.payload,'$.surfaceID')=?
        AND json_extract(p.payload,'$.kind') IN ('conversation_input_answer','conversation_input_cancel')
      LIMIT 1
      """, [.string(conversation), .string(id)]
    ).string
  }

  /// For the local composer and native controls. Agent dispatch has no route here.
  @discardableResult public func submitConversationInput(
    _ surface: ConversationSurface, response: ConversationInputResponse, draftRevision: Int? = nil
  ) throws -> String? {
    try submitConversationInput(
      surface, response: response, draftRevision: draftRevision,
      dateContext: ConversationDateContext())
  }

  package func submitConversationInput(
    _ surface: ConversationSurface, response: ConversationInputResponse, draftRevision: Int? = nil,
    dateContext: ConversationDateContext
  ) throws -> String? {
    let result = try mutation(
      "conversation_input_submit", request: .string(surface.id), actor: .human("Sevra.chat-input")
    ) {
      guard try isPendingConversationInput(surface),
        let input = surface.input
      else {
        throw SevraError("conversation_input", "That question is no longer waiting for an answer.")
      }
      let draft = try readConversationInputDraft(surface)
      if case .cancel = response {
        if let draftRevision {
          try require(
            draftRevision == (draft?.revision ?? 0), "conversation_input_conflict",
            "Another window saved different answers. Reopen the question before cancelling.")
        }
      } else {
        try require(
          draft?.values.isEmpty != false || draftRevision == draft?.revision,
          "conversation_input_conflict",
          "This question has saved fields. Send or clear those fields before answering in the composer."
        )
      }
      let id = identifier()
      let kind: String
      let body: String
      var declined = false
      var values: [String: Value] = [:]
      switch response {
      case .cancel:
        kind = "conversation_input_cancel"
        body = "Cancelled the question about “\(input.purpose)”."
      case .decline:
        kind = "conversation_input_answer"
        // Sevra asks only for business values, and a skipped one is not made up. Skipping is not
        // a refusal: the task goes on without it.
        body = "Skip this question. Go on without it."
        declined = true
      case .choice(let choiceID):
        guard let choice = input.choices.first(where: { $0.id == choiceID }) else {
          throw SevraError("conversation_input", "That choice is unavailable.")
        }
        kind = "conversation_input_answer"
        values = choice.values
        body = choice.label + "\n" + Self.inputSummary(input, values: values)
      case .fields(let fields):
        try input.validate(fields)
        try require(!fields.isEmpty, "conversation_input", "Enter at least one answer.")
        kind = "conversation_input_answer"
        values = fields
        body = Self.inputSummary(input, values: fields)
      case .text(let text):
        try require(
          input.allowTextReply && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && text.utf8.count <= 4096,
          "conversation_input", "Use the question’s controls or enter a shorter answer.")
        kind = "conversation_input_answer"
        body = text
        values = input.values(forText: text, dateContext: dateContext)
        if input.fields.contains(where: { $0.type == .record }) {
          try input.validate(values)
        }
      }
      for field in input.fields {
        if let records = field.records, let rowID = values[field.id]?.string {
          _ = try validateInputRecord(records, rowID: rowID)
        }
      }
      try insertSurfaceMessage(
        id, conversation: surface.conversation, role: "user", body: body, state: "complete",
        payload: .object([
          "kind": .string(kind), "surfaceID": .string(surface.id),
          "surfaceRevision": .number(Double(surface.revision)),
          "requestID": .string(surface.requestID),
          "values": .object(values),
          "declined": .bool(declined),
          "dateContext": try encoded(dateContext),
        ]))
      try discardConversationInputDraft(surface)
      return kind == "conversation_input_cancel" ? .null : .string(id)
    }
    return result.string
  }

  private static func inputSummary(_ input: ConversationSurface.Input, values: [String: Value])
    -> String
  {
    input.fields.compactMap { field in
      values[field.id].map { value in
        let text: String
        if case .bool(let flag) = value { text = flag ? "Yes" : "No" } else {
          text = field.records?.labels?[value.text] ?? value.text
        }
        return field.label + ": " + text
      }
    }.joined(separator: "\n")
  }

  package func admitConversationContinuation(
    answerID: String, conversation: String, model: String, cancellation: Cancellation
  ) throws -> ConversationContinuation {
    try mutation(
      "conversation_input_continue", request: .string(answerID), cancellation: cancellation,
      reading: { receipt in
        ConversationContinuation(
          request: .init(runID: receipt["runID"].text, messageID: answerID),
          questionID: receipt["questionID"].text,
          originalRequestID: receipt["originalRequestID"].text,
          originalTask: receipt["originalTask"].text, question: receipt["question"].text,
          answer: receipt["answer"].text, values: receipt["values"],
          priorAnswers: receipt["priorAnswers"],
          requestDateContext: try Self.readInputDateContext(receipt["requestDateContext"]),
          answerDateContext: try Self.readInputDateContext(receipt["answerDateContext"]),
          declined: receipt["declined"] == .bool(true),
          readOnly: receipt["readOnly"] == .bool(true))
      },
      {
        let answer = try conversationInputAnswer(answerID, conversation: conversation)
        try require(
          try runForInputAnswer(answerID) == nil,
          "conversation_input", "This answer already started.")
        let surface = answer.surface
        var originalRequest = try historyMessage(surface.requestID, conversation: conversation)
        // A skipped question leaves the original request's authority as it was: the task
        // goes on with defaults for the choices it left open.
        var readOnly = surface.readOnly
        var priorAnswers: [Value] = []
        while try messagePayload(originalRequest.id, conversation: conversation)["kind"]
          == .string("conversation_input_answer")
        {
          try require(
            priorAnswers.count < 4, "conversation_input",
            "Start a new request to continue this task."
          )
          let parent = try conversationInputAnswer(originalRequest.id, conversation: conversation)
          priorAnswers.append(
            .object([
              "messageID": .string(originalRequest.id), "answer": .string(parent.body),
              "question": .string(parent.surface.input!.question), "values": parent.values,
              "dateContext": parent.dateContext,
            ]))
          readOnly = readOnly || parent.surface.readOnly
          originalRequest = try historyMessage(parent.surface.requestID, conversation: conversation)
        }
        let runID = identifier()
        try createAgentRun(
          runID, conversation: conversation, model: model, requestMessageID: answerID)
        return .object([
          "runID": .string(runID), "questionID": .string(surface.id),
          "originalRequestID": .string(originalRequest.id),
          "originalTask": .string(originalRequest.body),
          "question": .string(surface.input!.question), "answer": .string(answer.body),
          "values": answer.values,
          "requestDateContext": try surface.requestDateContext.map(encoded) ?? .null,
          "answerDateContext": answer.dateContext,
          "declined": .bool(answer.declined),
          "readOnly": .bool(readOnly), "priorAnswers": .array(priorAnswers.reversed()),
        ])
      })
  }

  private func conversationInputAnswer(
    _ answerID: String, conversation: String
  ) throws -> (
    surface: ConversationSurface, body: String, values: Value, dateContext: Value, declined: Bool
  ) {
    let message = try historyMessage(answerID, conversation: conversation)
    let payload = try messagePayload(answerID, conversation: conversation)
    guard message.role == "user", payload["kind"] == .string("conversation_input_answer"),
      let surface = try readInput(payload["surfaceID"].text, conversation: conversation),
      payload["surfaceRevision"] == .number(Double(surface.revision)),
      payload["requestID"] == .string(surface.requestID),
      try inputAnswerID(surface.id, conversation: conversation) == answerID
    else { throw SevraError("conversation_input", "Choose a saved answer in this conversation.") }
    return (
      surface, message.body, payload["values"], payload["dateContext"],
      payload["declined"] == .bool(true)
    )
  }

  private static func readInputDateContext(_ value: Value) throws -> ConversationDateContext? {
    guard value != .null else { return nil }
    return try JSONDecoder().decode(ConversationDateContext.self, from: Data(value.json().utf8))
  }

  private func runForInputAnswer(_ id: String) throws -> String? {
    try db.scalar("SELECT run_id FROM run_requests WHERE message_id=?", [.string(id)]).string
  }

  public func resumableConversationAnswer(conversation: String) throws -> String? {
    try synchronized {
      guard
        let id = try db.scalar(
          """
          SELECT m.id FROM messages m JOIN message_payloads p ON p.message_id=m.id
          LEFT JOIN run_requests r ON r.message_id=m.id
          WHERE m.conversation_id=? AND m.role='user' AND r.run_id IS NULL
            AND json_extract(p.payload,'$.kind')='conversation_input_answer'
          ORDER BY m.rowid DESC LIMIT 1
          """, [.string(conversation)]
        ).string
      else { return nil }
      _ = try conversationInputAnswer(id, conversation: conversation)
      return id
    }
  }

  func insertSurfaceMessage(
    _ id: String, conversation: String, role: String, body: String, state: String, payload: Value
  ) throws {
    let data = try payload.json()
    try require(
      body.utf8.count <= 128_000 && data.utf8.count <= 64 * 1024,
      "message_limit", "The conversation surface is too large.")
    try db.execute(
      "INSERT INTO messages VALUES(?,?,?,?,?,?)",
      [
        .string(id), .string(conversation), .string(role), .string(body), .string(state),
        .string(timestamp()),
      ])
    try db.execute("INSERT INTO message_payloads VALUES(?,?)", [.string(id), .string(data)])
  }
}
