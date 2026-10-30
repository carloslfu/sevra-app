import Darwin
import Foundation
import SevraCore

private func expect(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
  if try !condition() { throw SevraError("test", message) }
}
private func refuses(_ code: String, _ action: () throws -> Void) throws {
  do { try action() } catch {
    try expect((error as? SevraError)?.code == code, "Expected \(code), got \(error)")
    return
  }
  throw SevraError("test", "Expected refusal: \(code)")
}

private final class Failures: @unchecked Sendable {
  private let lock = NSLock()
  private var codes: [String] = []
  func record(_ error: Error) {
    lock.lock()
    codes.append((error as? SevraError)?.code ?? "unexpected")
    lock.unlock()
  }
  func values() -> [String] {
    lock.lock()
    defer { lock.unlock() }
    return codes
  }
}

@main struct Checks {
  static func main() throws {
    if CommandLine.arguments.count == 4, CommandLine.arguments[1] == "--orphan-parent" {
      let parser = Process()
      parser.executableURL = ExtractionWorker.bundledExecutable
      parser.arguments = [CommandLine.arguments[3]]
      parser.standardInput = FileHandle.nullDevice
      parser.standardOutput = FileHandle.standardOutput
      parser.standardError = FileHandle.nullDevice
      try parser.run()
      try String(parser.processIdentifier).write(
        toFile: CommandLine.arguments[2], atomically: true, encoding: .utf8)
      parser.waitUntilExit()
      return
    }
    if CommandLine.arguments.count > 2, CommandLine.arguments[1] == "--fixture-worker" {
      try fixture()
      return
    }
    setbuf(stdout, nil)
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      "sevra-extraction-\(identifier())")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: root) }
    let source = root.appendingPathComponent("Evidence.txt")
    try Data("Original invoice brass 1042".utf8).write(to: source)
    let executable = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
    var passed = 0
    var failed = 0
    func check(_ title: String, _ body: () throws -> Void) {
      do {
        try body()
        passed += 1
        print("PASS \(title)")
      } catch {
        failed += 1
        print("FAIL \(title): \(error)")
      }
    }
    func worker(_ mode: String, timeout: Double = 2, memory: UInt64 = 1024 * 1024 * 1024)
      -> ExtractionWorker
    {
      ExtractionWorker(
        executable: executable,
        arguments: ["--fixture-worker", mode, root.appendingPathComponent(mode + ".pid").path],
        timeout: timeout, maximumMemoryBytes: memory)
    }
    func reaped(_ mode: String) throws {
      let value = try String(
        contentsOf: root.appendingPathComponent(mode + ".pid"), encoding: .utf8)
      guard let pid = Int32(value) else {
        throw SevraError("test", "Worker did not record its PID")
      }
      try expect(kill(pid, 0) == -1 && errno == ESRCH, "Worker remains alive after refusal")
    }
    check("packaged native helper returns exact text without a workbook handle") {
      let result = try ExtractionWorker().extract(source)
      try expect(
        result.state == "ready" && result.chunks.map(\.text) == ["Original invoice brass 1042"],
        "Text extraction changed")
    }
    check("child does not inherit an open workbook's database or lock descriptors") {
      let book = try Workbook.create(
        at: root.appendingPathComponent("Descriptors.sevra"), title: "Descriptors")
      _ = try withExtendedLifetime(book) { try worker("descriptors").extract(source) }
      try reaped("descriptors")
      try expect(try book.revision() == 0, "Descriptor check changed workbook state")
    }
    check("worker crash preserves original and prior searchable index; retry recovers") {
      let book = try Workbook.create(at: root.appendingPathComponent("Crash.sevra"), title: "Crash")
      let item = try book.importFile(source)
      try book.extract(item.id)
      let hash = try book.asset(item.assetID!).hash
      try refuses("extraction_crash") { try book.extract(item.id, worker: worker("crash")) }
      try reaped("crash")
      try expect(
        try book.extractionStatus(item.id)["state"].text == "partial", "Prior index was discarded")
      try expect(
        try book.search("1042").hits.contains { $0.itemID == item.id },
        "Prior evidence is no longer searchable")
      try expect(try book.asset(item.assetID!).hash == hash, "Original metadata changed")
      try expect(
        try Workbook.hashFile(book.assetURL(item.assetID!)) == hash, "Original bytes changed")
      try book.extract(item.id)
      try expect(
        try book.extractionStatus(item.id)["state"].text == "ready", "Retry did not recover")
    }
    check("uncooperative worker is killed at its parent deadline") {
      let started = ProcessInfo.processInfo.systemUptime
      try refuses("deadline") { _ = try worker("hang", timeout: 0.3).extract(source) }
      try reaped("hang")
      try expect(
        ProcessInfo.processInfo.systemUptime - started < 3, "Deadline teardown was unbounded")
    }
    check("cancellation interrupts a worker that ignores termination") {
      let cancel = Cancellation()
      DispatchQueue.global().asyncAfter(deadline: .now() + 0.3) { cancel.cancel() }
      try refuses("cancelled") { _ = try worker("cancel").extract(source, cancellation: cancel) }
      try reaped("cancel")
    }
    check("output flood cannot exceed the parent result limit") {
      try refuses("extraction_output") { _ = try worker("flood").extract(source) }
      try reaped("flood")
    }
    check("sampled worker memory refusal terminates the parser") {
      try refuses("extraction_memory") {
        _ = try worker("memory", memory: 32 * 1024 * 1024).extract(source)
      }
      try reaped("memory")
    }
    check("success requires complete bounded terminal output") {
      for mode in [
        "invalid-json", "trailing-json", "both-results", "missing-result", "wrong-version",
      ] {
        try refuses("extraction_protocol") { _ = try worker(mode).extract(source) }
        try reaped(mode)
      }
      try refuses("extraction_output") { _ = try worker("invalid-state").extract(source) }
      try reaped("invalid-state")
    }
    check("bounded stderr is drained without corrupting valid stdout") {
      let result = try worker("stderr").extract(source)
      try expect(
        result.state == "unsupported" && result.chunks.isEmpty, "Stderr corrupted the protocol")
      try reaped("stderr")
    }
    check("missing helper refuses without an in-process fallback") {
      try refuses("extraction_worker") {
        _ = try ExtractionWorker(executable: root.appendingPathComponent("missing")).extract(source)
      }
    }
    check("two active parsers bound concurrency and queued cancellation starts no worker") {
      let group = DispatchGroup()
      let results = Failures()
      let cancellations = [Cancellation(), Cancellation()]
      for index in 0..<2 {
        let parser = worker("slot-\(index)", timeout: 5)
        let cancellation = cancellations[index]
        group.enter()
        DispatchQueue.global().async {
          defer { group.leave() }
          do { _ = try parser.extract(source, cancellation: cancellation) } catch {
            results.record(error)
          }
        }
      }
      defer {
        for cancellation in cancellations { cancellation.cancel() }
        _ = group.wait(timeout: .now() + 4)
      }
      let paths = (0..<2).map { root.appendingPathComponent("slot-\($0).pid").path }
      let until = ProcessInfo.processInfo.systemUptime + 2
      while !paths.allSatisfy({ FileManager.default.fileExists(atPath: $0) })
        && ProcessInfo.processInfo.systemUptime < until
      { Thread.sleep(forTimeInterval: 0.01) }
      try expect(
        paths.allSatisfy { FileManager.default.fileExists(atPath: $0) }, "Two workers did not start"
      )
      let queued = Cancellation()
      DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) { queued.cancel() }
      try refuses("cancelled") { _ = try worker("queued").extract(source, cancellation: queued) }
      try expect(
        !FileManager.default.fileExists(atPath: root.appendingPathComponent("queued.pid").path),
        "A third parser was launched")
      for cancellation in cancellations { cancellation.cancel() }
      try expect(group.wait(timeout: .now() + 4) == .success, "Concurrent parsers did not stop")
      try expect(
        results.values() == ["cancelled", "cancelled"], "Concurrent cancellation lost its cause")
      for index in 0..<2 { try reaped("slot-\(index)") }
      _ = try ExtractionWorker().extract(source)
    }
    check("structured parsing preserves UTF-8, quoted newlines, empty quoted rows and TSV") {
      let csv = root.appendingPathComponent("Table.csv")
      let input = "\u{feff}name,note\r\nCafé,\"one\ntwo\"\r\nB,\"say \"\"yes\"\"\"\r\n"
      try Data(input.utf8).write(to: csv)
      let rows = try ExtractionWorker().readTable(csv, format: .csv).sheets[0].rows
      try expect(
        rows == [["name", "note"], ["Café", "one\ntwo"], ["B", "say \"yes\""]], "CSV values changed"
      )
      try expect(try CSV.parse("\"\"") == [[""]], "Quoted empty row disappeared")
      try Data("name\tquantity\r\nBrass\t12\r\n".utf8).write(to: csv)
      try expect(
        try ExtractionWorker().readTable(csv, format: .tsv).sheets[0].rows == [
          ["name", "quantity"], ["Brass", "12"],
        ], "TSV values changed")
    }
    check("CSV enforces exact terminal column, row and field limits") {
      let width = Array(repeating: "x", count: 500).joined(separator: ",")
      try expect(try CSV.parse(width)[0].count == 500, "500 columns were refused")
      try refuses("csv_limit") { _ = try CSV.parse(width + ",x") }
      try expect(
        try CSV.parse(String(repeating: "x\n", count: 100_000)).count == 100_000,
        "100,000 rows were refused")
      try refuses("csv_limit") { _ = try CSV.parse(String(repeating: "x\n", count: 100_000) + "x") }
      try expect(
        try CSV.parse(String(repeating: "x", count: 1_000_000))[0][0].utf8.count == 1_000_000,
        "1 MB field was refused")
      try refuses("csv_limit") { _ = try CSV.parse(String(repeating: "x", count: 1_000_001)) }
      let cancelled = Cancellation()
      cancelled.cancel()
      try refuses("cancelled") { _ = try CSV.parse("a,b", cancellation: cancelled) }
    }
    check("structured worker failure publishes no dataset and original remains searchable") {
      let csv = root.appendingPathComponent("Failure.csv")
      try Data("part,quantity\nBrass,12\n".utf8).write(to: csv)
      let book = try Workbook.create(
        at: root.appendingPathComponent("Structured failure.sevra"), title: "Failure")
      let item = try book.importFile(csv)
      try book.extract(item.id)
      for mode in ["crash", "invalid-json", "missing-result", "wrong-version", "stderr"] {
        try refuses(mode == "crash" ? "extraction_crash" : "extraction_protocol") {
          _ = try book.importCSV(item.id, worker: worker(mode))
        }
        try reaped(mode)
        try expect(try book.datasets().isEmpty, "Failed parser published table data")
        try expect(
          try book.extractionStatus(item.id)["state"].text == "ready",
          "Structured failure hid the content index")
        let pending = try Workbook(book.url).pendingExtractions()
        try expect(
          pending.contains {
            $0["item_id"].text == item.id && $0["parser"].text == "structured-v1"
              && $0["state"].text == "failed"
          }, "Failure did not survive reopen")
      }
      let table = try book.importCSV(item.id)
      let retry = try book.importCSV(item.id)
      try expect(table.id == retry.id && retry.rowCount == 1, "Retry duplicated table data")
      try expect(try book.pendingExtractions().isEmpty, "Recovered intake kept a stale error")
      try expect(
        try book.search("Brass").hits.contains { $0.itemID == item.id }, "Original search was lost")
      try expect(
        try Workbook.hashFile(book.assetURL(item.assetID!)) == book.asset(item.assetID!).hash,
        "Original changed")
    }
    check("late cancelled parser cannot replace a newer successful intake status") {
      let csv = root.appendingPathComponent("Concurrent.csv")
      try Data("part,quantity\nBrass,12\n".utf8).write(to: csv)
      let book = try Workbook.create(
        at: root.appendingPathComponent("Concurrent.sevra"), title: "Concurrent")
      let item = try book.importFile(csv)
      try book.extract(item.id)
      let cancelled = Cancellation()
      let group = DispatchGroup()
      let result = Failures()
      let parser = worker("older-parse", timeout: 5)
      group.enter()
      DispatchQueue.global().async {
        defer { group.leave() }
        do { _ = try book.importCSV(item.id, cancellation: cancelled, worker: parser) } catch {
          result.record(error)
        }
      }
      defer {
        cancelled.cancel()
        _ = group.wait(timeout: .now() + 4)
      }
      let pid = root.appendingPathComponent("older-parse.pid")
      let until = ProcessInfo.processInfo.systemUptime + 2
      while !FileManager.default.fileExists(atPath: pid.path)
        && ProcessInfo.processInfo.systemUptime < until
      {
        Thread.sleep(forTimeInterval: 0.01)
      }
      try expect(FileManager.default.fileExists(atPath: pid.path), "Older parser did not start")
      _ = try book.importCSV(item.id)
      cancelled.cancel()
      try expect(group.wait(timeout: .now() + 4) == .success, "Older parser did not stop")
      try reaped("older-parse")
      try expect(result.values() == ["cancelled"], "Cancellation lost its cause")
      try expect(
        try book.datasets().count == 1 && book.pendingExtractions().isEmpty,
        "Late completion replaced the current status")
    }
    check("structured import refuses source bytes changed during parsing") {
      let csv = root.appendingPathComponent("Changing.csv")
      try Data("part,quantity\nBrass,12\n".utf8).write(to: csv)
      let book = try Workbook.create(
        at: root.appendingPathComponent("Changing.sevra"), title: "Changing")
      let item = try book.importFile(csv, linked: true)
      try refuses("changed_asset") {
        _ = try book.importCSV(item.id, worker: worker("change-source"))
      }
      try reaped("change-source")
      try expect(try book.datasets().isEmpty, "Changed-source parser published rows")
    }
    check("structured cancellation and missing helper retain the same process boundary") {
      try refuses("deadline") {
        _ = try worker("hang", timeout: 0.3).readTable(source, format: .xlsx)
      }
      try reaped("hang")
      let cancel = Cancellation()
      DispatchQueue.global().asyncAfter(deadline: .now() + 0.3) { cancel.cancel() }
      try refuses("cancelled") {
        _ = try worker("cancel").readTable(source, format: .csv, cancellation: cancel)
      }
      try reaped("cancel")
      try refuses("extraction_worker") {
        _ = try ExtractionWorker(executable: root.appendingPathComponent("missing")).readTable(
          source, format: .csv)
      }
    }
    check("structured limits reject dense blank expansion and invalid UTF-8 before publication") {
      let csv = root.appendingPathComponent("Wide.csv")
      let text =
        Array(repeating: "column", count: 500).joined(separator: ",") + "\n"
        + String(repeating: "x\n", count: 2000)
      try Data(text.utf8).write(to: csv)
      try refuses("structured_output") { _ = try ExtractionWorker().readTable(csv, format: .csv) }
      try Data([0xff, 0xfe, 0x61]).write(to: csv)
      try refuses("encoding") { _ = try ExtractionWorker().readTable(csv, format: .csv) }
    }
    check("real helper exits after parent death while its output pipe is blocked") {
      let big = root.appendingPathComponent("Large text.txt")
      try Data(repeating: 0x41, count: 8_000_000).write(to: big)
      let pidFile = root.appendingPathComponent("orphan.pid")
      let parent = Process()
      let output = Pipe()
      parent.executableURL = executable
      parent.arguments = ["--orphan-parent", pidFile.path, big.path]
      parent.standardOutput = output
      parent.standardError = FileHandle.nullDevice
      var child: Int32?
      defer {
        if parent.isRunning { kill(parent.processIdentifier, SIGKILL) }
        if let child, kill(child, 0) == 0 { kill(child, SIGKILL) }
        try? output.fileHandleForReading.close()
        try? output.fileHandleForWriting.close()
      }
      try parent.run()
      try output.fileHandleForWriting.close()
      // The worker may write output before its parent finishes atomically
      // publishing the PID. Wait for both signals, without assuming their order.
      let readyDeadline = ProcessInfo.processInfo.systemUptime + 5
      while !FileManager.default.fileExists(atPath: pidFile.path) && parent.isRunning
        && ProcessInfo.processInfo.systemUptime < readyDeadline
      {
        Thread.sleep(forTimeInterval: 0.005)
      }
      child = (try? String(contentsOf: pidFile, encoding: .utf8)).flatMap(Int32.init)
      try expect(child != nil && kill(child!, 0) == 0, "Parent did not register a live worker")
      var fd = pollfd(
        fd: output.fileHandleForReading.fileDescriptor, events: Int16(POLLIN), revents: 0)
      try expect(poll(&fd, 1, 5000) > 0, "Worker never reached its large output")
      var byte: UInt8 = 0
      try expect(
        Darwin.read(fd.fd, &byte, 1) == 1 && byte == 0x7b, "Worker did not start a JSON response")
      try expect(child != nil && kill(child!, 0) == 0, "Worker exited before parent death")
      kill(parent.processIdentifier, SIGKILL)
      let until = ProcessInfo.processInfo.systemUptime + 3
      while (parent.isRunning || kill(child!, 0) == 0)
        && ProcessInfo.processInfo.systemUptime < until
      {
        Thread.sleep(forTimeInterval: 0.01)
      }
      try expect(
        !parent.isRunning && kill(child!, 0) == -1 && errno == ESRCH,
        "Orphaned parser survived with an unread output pipe")
    }
    print("\(passed) passed; \(failed) failed. Process isolation is not a security sandbox.")
    exit(failed == 0 ? 0 : 1)
  }

  static func fixture() throws {
    let mode = CommandLine.arguments[2]
    try String(getpid()).write(toFile: CommandLine.arguments[3], atomically: true, encoding: .utf8)
    let valid =
      "{\"version\":1,\"result\":{\"chunks\":[],\"state\":\"unsupported\",\"detail\":\"Synthetic fixture\"}}"
    switch mode {
    case "crash": kill(getpid(), SIGKILL)
    case "hang", "cancel", "slot-0", "slot-1", "older-parse":
      signal(SIGTERM, SIG_IGN)
      while true { Thread.sleep(forTimeInterval: 0.1) }
    case "memory":
      var bytes = [UInt8](repeating: 1, count: 128 * 1024 * 1024)
      for i in stride(from: 0, to: bytes.count, by: 4096) {
        bytes[i] = UInt8(truncatingIfNeeded: i)
      }
      withExtendedLifetime(bytes) { Thread.sleep(forTimeInterval: 5) }
    case "flood":
      let data = Data(repeating: 0x41, count: 1_048_576)
      for _ in 0..<80 { try FileHandle.standardOutput.write(contentsOf: data) }
    case "invalid-json": try FileHandle.standardOutput.write(contentsOf: Data("{".utf8))
    case "trailing-json":
      try FileHandle.standardOutput.write(contentsOf: Data((valid + valid).utf8))
    case "both-results":
      try FileHandle.standardOutput.write(
        contentsOf: Data(
          valid.dropLast().appending(",\"error\":{\"code\":\"fail\",\"message\":\"Fail\"}}").utf8))
    case "missing-result":
      try FileHandle.standardOutput.write(contentsOf: Data("{\"version\":1}".utf8))
    case "wrong-version":
      try FileHandle.standardOutput.write(
        contentsOf: Data(
          valid.replacingOccurrences(of: "\"version\":1", with: "\"version\":2").utf8))
    case "invalid-state":
      try FileHandle.standardOutput.write(
        contentsOf: Data(valid.replacingOccurrences(of: "unsupported", with: "unverified").utf8))
    case "stderr":
      let data = Data(repeating: 0x41, count: 65_536)
      for _ in 0..<100 { try FileHandle.standardError.write(contentsOf: data) }
      try FileHandle.standardOutput.write(contentsOf: Data(valid.utf8))
    case "change-source":
      try Data("part,quantity\nBrass,99\n".utf8).write(
        to: URL(fileURLWithPath: CommandLine.arguments.last!))
      try FileHandle.standardOutput.write(
        contentsOf: Data(
          #"{"version":1,"result":{"sheets":[{"name":"","rows":[["part","quantity"],["Brass","12"]],"rowNumbers":[1,2],"notes":[],"formulas":{},"unsettled":{}}]}}"#
            .utf8))
    case "descriptors":
      for fd in 3..<getdtablesize() {
        var path = [CChar](repeating: 0, count: Int(PATH_MAX))
        if fcntl(fd, F_GETPATH, &path) == 0 && String(cString: path).contains(".sevra/") {
          exit(85)
        }
      }
      try FileHandle.standardOutput.write(contentsOf: Data(valid.utf8))
    default: exit(64)
    }
  }
}
