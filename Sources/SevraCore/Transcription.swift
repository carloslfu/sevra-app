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
  /// Each run of a transcript is one word with its time. A run with no usable time keeps the last one.
  @available(macOS 26.0, *)
  static func words(_ text: AttributedString, after earlier: Double) -> [SpokenWord] {
    var last = earlier
    return text.runs.compactMap { run in
      let word = String(text[run.range].characters).trimmingCharacters(in: .whitespacesAndNewlines)
      guard !word.isEmpty else { return nil }
      let start = run.audioTimeRange?.start.seconds ?? last
      let end = run.audioTimeRange?.end.seconds ?? start
      guard start.isFinite, end.isFinite else {
        return SpokenWord(text: word, start: last, end: last)
      }
      last = end
      return SpokenWord(text: word, start: start, end: end)
    }
  }
  /// Waits for system work that may ignore Stop. Stop and the deadline always return here, and the
  /// work is told to stop. A speech model download left running finishes on its own.
  static func waiting(
    within bounded: Cancellation, for work: @escaping @Sendable () async throws -> Void
  ) async throws {
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      let waiter = Waiter(continuation)
      let task = Task {
        do {
          try await work()
          waiter.finish(.success(()))
        } catch { waiter.finish(.failure(error)) }
      }
      Task {
        while waiter.isOpen {
          do {
            try bounded.check()
            try await Task.sleep(nanoseconds: 100_000_000)
          } catch {
            task.cancel()
            waiter.finish(.failure(error))
            return
          }
        }
      }
    }
  }
  private final class Waiter: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Error>?
    init(_ continuation: CheckedContinuation<Void, Error>) { self.continuation = continuation }
    var isOpen: Bool {
      lock.lock()
      defer { lock.unlock() }
      return continuation != nil
    }
    func finish(_ result: Result<Void, Error>) {
      lock.lock()
      let open = continuation
      continuation = nil
      lock.unlock()
      open?.resume(with: result)
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
    let tracks = (try? await asset.loadTracks(withMediaType: .audio)) ?? []
    let duration = (try? await asset.load(.duration).seconds) ?? 0
    try require(
      !tracks.isEmpty && duration.isFinite && duration > 0, "audio",
      "This file has no readable audio track.")
    try require(
      duration <= durationLimit, "transcription_limit",
      "This version transcribes recordings up to two hours. Include a shorter excerpt to search its speech; the complete original stays in your workbook."
    )
    let transcriber = SpeechTranscriber(
      locale: language, transcriptionOptions: [], reportingOptions: [],
      attributeOptions: [.audioTimeRange])
    let installed = await SpeechTranscriber.installedLocales.contains {
      $0.identifier(.bcp47) == language.identifier(.bcp47)
    }
    if !installed,
      let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber])
    {
      progress("Downloading this language's speech model")
      cancellation.track(request.progress)
      defer { cancellation.untrack(request.progress) }
      let bounded = Cancellation(parent: cancellation, deadlineAfterSeconds: 1800)
      do {
        try await waiting(within: bounded) { try await request.downloadAndInstall() }
      } catch {
        try bounded.check()
        throw SevraError(
          "speech_unavailable",
          "This language's speech model could not be downloaded. The original remains available; no audio was sent to a server."
        )
      }
    }
    let bounded = Cancellation(parent: cancellation, deadlineAfterSeconds: max(120, duration))
    let folder = FileManager.default.temporaryDirectory
      .appendingPathComponent("sevra-transcription-" + identifier())
    defer { try? FileManager.default.removeItem(at: folder) }
    let audio = try soundFile(file, asset: asset, tracks: tracks, folder: folder, bounded: bounded)
    let analyzer = SpeechAnalyzer(modules: [transcriber])
    let heard = Task {
      var words: [SpokenWord] = []
      for try await result in transcriber.results {
        words += Self.words(result.text, after: words.last?.end ?? 0)
        if let end = words.last?.end {
          progress("Transcribing on this Mac, \(Int(max(0, min(99, end / duration * 100))))%")
        }
      }
      return words
    }
    defer {
      heard.cancel()
      Task { await analyzer.cancelAndFinishNow() }
    }
    do {
      try await waiting(within: bounded) {
        try await analyzer.start(inputAudioFile: audio, finishAfterFile: true)
        _ = try await heard.value
      }
    } catch {
      try bounded.check()
      throw SevraError("audio", "The sound in this file cannot be read.")
    }
    let words = try await heard.value
    try require(
      !words.isEmpty, "no_speech", "No speech was recognized. The original remains available.")
    return chunks(words)
  }
  /// The transcriber reads one track of the common formats directly. Every other recording, such as
  /// Opus, FLAC or a video with two audio tracks, is mixed into a temporary copy first.
  private static func soundFile(
    _ file: URL, asset: AVURLAsset, tracks: [AVAssetTrack], folder: URL, bounded: Cancellation
  ) throws -> AVAudioFile {
    let common: Set<AudioFormatID> = [
      kAudioFormatLinearPCM, kAudioFormatMPEG4AAC, kAudioFormatMPEGLayer3, kAudioFormatAppleLossless,
    ]
    if tracks.count == 1, let audio = try? AVAudioFile(forReading: file), audio.length > 0,
      common.contains(audio.fileFormat.streamDescription.pointee.mFormatID)
    {
      return audio
    }
    let unreadable = SevraError("audio", "The sound in this file cannot be read.")
    let settings: [String: Any] = [
      AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 16000, AVNumberOfChannelsKey: 1,
      AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false,
      AVLinearPCMIsNonInterleaved: false,
    ]
    guard let reader = try? AVAssetReader(asset: asset),
      let format = AVAudioFormat(settings: settings)
    else { throw unreadable }
    let mix = AVAssetReaderAudioMixOutput(audioTracks: tracks, audioSettings: settings)
    guard reader.canAdd(mix) else { throw unreadable }
    reader.add(mix)
    guard reader.startReading() else { throw unreadable }
    defer { reader.cancelReading() }
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let copy = folder.appendingPathComponent("sound.wav")
    var writer: AVAudioFile? = try AVAudioFile(
      forWriting: copy, settings: settings, commonFormat: .pcmFormatInt16, interleaved: true)
    while let sample = mix.copyNextSampleBuffer() {
      try bounded.check()
      let frames = AVAudioFrameCount(CMSampleBufferGetNumSamples(sample))
      guard frames > 0 else { continue }
      guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else {
        throw unreadable
      }
      buffer.frameLength = frames
      let copied = CMSampleBufferCopyPCMDataIntoAudioBufferList(
        sample, at: 0, frameCount: Int32(frames), into: buffer.mutableAudioBufferList)
      guard copied == noErr else { throw unreadable }
      try writer?.write(from: buffer)
    }
    // Closing the writer finishes the file before it is read back.
    writer = nil
    guard reader.status == .completed, let audio = try? AVAudioFile(forReading: copy),
      audio.length > 0
    else { throw unreadable }
    return audio
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
