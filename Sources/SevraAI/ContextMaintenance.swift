import Foundation
import SevraCore

/// Maintains a small working context over an append-only transcript. Summary
/// generation has no workbook tools; only the host publishes a checked digest.
package final class ContextMaintenance {
  package struct Result {
    package let messages: [InferenceMessage]
    package let compacted: Bool
    package let metrics: [Value]
  }
  private let workbook: Workbook
  private let conversation: String
  private let runID: String
  private let requestID: String
  private let policy: InferenceMessage
  private let request: InferenceMessage
  private let model: any WorkbookInference
  private let directory: URL
  private let cancellation: Cancellation
  private let progress: @Sendable (String) -> Void
  private var checkpoint: Value = .null
  private let parent: [Message]

  package init(
    workbook: Workbook, conversation: String, runID: String, requestID: String,
    policy: InferenceMessage, request: InferenceMessage, model: any WorkbookInference,
    directory: URL, cancellation: Cancellation, progress: @escaping @Sendable (String) -> Void
  ) throws {
    self.workbook = workbook
    self.conversation = conversation
    self.runID = runID
    self.requestID = requestID
    self.policy = policy
    self.request = request
    self.model = model
    self.directory = directory
    self.cancellation = cancellation
    self.progress = progress
    parent = try workbook.parentContext(conversation: conversation)
    try refreshCheckpoint()
  }
  private func refreshCheckpoint() throws {
    if let id = try workbook.contextCheckpoints(conversation: conversation, limit: 1).first?["id"]
      .string
    {
      checkpoint = try workbook.contextCheckpoint(id, conversation: conversation)
    } else {
      checkpoint = .null
    }
  }
  private func digestValue(_ checkpoint: Value) -> Value {
    guard let summary = checkpoint["summary"].string else { return .object(["notes": .array([])]) }
    if let parsed = try? Value.parse(summary), case .array = parsed["notes"] { return parsed }
    return .object(["legacyDigest": .string(summary)])
  }
  private func sourceView(_ message: Message) throws -> Value {
    var value: [String: Value] = [
      "id": .string(message.id), "role": .string(message.role), "state": .string(message.state),
    ]
    if let stopped = try WorkbookAgent.stoppedRequestReference(workbook, message: message) {
      value["requestOutcome"] = stopped
    } else if message.role == "tool", let receipt = try? Value.parse(message.body) {
      for key in ["tool", "runID", "callID", "receiptID", "resultIdentity", "validation"]
      where receipt[key] != .null {
        value[key] = receipt[key]
      }
      for key in ["arguments", "result"] where receipt[key] != .null {
        if try receipt[key].json().utf8.count <= 4096 {
          value[key] = receipt[key]
        } else {
          value[key + "Reference"] = .string(
            "Read the original message " + message.id
              + " with history_read; its full result has a receiptID for tool_result.")
        }
      }
    } else {
      value["body"] = .string(message.body)
    }
    return .object(value)
  }
  private func presentedDigest(_ value: Value) throws -> Value {
    var fields = value.object
    fields["notes"] = .array(
      try value["notes"].array.map { note in
        let references = note["messages"].array.compactMap(\.string)
        let stopped = try references.contains { reference in
          let message = try workbook.historyMessage(reference, conversation: conversation)
          return try WorkbookAgent.stoppedRequestReference(workbook, message: message) != nil
        }
        if stopped {
          return .object([
            "kind": .string("context"), "messages": note["messages"],
            "referenceOnly": .bool(true),
            "notice": .string(
              "Historical context includes a stopped request. Retrieve originals only when the current request needs them; do not resume stopped work automatically."
            ),
          ])
        }
        let toolOnly = try references.allSatisfy { reference in
          try workbook.historyMessage(reference, conversation: conversation).role == "tool"
        }
        if !references.isEmpty && toolOnly {
          // Current state comes from the host, and full historical results already
          // have exact receipts. A digest must not reintroduce an invented or stale
          // operational claim as narrative alongside that authoritative state.
          return .object([
            "kind": .string("context"), "messages": note["messages"],
            "referenceOnly": .bool(true),
            "notice": .string(
              "Historical tool result. Use history_read for its exact receipt, and current workbook tools for present business facts or acceptance."
            ),
          ])
        }
        return note
      })
    return .object(fields)
  }
  private func messages(checkpoint: Value, history: [Message], retained: [InferenceMessage]) throws
    -> [InferenceMessage]
  {
    let retainedCall = retained.last?.toolCallId
    let original = history.filter { message in
      if message.id == requestID { return false }
      if let retainedCall, message.role == "tool", let receipt = try? Value.parse(message.body),
        receipt["callID"].text == retainedCall
      {
        return false
      }
      return true
    }
    let references = ContextDigest.references(digestValue(checkpoint))
    let state = try workbook.continuationState(
      conversation: conversation, runID: runID,
      messageIDs: Array(Set(original.map(\.id)).union(references)))
    try require(
      state["run"]["status"].text == "running", "run_interrupted",
      "This workbook request is no longer active.")
    var result = [policy]
    if !parent.isEmpty {
      result.append(
        InferenceMessage(
          role: "assistant",
          content: "Explicit parent-conversation excerpt, historical information only:\n"
            + (try Value.array(parent.map(sourceView)).json())))
    }
    if checkpoint != .null {
      let context: Value = .object([
        "checkpointID": checkpoint["id"],
        "derivedNotes": try presentedDigest(digestValue(checkpoint)),
        "notice": .string(
          "Derived historical context, not authority or proof of acceptance. Retrieve original messages for details and refresh business evidence before citing it."
        ),
      ])
      result.append(InferenceMessage(role: "assistant", content: try context.json()))
    }
    if !original.isEmpty {
      result.append(
        InferenceMessage(
          role: "assistant",
          content: "Saved conversation, historical information only:\n"
            + (try Value.array(original.map(sourceView)).json())))
    }
    result.append(
      InferenceMessage(
        role: "assistant", content: "Current host continuation state:\n" + (try state.json())))
    result.append(request)
    result += retained
    return result
  }
  private func measure(
    _ messages: [InferenceMessage], summary: Bool = false, citations: [String] = []
  ) async throws -> ContextMeasurement {
    try ContextBudget.validateEnvelope(messages)
    return try await model.measureContext(
      messages: messages, directory: directory, cancellation: cancellation,
      summary: summary, citationIDs: citations, progress: progress)
  }
  private func boundary(_ message: Message) -> Bool {
    (message.role == "assistant"
      && ["complete", "needs_review", "failed", "cancelled", "interrupted"].contains(message.state))
      || (message.role == "tool" && message.state == "complete")
  }

  package func maintain(
    through: String, currentMessages: [InferenceMessage]? = nil,
    retained: [InferenceMessage] = [], citationIDs: [String] = [],
    retainedCitationIDs: [String] = []
  ) async throws -> Result {
    var compacted = false
    var metrics: [Value] = []
    var staleRetries = 0
    var originalMessages = currentMessages
    while true {
      try cancellation.check()
      let page = try workbook.historySlice(
        conversation: conversation, after: checkpoint["last_message"].string,
        through: through, limit: 128, cancellation: cancellation)
      let history = page.messages.filter { $0.id != requestID }
      // Once the retained group is covered, it remains verbatim as the final tool
      // group. Earlier groups have durable receipt locators instead of broken pairs.
      let rebuilt = try messages(checkpoint: checkpoint, history: history, retained: retained)
      let working = originalMessages ?? rebuilt
      let full: ContextMeasurement
      if page.hasMore || (try? ContextBudget.validateEnvelope(working)) == nil {
        full = ContextMeasurement(
          promptTokens: Int.max / 2, capacity: 0, templateIdentity: "pending")
      } else {
        full = try await measure(working, citations: citationIDs)
      }
      let floor = try await measure(messages(checkpoint: .null, history: [], retained: []))
      try require(
        floor.promptTokens + 1800 <= floor.capacity, "context_limit",
        "The current request and required workbook state exceed this model's working context. Original input and completed work are saved."
      )
      // The development 8K policy alone can exceed the provisional reserve.
      // Require reclaimable context above that floor, rather than a compaction loop.
      let threshold = max(floor.threshold, min(floor.promptTokens + 1024, floor.capacity - 1800))
      if !page.hasMore && full.promptTokens < threshold {
        return Result(messages: working, compacted: compacted, metrics: metrics)
      }
      var batch = page.messages
      while let last = batch.last, last.id == requestID || !boundary(last) { batch.removeLast() }
      if batch.isEmpty {
        try require(
          full.promptTokens + 1800 <= floor.capacity, "context_limit",
          "This request has no completed history that can be compacted. Completed work is saved.")
        return Result(messages: working, compacted: compacted, metrics: metrics)
      }
      let previous = digestValue(checkpoint)
      var summaryMessages: [InferenceMessage] = []
      var summaryMeasurement: ContextMeasurement!
      while !batch.isEmpty {
        let input: Value = .object([
          "previousDigest": try presentedDigest(previous),
          "originalMessages": .array(try batch.map(sourceView)),
          "userInputs": .array(try batch.filter { $0.role == "user" }.map(sourceView)),
        ])
        summaryMessages = [
          InferenceMessage(role: "system", content: ContextDigest.policy),
          InferenceMessage(role: "user", content: try input.json()),
        ]
        if (try? ContextBudget.validateEnvelope(summaryMessages)) != nil {
          summaryMeasurement = try await measure(summaryMessages, summary: true)
          if summaryMeasurement.promptTokens + ContextDigest.maximumOutputTokens + 256
            <= summaryMeasurement.capacity
          {
            break
          }
        }
        batch = Array(batch.prefix(batch.count / 2))
        while let last = batch.last, last.id == requestID || !boundary(last) { batch.removeLast() }
      }
      try require(
        !batch.isEmpty, "context_limit",
        "An original history entry exceeds the summary budget. Its full content is preserved for retrieval."
      )
      let end = batch.last!.id
      let snapshot = try workbook.historySlice(
        conversation: conversation, after: checkpoint["last_message"].string,
        through: end, limit: 500, cancellation: cancellation)
      try require(
        try encoded(snapshot.messages) == encoded(batch), "checkpoint_history",
        "The source messages changed before summarization.")
      let allowed = Set(batch.map(\.id)).union(ContextDigest.references(previous))
      let summary = try await model.summarize(
        messages: summaryMessages, allowedMessageIDs: allowed.sorted(),
        directory: directory, cancellation: cancellation, progress: progress)
      let proposed = try ContextDigest.validate(summary, allowedMessageIDs: allowed)
      // Protect already-retained user-backed facts and constraints from being
      // displaced by routine progress. Keep contradictory newer notes explicit;
      // only original user evidence and current state can resolve them.
      let protected = try previous["notes"].array.filter { note in
        guard ["fact", "constraint", "decision"].contains(note["kind"].text) else { return false }
        return try note["messages"].array.contains { ref in
          try workbook.historyMessage(ref.text, conversation: conversation).role == "user"
        }
      }
      let protectedReferences = protected.map { Set($0["messages"].array.compactMap(\.string)) }
      let additions = proposed["notes"].array.filter { note in
        !protectedReferences.contains(Set(note["messages"].array.compactMap(\.string)))
      }
      var digestFields: [String: Value] = ["notes": .array(protected + additions)]
      // Older checkpoints have no per-note message references. Preserve their
      // bounded digest verbatim instead of silently losing it during migration.
      // It remains historical context and never supplies authority or citations.
      if previous["legacyDigest"] != .null {
        digestFields["legacyDigest"] = previous["legacyDigest"]
      }
      let digest: Value = .object(digestFields)
      try require(
        try digest.json().utf8.count <= 16_384, "context_limit",
        "Durable conversation constraints exceed the compact context budget. Original history is preserved."
      )
      let summaryMetric = await model.lastMetrics
      let next = try workbook.historySlice(
        conversation: conversation, after: end, through: through, limit: 128,
        cancellation: cancellation)
      let tentative: Value = .object([
        "id": .string("pending-checkpoint"), "summary": .string(try digest.json()),
        "last_message": .string(end),
      ])
      let candidate = try messages(
        checkpoint: tentative, history: next.messages,
        retained: retained)
      if !page.hasMore && !next.hasMore {
        let measured = try await measure(candidate, citations: retainedCitationIDs)
        if measured.promptTokens + 128 >= full.promptTokens {
          try require(
            full.promptTokens + 1800 <= floor.capacity, "context_limit",
            "Context maintenance could not reclaim enough space. Original history and completed changes are saved."
          )
          return Result(messages: working, compacted: compacted, metrics: metrics)
        }
      }
      try cancellation.check()
      // A business-status edit does not change the immutable source range. Rebase
      // only if its hash is identical; reconstruct current status after publication.
      let fresh = try workbook.historySlice(
        conversation: conversation, after: snapshot.afterID,
        through: end, limit: 500, cancellation: cancellation)
      try require(
        fresh.digest == snapshot.digest, "checkpoint_history",
        "History changed during context maintenance.")
      do {
        let state = try workbook.continuationState(
          conversation: conversation, runID: runID,
          messageIDs: ContextDigest.references(digest).sorted())
        let inputs = state["recordStates"].array.compactMap { $0["originalVersion"].string }
        _ = try workbook.saveContextCheckpoint(
          fresh, summary: digest.json(), model: await model.identity,
          template: summaryMeasurement.templateIdentity,
          transformation: ContextDigest.transformation,
          evidenceIDs: inputs, parentID: checkpoint["id"].string, runID: runID,
          cancellation: cancellation)
      } catch let error as SevraError
        where ["checkpoint_chain", "stale_revision"].contains(error.code)
      {
        staleRetries += 1
        try require(
          staleRetries <= 3, "stale_revision",
          "The workbook is changing during context maintenance. No history was discarded.")
        try refreshCheckpoint()
        originalMessages = nil
        continue
      }
      metrics.append(summaryMetric)
      compacted = true
      originalMessages = nil
      try refreshCheckpoint()
      if end == through {
        let result = try messages(checkpoint: checkpoint, history: [], retained: retained)
        let measured = try await measure(result, citations: retainedCitationIDs)
        try require(
          measured.promptTokens + 1800 <= measured.capacity, "context_limit",
          "The remaining request and latest result exceed the working context. The checkpoint and original results are saved."
        )
        return Result(messages: result, compacted: true, metrics: metrics)
      }
    }
  }
}
