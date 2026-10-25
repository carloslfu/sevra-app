import Darwin
import Foundation
import SevraCore

setbuf(stdout, nil)
let base = FileManager.default.temporaryDirectory.appendingPathComponent(
  "sevra-benchmark-" + identifier())
try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: base) }
func elapsed<T>(_ body: () throws -> T) rethrows -> (T, Double) {
  let start = CFAbsoluteTimeGetCurrent()
  let value = try body()
  return (value, (CFAbsoluteTimeGetCurrent() - start) * 1000)
}
func percentile(_ list: [Double], _ p: Double) -> Double {
  let ordered = list.sorted()
  return ordered[min(ordered.count - 1, Int(Double(ordered.count - 1) * p))]
}
var reports: [Value] = []
for count in [10_000, 100_000] {
  let book = try Workbook.create(
    at: base.appendingPathComponent("\(count).sevra"), title: "Synthetic stock")
  let origin = try book.addItem(category: "source", kind: "fixture", title: "Synthetic inventory")
  let (table, ingest) = try elapsed {
    try book.createDataset(
      title: "Stock",
      columns: [
        .init(id: "sku", title: "SKU"), .init(id: "part", title: "Part"),
        .init(id: "supplier", title: "Supplier"),
        .init(id: "quantity", title: "Quantity", type: "decimal"),
      ],
      rows: (0..<count).map { n in
        [
          "sku": .string("SKU\(n)Z"), "part": .string(n % 10 == 0 ? "brass bolt" : "steel washer"),
          "supplier": .string(n % 17 == 0 ? "Café Bogotá" : "Supplier \(n%100)"),
          "quantity": .string(String(n % 200)),
        ]
      }, sourceID: origin.id)
  }
  let queries = [
    "SKU\(count-1)Z", "SKU123Z", "brass bolt", "cafe bogota", "supplier 42", "stock", "washer",
    "doesnotexist", "SK", "123Z",
  ]
  let reopened = try Workbook(book.url)
  var cold: [Double] = []
  var warm: [Double] = []
  var recall = true
  for q in queries {
    let (page, time) = try elapsed { try reopened.search(q) }
    cold.append(time)
    if q.hasPrefix("SKU") { recall = recall && !page.hits.isEmpty }
  }
  for _ in 0..<5 {
    for q in queries {
      let (_, time) = try elapsed { try reopened.search(q) }
      warm.append(time)
    }
  }
  let (_, sort) = try elapsed {
    try reopened.rows(table.id, limit: 200, sort: "quantity", descending: true)
  }
  let bytes =
    try book.url.appendingPathComponent("workbook.sqlite").resourceValues(forKeys: [.fileSizeKey])
    .fileSize ?? 0
  let report: Value = .object([
    "rows": .number(Double(count)), "databaseBytes": .number(Double(bytes)),
    "ingestMilliseconds": .number(ingest), "newConnectionP50ms": .number(percentile(cold, 0.5)),
    "newConnectionP95ms": .number(percentile(cold, 0.95)),
    "warmP50ms": .number(percentile(warm, 0.5)), "warmP95ms": .number(percentile(warm, 0.95)),
    "numericSortMilliseconds": .number(sort), "exactIdentifierRecall": .bool(recall),
    "queries": .array(queries.map(Value.string)),
    "firstPassMilliseconds": .array(cold.map(Value.number)),
  ])
  reports.append(report)
  print(try report.json())
}

// A document corpus exercises best-passage deduplication, not only table rows.
if ProcessInfo.processInfo.environment["SEVRA_BENCH_DOCUMENTS"] == "1" {
  for count in [10_000, 100_000] {
    let documents = 1000
    let perDocument = count / 1000
    let book = try Workbook.create(
      at: base.appendingPathComponent("documents-\(count).sevra"), title: "Synthetic documents")
    let (_, ingest) = try elapsed {
      for n in 0..<documents {
        let source = try book.addItem(
          category: "source", kind: "document", title: "invoice-\(n)-café.pdf")
        try book.index(
          source.id,
          chunks: (0..<perDocument).map { page in
            Chunk(
              "Invoice document SKU\(n)Z. Page \(page+1). Brass bolts and steel washers. Supplier \(n%100). Café Bogotá. \(String(repeating: "Delivery terms and purchase details. ", count: 8))",
              locator: "page=\(page+1)")
          })
      }
    }
    let queries = [
      "SKU999Z", "invoice", "brass bolts", "cafe bogota", "supplier 42", "999-caf",
      "missingunrelated",
    ]
    var times: [Double] = []
    var recall = true
    for _ in 0..<5 {
      for query in queries {
        let (result, time) = try elapsed { try book.search(query) }
        times.append(time)
        if query == "SKU999Z" { recall = recall && result.hits.count == 1 }
        if query == "invoice" {
          recall = recall && Set(result.hits.map(\.itemID)).count == result.hits.count
        }
      }
    }
    print(
      try Value.object([
        "corpus": .string("documents"), "chunks": .number(Double(count)),
        "documents": .number(Double(documents)), "ingestMilliseconds": .number(ingest),
        "warmP50ms": .number(percentile(times, 0.5)), "warmP95ms": .number(percentile(times, 0.95)),
        "recallAndDeduplication": .bool(recall),
      ]).json())
  }
}
