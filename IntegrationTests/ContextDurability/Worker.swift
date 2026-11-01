import Darwin
import Foundation
import SevraCore

private struct Plan: Codable {
  let history: HistorySlice
  let parent: String
  let references: [String]
  let forecast: String
  let forecastLogical: String
}

@main private struct ContextDurabilityWorker {
  static func emit(_ value: Value) {
    do {
      print(try value.json())
      fflush(stdout)
    } catch { exit(70) }
  }
  static func waitForController(_ phase: String, id: String = "") {
    emit(.object(["phase": .string(phase), "checkpoint": .string(id)]))
    guard readLine() == "continue" else { exit(71) }
  }
  static func snapshot(_ book: Workbook, plan: Plan) throws -> Value {
    let history = try book.historySlice(limit: 500)
    try require(!history.hasMore, "fixture", "Unexpected truncated fixture history.")
    let checkpoints = try book.contextCheckpoints()
    return .object([
      "revision": .number(Double(try book.revision())),
      "messages": try encoded(history.messages), "payloads": .object(history.payloads),
      "historyDigest": .string(history.digest), "items": try encoded(book.items(limit: 500)),
      "checkpoints": .array(checkpoints),
      "checkpointDetails": .array(
        try checkpoints.map { try book.contextCheckpoint($0["id"].text) }),
      "balance": try book.balance(subject: "brass bolts", asOf: "2099-12-31"),
      "forecast": try encoded(book.item(plan.forecastLogical)), "integrity": try book.verify(),
    ])
  }
  static func main() {
    do {
      let args = Array(CommandLine.arguments.dropFirst())
      try require(
        args.count == 2, "usage", "Expected operation and a disposable fixture directory.")
      let operation = args[0]
      let root = URL(fileURLWithPath: args[1])
      let path = root.appendingPathComponent("Checkpoint.sevra")
      let planPath = root.appendingPathComponent("plan.json")
      if operation == "setup" {
        _ = try Demo.create(at: path)
        let book = try Workbook(path)
        let source = try book.addItem(
          category: "source", kind: "assumption", title: "November estimate",
          text: "Estimated demand is four units.")
        let forecast = try book.addItem(
          category: "record", kind: "forecast", title: "November forecast",
          text: "Estimated demand is four units.", meaning: "estimate", inputs: [source.id])
        _ = try book.addMessage("Purchase code MAPLE-27. Keep stock unchanged.", role: "user")
        let end = try book.addMessage(
          "Recorded the supplied code and constraint.", role: "assistant")
        let prior = try book.saveContextCheckpoint(
          try book.historySlice(),
          summary:
            "The purchase code is MAPLE-27. The forecast is a draft estimate, not an actual movement.",
          model: "durability-fixture", template: "v1", evidenceIDs: [forecast.id])
        _ = try book.addMessage(
          "Use 0.25 kg per sample. Keep the original 0.10 kg value in history.", role: "user")
        _ = try book.addMessage(
          "Saved the revised packing instruction. No inventory changed.", role: "assistant")
        let plan = Plan(
          history: try book.historySlice(after: end), parent: prior, references: [forecast.id],
          forecast: forecast.id, forecastLogical: forecast.logicalID)
        try JSONEncoder().encode(plan).write(to: planPath, options: .atomic)
        emit(try snapshot(book, plan: plan))
        return
      }
      let plan = try JSONDecoder().decode(Plan.self, from: Data(contentsOf: planPath))
      let book = try Workbook(path)
      if operation == "inspect" {
        emit(try snapshot(book, plan: plan))
        return
      }
      if operation == "accept" {
        _ = try book.accept(plan.forecast)
        emit(try snapshot(book, plan: plan))
        return
      }
      if operation == "portable" {
        let archive = root.appendingPathComponent("Portable.sevraz")
        try book.export(to: archive)
        let restored = try Workbook.openArchive(
          archive, at: root.appendingPathComponent("Restored.sevra"))
        emit(try snapshot(restored, plan: plan))
        return
      }
      try require(
        ["pause-prepared", "pause-published", "pause-before", "cancel-prepared", "publish"]
          .contains(operation), "usage", "Unknown fixture operation.")
      let cancel = Cancellation()
      if operation == "pause-before" { waitForController("before") }
      let id = try CheckpointPublicationProbe.$observer.withValue(
        { stage, id in
          if operation == "pause-" + stage.rawValue { waitForController(stage.rawValue, id: id) }
          if operation == "cancel-prepared" && stage == .prepared { cancel.cancel() }
        },
        operation: {
          try book.saveContextCheckpoint(
            plan.history,
            summary:
              "Use 0.25 kg per sample; original 0.10 kg remains in history. No inventory change was authorized.",
            model: "durability-fixture", template: "v1", evidenceIDs: plan.references,
            parentID: plan.parent, token: "durability-checkpoint-once", cancellation: cancel)
        })
      emit(.object(["phase": .string("complete"), "checkpoint": .string(id)]))
    } catch let error as SevraError {
      emit(.object(["error": .string(error.code), "message": .string(error.message)]))
      exit(1)
    } catch {
      emit(
        .object(["error": .string("unexpected"), "message": .string(error.localizedDescription)]))
      exit(1)
    }
  }
}
