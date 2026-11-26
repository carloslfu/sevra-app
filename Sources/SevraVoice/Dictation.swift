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
  public var status: String {
    switch phase {
    case .idle: return "Not dictating"
    case .speechPermission: return "Waiting for speech permission"
    case .microphonePermission: return "Waiting for microphone permission"
    case .starting: return "Starting microphone"
    case .recording: return "Listening on this Mac"
    }
  }
  private static weak var owner: SpeechInput?
  private let makeDriver: () -> any DictationDriver
  private let pausePlayback: () -> Void
  private var driver: (any DictationDriver)?
  private var session: UUID?
  private var result: ((String) -> Void)?
  private var failure: ((String) -> Void)?
  private var finished: (() -> Void)?

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

  /// `finished` runs when the recognizer ends on its own, after its last result.
  public func start(
    result: @escaping (String) -> Void, failure: @escaping (String) -> Void,
    finished: (() -> Void)? = nil
  ) {
    guard !active else { return }
    Self.owner?.stop()
    Self.owner = self
    let id = UUID()
    let driver = makeDriver()
    session = id
    self.driver = driver
    self.result = result
    self.failure = failure
    self.finished = finished
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
          if final, self.session == id {
            let done = self.finished
            self.stop()
            done?()
          }
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
    finished = nil
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
  /// What dictation added after the text that was already in the box.
  public private(set) var dictated = ""
  public init(_ text: String) {
    prefix = text
    lastRendered = text
  }
  public mutating func apply(_ transcript: String, to current: String) -> String? {
    guard current == lastRendered else { return nil }
    guard !transcript.isEmpty else { return current }
    dictated = transcript
    lastRendered = rendering(transcript)
    return lastRendered
  }
  /// The box's text with the dictated part replaced, and the typed part left as it was.
  public func rendering(_ transcript: String) -> String {
    let separator = prefix.isEmpty || prefix.last?.isWhitespace == true ? "" : " "
    return prefix + separator + transcript
  }
}

/// The transcript of one dictation, kept whole across pauses. The on-device recognizer may start
/// a fresh transcript after a pause, or mark where an utterance ended; either way the finished
/// pieces stay and the new one is added after them.
package struct TranscriptPieces {
  private(set) var finished: [String] = []
  private(set) var current = ""
  package init() {}
  package var text: String {
    (finished + [current]).filter { !$0.isEmpty }.joined(separator: " ")
  }
  package mutating func update(_ transcript: String, utteranceEnded: Bool) {
    var next = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
    // A recognizer that keeps its transcript whole repeats the finished pieces: drop them.
    if current.isEmpty, let last = finished.last {
      let lastWords = Self.words(last)
      let tokens = next.split(whereSeparator: \.isWhitespace)
      if !lastWords.isEmpty, Self.words(next).starts(with: lastWords) {
        next = tokens.dropFirst(lastWords.count).joined(separator: " ")
      }
    }
    if !current.isEmpty, Self.restarts(from: current, to: next) { finished.append(current) }
    current = next
    if utteranceEnded, !current.isEmpty {
      finished.append(current)
      current = ""
    }
  }
  /// A partial result normally grows or revises a word or two. One that is half as long, or
  /// shorter with a different first word, is a new piece after a pause.
  static func restarts(from old: String, to new: String) -> Bool {
    let before = words(old)
    let after = words(new)
    guard before.count >= 2, !after.isEmpty else { return false }
    if after.count * 2 <= before.count { return true }
    return after.first != before.first && after.count < before.count
  }
  static func words(_ text: String) -> [String] {
    text.lowercased().split(whereSeparator: \.isWhitespace).map {
      $0.filter { $0.isLetter || $0.isNumber }
    }.filter { !$0.isEmpty }
  }
}

/// Rewrites a finished dictation the way the speaker meant to type it.
public protocol DictationCleaner: Sendable {
  func clean(_ transcript: String) async throws -> String
}

