import Darwin
import Foundation
import SevraAI
import SevraCore
import SevraNativeAI

func emit(_ value: Value) throws {
  try FileHandle.standardOutput.write(contentsOf: Data((try value.json() + "\n").utf8))
}
func clockNow() -> Double { ProcessInfo.processInfo.systemUptime }

actor ObservedModel: WorkbookInference {
  let underlying: any WorkbookInference
  let observations: Observations
  let identity: String
  private(set) var lastMetrics: Value = .null
  private var calls = 0
  private var responses: [Value] = []
  init(_ model: any WorkbookInference, observations: Observations) async {
    identity = await model.identity
    underlying = model
    self.observations = observations
  }
  func beginRun() async throws { try await underlying.beginRun() }
  func endRun() async { await underlying.endRun() }
  func releaseResources() async -> Bool { await underlying.releaseResources() }
  func reset() {
    calls = 0
    responses = []
    observations.reset()
  }
  func trace() -> Value {
    .object(["requests": .array(observations.snapshot()), "responses": .array(responses)])
  }
  func respond(
    messages: [InferenceMessage], directory: URL, cancellation: Cancellation,
    progress: @escaping @Sendable (String) -> Void, toolScope: InferenceToolScope,
    citationIDs: [String]
  ) async throws -> NativeReply {
    let start = clockNow()
    let reply = try await underlying.respond(
      messages: messages, directory: directory,
      cancellation: cancellation, progress: progress, toolScope: toolScope, citationIDs: citationIDs
    )
    lastMetrics = await underlying.lastMetrics
    calls += 1
    let normalized = reply.calls.enumerated().map { index, call in
      InferenceCall(
        id: "call_fixture_\(calls)_\(index)", name: call.name, inputJSON: call.inputJSON)
    }
    responses.append(
      .object([
        "wallSeconds": .number(clockNow() - start), "scope": .string(toolScope.rawValue),
        "text": .string(reply.text), "reasoning": .string(reply.reasoning),
        "calls": .array(
          try normalized.map {
            .object([
              "id": .string($0.id), "name": .string($0.name),
              "arguments": try Value.parse($0.inputJSON),
            ])
          }),
      ]))
    return NativeReply(text: reply.text, calls: normalized, reasoning: reply.reasoning)
  }
}

let prompts = [
  "supplier_space":
    "Compare the supplier quotes. Which supplier is cheaper, by how much and by what percentage? Create a Purchasing space with a table and a cost chart. Cite the supporting rows.",
  "formula_review":
    "Create a planning table named Workshop plan with one row: item Washers, quantity 3, unit_cost 2.50, and a total formula quantity*unit_cost. Leave it as a proposal for my review.",
  "inventory_evidence":
    "What is the current stock of brass bolts? Use the balance tool and cite the evidence. Do not change the workbook.",
  "missing_evidence":
    "Find the signed Lakehouse contract and its renewal price. If the evidence is missing or cannot be searched, say so clearly and do not guess.",
  "prime": "Reply with the word Ready. Do not change the workbook.",
]

