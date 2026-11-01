import Darwin
import Foundation

/// Single-owner, synchronous transport. Call on a worker, never the main/UI thread.
/// The app's inference actor will serialize access. No global process lookup or socket.
public final class SplashNativeProcess {
  public struct Ready {
    public let concurrent: UInt32
    public let context: UInt32
    public let vision: Bool
  }
  public struct Result {
    public let tokens: [UInt32]
    public let done: SplashWire.Done
    public let firstTokenSeconds: Double?
    public let requestSeconds: Double
  }
  private let process = Process()
  private let terminated = DispatchSemaphore(value: 0)
  private var started = false
  private var reaped = false
  private let input = Pipe(), output = Pipe(), errors = Pipe()
  private var decoder = SplashWire.Decoder()
  private var pending = Data()
  private var pendingOffset = 0
  private var stderr = Data()
  private var stderrOpen = true
  private var closed = false
  private var active = false
  private var lastRequest: UInt64 = 0
  public private(set) var ready: Ready?
  public var diagnosticTail: String { String(decoding: stderr, as: UTF8.self) }
  /// The helper's last line, for a failure message. A workbook keeps that message and can be
  /// shared, so the home folder stays out of it.
  public var lastDiagnostic: String {
    let line = diagnosticTail.split(whereSeparator: \.isNewline).last.map(String.init) ?? ""
    return String(line.replacingOccurrences(of: NSHomeDirectory(), with: "~").suffix(300))
  }
  /// False once the helper has exited or a transport failure closed it.
  public var isOpen: Bool { !closed && process.isRunning }
  public var processID: Int32 { process.processIdentifier }
  private var clock: Double { ProcessInfo.processInfo.systemUptime }

