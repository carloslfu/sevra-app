import Darwin
import Foundation
import SevraCore

/// Synthetic catalog qualification through the public core APIs. This is not a
/// bulk-write product interface or a claim about all workbook execution.
func runDefinitionBenchmark() throws -> Bool {
  let args = Array(CommandLine.arguments.dropFirst())
  try require(
    args.count == 5 && args[0] == "--definitions" && args[1] == "--count"
      && args[3] == "--output", "arguments",
    "sevra-benchmark --definitions --count 1000 --output NEW_DIRECTORY")
  guard let count = Int(args[2]), (10...10_000).contains(count) else {
    throw SevraError("arguments", "Use 10 to 10,000 synthetic definitions.")
  }
  let root = URL(fileURLWithPath: args[4]).standardizedFileURL
  try require(
    !FileManager.default.fileExists(atPath: root.path), "exists",
    "Use a new qualification directory.")
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  let book = try Workbook.create(
    at: root.appendingPathComponent("Catalog.sevra"), title: "Synthetic definition qualification")
  func now() -> Double { ProcessInfo.processInfo.systemUptime }
  func function(_ n: Int, target: ApplicationDefinition? = nil) -> Value {
    let calls: [Value] =
      target.map { target in
        [
          .object([
            "alias": .string("base"),
            "binding": .object(["mode": .string("live"), "logicalID": .string(target.logicalID)]),
            "arguments": .object(["x": .object(["parameter": .string("x")])]),
          ])
        ]
      } ?? []
    return .object([
      "kind": .string("function"), "title": .string("Synthetic definition \(n)"),
      "description": .string(
        n % 10 == 0 ? "Citrus reusable calculation" : "Ordinary reusable calculation"),
      "parameters": .array([
        .object([
          "id": .string("x"), "label": .string("Quantity"), "type": .string("decimal"),
          "required": .bool(true),
        ])
      ]),
      "payload": .object([
        "expression": .string((target == nil ? "x" : "base") + "+\(max(n, 0))"),
        "calls": .array(calls),
      ]),
    ])
  }
  let start = now()
  let common = try book.saveApplicationDefinition(logicalID: identifier(), content: function(-1))
  var last: ApplicationDefinition = common
  var creationChunks: [Value] = []
  var chunkStart = now()
  for n in 0..<count {
    last = try book.saveApplicationDefinition(
      logicalID: identifier(), content: function(n, target: n % 2 == 1 ? common : nil))
    if (n + 1) % 1000 == 0 {
      creationChunks.append(
        .object(["through": .number(Double(n + 1)), "seconds": .number(now() - chunkStart)]))
      fputs("Created \(n + 1) definitions\n", stderr)
      chunkStart = now()
    }
  }
  let creationSeconds = now() - start
  let beforeEvaluation = try book.revision()
  let evaluated = try book.evaluateApplicationDefinition(
    last.logicalID, arguments: .object(["x": .string("2.10")]))
  try require(
    evaluated["result"] == .string(try Numbers.calculate("2.10+\(count - 1)"))
      && evaluated["resolvedDefinitions"].array.count == 2,
    "qualification", "Function evaluation or resolved bindings differ.")
  try require(
    try book.revision() == beforeEvaluation, "qualification",
    "Read-only evaluation changed business state.")
  func pageAll(_ query: String, expected: Int) throws -> Value {
    var cursor: String?
    var found: Set<String> = []
    var times: [Double] = []
    repeat {
      let begin = now()
      let page = try book.searchApplicationDefinitions(query, limit: 50, cursor: cursor)
      times.append(now() - begin)
      for hit in page["hits"].array {
        try require(
          found.insert(hit["id"].text).inserted, "qualification",
          "Discovery repeated an exact version.")
      }
      cursor = page["nextCursor"].string
    } while cursor != nil
    try require(found.count == expected, "qualification", "Discovery omitted or added definitions.")
    let sorted = times.sorted()
    return .object([
      "hits": .number(Double(found.count)), "pages": .number(Double(times.count)),
      "medianSeconds": .number(sorted[sorted.count / 2]), "maximumSeconds": .number(sorted.last!),
    ])
  }
  let search = try pageAll("Citrus", expected: (count + 9) / 10)
  let parameterSearch = try pageAll("Quantity", expected: count + 1)
  let listing = try pageAll("", expected: count + 1)
  let dependencyStart = now()
  let dependencies = try book.applicationDefinitionDependencies(last.id)
  let dependencySeconds = now() - dependencyStart
  try require(
    dependencies.count == 1 && dependencies[0]["target_version"] == .string(common.id),
    "qualification", "Dependency lookup lost its saved binding.")
  let verifyStart = now()
  _ = try book.verify()
  let verifySeconds = now() - verifyStart
  let reconstructStart = now()
  let reconstructed = try book.reconstruct(to: root.appendingPathComponent("Reconstructed.sevra"))
  let reconstructionSeconds = now() - reconstructStart
  try require(
    try reconstructed.evaluateApplicationDefinition(
      last.id, arguments: .object(["x": .string("2.10")])) == evaluated,
    "qualification", "Inert reconstruction changed evaluation or its snapshot.")
  try require(
    try reconstructed.applicationDefinitionDependencies(last.id) == dependencies, "qualification",
    "Inert reconstruction changed dependencies.")
  try require(
    try reconstructed.searchApplicationDefinitions("Citrus")["hits"].array.count
      == min(20, (count + 9) / 10), "qualification", "Inert FTS rebuild lost discoveries.")
  let archive = root.appendingPathComponent("Portable.sevraz")
  try book.export(to: archive)
  let portable = try Workbook.openArchive(
    archive, at: root.appendingPathComponent("Portable.sevra"))
  try require(
    try portable.applicationDefinition(last.id).id == last.id, "qualification",
    "Portable package lost definition identity.")
  _ = try portable.verify()
  var usage = rusage()
  getrusage(RUSAGE_SELF, &usage)
  let report: Value = .object([
    "ok": .bool(true), "definitions": .number(Double(count + 1)),
    "createdCount": .number(Double(count)),
    "creationSeconds": .number(creationSeconds), "creationChunks": .array(creationChunks),
    "search": search, "parameterSearch": parameterSearch, "listing": listing,
    "dependencySeconds": .number(dependencySeconds), "verifySeconds": .number(verifySeconds),
    "reconstructionSeconds": .number(reconstructionSeconds),
    "peakResidentBytes": .string(String(usage.ru_maxrss)),
    "physicalMemoryBytes": .string(String(ProcessInfo.processInfo.physicalMemory)),
    "processorCount": .number(Double(ProcessInfo.processInfo.processorCount)),
    "lastDefinitionID": .string(last.id), "lastLogicalID": .string(last.logicalID),
    "exactDependencies": .array(dependencies), "evaluation": evaluated,
    "inertReconstruction": .bool(true), "portableReopen": .bool(true),
    "scope": .string(
      "synthetic public core catalog/function/FTS qualification on one Mac; no native form or local-model authoring proof"
    ),
  ])
  let json = try report.json()
  try Data(json.utf8).write(to: root.appendingPathComponent("result.json"), options: .atomic)
  print(json)
  return true
}