func performJob(
  _ name: String, seed: UInt32, model: ObservedModel, directory: URL, root: URL,
  promptOverride: String? = nil
)
  async throws -> Value
{
  try await FixtureContext.$current.withValue(FixtureContext(seed: seed)) {
    let path = root.appendingPathComponent("Job.sevra")
    if FileManager.default.fileExists(atPath: path.path) {
      try FileManager.default.removeItem(at: path)
    }
    _ = try Demo.create(at: path)
    let book = try Workbook(path)
    if name == "missing_evidence" {
      let source = try book.addItem(
        category: "source", kind: "document", title: "Unsearchable attachment", text: "")
      try book.index(
        source.id, chunks: [], state: "unsupported", detail: "Synthetic unsupported file fixture")
    }
    let original = try book.items()
    let originalIDs = Set(original.map(\.id))
    let originalSpaces = try book.spaces()
    let startingState = try encoded(original)
    let prompt = promptOverride ?? prompts[name]!
    let originalBalance =
      name == "inventory_evidence" ? try book.balance(subject: "brass bolts") : .null
    await model.reset()
    let began = clockNow()
    var result: AgentResult?
    var error: String?
    var review: Value = .null
    do {
      result = try await WorkbookAgent.run(
        prompt, workbook: book, modelDirectory: directory,
        cancellation: Cancellation(deadlineAfterSeconds: 600), model: model, enableCompaction: false
      )
      if name == "formula_review" {
        let proposal = try book.items(kind: "table-creation").first {
          $0.status == "draft" && $0.data["title"].text == "Workshop plan"
        }
        guard let proposal else { throw SevraError("workflow", "Missing requested table proposal") }
        try reviewProposal(proposal, in: book, receipt: &review)
      }
    } catch let failure { error = failure.localizedDescription }
    let elapsed = clockNow() - began
    var errors = error.map { [$0] } ?? []
    func check(_ condition: Bool, _ text: String) { if !condition { errors.append(text) } }
    let trace = await model.trace()
    let items = try book.items()
    let spaces = try book.spaces()
    check(
      items.filter { originalIDs.contains($0.id) } == original, "Original business items changed")
    check(try book.verify()["ok"] == .bool(true), "Workbook integrity failed")
    if let result {
      switch name {
      case "prime":
        check(
          result.answer == "Ready" && result.state == "complete", "Priming did not answer Ready")
      case "inventory_evidence":
        let required = Set(
          [originalBalance["basis"].text]
            + originalBalance["effects"].array.map { $0["item_id"].text })
        check(
          result.state == "complete" && result.answer.contains("18")
            && Set(result.citations).isSuperset(of: required),
          "Stock answer or evidence is incomplete")
      case "supplier_space":
        check(
          result.state == "complete" && result.answer.contains("Oak")
            && result.answer.contains("3.5") && result.answer.contains("12.73")
            && result.citations.count >= 2, "Comparison omitted its requested result/evidence")
        check(!result.answer.contains { "$€£".contains($0) }, "Comparison invented a currency")
        let composed = spaces.first { $0.title.lowercased() == "purchasing" }
        check(
          composed.map {
            Set($0.definition.components.map(\.type)).isSuperset(of: ["table", "chart"])
          } ?? false, "Requested table/chart space missing")
      case "formula_review":
        check(result.state == "needs_review", "Proposal was not left for review")
        check(
          review["before"]["rows"].array.first?["values"]["total"].text == "7.5",
          "Accepted formula has wrong value")
        check(
          review["after"]["rows"].array.first?["values"]["total"].text == "10",
          "Formula did not recalculate")
        check(
          review["restored"]["rows"].array.first?["values"]["total"].text == "7.5",
          "Undo did not restore formula result")
        check(
          review["before"]["dataset"]["columns"].array.contains {
            $0["id"].text == "total"
              && $0["formula"].text.replacingOccurrences(of: " ", with: "") == "quantity*unit_cost"
          }, "Formula was replaced with a stored number")
      case "missing_evidence":
        check(
          result.answer.contains("These searches do not establish")
            && result.answer.contains("incomplete") && result.citations.isEmpty,
          "Missing-evidence answer overclaimed or lost indexing limits")
      default: errors.append("Unknown workflow")
      }
    }
    let newItems = items.filter { !originalIDs.contains($0.id) }
    if name == "inventory_evidence" {
      check(try book.balance(subject: "brass bolts") == originalBalance, "Stock balance changed")
    }
    check(
      newItems.filter { $0.category == "source" && $0.kind == "request" }.count == 1,
      "Expected exactly one preserved user request")
    if name != "formula_review" {
      check(newItems.count == 1, "Unrequested business items were created")
    }
    if name != "supplier_space" {
      check(try encoded(spaces) == encoded(originalSpaces), "Unrequested space change")
    }
    for request in trace["requests"].array {
      check(request["promptTokens"].array.count <= 24000, "Workflow exceeded declared prompt bound")
      check(request["metrics"]["outputBudget"].int == 1800, "Workflow changed output budget")
    }
    let messages = try book.messages(limit: 500)
    let validationFailures = messages.filter { message in
      guard message.role == "tool", let receipt = try? Value.parse(message.body) else {
        return false
      }
      return !receipt["validation"].text.isEmpty
    }.count
    return .object([
      "id": .string(name), "seed": .number(Double(seed)), "completeSeconds": .number(elapsed),
      "prompt": .string(prompt),
      "errors": .array(errors.map(Value.string)), "startingItems": startingState,
      "answer": result.map { .string($0.answer) } ?? .null,
      "state": result.map { .string($0.state) } ?? .null,
      "steps": result.map { .number(Double($0.steps)) } ?? .null,
      "citations": .array(result?.citations.map(Value.string) ?? []), "review": review,
      "validationFailures": .number(Double(validationFailures)), "trace": trace,
      "runs": .array(try book.agentRuns()), "messages": try encoded(messages),
      "finalItems": try encoded(items), "finalSpaces": try encoded(spaces),
    ])
  }
}

