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
    guard !steps.isEmpty else {
      throw SevraError("fixture", "The script ran out at: " + (messages.last?.content ?? ""))
    }
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
  print("PASS decimal commas, joined units and stated percentages ground; wrong ones refused")
}

func checkAttachedCalculationInputs() async throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(
    "sevra-calculation-inputs-" + identifier())
  defer { try? FileManager.default.removeItem(at: root) }
  let book = try Workbook.create(at: root.appendingPathComponent("a.sevra"), title: "Inputs")
  let source = try book.addItem(
    category: "source", kind: "note", title: "Quotes", text: "Supplier quotes.")
  let columns: [Column] = [
    .init(id: "supplier", title: "Supplier"), .init(id: "total", title: "Total", type: "decimal"),
  ]
  func table(_ title: String, rows: Int) throws -> Dataset {
    try book.createDataset(
      title: title, columns: columns,
      rows: (0..<rows).map { ["supplier": .string("S\($0)"), "total": .string(String(100 + $0))] },
      sourceID: source.id)
  }
  func compare(_ table: Dataset) -> ScriptedCalls.Step {
    call(
      "compare_rows",
      .object([
        "datasetID": .string(table.id), "labelColumn": .string("supplier"),
        "valueColumn": .string("total"),
      ]))
  }

  // Past 16,000 bytes the receipt is paged and past 256 rows no grammar can name its inputs. The
  // comparison still counts, and the model owes no list of them.
  let long = try table("Long quotes", rows: 500)
  let model = ScriptedCalls([compare(long), finish("S0 has the lowest total.", basis: "evidence")])
  let answer = try await WorkbookAgent.run(
    "Which quote is cheapest?", workbook: book, context: "Table: \(long.id)", model: model)
  try expectEqual(answer.state, "complete")
  try expectEqual(answer.steps, 2)
  try expectEqual(answer.citations.count, 500)
  try expectEqual(answer.answer.components(separatedBy: "sevra://item/").count, 2)
  try expectEqual(answer.answer.contains("[500 calculation inputs](sevra://item/"), true)
  try expectEqual(await model.vocabularies.last!.count <= 3, true)
  let saved = try expectValue(book.messages().last { $0.role == "assistant" })
  try expectEqual(try book.messagePayload(saved.id)["calculationInputs"]["attached"].int, 500)

  let count = try book.addItem(
    category: "source", kind: "note", title: "Count", text: "Opening count: 20 brass bolts.",
    status: "accepted")
  try book.setOpeningBalance(
    subject: "brass bolts", quantity: "20", effective: "2026-01-01T00:00:00Z", sourceID: count.id)
  for index in 0..<70 {
    let movement = try book.movement(
      subject: "brass bolts", quantity: "1", occurrence: "delivery-\(index)",
      effective: String(format: "2026-02-01T10:%02d:00Z", index % 60), input: count.id)
    _ = try book.accept(movement.id)
  }
  let stocked = ScriptedCalls([
    call("balance", .object(["subject": .string("brass bolts")])),
    finish("Stock is 90 brass bolts.", basis: "evidence"),
  ])
  let stock = try await WorkbookAgent.run(
    "What is the brass bolt stock?", workbook: book, model: stocked)
  try expectEqual(stock.state, "complete")
  try expectEqual(stock.citations.count, 71)
  try expectEqual(stock.answer.contains("[71 calculation inputs](sevra://item/\(count.id))"), true)

  // A small receipt stays citable by name, and what the model does cite is not repeated.
  let short = try table("Short quotes", rows: 3)
  let rows = try book.rows(short.id).map(\.id)
  let named = ScriptedCalls([
    compare(short), finish("S0 has the lowest total.", basis: "evidence", citations: rows),
  ])
  let cited = try await WorkbookAgent.run(
    "Which quote is cheapest?", workbook: book, context: "Table: \(short.id)", model: named)
  try expectEqual(cited.state, "complete")
  try expectEqual(cited.citations, rows)
  try expectEqual(cited.answer.contains("calculation inputs"), false)

  // A write afterwards leaves a host-only answer, which reports no calculation and needs none.
  let saving = ScriptedCalls([
    compare(short),
    call(
      "save_space",
      .object([
        "title": .string("Quotes"),
        "definition": .object(["version": .number(1), "components": .array([])]),
      ])),
    finish("Done.", basis: "general"),
  ])
  let spaced = try await WorkbookAgent.run(
    "Compare the quotes and save a Quotes space.", workbook: book,
    context: "Table: \(short.id)", model: saving)
  try expectEqual(spaced.state, "complete")
  try expectEqual(spaced.steps, 3)
  try expectEqual(spaced.answer, "Saved space “Quotes”.")
  try expectEqual(spaced.citations, [])

  // The grounding rules stay. No calculation means no attached inputs, a citation still has to
  // be inspected, and an input that moved on is read before it is reported.
  let uninspected = ScriptedCalls([
    compare(short), finish("S0 is lowest.", basis: "evidence", citations: [source.id]),
    finish("S0 is lowest.", basis: "evidence"),
  ])
  let kept = try await WorkbookAgent.run(
    "Which quote is cheapest?", workbook: book, context: "Table: \(short.id)", model: uninspected)
  try expectEqual(kept.state, "complete")
  let refused = await uninspected.refusals
  try expectEqual(refused.count, 1)
  try expectEqual(refused[0].contains("Citations must be inspected"), true)
  let bare = ScriptedCalls([finish("It is S0.", basis: "evidence"), call("datasets")])
  do {
    _ = try await WorkbookAgent.run("Which quote is cheapest?", workbook: book, model: bare)
    throw SevraError("fixture", "An uncited answer completed.")
  } catch let error as SevraError where error.code == "fixture" {
    let refusals = await bare.refusals
    try expectEqual(refusals[0].contains("requires inspected citations"), true)
  }
  let stale = ScriptedCalls([
    compare(short),
    { _ in
      _ = try book.editRow(rows[0], values: ["total": .string("90")])
      return ("finish", .object(["answer": .string("S0."), "basis": .string("evidence")]))
    },
    { _ in ("read", .object(["id": .string(try book.rows(short.id)[0].id)])) },
    finish("S0.", basis: "evidence"),
  ])
  let refreshed = try await WorkbookAgent.run(
    "Which quote is cheapest? Inspect the rows.", workbook: book,
    context: "Row: \(try book.rows(short.id)[0].logicalID)", model: stale)
  try expectEqual(refreshed.state, "complete")
  let moved = await stale.refusals
  try expectEqual(moved.count, 1)
  try expectEqual(moved[0].contains("A cited version is historical"), true)
  try expectEqual(refreshed.answer.contains("Version check:"), true)
  print("PASS calculation inputs attach from receipts as one link; grounding rules stay")
}
