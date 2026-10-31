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

@MainActor public enum FileTranscriber {
  /// The recognizer takes about a minute at a time. Parts overlap so that a word cut at one
  /// boundary is heard whole in the next.
  nonisolated static let partSeconds = 58.0
  nonisolated static let overlapSeconds = 2.0
  nonisolated static let durationLimit = 7200.0

  nonisolated static func partStarts(duration: Double) -> [Double] {
    guard duration > 60 else { return [0] }
    return Array(stride(from: 0, to: duration - overlapSeconds, by: partSeconds - overlapSeconds))
  }
  /// The end of a part is unreliable: the recognizer can drop a cut word and stretch the one before
  /// it across the gap. So a part hands over halfway through the overlap, and the next part supplies
  /// every word after the last one kept. A silent next part takes nothing away.
  nonisolated static func joined(_ words: [SpokenWord], _ next: [SpokenWord], offset: Double)
    -> [SpokenWord]
  {
    guard !next.isEmpty else { return words }
    let kept = words.filter { $0.end <= offset + overlapSeconds / 2 }
    let heard = kept.last?.end ?? 0
    return kept
      + next.map { SpokenWord(text: $0.text, start: $0.start + offset, end: $0.end + offset) }
      .filter { ($0.start + $0.end) / 2 >= heard }
  }
  nonisolated static func chunks(_ words: [SpokenWord]) -> [Chunk] {
    stride(from: 0, to: words.count, by: 24).map { index in
      let group = words[index..<min(index + 24, words.count)]
      return Chunk(
        group.map(\.text).joined(separator: " "),
        locator: "time=\(group.first!.start); end=\(group.last!.end)")
    }
  }
  /// Never requests permission or enables a remote recognizer. The app owns that explicit interaction.
  public static func transcribe(
    _ file: URL, cancellation: Cancellation, progress: @escaping @Sendable (String) -> Void = { _ in }
  ) async throws -> [Chunk] {
    try cancellation.check()
    try require(
      SFSpeechRecognizer.authorizationStatus() == .authorized, "speech_permission",
      "Enable speech recognition through Sevra's Transcribe action before using file transcription."
    )
    guard let recognizer = SFSpeechRecognizer(), recognizer.supportsOnDeviceRecognition,
      recognizer.isAvailable
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
    let folder = FileManager.default.temporaryDirectory
      .appendingPathComponent("sevra-transcription-" + identifier())
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let starts = partStarts(duration: duration)
    var words: [SpokenWord] = []
    for (index, start) in starts.enumerated() {
      try cancellation.check()
      if starts.count > 1 {
        progress("Transcribing part \(index + 1) of \(starts.count) on this Mac")
      }
      var part = file
      if starts.count > 1 {
        part = folder.appendingPathComponent("\(index).m4a")
        try await export(asset, from: start, to: part)
      }
      // A silent part is not a failed recording.
      let heard = try await SpeechFileJob().run(part, recognizer: recognizer, cancellation: cancellation)
      words = joined(words, heard, offset: start)
      if part != file { try? FileManager.default.removeItem(at: part) }
    }
    try require(
      !words.isEmpty, "no_speech", "No speech was recognized. The original remains available.")
    return chunks(words)
  }
  static func export(_ asset: AVURLAsset, from start: Double, to file: URL) async throws {
    guard
      let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A)
    else { throw SevraError("audio", "This recording cannot be divided into parts.") }
    session.timeRange = CMTimeRange(
      start: CMTime(seconds: start, preferredTimescale: 600),
      duration: CMTime(seconds: partSeconds, preferredTimescale: 600))
    try await session.export(to: file, as: .m4a)
  }
}

@MainActor private final class SpeechFileJob {
  private var continuation: CheckedContinuation<[SpokenWord], Error>?
  private var task: SFSpeechRecognitionTask?
  private var monitor: Task<Void, Never>?
  func run(_ file: URL, recognizer: SFSpeechRecognizer, cancellation: Cancellation) async throws
    -> [SpokenWord]
  {
    let bounded = Cancellation(parent: cancellation, deadlineAfterSeconds: 90)
    return try await withCheckedThrowingContinuation { continuation in
      self.continuation = continuation
      let request = SFSpeechURLRecognitionRequest(url: file)
      request.requiresOnDeviceRecognition = true
      request.shouldReportPartialResults = false
      task = recognizer.recognitionTask(with: request) { [weak self] result, error in
        Task { @MainActor in
          guard let self else { return }
          if let result, result.isFinal {
            self.finish(
              .success(
                result.bestTranscription.segments.map {
                  SpokenWord(
                    text: $0.substring, start: $0.timestamp, end: $0.timestamp + $0.duration)
                }))
          } else if let error {
            // The recognizer reports a part with nothing to hear as an error.
            let silent = (error as NSError).code == 1110
            self.finish(silent ? .success([]) : .failure(error))
          }
        }
      }
      monitor = Task { [weak self] in
        while !Task.isCancelled {
          do {
            try bounded.check()
            try await Task.sleep(nanoseconds: 100_000_000)
          } catch {
            self?.finish(.failure(error))
            return
          }
        }
      }
    }
  }
  private func finish(_ result: Result<[SpokenWord], Error>) {
    guard let continuation else { return }
    self.continuation = nil
    monitor?.cancel()
    monitor = nil
    task?.cancel()
    task = nil
    continuation.resume(with: result)
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
        parser: "apple-speech-ondevice-v1")
    }.value
  }
}
