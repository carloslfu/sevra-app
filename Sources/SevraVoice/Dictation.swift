import Combine
import Foundation

@MainActor package protocol DictationDriver: AnyObject, Sendable {
  func requestSpeechPermission(_ completion: @escaping @MainActor (Bool) -> Void)
  func requestMicrophonePermission(_ completion: @escaping @MainActor (Bool) -> Void)
  func begin(
    result: @escaping @MainActor (String, Bool) -> Void,
    failure: @escaping @MainActor (String) -> Void
  ) throws
  func stop()
}

/// One explicit recording owner across workbook windows. Permission and
/// recognition callbacks belong to a session, including before capture starts.
@MainActor public final class SpeechInput: ObservableObject {
  public enum Phase: Equatable {
    case idle, speechPermission, microphonePermission, starting, recording
  }
  @Published public private(set) var phase: Phase = .idle
  public var active: Bool { phase != .idle }
  private static weak var owner: SpeechInput?
  private let makeDriver: () -> any DictationDriver
  private let pausePlayback: () -> Void
  private var driver: (any DictationDriver)?
  private var session: UUID?
  private var result: ((String) -> Void)?
  private var failure: ((String) -> Void)?

  public convenience init(pausePlayback: @escaping () -> Void = {}) {
    self.init(driverFactory: { SystemDictationDriver() }, pausePlayback: pausePlayback)
  }

  package init(
    driverFactory: @escaping () -> any DictationDriver, pausePlayback: @escaping () -> Void = {}
  ) {
    makeDriver = driverFactory
    self.pausePlayback = pausePlayback
  }

  deinit {
    if let driver { Task { @MainActor in driver.stop() } }
  }

  public func start(result: @escaping (String) -> Void, failure: @escaping (String) -> Void) {
    guard !active else { return }
    Self.owner?.stop()
    Self.owner = self
    let id = UUID()
    let driver = makeDriver()
    session = id
    self.driver = driver
    self.result = result
    self.failure = failure
    phase = .speechPermission
    driver.requestSpeechPermission { [weak self] allowed in
      guard let self, self.session == id, self.phase == .speechPermission else { return }
      guard allowed else {
        self.fail(id, "Speech recognition permission is required. You can continue typing.")
        return
      }
      self.phase = .microphonePermission
      self.driver?.requestMicrophonePermission { [weak self] allowed in
        guard let self, self.session == id, self.phase == .microphonePermission else { return }
        guard allowed else {
          self.fail(
            id,
            "Microphone access is disabled. You can enable it in System Settings or continue typing."
          )
          return
        }
        self.begin(id)
      }
    }
  }

  private func begin(_ id: UUID) {
    guard session == id, let driver else { return }
    phase = .starting
    pausePlayback()
    do {
      try driver.begin(
        result: { [weak self] text, final in
          guard let self, self.session == id else { return }
          self.result?(text)
          // Rendering can stop dictation when the user has edited or left.
          if final, self.session == id { self.stop() }
        },
        failure: { [weak self] error in self?.fail(id, error) })
      guard session == id else {
        driver.stop()
        return
      }
      phase = .recording
    } catch {
      fail(id, error.localizedDescription)
    }
  }

  private func fail(_ id: UUID, _ message: String) {
    guard session == id else { return }
    let report = failure
    stop()
    report?(message)
  }

  public func stop() {
    // Invalidate before cancelling a driver: cancellation may deliver callbacks.
    session = nil
    let stopped = driver
    driver = nil
    result = nil
    failure = nil
    phase = .idle
    if Self.owner === self { Self.owner = nil }
    stopped?.stop()
  }
}

/// Dictation appends to the existing draft. Only the segment it last rendered
/// may be replaced; user edits win over delayed partial recognition.
public struct DictationDraft {
  private let prefix: String
  public private(set) var lastRendered: String
  public init(_ text: String) {
    prefix = text
    lastRendered = text
  }
  public mutating func apply(_ transcript: String, to current: String) -> String? {
    guard current == lastRendered else { return nil }
    guard !transcript.isEmpty else { return current }
    let separator = prefix.isEmpty || prefix.last?.isWhitespace == true ? "" : " "
    lastRendered = prefix + separator + transcript
    return lastRendered
  }
}
