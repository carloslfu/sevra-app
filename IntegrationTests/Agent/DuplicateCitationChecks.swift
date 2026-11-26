import Foundation
import SevraAI
import SevraCore

/// Reads one record, then finishes citing it twice, as a real model did on November 25, 2026.
private actor DuplicateCitationInference: WorkbookInference {
  let identity = "scripted duplicate citation"
  let lastMetrics: Value = .null
  let record: String
  var step = 0
  init(record: String) { self.record = record }
  func beginRun() {}
  func endRun() {}
  func respond(
    messages: [InferenceMessage], directory: URL, cancellation: Cancellation,
    progress: @escaping @Sendable (String) -> Void, toolScope: InferenceToolScope,
    citationIDs: [String]
  ) throws -> NativeReply {
    step += 1
    if step == 1 {
      return .init(
        text: "",
        calls: [
          .init(
            id: identifier(), name: "read",
            inputJSON: try Value.object(["id": .string(record)]).json())
        ])
    }
    return .init(
      text: "",
      calls: [
        .init(
          id: identifier(), name: "finish",
          inputJSON: try Value.object([
            "answer": .string("The preferred supplier is Oak Supply."),
            "basis": .string("evidence"),
            "citations": .array([.string(record), .string(record)]),
          ]).json())
      ])
  }
}

func checkDuplicateCitations() async throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(
    "sevra-duplicate-citation-" + identifier())
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: root) }
  let book = try Workbook.create(at: root.appendingPathComponent("Cite.sevra"), title: "Cite")
  let note = try book.addItem(
    category: "source", kind: "document", title: "Supplier note",
    text: "The preferred supplier is Oak Supply.")
  let result = try await WorkbookAgent.run(
    "Who is the preferred supplier in \(note.id)?", workbook: book,
    model: DuplicateCitationInference(record: note.id))
  try expectEqual(result.citations, [note.id])
  try expectEqual(result.answer.components(separatedBy: "sevra://item/" + note.id).count - 1, 1)
  try expectEqual(try book.verify()["ok"], .bool(true))
  print("PASS a citation the model names twice is linked once")
}
