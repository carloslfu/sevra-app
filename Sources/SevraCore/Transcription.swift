import AVFoundation
import Foundation
import Speech

public struct SpokenWord: Equatable, Sendable {
  public let text: String
  public let start: Double
  public let end: Double
  public init(text: String, start: Double, end: Double) {
    self.text = text
    self.start = start
    self.end = end
  }
}

public enum FileTranscriber {
  static let durationLimit = 7200.0

  /// A chunk ends with a sentence where it can, and at 24 words where it cannot.
  static func chunks(_ words: [SpokenWord]) -> [Chunk] {
    var groups: [[SpokenWord]] = []
    var group: [SpokenWord] = []
    for word in words {
      group.append(word)
      let sentence = word.text.last.map { ".?!".contains($0) } ?? false
      if group.count == 24 || (group.count >= 12 && sentence) {
        groups.append(group)
        group = []
      }
    }
    if !group.isEmpty { groups.append(group) }
    return groups.map {
      Chunk(
        $0.map(\.text).joined(separator: " "),
        locator: "time=\($0.first!.start); end=\($0.last!.end)")
    }
  }
  /// Each run of a transcript is one word with its time. A run with no time keeps the last one.
  @available(macOS 26.0, *)
  static func words(_ text: AttributedString, after earlier: Double) -> [SpokenWord] {
    var last = earlier
    return text.runs.compactMap { run in
      let word = String(text[run.range].characters).trimmingCharacters(in: .whitespacesAndNewlines)
      guard !word.isEmpty else { return nil }
      let start = run.audioTimeRange?.start.seconds ?? last
      let end = run.audioTimeRange?.end.seconds ?? start
      last = end
      return SpokenWord(text: word, start: start, end: end)
    }
  }
  /// A whole recording goes to the long-form transcriber in one pass, with no speech permission.
  /// The file recognizer it replaced took about a minute at a time and discarded the speech before
  /// a pause of several seconds, while still reporting success. Audio never leaves this Mac; the
  /// first use of a language can download its speech model from Apple.
  public static func transcribe(
    _ file: URL, cancellation: Cancellation, progress: @escaping @Sendable (String) -> Void = { _ in }
  ) async throws -> [Chunk] {
    try cancellation.check()
    guard #available(macOS 26.0, *), SpeechTranscriber.isAvailable,
      let language = await SpeechTranscriber.supportedLocale(equivalentTo: .current)
    else {
      throw SevraError(
        "speech_unavailable",
        "On-device transcription is unavailable for this language. The original remains available; no audio was sent to a server."
      )
    }
    let asset = AVURLAsset(url: file)
    let duration = try await asset.load(.duration).seconds
    try require(
      duration.isFinite && duration > 0 && duration <= durationLimit, "transcription_limit",
      "This version transcribes recordings up to two hours. Include a shorter excerpt to search its speech; the complete original stays in your workbook."
    )
    let tracks = try await asset.loadTracks(withMediaType: .audio)
    try require(
      !tracks.isEmpty, "audio",
      "This file has no readable audio track.")
    let transcriber = SpeechTranscriber(
      locale: language, transcriptionOptions: [], reportingOptions: [],
      attributeOptions: [.audioTimeRange])
    let installed = await SpeechTranscriber.installedLocales.contains {
      $0.identifier(.bcp47) == language.identifier(.bcp47)
    }
    if !installed,
      let download = try await AssetInventory.assetInstallationRequest(supporting: [transcriber])
    {
      progress("Downloading this language's speech model")
      try await download.downloadAndInstall()
    }
    try cancellation.check()
    guard let audio = try? AVAudioFile(forReading: file) else {
      throw SevraError("audio", "The sound in this file cannot be read.")
    }
    let analyzer = SpeechAnalyzer(modules: [transcriber])
    let bounded = Cancellation(parent: cancellation, deadlineAfterSeconds: max(120, duration))
    let heard = Task {
      var words: [SpokenWord] = []
      for try await result in transcriber.results {
        words += Self.words(result.text, after: words.last?.end ?? 0)
        if let end = words.last?.end {
          progress("Transcribing on this Mac, \(min(99, Int(end / duration * 100)))%")
        }
      }
      return words
    }
    let monitor = Task {
      while !Task.isCancelled {
        do {
          try bounded.check()
          try await Task.sleep(nanoseconds: 100_000_000)
        } catch {
          await analyzer.cancelAndFinishNow()
          return
        }
      }
    }
    defer {
      monitor.cancel()
      heard.cancel()
    }
    let words: [SpokenWord]
    do {
      try await analyzer.start(inputAudioFile: audio, finishAfterFile: true)
      words = try await heard.value
    } catch {
      try bounded.check()
      throw error
    }
    try bounded.check()
    try require(
      !words.isEmpty, "no_speech", "No speech was recognized. The original remains available.")
    return chunks(words)
  }
}

extension Workbook {
  public func transcribe(
    _ sourceID: String, cancellation: Cancellation = .init(),
    progress: @escaping @Sendable (String) -> Void = { _ in }
  ) async throws {
    let source = try item(sourceID)
    guard let assetID = source.assetID else {
      throw SevraError("audio", "Choose an audio or video file.")
    }
    let file = try await Task.detached {
      try self.assetURL(assetID, verify: true, cancellation: cancellation)
    }.value
    let chunks = try await FileTranscriber.transcribe(
      file, cancellation: cancellation, progress: progress)
    try cancellation.check()
    try await Task.detached {
      _ = try self.assetURL(assetID, verify: true, cancellation: cancellation)
      try self.index(
        sourceID, chunks: chunks, state: "ready",
        detail:
          "On-device speech transcription with timestamps. Recognition may contain errors; check the original.",
        parser: "apple-speech-analyzer-v1")
    }.value
  }
}