func reviewProposal(_ proposal: Item, in book: Workbook, receipt: inout Value) throws {
  var proof: [String: Value] = ["proposal": try encoded(proposal)]
  defer { receipt = .object(proof) }
  try require(
    try !book.datasets().contains { $0.title == "Workshop plan" }, "workflow",
    "Table existed before human acceptance")
  let accepted = try book.accept(proposal.id)
  proof["accepted"] = try encoded(accepted)
  let tableID = accepted.data["datasetID"].text
  let tools = WorkbookTools(book)
  proof["before"] = try tools.execute("rows", .object(["datasetID": .string(tableID)]))
  let row = try book.rows(tableID)[0]
  var values = row.data.object
  values["quantity"] = .string("4")
  let change = try book.editRows(tableID, edits: [.init(id: row.id, values: values)])
  proof["changeID"] = .string(change.id)
  proof["after"] = try tools.execute("rows", .object(["datasetID": .string(tableID)]))
  _ = try book.undoTableChange(change.id)
  proof["restored"] = try tools.execute("rows", .object(["datasetID": .string(tableID)]))
}

func selfCheck() async throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(
    "sevra-workflow-fixture-" + identifier())
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: root) }
  @Sendable func fixture(_ directory: String, seed: UInt32) async throws -> Value {
    try await FixtureContext.$current.withValue(
      FixtureContext(seed: seed, date: "2001-01-01T00:00:00Z")
    ) {
      let path = root.appendingPathComponent(directory)
      _ = try Demo.create(at: path)
      let inherited = await Task { timestamp() }.value
      let detached = await Task.detached { FixtureContext.current == nil }.value
      try require(
        inherited == "2001-01-01T00:00:00Z" && detached, "fixture",
        "Task inheritance or detached isolation changed")
      let book = try Workbook(path)
      return .object([
        "items": try encoded(book.items()), "spaces": try encoded(book.spaces()),
        "messages": try encoded(book.messages()), "nextID": .string(identifier()),
        "date": .string(timestamp()),
      ])
    }
  }
  let first = try await fixture("first.sevra", seed: 1)
  let second = try await fixture("second.sevra", seed: 1)
  try require(first == second, "fixture", "Identical fixtures diverged")
  async let a = fixture("a.sevra", seed: 2)
  async let b = fixture("b.sevra", seed: 3)
  let paired = try await (a, b)
  let expectedA = try await fixture("expected-a.sevra", seed: 2)
  let expectedB = try await fixture("expected-b.sevra", seed: 3)
  try require(
    paired.0 == expectedA && paired.1 == expectedB && paired.0 != paired.1,
    "fixture", "Concurrent fixture contexts leaked")
  let book = try Workbook(root.appendingPathComponent("first.sevra"))
  let evidence = try book.addItem(
    category: "source", kind: "request", title: "Plan request",
    text: prompts["formula_review"]!)
  let proposal = try book.proposeTable(
    title: "Workshop plan",
    columns: [
      .init(id: "item", title: "Item"), .init(id: "quantity", title: "Quantity", type: "decimal"),
      .init(id: "unit_cost", title: "Unit cost", type: "decimal"),
      .init(id: "total", title: "Total", type: "decimal", formula: "quantity*unit_cost"),
    ],
    rows: [["item": .string("Washers"), "quantity": .string("3"), "unit_cost": .string("2.50")]],
    inputs: [evidence.id])
  var review: Value = .null
  try reviewProposal(proposal, in: book, receipt: &review)
  for (stage, value) in [("before", "7.5"), ("after", "10"), ("restored", "7.5")] {
    try require(
      review[stage]["rows"].array.first?["values"]["total"].text == value,
      "fixture", "Scripted human review did not preserve formula behavior at " + stage)
  }
  try require(try book.verify()["ok"] == .bool(true), "fixture", "Review damaged workbook")
  try require(
    FixtureContext.current == nil && timestamp() != "2001-01-01T00:00:00Z"
      && identifier() != identifier(), "fixture", "Fixture changed ordinary identity or time")
  let masks = Observations()
  masks.appendMask([1], [2], 2, [1, 0, 3, 0])
  masks.append(.object([:]))
  let trace = masks.snapshot()[0]["maskTrace"].array
  try require(
    trace.count == 2 && trace[0]["tokenCount"].int == 1 && trace[1]["tokenCount"].int == 2,
    "fixture", "Mask trace lost prefix position")
  try require(
    trace[0]["prefixSHA256"].text
      == "67abdd721024f0ff4e0b3f4c2fc13bc5bad42d0b7851d456d88d203d15aaa450"
      && trace[1]["prefixSHA256"].text
        == "34fb5c825de7ca4aea6e712f19d439c1da0c92c37b423936c5f618545ca4fa1f",
    "fixture", "Mask prefix digest differs from little-endian Python golden")
  masks.reset()
  masks.append(.object([:]))
  try require(
    masks.snapshot()[0]["maskTrace"] == .null, "fixture", "Mask trace leaked between jobs")
  print(
    "PASS deterministic fixture state, task inheritance, concurrent isolation, unchanged defaults and actual formula acceptance/edit/undo"
  )
}

