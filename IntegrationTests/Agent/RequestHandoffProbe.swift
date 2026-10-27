import CryptoKit
import Foundation
import SevraAI
import SevraCore
import SevraNativeAI

/// Synthetic qualification only. Product workbooks never persist reasoning.
private actor HandoffTraceModel: WorkbookInference {
  let identity: String
  var lastMetrics: Value = .null
  let base: NativeWorkbookModel
  let path: URL
  var trace: [Value] = []
  init(base: NativeWorkbookModel, identity: String, path: URL) {
    self.base = base
    self.identity = identity
    self.path = path
  }
  func beginRun() async throws { try await base.beginRun() }
  func endRun() async { await base.endRun() }
  func respond(
    messages: [InferenceMessage], directory: URL, cancellation: Cancellation,
    progress: @escaping @Sendable (String) -> Void, toolScope: InferenceToolScope,
    citationIDs: [String]
  ) async throws -> NativeReply {
    func calls(_ values: [InferenceCall]) -> Value {
      .array(
        values.map { .object(["name": .string($0.name), "arguments": .string($0.inputJSON)]) })
    }
    let input: Value = .array(
      messages.map {
        .object([
          "role": .string($0.role), "content": .string($0.content),
          "reasoning": .string($0.reasoning),
          "calls": calls($0.toolCalls),
          "conversationActions": $0.conversationActions.map { .array($0.map(Value.string)) }
            ?? .null,
        ])
      })
    let response = try await base.respond(
      messages: messages, directory: directory,
      cancellation: cancellation, progress: progress, toolScope: toolScope, citationIDs: citationIDs
    )
    lastMetrics = await base.lastMetrics
    trace.append(
      .object([
        "messages": input, "reasoning": .string(response.reasoning),
        "calls": calls(response.calls), "metrics": lastMetrics,
      ]))
    try Data(Value.array(trace).json().utf8).write(to: path, options: .atomic)
    return response
  }
}