  public init(
    executable: URL, arguments: [String], timeout: Double = 90,
    cancelled: () -> Bool = { false }
  ) throws {
    try check(timeout.isFinite && timeout > 0, "Invalid startup timeout")
    process.executableURL = executable
    process.arguments = arguments
    process.standardInput = input
    process.standardOutput = output
    process.standardError = errors
    let terminated = self.terminated
    process.terminationHandler = { _ in terminated.signal() }
    do {
      try process.run()
      started = true
      // Parent retains only its ends. EOF and teardown must not depend on Pipe deinit.
      try input.fileHandleForReading.close()
      try output.fileHandleForWriting.close()
      try errors.fileHandleForWriting.close()
      for fd in [
        input.fileHandleForWriting.fileDescriptor, output.fileHandleForReading.fileDescriptor,
        errors.fileHandleForReading.fileDescriptor,
      ] {
        try check(
          fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK) != -1, "Cannot configure native pipes"
        )
      }
      try check(
        fcntl(input.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1) != -1,
        "Cannot protect native pipe writes")
      let deadline = clock + timeout
      while ready == nil {
        if cancelled() { throw SplashError("Native startup cancelled") }
        let events = try pump(deadline: deadline)
        for event in events {
          switch event {
          case .ready(let lanes, let context, let vision):
            try check(ready == nil, "Duplicate native readiness")
            ready = Ready(concurrent: lanes, context: context, vision: vision)
          case .error(let failure): throw failure
          default: throw SplashError("Unexpected event before native readiness")
          }
        }
      }
    } catch {
      close()
      guard let failure = error as? SplashError, !lastDiagnostic.isEmpty else { throw error }
      throw SplashError(failure.description + ": " + lastDiagnostic)
    }
  }

  deinit { close() }

  public func generate(
    _ request: SplashWire.Request, timeout: Double = 180,
    cancelled: () -> Bool = { false },
    mask: (([UInt32], [UInt32], UInt32) throws -> [UInt32])? = nil,
    event: (SplashWire.Event) throws -> Void = { _ in }
  ) throws -> Result {
    try check(
      !closed && !active && ready != nil && request.id > lastRequest,
      "Native runtime is closed or request id was reused")
    try check(timeout.isFinite && timeout > 0, "Invalid request timeout")
    try check(request.tokenMask == (mask != nil), "Constraint mode needs exactly one mask provider")
    active = true
    defer { active = false }
    let bytes = try request.encoded()
    try check(request.prompt.count <= ready!.context, "Prompt exceeds native context")
    lastRequest = request.id
    try queue(bytes)
    let started = clock
    var deadline = started + timeout
    var first: Double?
    var state = SplashStreamState(request)
    do {
      while true {
        if cancelled() && !state.cancelled {
          state.cancelled = true
          try queue(SplashWire.cancel(request.id))
          deadline = min(deadline, clock + 3)
        }
        let events = try pump(deadline: deadline)
        var completion: SplashWire.Done?
        for (index, message) in events.enumerated() {
          if case .error = message {
            try check(index == events.count - 1, "Unexpected event after native error")
          }
          if case .start(_, let lane, _) = message {
            try check(lane < ready!.concurrent, "Invalid native lane")
          }
          let done = try state.accept(message)
          if case .tokens = message, first == nil { first = clock - started }
          if case .mask(_, let maskID, let words, let simulation) = message {
            guard let mask else { throw SplashError("Missing mask provider") }
            let result = try mask(state.tokens, simulation, words)
            try check(
              result.count == Int(words) * (simulation.count + 1),
              "Mask provider returned incorrect dimensions")
            try queue(SplashWire.mask(id: request.id, maskID: maskID, words: result))
          }
          try event(message)
          if let done { completion = done }
        }
        if let completion {
          return Result(
            tokens: state.tokens, done: completion, firstTokenSeconds: first,
            requestSeconds: clock - started)
        }
      }
    } catch let failure as SplashWire.Failure where failure.classification == 1 {
      // A request refusal is terminal for that request. The next id may still run.
      throw failure
    } catch {
      close()
      throw error
    }
  }

  public func status(id: UInt64, release: Bool = false, timeout: Double = 30) throws -> Data {
    try check(!closed && !active && timeout.isFinite && timeout > 0, "Invalid status request")
    active = true
    defer { active = false }
    try queue(SplashWire.status(id, release: release))
    let deadline = clock + timeout
    do {
      while true {
        let events = try pump(deadline: deadline)
        if events.isEmpty { continue }
        try check(events.count == 1, "Unexpected additional status event")
        switch events[0] {
        case .status(let responseID, let json):
          try check(responseID == id, "Status correlation mismatch")
          return json
        case .error(let failure): throw failure
        default: throw SplashError("Unexpected native status response")
        }
      }
    } catch {
      close()
      throw error
    }
  }

  private func queue(_ bytes: Data) throws {
    try check(
      pending.count - pendingOffset + bytes.count <= 8 * 1024 * 1024,
      "Native write queue exceeded its bound")
    if pendingOffset > 0 {
      pending = pending.subdata(in: pendingOffset..<pending.count)
      pendingOffset = 0
    }
    pending.append(bytes)
  }

  private func pump(deadline: Double) throws -> [SplashWire.Event] {
    try check(clock < deadline, "Native operation timed out")
    var fds = [
      pollfd(fd: output.fileHandleForReading.fileDescriptor, events: Int16(POLLIN), revents: 0),
      pollfd(
        fd: stderrOpen ? errors.fileHandleForReading.fileDescriptor : -1, events: Int16(POLLIN),
        revents: 0),
      pollfd(
        fd: pendingOffset < pending.count ? input.fileHandleForWriting.fileDescriptor : -1,
        events: Int16(POLLOUT), revents: 0),
    ]
    let result = poll(&fds, nfds_t(fds.count), Int32(max(1, min(50, (deadline - clock) * 1000))))
    if result < 0 {
      if errno == EINTR { return [] }
      throw SplashError("Native pipe polling failed")
    }
    if fds[1].revents != 0 {
      let data = try readChunk(fds[1].fd)
      if let data {
        if data.isEmpty {
          stderrOpen = false
        } else {
          stderr.append(data)
          if stderr.count > 65536 { stderr = Data(stderr.suffix(65536)) }
        }
      }
    }
    var events: [SplashWire.Event] = []
    if fds[0].revents != 0, let data = try readChunk(fds[0].fd) {
      if data.isEmpty {
        try decoder.finish()
        throw SplashError("Native engine closed its output")
      }
      events = try decoder.consume(data)
    }
    if fds[2].revents != 0 {
      let written = pending.withUnsafeBytes { ptr in
        Darwin.write(
          fds[2].fd, ptr.baseAddress!.advanced(by: pendingOffset), pending.count - pendingOffset)
      }
      if written < 0 {
        if errno != EAGAIN && errno != EINTR { throw SplashError("Native engine closed its input") }
      } else {
        pendingOffset += written
      }
      if pendingOffset == pending.count {
        pending.removeAll(keepingCapacity: false)
        pendingOffset = 0
      }
    }
    return events
  }

  private func readChunk(_ fd: Int32) throws -> Data? {
    var bytes = [UInt8](repeating: 0, count: 65536)
    let count = Darwin.read(fd, &bytes, bytes.count)
    if count < 0 {
      if errno == EAGAIN || errno == EINTR { return nil }
      throw SplashError("Cannot read native engine pipe")
    }
    return Data(bytes.prefix(count))
  }

  @discardableResult public func close() -> Bool {
    if closed && reaped { return true }
    closed = true
    try? input.fileHandleForWriting.close()
    if !started || !process.isRunning { reaped = true }
    if !reaped {
      process.terminate()
      reaped = terminated.wait(timeout: .now() + 1) == .success || !process.isRunning
      if !reaped {
        Darwin.kill(process.processIdentifier, SIGKILL)
        reaped = terminated.wait(timeout: .now() + 3) == .success || !process.isRunning
      }
    }
    try? output.fileHandleForReading.close()
    try? errors.fileHandleForReading.close()
    pending.removeAll()
    pendingOffset = 0
    ready = nil
    // Never enter Foundation's unbounded waitUntilExit from the serial worker.
    // A failed bounded reap leaves the owning model lease held for explicit retry.
    return reaped
  }
}
