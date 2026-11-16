import Foundation

/// Saved descriptors are descriptive data. Only a host submission can answer
/// one, and only the current question in the exact conversation is actionable.
public struct ConversationSurface: Codable, Equatable, Identifiable, Sendable {
  public enum Kind: String, Codable, Sendable { case question, input, review, result }

  public struct Field: Codable, Equatable, Identifiable, Sendable {
    public enum Kind: String, Codable, Sendable { case text, boolean, decimal, date }
    public let id: String
    public let label: String
    public let type: Kind
    public let required: Bool

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
    public let fields: [Field]
    public let choices: [Choice]
    public let allowTextReply: Bool

    package static func parse(_ value: Value) throws -> Self {
      let shape: Set<String> = [
        "kind", "purpose", "question", "fields", "choices", "allowTextReply",
      ]
      let fieldShape: Set<String> = ["id", "label", "type", "required"]
      let choiceShape: Set<String> = ["id", "label", "values"]
      try require(
        Set(value.object.keys) == shape
          && value["fields"].array.allSatisfy { Set($0.object.keys) == fieldShape }
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
      let ids = input.fields.map(\.id)
      let choiceIDs = input.choices.map(\.id)
      try require(
        Set(ids).count == ids.count && Set(choiceIDs).count == choiceIDs.count
          && input.fields.allSatisfy {
            Self.validID($0.id) && Self.validText($0.label, maximum: 120)
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
          (97...122).contains($0) || (48...57).contains($0) || $0 == 95
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

    fileprivate func values(forText text: String) -> [String: Value] {
      let reply = text.trimmingCharacters(in: .whitespacesAndNewlines)
      let matches = choices.filter {
        $0.id.caseInsensitiveCompare(reply) == .orderedSame
          || $0.label.caseInsensitiveCompare(reply) == .orderedSame
      }
      if matches.count == 1 { return matches[0].values }
      guard matches.isEmpty, fields.count == 1, let field = fields.first else { return [:] }
      let value: Value
      switch field.type {
      case .boolean:
        guard ["true", "false"].contains(reply.lowercased()) else { return [:] }
        value = .bool(reply.lowercased() == "true")
      case .decimal, .date: value = .string(reply)
      case .text:
        guard choices.isEmpty else { return [:] }
        value = .string(text)
      }
      guard (try? field.validate(value)) != nil else { return [:] }
      return [field.id: value]
    }

    fileprivate var fallback: String {
      var lines = [question]
      if !choices.isEmpty {
        lines += choices.map { "• " + $0.label }
      } else {
        lines += fields.map { "• " + $0.label + ($0.type == .date ? " (YYYY-MM-DD)" : "") }
      }
      if allowTextReply {
        lines.append("You can also reply with Answer: followed by your response.")
      }
      return lines.joined(separator: "\n")
    }
  }

  public let id: String
  public let version: Int
  public let revision: Int
  public let kind: Kind
  public let conversation: String
  public let runID: String
  public let requestID: String
  public let readOnly: Bool
  public let input: Input?
}

public enum ConversationInputResponse: Sendable {
  case choice(String)
  case fields([String: Value])
  case text(String)
  case cancel
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
  package let readOnly: Bool
}

extension Workbook {
  package func publishConversationInput(
    _ input: ConversationSurface.Input, runID: String, conversation: String, readOnly: Bool,
    steps: Int, metrics: Value, cancellation: Cancellation
  ) throws -> (id: String, body: String) {
    let id = identifier()
    let body = input.fallback
    let saved = try mutation(
      "conversation_input", token: runID + "-input", request: try encoded(input),
      cancellation: cancellation, commitGuard: { try cancellation.check() }
    ) {
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
      let descriptor = ConversationSurface(
        id: id, version: 1, revision: 1, kind: input.kind, conversation: conversation,
        runID: runID, requestID: request["message_id"]!.text, readOnly: readOnly, input: input)
      try insertSurfaceMessage(
        id, conversation: conversation, role: "assistant", body: body, state: "needs_input",
        payload: .object([
          "kind": .string("conversation_surface"), "surface": try encoded(descriptor),
        ]))
      try db.execute(
        "UPDATE agent_runs SET status='needs_input',steps=?,metrics=?,updated=? WHERE id=?",
        [.number(Double(steps)), .string(try metrics.json()), .string(timestamp()), .string(runID)])
      return .string(id)
    }
    return (saved.text, body)
  }

  public func pendingConversationInput(conversation: String) throws -> ConversationSurface? {
    try synchronized {
      guard
        let id = try db.scalar(
          """
          SELECT id FROM messages WHERE conversation_id=? AND role='assistant' AND state='needs_input'
          ORDER BY rowid DESC LIMIT 1
          """, [.string(conversation)]
        ).string, let surface = try readInput(id, conversation: conversation),
        try inputAnswerID(id, conversation: conversation) == nil
      else { return nil }
      let advanced = try db.scalar(
        """
        SELECT EXISTS(SELECT 1 FROM messages WHERE conversation_id=? AND role='user'
          AND rowid>(SELECT rowid FROM messages WHERE id=?))
        """, [.string(conversation), .string(id)])
      return advanced.int == 1 ? nil : surface
    }
  }

  private func readInput(_ id: String, conversation: String) throws -> ConversationSurface? {
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
    guard (try? ConversationSurface.Input.parse(encoded(input))) != nil else { return nil }
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
    let result = try mutation(
      "conversation_input_submit", request: .string(surface.id), actor: .human("Sevra.chat-input")
    ) {
      guard try pendingConversationInput(conversation: surface.conversation) == surface,
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
      var values: [String: Value] = [:]
      switch response {
      case .cancel:
        kind = "conversation_input_cancel"
        body = "Cancelled the question about “\(input.purpose)”."
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
        values = input.values(forText: text)
      }
      try insertSurfaceMessage(
        id, conversation: surface.conversation, role: "user", body: body, state: "complete",
        payload: .object([
          "kind": .string(kind), "surfaceID": .string(surface.id),
          "surfaceRevision": .number(Double(surface.revision)),
          "requestID": .string(surface.requestID),
          "values": .object(values),
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
      values[field.id].map { field.label + ": " + $0.text }
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
          readOnly: receipt["readOnly"] == .bool(true))
      }
    ) {
      let answer = try conversationInputAnswer(answerID, conversation: conversation)
      try require(
        try resumableConversationAnswer(conversation: conversation) == answerID,
        "conversation_input", "This answer already started or the conversation moved on.")
      let surface = answer.surface
      var originalRequest = try historyMessage(surface.requestID, conversation: conversation)
      var readOnly = surface.readOnly
      var priorAnswers: [Value] = []
      while try messagePayload(originalRequest.id, conversation: conversation)["kind"]
        == .string("conversation_input_answer")
      {
        try require(
          priorAnswers.count < 4, "conversation_input", "Start a new request to continue this task."
        )
        let parent = try conversationInputAnswer(originalRequest.id, conversation: conversation)
        priorAnswers.append(
          .object([
            "messageID": .string(originalRequest.id), "answer": .string(parent.body),
            "question": .string(parent.surface.input!.question), "values": parent.values,
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
        "readOnly": .bool(readOnly), "priorAnswers": .array(priorAnswers.reversed()),
      ])
    }
  }

  private func conversationInputAnswer(
    _ answerID: String, conversation: String
  ) throws -> (surface: ConversationSurface, body: String, values: Value) {
    let message = try historyMessage(answerID, conversation: conversation)
    let payload = try messagePayload(answerID, conversation: conversation)
    guard message.role == "user", payload["kind"] == .string("conversation_input_answer"),
      let surface = try readInput(payload["surfaceID"].text, conversation: conversation),
      payload["surfaceRevision"] == .number(Double(surface.revision)),
      payload["requestID"] == .string(surface.requestID),
      try inputAnswerID(surface.id, conversation: conversation) == answerID
    else { throw SevraError("conversation_input", "Choose a saved answer in this conversation.") }
    return (surface, message.body, payload["values"])
  }

  private func runForInputAnswer(_ id: String) throws -> String? {
    try db.scalar("SELECT run_id FROM run_requests WHERE message_id=?", [.string(id)]).string
  }

  public func resumableConversationAnswer(conversation: String) throws -> String? {
    try synchronized {
      guard
        let id = try db.scalar(
          "SELECT id FROM messages WHERE conversation_id=? AND role='user' ORDER BY rowid DESC LIMIT 1",
          [.string(conversation)]
        ).string, try runForInputAnswer(id) == nil,
        try messagePayload(id, conversation: conversation)["kind"]
          == .string("conversation_input_answer")
      else { return nil }
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
