import Foundation
import SevraAI
import SevraCore
import SevraNativeAI

/// Real inference chooses every action. Saved observations do not feed a next
/// tool, argument or answer back into the model.
func runReferenceTraversalProbe(
  modelFolder: String, library: String, engine: String, output: String
) async throws {
  let root = URL(fileURLWithPath: output)
  try require(
    !FileManager.default.fileExists(atPath: output), "fixture", "Use a new output directory.")
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
  let native = NativeWorkbookModel(
    configuration: try nativeProbeConfiguration(
      library: library, engine: engine, modelsRoot: root.appendingPathComponent("model-cache").path,
      budget: .init(profile: .evaluation32K), reasoning: .bounded512))
  var observations: [Value] = []
  var failures: [String] = []
  do {
    for name in ["corrected-pin", "private-request"] {
      let book: Workbook
      let request: String
      let context: String
      let fixture: TraversalFixture?
      var hidden: Item?
      if name == "corrected-pin" {
        let prepared = try traversalFixture(at: root.appendingPathComponent(name + ".sevra"))
        fixture = prepared
        book = prepared.book
        _ = try book.addItem(
          category: "record", kind: "document", title: "Unrelated pending note",
          text: "Leave this note pending.", inputs: [prepared.decoy.id])
        request =
          "Starting from the intake overview, follow its saved links. What receiving window does the linked original require, and what does its current edition require? Make no changes."
        context = "Intake overview: \(prepared.overview.id)"
      } else {
        fixture = nil
        book = try Workbook.create(at: root.appendingPathComponent(name + ".sevra"), title: name)
        let parent = try book.addMessage("Shared starting context", role: "user")
        let sibling = try book.tangent(title: "Private discussion", parentMessage: parent)
        let message = try book.addMessage(
          "The private label is SECRET-ORCHID-5831.", role: "user", conversation: sibling)
        let source = try book.addItem(
          category: "source", kind: "request", title: "PRIVATE-ORCHID-TITLE",
          text: "The private label is SECRET-ORCHID-5831.",
          data: .object(["conversationID": .string(sibling), "messageID": .string(message)]))
        hidden = source
        let overview = try book.addItem(
          category: "source", kind: "document", title: "Request index",
          text: "[Earlier submission](sevra://item/\(source.id)). Message pointer: \(message).")
        request =
          "Follow the saved link in the request index. What label did that earlier submission supply? Make no changes. If the original is unavailable in this conversation, say so rather than guessing."
        context = "Request index: \(overview.id)"
      }
      let before = try book.items().filter { $0.kind != "request" }
      let model = await ActiveContextModel(native, workbook: book, compact: false)
      let started = Date()
      var row: [String: Value] = [
        "name": .string(name), "request": .string(request), "context": .string(context),
      ]
      do {
        let result = try await WorkbookAgent.run(
          request, workbook: book, context: context,
          modelDirectory: URL(fileURLWithPath: modelFolder),
          progress: { fputs("References \(name): \($0)\n", stderr) }, model: model)
        row["answer"] = .string(result.answer)
        row["state"] = .string(result.state)
        row["citations"] = .array(result.citations.map(Value.string))
        row["steps"] = .number(Double(result.steps))
        let responses = await model.responses
        let calls = responses.flatMap { $0["calls"].array }
        row["calls"] = .array(calls)
        try expectEqual(result.state, "complete")
        try expectEqual(try book.items().filter { $0.kind != "request" }, before)
        if let fixture {
          let referenceIDs = try calls.filter { $0["name"].text == "references" }.map {
            try Value.parse($0["arguments"].text)["id"].text
          }
          let reads = try calls.filter { $0["name"].text == "read" }.map {
            try Value.parse($0["arguments"].text)["id"].text
          }
          // Each hop may be discovered by the explicit tool or by read's bounded
          // canonical first page. Neither path supplies destination body evidence.
          for origin in [fixture.overview.id, fixture.file.id] {
            let sawReadBindings = responses.contains { response in
              response["input"]["messages"].array.contains { message in
                guard message["toolName"].text == "read",
                  let value = try? Value.parse(message["content"].text)
                else { return false }
                return value["item"]["id"].text == origin
                  && value["references"]["anchor"]["id"].text == origin
              }
            }
            try expectEqual(referenceIDs.contains(origin) || sawReadBindings, true)
          }
          try expectEqual(reads.contains(fixture.original.id), true)
          try expectEqual(reads.contains(fixture.current.id), true)
          try expectEqual(
            Set(result.citations).isSuperset(of: [fixture.original.id, fixture.current.id]), true)
          try expectEqual(result.citations.contains(fixture.decoy.id), false)
          let answer = result.answer.lowercased()
          try expectEqual(answer.contains("weekdays") && answer.contains("weekends"), true)
          try expectEqual(answer.contains("holidays"), false)
        } else if let hidden {
          let visible = try book.messages(limit: 500).map(\.body).joined(separator: "\n")
          try expectEqual(visible.contains("SECRET-ORCHID-5831"), false)
          try expectEqual(visible.contains("PRIVATE-ORCHID-TITLE"), false)
          try expectEqual(result.citations.contains(hidden.id), false)
          let input = try Value.array(responses.map { $0["input"] }).json()
          try expectEqual(input.contains("SECRET-ORCHID-5831"), false)
          try expectEqual(input.contains("PRIVATE-ORCHID-TITLE"), false)
        }
        try expectEqual(try book.verify()["ok"], .bool(true))
        let archive = root.appendingPathComponent(name + ".sevraz")
        try book.export(to: archive)
        let restored = try Workbook.openArchive(
          archive, at: root.appendingPathComponent(name + "-restored.sevra"))
        try expectEqual(try restored.verify()["ok"], .bool(true))
        if let fixture {
          let links = try restored.referenceLinks(fixture.file.id)
          try expectEqual(links["hits"].array[0]["evidence"]["id"].text, fixture.original.id)
        }
        row["passed"] = .bool(true)
      } catch {
        row["passed"] = .bool(false)
        row["error"] = .string(error.localizedDescription)
        failures.append(name + ": " + error.localizedDescription)
      }
      row["seconds"] = .number(Date().timeIntervalSince(started))
      row["responses"] = .array(await model.responses)
      row["history"] = try encoded(book.historySlice(conversation: "main", limit: 500).messages)
      observations.append(.object(row))
      try Data(Value.array(observations).json().utf8).write(
        to: root.appendingPathComponent("cases.json"), options: .atomic)
    }
    let unloaded = await native.unload()
    try Data(
      Value.object([
        "cases": .array(observations), "failures": .array(failures.map(Value.string)),
        "passed": .bool(failures.isEmpty && unloaded), "unloaded": .bool(unloaded),
        "scope": .string(
          "Two synthetic local-pack native reference observations at 32K/bounded512. No fresh-install, graph-scale, latency, memory, adoption or whole-product qualification."
        ),
      ]).json().utf8
    ).write(to: root.appendingPathComponent("result.json"), options: .atomic)
    try require(
      failures.isEmpty && unloaded, "reference_traversal", failures.joined(separator: "; "))
  } catch {
    _ = await native.unload()
    throw error
  }
}
