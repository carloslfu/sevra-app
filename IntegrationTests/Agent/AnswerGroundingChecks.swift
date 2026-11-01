import Foundation
import SevraAI
import SevraCore

/// Plays one tool call per step and keeps every prompt, so a check can read what the host said.
actor ScriptedCalls: WorkbookInference {
  typealias Step = @Sendable ([InferenceMessage]) throws -> (String, Value)
  let identity = "synthetic scripted calls"
  let lastMetrics: Value = .null
  private var steps: [Step]
  private(set) var prompts: [[InferenceMessage]] = []
  private(set) var vocabularies: [[String]] = []
  init(_ steps: [Step]) { self.steps = steps }
  func beginRun() {}
  func endRun() {}
  func respond(
    messages: [InferenceMessage], directory: URL, cancellation: Cancellation,
    progress: @escaping @Sendable (String) -> Void, toolScope: InferenceToolScope,
    citationIDs: [String]
  ) throws -> NativeReply {
    prompts.append(messages)
    vocabularies.append(citationIDs)
    guard !steps.isEmpty else { throw SevraError("fixture", "The script ran out of steps.") }
    let (tool, arguments) = try steps.removeFirst()(messages)
    return .init(
      text: "", calls: [.init(id: identifier(), name: tool, inputJSON: try arguments.json())])
  }
  /// What the host answered to each finish it refused.
  var refusals: [String] {
    prompts.compactMap { messages in
      guard let last = messages.last, last.role == "tool", last.toolName == "finish" else {
        return nil
      }
      return last.content
    }
  }
}

func call(_ tool: String, _ arguments: Value = .object([:])) -> ScriptedCalls.Step {
  { _ in (tool, arguments) }
}
func finish(_ answer: String, basis: String, citations: [String] = []) -> ScriptedCalls.Step {
  call(
    "finish",
    .object([
      "answer": .string(answer), "basis": .string(basis),
      "citations": .array(citations.map(Value.string)),
    ]))
}

func checkAnswerGrounding() async throws {
  let readings: [(String, Set<String>)] = [
    ("El total es 1.244,56 pesos.", ["1244.56"]),
    ("Son 1.234.567,89 COP y 1.234.567 unidades.", ["1234567.89", "1234567"]),
    ("Pagó 144USD por 25kg.", ["144", "25"]),
    ("1,234 and 1,234.50 and 1.234", ["1234", "1234.5", "1.234"]),
    ("0,125 y 12,5", ["0.125", "12.5"]),
    ("Filas 1,2,3 y 10,20,30", ["1", "2", "3", "10", "20", "30"]),
    ("The 2nd and 3rd, el 1er y 2do, H2O, Q3.", []),
  ]
  for (text, values) in readings { try expectEqual(WorkbookAgent.numericValues(text), values) }
  try expectEqual(
    WorkbookAgent.percentValues("IVA 12,5 %, 1.234,5%, 19 percent, 7 por ciento y -5%"),
    [12.5, 1234.5, 19, 7, 5].map { Decimal($0) })
  try expectEqual(WorkbookAgent.percentValues("Costs 12 percentage points more."), [])

  let root = FileManager.default.temporaryDirectory.appendingPathComponent(
    "sevra-grounding-" + identifier())
  defer { try? FileManager.default.removeItem(at: root) }
  let book = try Workbook.create(at: root.appendingPathComponent("a.sevra"), title: "Grounding")

  let note = try book.addItem(
    category: "source", kind: "note", title: "Invoice", text: "VAT on this invoice is 19 %.")

  // Numbers in the request stay grounded in the form they were written. A wrong one fails.
  let supplied = ScriptedCalls([
    call("read", .object(["id": .string(note.id)])),
    finish("El total es 1.244,57.", basis: "current_request"),
    finish("El total es 145USD.", basis: "current_request"),
    finish("El descuento es 13,5 %.", basis: "current_request"),
    finish("Son 1.244,56 o 144USD, con 12,5 % de descuento.", basis: "current_request"),
  ])
  let answered = try await WorkbookAgent.run(
    "Factura por 1.244,56 o 144USD con descuento de 12,5 %. ¿Qué dice?", workbook: book,
    context: "Invoice: \(note.id)", model: supplied)
  try expectEqual(answered.state, "complete")
  try expectEqual(answered.steps, 5)
  let refused = await supplied.refusals
  try expectEqual(refused.count, 3)
  for text in refused.prefix(2) {
    try expectEqual(text.contains("numbers not supplied in the current request"), true)
  }
  try expectEqual(refused[2].contains("percentage is unsupported"), true)

  // A rate read from the workbook needs no calculation, and only that rate is grounded.
  let stated = ScriptedCalls([
    call("read", .object(["id": .string(note.id)])),
    finish("VAT is 17%.", basis: "evidence", citations: [note.id]),
    finish("VAT is 19%.", basis: "evidence", citations: [note.id]),
  ])
  let read = try await WorkbookAgent.run(
    "What VAT does the invoice state?", workbook: book, context: "Invoice: \(note.id)",
    model: stated)
  try expectEqual(read.state, "complete")
  let unsupported = await stated.refusals
  try expectEqual(unsupported.count, 1)
  try expectEqual(unsupported[0].contains("percentage is unsupported"), true)
  try expectEqual(unsupported[0].contains("Call compare_rows or calculate"), false)
}
