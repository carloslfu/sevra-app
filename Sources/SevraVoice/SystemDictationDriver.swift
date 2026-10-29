import AVFoundation
import Foundation
import Speech

@MainActor final class SystemDictationDriver: DictationDriver {
  private let engine = AVAudioEngine()
  private var recognizer: SFSpeechRecognizer?
  private var request: SFSpeechAudioBufferRecognitionRequest?
  private var task: SFSpeechRecognitionTask?
  private var tapped = false

  func requestSpeechPermission(_ completion: @escaping @MainActor (Bool) -> Void) {
    SFSpeechRecognizer.requestAuthorization { authorization in
      Task { @MainActor in completion(authorization == .authorized) }
    }
  }
  func requestMicrophonePermission(_ completion: @escaping @MainActor (Bool) -> Void) {
    AVCaptureDevice.requestAccess(for: .audio) { allowed in
      Task { @MainActor in completion(allowed) }
    }
  }
  func begin(
    result: @escaping @MainActor (String, Bool) -> Void,
    failure: @escaping @MainActor (String) -> Void
  ) throws {
    guard let recognizer = SFSpeechRecognizer(), recognizer.supportsOnDeviceRecognition,
      recognizer.isAvailable
    else {
      throw DictationError(
        "On-device dictation is unavailable for this language. Sevra will not send audio to a server."
      )
    }
    let node = engine.inputNode
    let format = node.outputFormat(forBus: 0)
    guard format.sampleRate > 0, format.channelCount > 0 else {
      throw DictationError("No working microphone is available.")
    }
    let request = SFSpeechAudioBufferRecognitionRequest()
    request.requiresOnDeviceRecognition = true
    request.shouldReportPartialResults = true
    self.recognizer = recognizer
    self.request = request
    node.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
      request.append(buffer)
    }
    tapped = true
    task = recognizer.recognitionTask(with: request) { value, error in
      Task { @MainActor in
        if let value { result(value.bestTranscription.formattedString, value.isFinal) }
        if let error { failure(error.localizedDescription) }
      }
    }
    do {
      engine.prepare()
      try engine.start()
    } catch {
      stop()
      throw error
    }
  }
  func stop() {
    if tapped {
      engine.inputNode.removeTap(onBus: 0)
      tapped = false
    }
    engine.stop()
    request?.endAudio()
    task?.cancel()
    task = nil
    request = nil
    recognizer = nil
  }
}

private struct DictationError: LocalizedError {
  let errorDescription: String?
  init(_ message: String) { errorDescription = message }
}
