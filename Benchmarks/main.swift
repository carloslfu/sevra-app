import Darwin
import Foundation
import SevraCore

setbuf(stdout, nil)

struct Corpus {
  let book: Workbook
  let datasetID: String?
  let queries: [String]
  let expectedDocuments: Set<String>?
  let validate: (String, SearchPage) throws -> Bool
}

func rowCorpus(at url: URL, count: Int, pageSize: Int) throws -> Corpus {
  let book = try Workbook.create(at: url, title: "Synthetic stock")
  let origin = try book.addItem(category: "source", kind: "fixture", title: "Synthetic inventory")
  let table = try book.createDataset(
    title: "Stock",
    columns: [
      .init(id: "sku", title: "SKU"), .init(id: "part", title: "Part"),
      .init(id: "supplier", title: "Supplier"),
      .init(id: "quantity", title: "Quantity", type: "decimal"),
    ],
    rows: (0..<count).map { n in
      [
        "sku": .string("SKU\(n)Z"), "part": .string(n % 10 == 0 ? "brass bolt" : "steel washer"),
        "supplier": .string(n % 17 == 0 ? "Café Bogotá" : "Supplier \(n % 100)"),
        "quantity": .string(String(n % 200)),
      ]
    }, sourceID: origin.id)
  let last = "SKU\(count - 1)Z"
  let other = "SKU\(min(123, count - 1))Z"
  let exact = [
    last: try book.rows(table.id, offset: count - 1, limit: 1)[0].id,
    other: try book.rows(table.id, offset: min(123, count - 1), limit: 1)[0].id,
  ]
  return Corpus(
    book: book, datasetID: table.id,
    queries: [last, other, "brass bolt", "cafe bogota", "stock", "washer", "doesnotexist", "SK"],
    expectedDocuments: nil,
    validate: { query, page in
      if let id = exact[query] { return page.hits.map(\.itemID) == [id] && page.nextCursor == nil }
      if query == "doesnotexist" { return page.hits.isEmpty && page.nextCursor == nil }
      let expected: Int
      let property: String?
      let value: String?
      switch query {
      case "brass bolt":
        expected = (count + 9) / 10
        property = "part"
        value = "brass bolt"
      case "cafe bogota":
        expected = (count + 16) / 17
        property = "supplier"
        value = "Café Bogotá"
      case "washer":
        expected = count - (count + 9) / 10
        property = "part"
        value = "steel washer"
      default:
        expected = count
        property = nil
        value = nil
      }
      guard page.hits.count == min(pageSize, expected),
        (page.nextCursor != nil) == (expected > pageSize)
      else { return false }
      return try page.hits.allSatisfy { hit in
        let item = try book.item(hit.itemID)
        return item.kind == "row" && (property.map { item.data[$0].text == value } ?? true)
      }
    })
}

func documentCorpus(at url: URL, chunks: Int, pageSize: Int) throws -> Corpus {
  let documents = min(1000, chunks / 10)
  let perDocument = chunks / documents
  let book = try Workbook.create(at: url, title: "Synthetic documents")
  var ids: [String] = []
  for index in 0..<documents {
    let source = try book.addItem(
      category: "source", kind: "document", title: "invoice-\(index)-café.pdf")
    try book.index(
      source.id,
      chunks: (0..<perDocument).map { page in
        Chunk(
          "Invoice document SKU\(index)Z. Page \(page + 1). Brass bolts and steel washers. Supplier \(index % 100). Café Bogotá. \(String(repeating: "Delivery terms and purchase details. ", count: 8))",
          locator: "page=\(page + 1)")
      })
    ids.append(source.id)
  }
  let last = "SKU\(documents - 1)Z"
  let filename = "\(documents - 1)-caf"
  let expected = Set(ids)
  let lastID = ids.last!
  return Corpus(
    book: book, datasetID: nil,
    queries: [last, "invoice", "brass bolts", "cafe bogota", filename, "missingunrelated"],
    expectedDocuments: expected,
    validate: { query, page in
      if query == "missingunrelated" { return page.hits.isEmpty && page.nextCursor == nil }
      if query == last || query == filename {
        return page.hits.map(\.itemID) == [lastID] && page.nextCursor == nil
      }
      return page.hits.count == min(pageSize, documents)
        && (page.nextCursor != nil) == (documents > pageSize)
        && page.hits.allSatisfy { expected.contains($0.itemID) && $0.locator.contains("page=") }
    })
}

