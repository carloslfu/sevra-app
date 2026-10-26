import Darwin
import Foundation
import SevraCore
import SevraSplash
import SevraSplashGrammar
import SevraSplashText

/// Opt-in synthetic vertical slice, using the same tool declarations and actual
/// workbook dispatcher. Explicitly named tools isolate the integration; this is
/// not yet the autonomous WorkbookAgent or an installed UI acceptance journey.
func runNativeWorkbookProbe(
  frontend: SplashTextFrontend, factory: SplashGrammarFactory,
  engine: String, assembly: String
) throws {
  let support = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
    "Library/Application Support/Sevra")
  try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
  let descriptor = Darwin.open(
    support.appendingPathComponent("inference.lock").path, O_CREAT | O_RDWR | O_NOFOLLOW, 0o600)
  guard descriptor >= 0 else { throw SplashError("Cannot open Sevra inference lock") }
  defer { Darwin.close(descriptor) }
  guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
    throw SplashError("Another Sevra process owns inference")
  }
  defer { flock(descriptor, LOCK_UN) }
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(
    "sevra-native-workbook-" + identifier())
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: root) }
  let path = root.appendingPathComponent("Suppliers.sevra")
  let workbook = try Workbook.create(at: path, title: "Synthetic suppliers")
  let instruction =
    "Create a table named Supplier quotes. Meaning actual. Exactly three columns: supplier (text), price (decimal), quantity (decimal). Exactly two rows: Oak Supply has price 2.40 and quantity 10; Cedar Tools has price 2.75 and quantity 10. Use decimal strings and these exact column IDs. Use an empty inputs array, because the host attaches this preserved user request as evidence. Do not include a formula or an extra column."
  let source = try workbook.addItem(
    category: "source", kind: "request", title: "Synthetic table request",
    text: instruction, meaning: "plan", status: "accepted")
  let tools = WorkbookTools(
    workbook, runID: "native-integration-fixture", requestSourceID: source.id)
  let declaration = try Data(
    contentsOf: Bundle.module.url(forResource: "workbook-tools", withExtension: "json")!)
  let helper = try SplashNativeProcess(
    executable: URL(fileURLWithPath: engine),
    arguments: [
      "serve-native", assembly, "8192", "12884901888", "--persistent-cache", "off", "--idle-sleep",
      "allow", "--verify-rows", "all",
    ], timeout: 180)
  defer { helper.close() }
  var acceptedID: String?
  for id: UInt64 in 1...4 {
    let named = (id == 2 || id == 3) ? "propose_table" : "calculate"
    let policy = try SplashToolPolicy(toolsJSON: declaration, choice: .named(named))
    let prompt = try frontend.prepare(
      messages: [
        [
          "role": "system",
          "content":
            "Call exactly the requested native tool. Preserve all supplied facts and decimal strings.",
        ],
        [
          "role": "user",
          "content": named == "propose_table"
            ? instruction
            : "Call calculate. Use expression cost * 2 and values {\"cost\":\"12.40\"}.",
        ],
      ], tools: policy.promptTools())
    let constraint = try factory.create(grammar: policy.grammar)
    let output = try SplashOutputStream(frontend: frontend, tools: policy.outputTools)
    var request = SplashWire.Request(
      id: id, prompt: prompt.tokens,
      absoluteDeadline: UInt64((Date().timeIntervalSince1970 + 180) * 1e6),
      remainingDeadline: 180_000_000)
    request.generationTokens = prompt.generationTokens
    request.maxOutput = 900
    request.tokenMask = true
    let generated = try helper.generate(
      request, cancelled: { id == 3 },
      mask: { committed, simulation, words in
        try constraint.masks(committed: committed, simulation: simulation, words: words)
      },
      event: { event in
        if case .tokens(_, _, let tokens) = event { _ = try output.append(tokens: tokens) }
      })
    try constraint.finish(committed: generated.tokens, requireComplete: id != 3)
    let response = try output.finish(generated.done.reason).0
    var result = Value.null
    if id == 3 {
      try expectEqual(generated.done.reason, .cancelled)
      try expectEqual(response.calls.count, 0)
      try expectEqual(try workbook.datasets().count, 1)
    } else {
      try expectEqual(generated.done.reason, .stop)
      let call = try expectValue(response.calls.first)
      try expectEqual(response.calls.count, 1)
      try policy.validate(call)
      let arguments = try Value.parse(String(decoding: call.arguments, as: UTF8.self))
      if id == 2 {
        try expectEqual(arguments["rows"].array.count, 2)
        try expectEqual(
          arguments["columns"].array.map { $0["id"].text }.sorted(),
          ["price", "quantity", "supplier"])
      }
      result = try tools.execute(call.name, arguments)
      if id == 2 {
        try expectEqual(result["status"].text, "draft")
        try expectEqual(try workbook.datasets().count, 0)
        // The fixture explicitly exercises the separate human acceptance path.
        let accepted = try workbook.accept(result["id"].text, token: "fixture-human-accept")
        let datasetID = accepted.data["datasetID"].text
        acceptedID = datasetID
        let rows = try workbook.rows(datasetID)
        try expectEqual(rows.count, 2)
        let values = Dictionary(
          uniqueKeysWithValues: rows.map { ($0.data["supplier"].text, $0.data) })
        try expectEqual(
          try Numbers.decimal(values["Oak Supply"]?["price"].text ?? ""),
          try Numbers.decimal("2.40"))
        try expectEqual(
          try Numbers.decimal(values["Cedar Tools"]?["price"].text ?? ""),
          try Numbers.decimal("2.75"))
        for row in rows {
          try expectEqual(try Numbers.decimal(row.data["quantity"].text), try Numbers.decimal("10"))
        }
        let reopened = try Workbook(path)
        try expectEqual(try reopened.rows(datasetID).map(\.data), rows.map(\.data))
        guard
          try workbook.lineage(accepted.id).contains(where: {
            $0["parent"].text == result["id"].text
          }),
          try workbook.lineage(result["id"].text).contains(where: { $0["parent"].text == source.id }
          )
        else {
          throw SplashError("Accepted table lost its lineage")
        }
      } else {
        try expectEqual(result["result"].text, "24.8")
      }
    }
    print(
      try Value.object([
        "request": .number(Double(id)), "tool": .string(named),
        "finish": .number(Double(generated.done.reason.rawValue)),
        "promptTokens": .number(Double(prompt.tokens.count)),
        "outputTokens": .number(Double(generated.tokens.count)),
        "seconds": .number(generated.requestSeconds),
        "toolCalls": .number(Double(response.calls.count)), "result": result,
      ]).json())
  }
  guard acceptedID != nil else { throw SplashError("Native workbook table was not accepted") }
  let status = try Value.parse(
    String(decoding: helper.status(id: 100, release: true), as: UTF8.self))
  try expectEqual(status["weights"]["released"], .bool(true))
  try expectEqual(status["metal"]["healthy"], .bool(true))
  try expectEqual(status["requests"]["completed"].int, 3)
  try expectEqual(status["requests"]["cancelled"].int, 1)
  try expectEqual(status["requests"]["failed"].int, 0)
  print(
    try Value.object([
      "completed": .bool(true), "requests": status["requests"],
      "weightsReleased": status["weights"]["released"], "metalHealthy": status["metal"]["healthy"],
      "datasetCount": .number(Double(try workbook.datasets().count)),
      "acceptedTableRows": .number(2),
      "reopen": .bool(true), "lineage": .bool(true), "engineMemoryActual": status["memory_actual"],
    ]).json())
}
