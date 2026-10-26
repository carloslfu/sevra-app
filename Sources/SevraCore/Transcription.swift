import AVFoundation
import Foundation
import Speech

@MainActor public enum FileTranscriber {
  /// Never requests permission or enables a remote recognizer. The app owns that explicit interaction.
  public static func transcribe(_ file: URL, cancellation: Cancellation) async throws -> [Chunk] {
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
      duration.isFinite && duration > 0 && duration <= 60, "transcription_limit",
      "This version transcribes clips up to 60 seconds. Include a shorter excerpt to search its speech; the complete original stays in your workbook."
    )
    let tracks = try await asset.loadTracks(withMediaType: .audio)
    try require(
      !tracks.isEmpty, "audio",
      "This file has no readable audio track.")
    try cancellation.check()
    let job = SpeechFileJob()
    return try await job.run(file, recognizer: recognizer, cancellation: cancellation)
  }
}

@MainActor private final class SpeechFileJob {
  private var continuation: CheckedContinuation<[Chunk], Error>?
  private var task: SFSpeechRecognitionTask?
  private var monitor: Task<Void, Never>?
  func run(_ file: URL, recognizer: SFSpeechRecognizer, cancellation: Cancellation) async throws
    -> [Chunk]
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
            let segments = result.bestTranscription.segments
            var chunks: [Chunk] = []
            var words: [String] = []
            var start: Double = 0
            var end: Double = 0
            for segment in segments {
              if words.isEmpty { start = segment.timestamp }
              words.append(segment.substring)
              end = segment.timestamp + segment.duration
              if words.count >= 24 {
                chunks.append(
                  Chunk(words.joined(separator: " "), locator: "time=\(start); end=\(end)"))
                words = []
              }
            }
            if !words.isEmpty {
              chunks.append(
                Chunk(words.joined(separator: " "), locator: "time=\(start); end=\(end)"))
            }
            if chunks.isEmpty {
              self.finish(
                .failure(
                  SevraError(
                    "no_speech", "No speech was recognized. The original remains available.")))
            } else {
              self.finish(.success(chunks))
            }
          } else if let error {
            self.finish(.failure(error))
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
  private func finish(_ result: Result<[Chunk], Error>) {
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
  public func transcribe(_ sourceID: String, cancellation: Cancellation = .init()) async throws {
    let source = try item(sourceID)
    guard let assetID = source.assetID else {
      throw SevraError("audio", "Choose an audio or video file.")
    }
    let file = try await Task.detached { try self.assetURL(assetID, verify: true) }.value
    let chunks = try await FileTranscriber.transcribe(file, cancellation: cancellation)
    try cancellation.check()
    try await Task.detached {
      _ = try self.assetURL(assetID, verify: true)
      try self.index(
        sourceID, chunks: chunks, state: "ready",
        detail:
          "On-device speech transcription with timestamps. Recognition may contain errors; check the original.",
        parser: "apple-speech-ondevice-v1")
    }.value
  }
}