func runRequestHandoffProbe(modelsRoot: String, library: String, engine: String, output: String)
  async throws
{
  let root = URL(fileURLWithPath: output)
  try require(
    !FileManager.default.fileExists(atPath: root.path), "fixture", "Use a new output folder.")
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
  let cases: [(String, String)] = [
    (
      "supplied-prices",
      "Start a new thread called Price comparison and calculate the difference between 14.80 and 12.40 there."
    ),
    (
      "stored-prices",
      "Take this into a new thread called Supplier comparison and compare the Birch and Cedar quotes in this workbook. Read both original quotes and tell me which has the lower unit cost and by how much."
    ),
    (
      "proposal",
      "Start a new thread called Receiving and propose an inventory movement for the two fittings handed over, using the Handover note. Leave it as a proposal for my review."
    ),
    ("branch-only", "Take this discussion into a new thread called Delivery dates."),
    (
      "hypothetical",
      "Would starting a thread let us compare the Birch and Cedar quotes separately? Explain only; do not start one."
    ),
  ]
  let protocolValue: Value = .object([
    "version": .number(2),
    "cases": .array(cases.map { .object(["name": .string($0.0), "prompt": .string($0.1)]) }),
    "checks": .string(
      "Compound cases create exactly one thread, start_thread_and_continue before attempted changes (prior reads allowed), exact carried request, one Source, two linked runs, original continued and child terminal, total <=12 steps. Prices require deterministic calculation and result 2.4. Stored prices cite both originals. Proposal remains draft with original request and Handover note lineage; accepted inventory stays 20. Branch-only remains one terminal step. Hypothetical has no action. Verify unchanged originals and workbook integrity. Review answer semantics separately."
    ),
  ])
  try Data(protocolValue.json().utf8).write(to: root.appendingPathComponent("protocol.json"))
  func hash(_ path: String) throws -> Value {
    .string(
      SHA256.hash(data: try Data(contentsOf: URL(fileURLWithPath: path))).map {
        String(format: "%02x", $0)
      }.joined())
  }
  try Data(
    Value.object([
      "binarySHA256": try hash(CommandLine.arguments[0]), "engineSHA256": try hash(engine),
      "grammarLibrarySHA256": try hash(library),
      "model": .string("Qwen3.6-35B installed, native 32K, bounded512"),
    ]).json().utf8
  ).write(to: root.appendingPathComponent("execution.json"))
  let model = NativeWorkbookModel(
    configuration: try nativeProbeConfiguration(
      library: library, engine: engine, modelsRoot: modelsRoot,
      budget: .init(profile: .evaluation32K), reasoning: .bounded512, modelLayout: .installed))
  var results: [Value] = []
  var failures = 0
  for (name, prompt) in cases {
    let book = try Workbook.create(at: root.appendingPathComponent(name + ".sevra"), title: name)
    let birch = try book.addItem(
      category: "source", kind: "quote", title: "Birch quote",
      text: "Birch quoted a unit cost of 14.80 for a brass fitting. No currency was specified.")
    let cedar = try book.addItem(
      category: "source", kind: "quote", title: "Cedar quote",
      text:
        "Cedar quoted a unit cost of 12.40 for the same brass fitting. No currency was specified.")
    let handover = try book.addItem(
      category: "source", kind: "observation", title: "Handover note",
      text:
        "Two fittings were handed over to a customer for a sale on 2026-01-02T12:00:00Z. The two units left our stock; this was not a receipt. Inventory subject: fittings. Occurrence identifier: handover-1. Opening stock was 20 fittings."
    )
    try book.setOpeningBalance(
      subject: "fittings", quantity: "20", effective: "2026-01-01T00:00:00Z", sourceID: handover.id)
    _ = try book.addMessage("Explore supplier choices.", role: "user")
    let parent = try book.addMessage(
      "We can compare costs and delivery evidence.", role: "assistant")
    let originals = try encoded([birch, cedar, handover])
    var record: [String: Value] = ["name": .string(name), "prompt": .string(prompt)]
    let traced = HandoffTraceModel(
      base: model, identity: await model.identity,
      path: root.appendingPathComponent(name + "-trace.json"))
    do {
      let result = try await WorkbookAgent.run(
        prompt, workbook: book,
        modelDirectory: URL(fileURLWithPath: modelsRoot),
        cancellation: .init(deadlineAfterSeconds: 240),
        model: traced, enableCompaction: false)
      record["answer"] = .string(result.answer)
      record["steps"] = .number(Double(result.steps))
      record["state"] = .string(result.state)
      record["citations"] = .array(result.citations.map(Value.string))
      record["conversationAction"] = try result.conversationAction.map(encoded) ?? .null
      let runs = try book.agentRuns()
      let mainCalls = try book.messages().filter { $0.role == "tool" }.map {
        try Value.parse($0.body)
      }
      try require(result.steps <= 12, "handoff", "Shared step budget exceeded.")
      try require(
        book.items().filter { $0.kind == "request" }.count == 1, "handoff",
        "Request Source duplicated.")
      if name == "hypothetical" {
        try require(
          result.conversationAction == nil && book.conversations().count == 1 && mainCalls.isEmpty,
          "handoff", "Hypothetical question triggered an action or irrelevant tools.")
      } else {
        guard let action = result.conversationAction else {
          throw SevraError("handoff", "No thread was created.")
        }
        try require(
          action.kind == .created && action.message == parent && book.conversations().count == 2,
          "handoff", "Wrong branch or duplicate thread.")
        let childMessages = try book.messages(conversation: action.conversation)
        if name == "branch-only" {
          try require(
            result.steps == 1 && runs.count == 1 && childMessages.isEmpty
              && mainCalls.first?["tool"].text == "start_thread",
            "handoff", "Branch-only request continued work.")
        } else {
          try require(
            mainCalls.last?["tool"].text == "start_thread_and_continue"
              && mainCalls.dropLast().allSatisfy {
                WorkbookTools.readOnlyTools.contains($0["tool"].text)
              },
            "handoff", "Compound request did not hand off before attempted changes.")
          try require(
            runs.count == 2
              && runs.contains {
                $0["conversation_id"].text == "main" && $0["status"].text == "continued"
              },
            "handoff", "Original run is not recorded as continued.")
          try require(
            childMessages.first { $0.role == "user" }?.body == prompt, "handoff",
            "The carried request changed.")
          let calls = try childMessages.filter { $0.role == "tool" }.map {
            try Value.parse($0.body)
          }
          if name.contains("prices") {
            try require(
              calls.contains { ["calculate", "compare_rows"].contains($0["tool"].text) }
                && result.answer.contains("2.4"), "handoff", "Missing checked price difference.")
            if name == "stored-prices" {
              try require(
                Set([birch.id, cedar.id]).isSubset(of: Set(result.citations))
                  && result.answer.lowercased().contains("cedar"),
                "handoff", "Wrong supplier or missing original citations.")
            }
          } else {
            try require(
              result.state == "needs_review", "handoff", "Proposal was not left for review.")
            let movements = try book.items().filter { $0.kind == "movement" }
            try require(
              movements.count == 1 && movements[0].status == "draft", "handoff",
              "Incorrect movement state.")
            let movement = try book.item(movements[0].id)
            let inputs = Set(
              try book.lineage(movement.id).filter { $0["child"].text == movement.id }.map {
                $0["parent"].text
              })
            let requestSource = try book.items().first { $0.kind == "request" }!
            try require(
              inputs.contains(handover.id) && inputs.contains(requestSource.id), "handoff",
              "Missing original request or observation lineage.")
            try require(
              movement.data["quantity"].text == "-2", "handoff", "Incorrect movement quantity.")
          }
        }
      }
      try require(
        try encoded([book.item(birch.id), book.item(cedar.id), book.item(handover.id)])
          == originals,
        "handoff", "Original evidence changed.")
      try require(
        try WorkbookTools(book).execute("balance", .object(["subject": .string("fittings")]))[
          "quantity"
        ].text == "20",
        "handoff", "Accepted stock changed without approval.")
      try require(try book.verify()["ok"] == .bool(true), "handoff", "Integrity failure.")
      record["passed"] = .bool(true)
    } catch {
      failures += 1
      record["passed"] = .bool(false)
      record["error"] = .string(error.localizedDescription)
    }
    record["runs"] = .array(try book.agentRuns())
    record["messages"] = .array(
      try book.conversations().map { conversation in
        .object([
          "conversation": conversation,
          "messages": try encoded(book.messages(conversation: conversation["id"].text)),
        ])
      })
    results.append(.object(record))
    try Data(Value.array(results).json().utf8).write(
      to: root.appendingPathComponent("results.json"), options: .atomic)
    print("\(record["passed"] == .bool(true) ? "PASS" : "FAIL") request handoff \(name)")
    fflush(stdout)
  }
  let released = await model.releaseResources()
  try require(released, "handoff", "Model resources did not release.")
  try require(failures == 0, "handoff", "\(failures) cases failed; preserve evidence.")
}