/// Dictation into one text box: the only code that starts, writes, cleans and stops it. Every box
/// where the person writes to Sevra uses one, through the same control. Dictation adds to what is
/// typed and keeps every piece across pauses. When it ends, one cleanup pass rewrites only the
/// dictated part; the original stays one tap away until the person edits. Typing over dictated
/// text stops it, and nothing said is lost when cleanup fails or is slow.
@MainActor public final class Dictation: ObservableObject {
  public let speech: SpeechInput
  private let cleaner: (any DictationCleaner)?
  private let cleanupLimit: Duration
  @Published public private(set) var failure: String?
  @Published public private(set) var cleaning = false
  /// The box's text before the last cleanup, while the box still shows the cleaned text.
  @Published public private(set) var original: String?
  private var draft: DictationDraft?
  private var read: (() -> String)?
  private var write: ((String) -> Void)?
  private var cleaned: String?
  private var cleanup: Task<Void, Never>?

  public init(
    speech: SpeechInput, cleaner: (any DictationCleaner)? = nil,
    cleanupLimit: Duration = .seconds(6)
  ) {
    self.speech = speech
    self.cleaner = cleaner
    self.cleanupLimit = cleanupLimit
  }

  public var active: Bool { speech.active }
  /// Listening or cleaning up: what is in the box is not final yet.
  public var busy: Bool { speech.active || cleaning }

  /// Starts dictation into the text `read` returns and `write` sets, or ends it and cleans up.
  public func toggle(read: @escaping () -> String, write: @escaping (String) -> Void) {
    if speech.active {
      Task { await finish() }
      return
    }
    guard !cleaning else { return }
    failure = nil
    original = nil
    cleaned = nil
    draft = DictationDraft(read())
    self.read = read
    self.write = write
    speech.start { [weak self] transcript in
      guard let self else { return }
      guard var current = self.draft, let rendered = current.apply(transcript, to: read()) else {
        self.stop()
        return
      }
      // The draft records the text first, so the write is known as dictation.
      self.draft = current
      write(rendered)
    } failure: { [weak self] message in
      self?.failure = message
    } finished: { [weak self] in
      Task { await self?.finish() }
    }
  }

  /// Ends listening and cleans up what was dictated. Returns when the box holds the result.
  public func finish() async {
    if let cleanup {
      await cleanup.value
      return
    }
    if speech.active { speech.stop() }
    guard let draft, let read, let write, let cleaner,
      !draft.dictated.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      read() == draft.lastRendered
    else {
      self.draft = nil
      return
    }
    cleaning = true
    let raw = draft.dictated
    let limit = cleanupLimit
    let task = Task { @MainActor [weak self] in
      let result = await Self.clean(raw, with: cleaner, within: limit)
      guard let self, !Task.isCancelled else { return }
      // Apply only to the text dictation left. A person who typed meanwhile keeps their text.
      if let result, read() == draft.lastRendered {
        let text = draft.rendering(result)
        if text != draft.lastRendered {
          self.original = draft.lastRendered
          self.cleaned = text
          write(text)
        }
      }
      self.cleaning = false
      self.cleanup = nil
      self.draft = nil
    }
    cleanup = task
    await task.value
  }

  /// The box's text changed. A change dictation or cleanup did not make is the person typing:
  /// it stops dictation, and the cleaned text is now theirs, so the original is let go.
  public func edited(_ text: String) {
    if speech.active, text != draft?.lastRendered { stop() }
    if original != nil, text != cleaned {
      original = nil
      cleaned = nil
    }
  }

  /// Puts back what was dictated before the cleanup.
  public func restoreOriginal() {
    guard let original, let read, let write, read() == cleaned else { return }
    self.original = nil
    cleaned = nil
    write(original)
  }

  /// Stops without cleaning up: the person left, typed over it, or the box is closing.
  public func stop() {
    cleanup?.cancel()
    cleanup = nil
    cleaning = false
    draft = nil
    speech.stop()
  }

  private nonisolated static func clean(
    _ raw: String, with cleaner: any DictationCleaner, within limit: Duration
  ) async -> String? {
    await withTaskGroup(of: String?.self) { group in
      group.addTask { try? await cleaner.clean(raw) }
      group.addTask {
        try? await Task.sleep(for: limit)
        return nil
      }
      let first = await group.next() ?? nil
      group.cancelAll()
      return first.flatMap { accepted($0, raw: raw) }
    }
  }

  /// A cleanup that is empty or much longer than what was said is a reply, not a cleanup.
  nonisolated static func accepted(_ result: String, raw: String) -> String? {
    let text = result.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty, text.count <= raw.count + raw.count / 2 + 20 else { return nil }
    return text
  }
}
