import Darwin
import Foundation
import SevraCore

func elapsed<T>(_ body: () throws -> T) rethrows -> (T, Double) {
  let start = ProcessInfo.processInfo.systemUptime
  return (try body(), (ProcessInfo.processInfo.systemUptime - start) * 1000)
}

func percentile(_ values: [Double], _ fraction: Double) -> Value {
  guard !values.isEmpty else { return .null }
  let sorted = values.sorted()
  // Nearest rank, retained explicitly with the raw observations.
  let rank = max(1, Int(ceil(Double(sorted.count) * fraction)))
  return .number(sorted[min(sorted.count, rank) - 1])
}

func benchmarkIdentity() throws -> Value {
  let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
  var paths = ["Package.swift", "Package.resolved"]
  for folder in ["Sources/SevraCore", "Benchmarks"] {
    guard
      let files = FileManager.default.enumerator(atPath: root.appendingPathComponent(folder).path)
    else { throw SevraError("benchmark", "Run the benchmark from its repository root.") }
    for case let file as String in files where file.hasSuffix(".swift") {
      paths.append(folder + "/" + file)
    }
  }
  var hashes: [String: Value] = [:]
  for path in paths.sorted() {
    hashes[path] = .string(try Workbook.hashFile(root.appendingPathComponent(path)))
  }
  func command(_ executable: String, _ arguments: [String]) throws -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice
    try process.run()
    let output = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    try require(process.terminationStatus == 0, "benchmark", "Could not record benchmark identity.")
    return String(decoding: output, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
  }
  return .object([
    "protocol": .string("search-scale-v2"), "date": .string(timestamp()),
    "commit": .string(try command("/usr/bin/git", ["rev-parse", "HEAD"])),
    "worktreeDirty": .bool(try !command("/usr/bin/git", ["status", "--porcelain"]).isEmpty),
    "model": .string(try command("/usr/sbin/sysctl", ["-n", "hw.model"])),
    "processor": .string(try command("/usr/sbin/sysctl", ["-n", "machdep.cpu.brand_string"])),
    "os": .string(ProcessInfo.processInfo.operatingSystemVersionString),
    "physicalMemoryBytes": .number(Double(ProcessInfo.processInfo.physicalMemory)),
    "binarySHA256": .string(try Workbook.hashFile(URL(fileURLWithPath: CommandLine.arguments[0]))),
    "sourceSHA256": .object(hashes), "percentile": .string("nearest-rank"),
    "cacheConditions": .string("New connection and warmed reads; OS caches are uncontrolled."),
    "limits": .string(
      "Synthetic lexical search. No model, UI, OS-cold or general hardware qualification."),
  ])
}

func sampleSearches(
  _ book: Workbook, queries: [String], repetitions: Int, pageSize: Int,
  validate: (String, SearchPage) throws -> Bool
) throws -> (samples: [Value], warm: [Double], failures: [String]) {
  var samples: [Value] = []
  var warm: [Double] = []
  var failures: [String] = []
  for repetition in 0...repetitions {
    for query in queries {
      var report: [String: Value] = [
        "query": .string(query), "repetition": .number(Double(repetition)),
        "phase": .string(repetition == 0 ? "first-pass" : "warm"),
      ]
      do {
        let (page, milliseconds) = try elapsed { try book.search(query, limit: pageSize) }
        // Fixture validation is outside the timed search call.
        let correct =
          try validate(query, page)
          && Set(page.hits.map(\.itemID)).count == page.hits.count && page.incomplete == 0
        report["milliseconds"] = .number(milliseconds)
        report["correct"] = .bool(correct)
        report["ids"] = .array(page.hits.map { .string($0.itemID) })
        report["hasMore"] = .bool(page.nextCursor != nil)
        if repetition > 0 { warm.append(milliseconds) }
        if !correct { failures.append("Unexpected matches: " + query) }
      } catch {
        report["error"] = .string(error.localizedDescription)
        failures.append(query + ": " + error.localizedDescription)
      }
      samples.append(.object(report))
    }
  }
  return (samples, warm, failures)
}

func verifyPaging(_ book: Workbook, query: String, expected: Set<String>, pageSize: Int) throws
  -> Value
{
  var cursor: String?
  var seen = Set<String>()
  var cursors = Set<String>()
  var pages = 0
  repeat {
    let page = try book.search(query, limit: pageSize, cursor: cursor)
    let ids = page.hits.map(\.itemID)
    try require(
      Set(ids).count == ids.count && seen.isDisjoint(with: ids), "benchmark_recall",
      "Pagination repeated an evidence version.")
    seen.formUnion(ids)
    cursor = page.nextCursor
    pages += 1
    if let cursor {
      try require(cursors.insert(cursor).inserted, "benchmark_recall", "Search repeated a cursor.")
    }
    try require(pages <= expected.count + 1, "benchmark_recall", "Search did not terminate.")
  } while cursor != nil
  try require(
    seen == expected, "benchmark_recall", "Pagination missed or added an evidence version.")
  return .object([
    "pages": .number(Double(pages)), "exactUniqueEvidence": .number(Double(seen.count)),
  ])
}

private final class SearchOutcome: @unchecked Sendable {
  private let lock = NSLock()
  private var result: (String, Double)?
  func set(_ code: String) {
    lock.lock()
    defer { lock.unlock() }
    result = (code, ProcessInfo.processInfo.systemUptime)
  }
  func get() -> (String, Double)? {
    lock.lock()
    defer { lock.unlock() }
    return result
  }
}

/// Cancels after the search call starts. Report an already finished call as a
/// coverage gap, never as an interrupted query. Do not manufacture SQL work.
func cancellationProbe(_ book: Workbook, query: String) throws -> Value {
  let revision = try book.revision()
  let control = Cancellation()
  let entered = DispatchSemaphore(value: 0)
  let finished = DispatchSemaphore(value: 0)
  let outcome = SearchOutcome()
  DispatchQueue.global(qos: .userInitiated).async {
    entered.signal()
    do {
      _ = try book.search(query, cancellation: control)
      outcome.set("complete")
    } catch {
      outcome.set((error as? SevraError)?.code ?? error.localizedDescription)
    }
    finished.signal()
  }
  try require(entered.wait(timeout: .now() + 5) == .success, "benchmark", "Search did not start.")
  Thread.sleep(forTimeInterval: 0.005)
  let active = outcome.get() == nil
  let cancelledAt = ProcessInfo.processInfo.systemUptime
  control.cancel()
  try require(finished.wait(timeout: .now() + 5) == .success, "benchmark", "Search did not stop.")
  let result = outcome.get()!
  let observed = active && result.0 == "cancelled"
  let followup = try book.search(query)
  let unchanged = try book.revision() == revision
  try require(
    !followup.hits.isEmpty && unchanged, "benchmark", "Cancelled search damaged later reads.")
  try require(
    ["complete", "cancelled"].contains(result.0), "benchmark", "Search failed: " + result.0)
  return .object([
    "callStillActiveAtStop": .bool(active), "outcome": .string(result.0),
    "interruptionObserved": .bool(observed),
    "stopToReturnMilliseconds": observed ? .number(max(0, result.1 - cancelledAt) * 1000) : .null,
    "followingQueryPassed": .bool(true), "revisionUnchanged": .bool(unchanged),
    "limit": .string(
      "Call-level observation; not a trace of the exact SQLite instruction at cancellation."),
  ])
}