func runBenchmark() throws -> Bool {
  let arguments = Set(CommandLine.arguments.dropFirst())
  if arguments.contains("--help") {
    print("sevra-benchmark [--self-check] [--rows-only | --documents-only]")
    return true
  }
  try require(
    arguments.isSubset(of: ["--self-check", "--rows-only", "--documents-only"])
      && !(arguments.contains("--rows-only") && arguments.contains("--documents-only")),
    "usage", "Use --help for supported benchmark options.")
  let selfCheck = arguments.contains("--self-check")
  let counts = selfCheck ? [200] : [10_000, 100_000]
  let repetitions = selfCheck ? 2 : 5
  let pageSize = selfCheck ? 7 : 30
  let kinds =
    arguments.contains("--rows-only")
    ? ["rows"]
    : arguments.contains("--documents-only") ? ["documents"] : ["rows", "documents"]
  let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent(".build/search-scale-" + identifier())
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  var identity = try benchmarkIdentity().object
  identity["selfCheck"] = .bool(selfCheck)
  identity["counts"] = .array(counts.map { .number(Double($0)) })
  identity["warmRepetitions"] = .number(Double(repetitions))
  identity["pageSize"] = .number(Double(pageSize))
  identity["warmP95TargetMilliseconds"] = .number(200)
  try Data(Value.object(identity).json().utf8).write(
    to: root.appendingPathComponent("identity.json"))
  print("Evidence directory: .build/" + root.lastPathComponent)
  var reports: [Value] = []
  var allPassed = true
  for kind in kinds {
    for count in counts {
      var report: [String: Value] = [
        "corpus": .string(kind), "entries": .number(Double(count)),
        "entriesMeaning": .string(kind == "rows" ? "dataset rows" : "indexed document chunks"),
        "selfCheck": .bool(selfCheck), "performanceQualification": .bool(false),
      ]
      do {
        let (corpus, ingest) = try elapsed {
          try FixtureContext.$current.withValue(
            FixtureContext(seed: UInt32(count + (kind == "rows" ? 0 : 1)))
          ) {
            let path = root.appendingPathComponent("\(kind)-\(count).sevra")
            return kind == "rows"
              ? try rowCorpus(at: path, count: count, pageSize: pageSize)
              : try documentCorpus(at: path, chunks: count, pageSize: pageSize)
          }
        }
        report["ingestMilliseconds"] = .number(ingest)
        report["databaseBytes"] = .number(
          Double(
            try corpus.book.url.appendingPathComponent("workbook.sqlite")
              .resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0))
        let reopened = try Workbook(corpus.book.url)
        let samples = try sampleSearches(
          reopened, queries: corpus.queries, repetitions: repetitions, pageSize: pageSize,
          validate: corpus.validate)
        report["samples"] = .array(samples.samples)
        let firstPass = samples.samples.filter { $0["phase"].text == "first-pass" }
          .compactMap { Double($0["milliseconds"].text) }
        report["firstPassP50ms"] = percentile(firstPass, 0.5)
        report["firstPassP95ms"] = percentile(firstPass, 0.95)
        report["warmP50ms"] = percentile(samples.warm, 0.5)
        report["warmP95ms"] = percentile(samples.warm, 0.95)
        report["semanticFailures"] = .array(samples.failures.map(Value.string))
        if let dataset = corpus.datasetID {
          let (rows, milliseconds) = try elapsed {
            try reopened.rows(dataset, limit: 200, sort: "quantity", descending: true)
          }
          try require(
            rows.first?.data["quantity"].text == String(min(count - 1, 199)),
            "benchmark_sort", "Numeric sort did not return the maximum fixture quantity.")
          report["numericSortMilliseconds"] = .number(milliseconds)
        }
        if let expected = corpus.expectedDocuments {
          report["documents"] = .number(Double(expected.count))
          report["paging"] = try verifyPaging(
            reopened, query: "invoice", expected: expected, pageSize: pageSize)
        }
        let cancellation = try cancellationProbe(
          reopened, query: kind == "rows" ? "stock" : "invoice")
        report["cancellation"] = cancellation
        let cancelled = cancellation["interruptionObserved"] == .bool(true)
        let promptStop = (Double(cancellation["stopToReturnMilliseconds"].text) ?? .infinity) < 1000
        let cancellationRequired = !selfCheck && count == 100_000
        let cancellationPassed = !cancellationRequired || (cancelled && promptStop)
        let latencyPassed = (Double(report["warmP95ms"]!.text) ?? .infinity) < 200
        let passed =
          samples.failures.isEmpty && cancellationPassed
          && (selfCheck || count != 100_000 || latencyPassed)
        report["warmP95TargetMet"] = .bool(latencyPassed)
        report["cancellationRequired"] = .bool(cancellationRequired)
        report["cancellationTargetMet"] = cancellationRequired ? .bool(cancellationPassed) : .null
        report["correctnessPassed"] = .bool(samples.failures.isEmpty)
        report["protocolChecksPassed"] = .bool(passed)
        allPassed = allPassed && passed
      } catch {
        report["error"] = .string(error.localizedDescription)
        report["protocolChecksPassed"] = .bool(false)
        allPassed = false
      }
      let value = Value.object(report)
      reports.append(value)
      try Data(value.json().utf8).write(
        to: root.appendingPathComponent("\(kind)-\(count).json"), options: .atomic)
      print(
        try Value.object([
          "corpus": .string(kind), "entries": .number(Double(count)),
          "passed": report["protocolChecksPassed"]!, "warmP95ms": report["warmP95ms"] ?? .null,
          "error": report["error"] ?? .null,
        ]).json())
    }
  }
  let after = try benchmarkIdentity()
  let unchanged =
    after["sourceSHA256"] == identity["sourceSHA256"]
    && after["binarySHA256"] == identity["binarySHA256"]
  allPassed = allPassed && unchanged
  let final: Value = .object([
    "identity": .object(identity), "reports": .array(reports),
    "identityAfter": after, "sourcesAndBinaryUnchanged": .bool(unchanged),
    "protocolChecksPassed": .bool(allPassed), "performanceQualification": .bool(false),
    "qualificationLimit": .string(
      "A passing self-check is only a small-fixture regression. Full results need reference-hardware, power/thermal and no-overlap review before qualification."
    ),
  ])
  try Data(final.json().utf8).write(
    to: root.appendingPathComponent("result.json"), options: .atomic)
  return allPassed
}

do {
  exit(try runBenchmark() ? 0 : 1)
} catch {
  fputs("Search benchmark failed: \(error.localizedDescription)\n", stderr)
  exit(1)
}
