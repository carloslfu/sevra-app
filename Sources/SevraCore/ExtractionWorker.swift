import Darwin
import Foundation

/// One bounded parser process. The host owns publication and never gives the
/// child a database handle or authority to change the workbook.
public struct ExtractionWorker: Sendable {
  public let executable: URL
  public let arguments: [String]
  public let timeout: TimeInterval
  public let maximumMemoryBytes: UInt64
  static let maximumOutputBytes = 64 * 1024 * 1024

  public init(
    executable: URL? = nil, arguments: [String] = [], timeout: TimeInterval = 60,
    maximumMemoryBytes: UInt64 = 1024 * 1024 * 1024
  ) {
    self.executable = executable ?? Self.bundledExecutable
    self.arguments = arguments
    self.timeout = timeout
    self.maximumMemoryBytes = maximumMemoryBytes
  }

  public static var bundledExecutable: URL {
    (Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0]))
      .resolvingSymlinksInPath().deletingLastPathComponent().appendingPathComponent("sevra-extract")
  }

  public func workflowIdentity(cancellation: Cancellation = .init()) throws -> Value {
    try require(arguments.isEmpty, "workflow_extraction_worker", "Use the native document helper.")
    let identity: Value = .object([
      "protocol": .string("sevra-extract-v1"),
      "sha256": .string(try Workbook.hashFile(executable, cancellation: cancellation)),
      "timeoutSeconds": .number(timeout), "memoryBytes": .number(Double(maximumMemoryBytes)),
    ])
    try Self.validateWorkflowIdentity(identity)
    return identity
  }

  static func validateWorkflowIdentity(_ value: Value) throws {
    guard case .number(let timeout) = value["timeoutSeconds"],
      case .number(let memory) = value["memoryBytes"]
    else {
      throw SevraError("workflow_extraction_worker", "Use numeric native helper limits.")
    }
    try require(
      Set(value.object.keys) == ["protocol", "sha256", "timeoutSeconds", "memoryBytes"]
        && value["protocol"] == .string("sevra-extract-v1")
        && value["sha256"].text.range(of: "^[0-9a-f]{64}\\z", options: .regularExpression) != nil
        && timeout.isFinite && timeout > 0 && timeout <= 60
        && memory.isFinite && memory > 0 && memory <= 1_073_741_824,
      "workflow_extraction_worker", "Use the bounded native document helper identity.")
  }

  public func extract(_ url: URL, cancellation: Cancellation = .init()) throws -> ExtractionResult {
    let result: ExtractionResult = try run(url, mode: [], cancellation: cancellation)
    try result.validate()
    return result
  }

  public func readTable(
    _ url: URL, format: StructuredFormat, cancellation: Cancellation = .init()
  ) throws -> StructuredResult {
    let result: StructuredResult = try run(
      url, mode: ["--structured=" + format.rawValue], cancellation: cancellation)
    try result.validate()
    try require(
      format == .xlsx || result.sheets.count == 1, "structured_output",
      "Delimited text must return one table.")
    return result
  }

  public func excelEvidence(_ url: URL, cancellation: Cancellation = .init()) throws
    -> [ExcelEvidence]
  {
    let result: [ExcelEvidence] = try run(
      url, mode: ["--excel-evidence"], cancellation: cancellation)
    try require(
      result.count <= 256 && Set(result.map(\.id)).count == result.count
        && result.allSatisfy { !$0.id.isEmpty && $0.id.utf8.count <= 1024 && $0.sha256.count == 64 }
        && result.reduce(0) { $0 + $1.text.utf8.count } <= 32_000_000,
      "excel_evidence_limit", "Invalid or excessive workbook evidence.")
    return result
  }

  public func excelBehavior(_ request: Value, cancellation: Cancellation = .init()) throws -> Value
  {
    let bytes = Data(try request.json().utf8)
    try require(
      bytes.count <= 4_000_000, "excel_behavior_limit", "Workbook calculation input exceeds 4 MB.")
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      "sevra-excel-" + identifier())
    try FileManager.default.createDirectory(
      at: root, withIntermediateDirectories: false,
      attributes: [.posixPermissions: 0o700])
    defer { try? FileManager.default.removeItem(at: root) }
    let input = root.appendingPathComponent("request.json")
    try bytes.write(to: input, options: .atomic)
    return try run(input, mode: ["--excel-behavior"], cancellation: cancellation)
  }

  /// One pass of a `run` chat script in the helper's sandbox. See `Workbook.chatRun`.
  public func chatScript(_ request: Value, cancellation: Cancellation = .init()) throws -> Value {
    let bytes = Data(try request.json().utf8)
    try require(bytes.count <= 4_000_000, "run_limit", "The script's input exceeds 4 MB.")
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      "sevra-run-" + identifier())
    try FileManager.default.createDirectory(
      at: root, withIntermediateDirectories: false,
      attributes: [.posixPermissions: 0o700])
    defer { try? FileManager.default.removeItem(at: root) }
    let input = root.appendingPathComponent("request.json")
    try bytes.write(to: input, options: .atomic)
    return try run(input, mode: ["--chat-script"], cancellation: cancellation)
  }

  /// A ZIP library that traps on a hostile file stops this helper, which is a refused file.
  public func zipMembers(_ url: URL, cancellation: Cancellation = .init()) throws -> [ZIPMember] {
    do {
      return try run(url, mode: ["--zip-members"], cancellation: cancellation)
    } catch let error as SevraError where error.code == "extraction_crash" {
      throw ZIPDirectory.damaged
    }
  }

  func run<Result: Codable>(
    _ url: URL, mode: [String], cancellation: Cancellation
  ) throws -> Result {
    try require(
      timeout.isFinite && timeout > 0 && maximumMemoryBytes > 0, "extraction_policy",
      "Invalid extraction limits.")
    try cancellation.check()
    try require(url.isFileURL, "extraction_input", "Choose a local file for extraction.")
    try require(
      FileManager.default.isExecutableFile(atPath: executable.path), "extraction_worker",
      "The document extractor is missing. Reinstall Sevra or build the sevra-extract helper.")
    let bounded = Cancellation(parent: cancellation, deadlineAfterSeconds: timeout)
    try ExtractionSlots.shared.acquire(bounded)
    let process = Process()
    let terminated = DispatchSemaphore(value: 0)
    let output = Pipe()
    let errors = Pipe()
    var started = false
    var outputOpen = true
    var errorsOpen = true
    var bytes = Data()
    var diagnostic = Data()
    process.executableURL = executable
    process.arguments = arguments + mode + [url.path]
    process.standardInput = FileHandle.nullDevice
    process.standardOutput = output
    process.standardError = errors
    process.environment = [
      "PATH": "/usr/bin:/bin", "HOME": NSHomeDirectory(), "TMPDIR": NSTemporaryDirectory(),
    ]
    process.terminationHandler = { _ in terminated.signal() }
    defer {
      var reaped = !started || !process.isRunning
      if !reaped {
        process.terminate()
        reaped = terminated.wait(timeout: .now() + 0.25) == .success || !process.isRunning
        if !reaped {
          Darwin.kill(process.processIdentifier, SIGKILL)
          reaped = terminated.wait(timeout: .now() + 2) == .success || !process.isRunning
        }
      }
      try? output.fileHandleForReading.close()
      try? output.fileHandleForWriting.close()
      try? errors.fileHandleForReading.close()
      try? errors.fileHandleForWriting.close()
      if reaped {
        ExtractionSlots.shared.release()
      } else {
        // A process stuck in kernel IO must continue to occupy its slot. Never
        // spawn replacements indefinitely or block a workbook/UI on its reap.
        DispatchQueue.global(qos: .utility).async {
          process.waitUntilExit()
          ExtractionSlots.shared.release()
        }
      }
    }
    do {
      try process.run()
      started = true
    } catch {
      throw SevraError(
        "extraction_worker",
        "The document extractor could not start. Reinstall Sevra and retry intake.")
    }
    try output.fileHandleForWriting.close()
    try errors.fileHandleForWriting.close()
    let descriptors = [
      output.fileHandleForReading.fileDescriptor, errors.fileHandleForReading.fileDescriptor,
    ]
    for fd in descriptors {
      try require(
        fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK) != -1, "extraction_pipe",
        "Cannot read the document extractor.")
    }
    while true {
      try bounded.check()
      if process.isRunning {
        var usage = rusage_info_v4()
        let status = withUnsafeMutablePointer(to: &usage) { pointer in
          pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
            proc_pid_rusage(process.processIdentifier, RUSAGE_INFO_V4, $0)
          }
        }
        if status == 0 {
          try require(
            usage.ri_phys_footprint <= maximumMemoryBytes, "extraction_memory",
            "This document needs too much memory to index. The original is kept; try a smaller excerpt."
          )
        } else if errno != ESRCH && process.isRunning {
          throw SevraError(
            "extraction_memory",
            "The document extractor's memory could not be checked. Retry intake.")
        }
      }
      var fds = [
        pollfd(fd: outputOpen ? descriptors[0] : -1, events: Int16(POLLIN), revents: 0),
        pollfd(fd: errorsOpen ? descriptors[1] : -1, events: Int16(POLLIN), revents: 0),
      ]
      let ready = poll(&fds, nfds_t(fds.count), 25)
      if ready < 0 && errno != EINTR {
        throw SevraError("extraction_pipe", "The document extractor connection failed.")
      }
      for index in 0..<fds.count where fds[index].revents != 0 {
        // Bound each drain so a producer flooding either stream cannot starve
        // cancellation, deadline or memory checks.
        for _ in 0..<32 {
          var buffer = [UInt8](repeating: 0, count: 65_536)
          let count = Darwin.read(fds[index].fd, &buffer, buffer.count)
          if count == 0 {
            if index == 0 { outputOpen = false } else { errorsOpen = false }
            break
          }
          if count < 0 {
            if errno == EAGAIN || errno == EINTR { break }
            throw SevraError("extraction_pipe", "The document extractor connection failed.")
          }
          if index == 0 {
            try require(
              bytes.count + count <= Self.maximumOutputBytes, "extraction_output",
              "This document's index is too large. The original is kept; try a smaller excerpt.")
            bytes.append(contentsOf: buffer.prefix(count))
          } else {
            diagnostic.append(contentsOf: buffer.prefix(count))
            if diagnostic.count > 16_384 { diagnostic = Data(diagnostic.suffix(16_384)) }
          }
        }
      }
      if !process.isRunning && !outputOpen && !errorsOpen { break }
    }
    try bounded.check()
    try require(
      process.terminationReason == .exit && process.terminationStatus == 0, "extraction_crash",
      "The document extractor stopped unexpectedly. The original and any previous index are kept. Retry intake."
    )
    guard let response = try? JSONDecoder().decode(ParserReply<Result>.self, from: bytes),
      response.version == 1,
      (response.result == nil) != (response.error == nil)
    else {
      throw SevraError(
        "extraction_protocol", "The document extractor returned an unreadable result. Retry intake."
      )
    }
    if let error = response.error {
      try require(
        error.code.utf8.count <= 128 && error.message.utf8.count <= 4096, "extraction_protocol",
        "The document extractor returned an invalid error.")
      throw error
    }
    return response.result!
  }

  /// Dedicated helper entry point. No workbook or network service is opened.
  public static func runMain(
    behavior: ((URL) throws -> Value)? = nil, layout: ((URL) throws -> Value)? = nil,
    script: ((URL) throws -> Value)? = nil
  ) -> Never {
    let arguments = Array(CommandLine.arguments.dropFirst())
    let format: StructuredFormat?
    let listing = arguments.count == 2 && arguments[0] == "--zip-members"
    let evidence = arguments.count == 2 && arguments[0] == "--excel-evidence"
    let calculating = arguments.count == 2 && arguments[0] == "--excel-behavior"
    let diagram = arguments.count == 2 && arguments[0] == "--diagram-layout"
    let scripting = arguments.count == 2 && arguments[0] == "--chat-script"
    let imageSize =
      arguments.count == 3 && arguments[0].hasPrefix("--image-preview=")
      ? Int(arguments[0].dropFirst("--image-preview=".count)) : nil
    if arguments.count == 1 || listing || evidence || calculating || diagram || scripting
      || imageSize != nil
    {
      format = nil
    } else if arguments.count == 2, arguments[0].hasPrefix("--structured="),
      let selected = StructuredFormat(rawValue: String(arguments[0].dropFirst(13)))
    {
      format = selected
    } else {
      exit(64)
    }
    let url = URL(fileURLWithPath: arguments.last!)
    let parent = getppid()
    guard parent > 1 else { exit(75) }
    let started = ProcessInfo.processInfo.systemUptime
    let watchdog = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
    watchdog.schedule(deadline: .now() + 0.5, repeating: .milliseconds(500))
    watchdog.setEventHandler {
      if getppid() != parent || ProcessInfo.processInfo.systemUptime - started > 70 { _exit(75) }
    }
    watchdog.resume()
    let status: Int32 = withExtendedLifetime(watchdog) {
      if let imageSize {
        return writeReply {
          try ImagePreviewPixels.decode(url, dimension: imageSize, hash: arguments[1])
        }
      }
      if diagram {
        return writeReply {
          guard let layout else {
            throw SevraError("diagram_layout", "Diagram layout is unavailable.")
          }
          return try layout(url)
        }
      }
      if scripting {
        return writeReply {
          guard let script else { throw SevraError("run", "The script helper is unavailable.") }
          return try script(url)
        }
      }
      if calculating {
        return writeReply {
          guard let behavior else {
            throw SevraError("excel_behavior", "Calculation helper is unavailable.")
          }
          return try behavior(url)
        }
      }
      if evidence {
        return writeReply {
          try ExcelEvidence.readInProcess(url, cancellation: Cancellation(deadlineAfterSeconds: 60))
        }
      }
      if listing {
        return writeReply {
          try ZIPDirectory.members(url, cancellation: Cancellation(deadlineAfterSeconds: 60))
        }
      }
      if let format {
        return writeReply {
          let result = try StructuredResult.readInProcess(
            url, format: format, cancellation: Cancellation(deadlineAfterSeconds: 60))
          try result.validate()
          return result
        }
      }
      return writeReply {
        let result = try Extractor.extractInProcess(
          url, cancellation: Cancellation(deadlineAfterSeconds: 60))
        try result.validate()
        return result
      }
    }
    watchdog.cancel()
    exit(status)
  }
  private static func writeReply<Result: Codable>(_ parse: () throws -> Result) -> Int32 {
    let reply: ParserReply<Result>
    do {
      reply = ParserReply(version: 1, result: try parse(), error: nil)
    } catch {
      let failure =
        error as? SevraError
        ?? SevraError(
          "extraction_failed",
          "This file could not be read. The original is kept; retry intake or use a smaller excerpt."
        )
      reply = ParserReply(
        version: 1, result: nil,
        error: SevraError(String(failure.code.prefix(128)), String(failure.message.prefix(1024))))
    }
    do {
      let data = try JSONEncoder().encode(reply)
      guard data.count <= maximumOutputBytes else { return 74 }
      try FileHandle.standardOutput.write(contentsOf: data)
      return 0
    } catch { return 74 }
  }
}

private struct ParserReply<Result: Codable>: Codable {
  let version: Int
  let result: Result?
  let error: SevraError?
}

extension ExtractionResult {
  func validate() throws {
    try require(
      ["ready", "partial", "unsupported"].contains(state) && detail.utf8.count <= 4096
        && chunks.count <= 100_000,
      "extraction_output", "The document extractor exceeded its result limits.")
    var total = 0
    for chunk in chunks {
      total += chunk.text.utf8.count
      try require(
        total <= 16_000_000 && chunk.locator.utf8.count <= 1024, "extraction_output",
        "This document's text exceeds the indexing limit. Try a smaller excerpt.")
    }
  }
}

private final class ExtractionSlots: @unchecked Sendable {
  static let shared = ExtractionSlots()
  private let semaphore = DispatchSemaphore(value: 2)
  func acquire(_ cancellation: Cancellation) throws {
    while true {
      try cancellation.check()
      if semaphore.wait(timeout: .now() + 0.025) == .success {
        do { try cancellation.check() } catch {
          semaphore.signal()
          throw error
        }
        return
      }
    }
  }
  func release() { semaphore.signal() }
}