@main struct WorkflowPerformance {
  static func main() async {
    var activeModel: ObservedModel?
    do {
      if CommandLine.arguments == [CommandLine.arguments[0], "--self-check"] {
        try await selfCheck()
        return
      }
      try require(
        CommandLine.arguments.count == 3, "usage",
        "sevra-workflow-performance CONFIG.json native|reference")
      let config = try Value.parse(String(contentsOfFile: CommandLine.arguments[1]))
      let backend = CommandLine.arguments[2]
      let observations = Observations()
      let underlying: any WorkbookInference
      if backend == "native" {
        let maskObserver: (@Sendable ([UInt32], [UInt32], UInt32, [UInt32]) -> Void)?
        if config["diagnosticMasks"] == .bool(true) {
          maskObserver = { committed, simulation, words, masks in
            observations.appendMask(committed, simulation, words, masks)
          }
        } else {
          maskObserver = nil
        }
        underlying = NativeWorkbookModel(
          configuration: .init(
            engine: URL(fileURLWithPath: config["engine"].text),
            engineFiles: config["engineFiles"].object.mapValues(\.text),
            grammarLibrary: URL(fileURLWithPath: config["grammarLibrary"].text),
            grammarSHA256: config["grammarSHA256"].text,
            modelsRoot: URL(fileURLWithPath: config["modelsRoot"].text),
            memoryBytes: 12_884_901_888,
            contextBudget: .init(profile: .evaluation32K), reasoning: .bounded512,
            modelLayout: .installed, contextMaintenanceEnabled: false,
            observeRequest: { observations.append($0) },
            observeMask: maskObserver))
      } else {
        try require(backend == "reference", "usage", "Unknown qualification frontend")
        underlying = ReferenceModel(config: config, observations: observations)
      }
      let model = await ObservedModel(underlying, observations: observations)
      activeModel = model
      let directory = URL(fileURLWithPath: config["modelsRoot"].text)
      let root = FileManager.default.temporaryDirectory.appendingPathComponent(
        "sevra-workflow-worker-" + UUID().uuidString)
      try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
      defer { try? FileManager.default.removeItem(at: root) }
      let began = clockNow()
      let prime = try await performJob(
        "prime", seed: 0, model: model, directory: directory, root: root)
      try emit(
        .object([
          "ready": .bool(prime["errors"].array.isEmpty), "pid": .number(Double(getpid())),
          "startupSeconds": .number(clockNow() - began), "prime": prime,
        ]))
      if !prime["errors"].array.isEmpty {
        _ = await model.releaseResources()
        exit(1)
      }
      while let line = readLine() {
        let command = try Value.parse(line)
        if command["op"].text == "close" {
          try emit(.object(["closed": .bool(await model.releaseResources())]))
          return
        }
        let name = command["id"].text
        try require(prompts[name] != nil && name != "prime", "workflow", "Unknown workload")
        guard let seed = command["seed"].int, let unsignedSeed = UInt32(exactly: seed) else {
          throw SevraError("workflow", "Missing or invalid fixture seed")
        }
        var promptOverride: String?
        if name == "inventory_evidence", config["inventoryPrompts"] != .null {
          let choices = config["inventoryPrompts"].array
          try require(
            seed > 0 && seed <= choices.count && choices.allSatisfy { $0.string != nil },
            "workflow", "Invalid preregistered inventory prompt schedule")
          promptOverride = choices[seed - 1].text
        }
        let row = try await performJob(
          name, seed: unsignedSeed, model: model, directory: directory, root: root,
          promptOverride: promptOverride)
        try emit(row)
      }
      _ = await model.releaseResources()
    } catch {
      let closed = await activeModel?.releaseResources() ?? true
      try? emit(.object(["error": .string(error.localizedDescription), "closed": .bool(closed)]))
      exit(1)
    }
  }
}
