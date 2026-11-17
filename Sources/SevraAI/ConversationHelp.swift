import Foundation
import SevraCore

/// A deliberately closed, read-only route. Unrecognized or compound requests
/// keep the full agent, including evidence, calculations and action authority.
package struct ConversationHelp: Sendable {
  package enum Kind: String, Sendable { case greeting, capabilities, detail, summary, thanks }
  package let kind: Kind
  package let spanish: Bool
  package var topic: String {
    kind == .greeting || kind == .thanks ? kind.rawValue : "capabilities"
  }
  package static func select(_ prompt: String, workbook: Workbook, conversation: String) throws
    -> Self?
  {
    let text = prompt.lowercased().replacingOccurrences(of: "’", with: "'")
      .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
      .split(whereSeparator: \.isWhitespace).joined(separator: " ")
    let spanish = [
      "hola", "buenos", "buenas", "gracias", "muchas", "que", "qué", "cómo",
      "cuéntame", "dime", "resúmelo", "en resumen", "más",
    ].contains { text.hasPrefix($0) }
    let kind: Kind
    switch text {
    case "hi", "hey", "hello", "hey sevra", "hi sevra", "hello sevra", "good morning",
      "good afternoon", "good evening", "hola", "hola sevra", "buenos días", "buenas tardes":
      kind = .greeting
    case "thanks", "thank you", "thanks sevra", "thank you sevra", "gracias", "muchas gracias":
      kind = .thanks
    case "what can you do", "what can you do for me", "how can you help", "how can you help me",
      "what can sevra do", "what is sevra", "what's sevra", "que puedes hacer",
      "qué puedes hacer", "qué puedes hacer por mí", "cómo puedes ayudarme", "qué es sevra":
      kind = .capabilities
    case "tell me more", "more details", "explain more", "go on", "cuéntame más", "dime más":
      kind = .detail
    case "tldr", "tl;dr", "tl dr", "in short", "shorter", "make it shorter", "summarize that",
      "resúmelo", "en resumen", "más breve":
      kind = .summary
    default: return nil
    }
    guard [.detail, .summary].contains(kind) else {
      return .init(kind: kind, spanish: spanish)
    }
    // A vague follow-up after business work must retain that work's evidence.
    // Only a host-marked product explanation can enter the small help context.
    guard
      let last = try workbook.messages(conversation: conversation, limit: 4)
        .last(where: { ["user", "assistant"].contains($0.role) }),
      last.role == "assistant", last.state == "complete",
      try workbook.messagePayload(last.id, conversation: conversation)["kind"]
        == .string("product_help"),
      try workbook.messagePayload(last.id, conversation: conversation)["conversationHelp"]["topic"]
        == .string("capabilities")
    else { return nil }
    return .init(kind: kind, spanish: spanish)
  }
  /// App-owned help is explicit product copy, not a model answer or a report
  /// about this workbook. It avoids waking a multi-gigabyte model for a greeting.
  package var answer: String {
    switch (kind, spanish) {
    case (.greeting, false):
      return
        "Hey! What would you like to work on? I can help compare supplier quotes or organize inventory."
    case (.thanks, false): return "You're welcome!"
    case (.capabilities, false):
      return
        "I can help you find answers in your files, compare supplier quotes with checked calculations and source citations, and organize tables, charts or small inventory apps. Add a file or describe a job you'd like to work on. Your files and AI stay on your Mac."
    case (.detail, false):
      return
        "For example, add two supplier quotes and ask me to compare goods plus shipping. You can inspect the source citations, keep missing tax marked as unknown, and save a table or chart for next time. For recurring work, we can build a small native app, such as an inventory tracker, with access you review and approve."
    case (.summary, false):
      return
        "I help you turn your files into cited answers, checked comparisons and reusable tables or small apps, all locally on your Mac."
    case (.greeting, true):
      return
        "¡Hola! ¿En qué quieres trabajar? Puedo ayudarte a comparar cotizaciones u organizar tu inventario."
    case (.thanks, true): return "¡De nada!"
    case (.capabilities, true):
      return
        "Puedo ayudarte a encontrar respuestas en tus archivos, comparar cotizaciones con cálculos y citas, y organizar tablas, gráficos o pequeñas apps de inventario. Añade un archivo o describe el trabajo que quieres hacer. Tus archivos y la IA se quedan en tu Mac."
    case (.detail, true):
      return
        "Por ejemplo, añade dos cotizaciones y pídeme comparar productos y envío. Puedes revisar las fuentes, mantener como desconocidos los impuestos que falten y guardar una tabla o un gráfico para la próxima vez. Para trabajos recurrentes podemos crear una pequeña app, como un inventario, con acceso que tú revisas y apruebas."
    case (.summary, true):
      return
        "Te ayudo a convertir tus archivos en respuestas con fuentes, comparaciones verificadas y tablas o pequeñas apps reutilizables, todo localmente en tu Mac."
    }
  }

  package func reply(
    to prompt: String, workbook: Workbook, conversation: String, context: String,
    cancellation: Cancellation, requestStarted: @Sendable (AgentRequest, String) -> Void
  ) throws -> AgentResult {
    do { try cancellation.check() } catch {
      let rejected = try workbook.rejectAgentRequest(
        prompt, conversation: conversation, model: "Sevra product help",
        cancelled: cancellation.isCancelled, reason: error.localizedDescription)
      requestStarted(rejected, conversation)
      throw error
    }
    let request = try workbook.startProductHelpRequest(prompt, conversation: conversation)
    requestStarted(request, conversation)
    do {
      let source = try workbook.captureUserRequest(
        prompt,
        data: .object([
          "conversationID": .string(conversation), "messageID": .string(request.messageID),
          "context": .string(context),
        ]), token: request.runID + "-request", cancellation: cancellation)
      let metrics: Value = .array([
        .object([
          "backend": .string("product-help"), "kind": .string(kind.rawValue),
          "modelCalls": .number(0), "promptTokens": .number(0), "reasoningTokens": .number(0),
        ])
      ])
      _ = try workbook.finishAgentAnswer(
        answer,
        payload: .object([
          "kind": .string("product_help"),
          "conversationHelp": .object([
            "topic": .string(topic), "version": .number(1),
          ]), "requestSourceID": .string(source.id), "runID": .string(request.runID),
          "presentation": .string("answer"),
        ]), runID: request.runID, conversation: conversation, steps: 0,
        metrics: metrics, cancellation: cancellation)
      return .init(answer: answer, citations: [], steps: 0, state: "complete", focus: nil)
    } catch {
      try? workbook.finishAgentRun(
        request.runID, status: cancellation.isCancelled ? "cancelled" : "failed", steps: 0,
        metrics: .array([]))
      _ = try? workbook.addMessage(
        error.localizedDescription, role: "assistant", conversation: conversation,
        state: cancellation.isCancelled ? "cancelled" : "failed")
      throw error
    }
  }
}
