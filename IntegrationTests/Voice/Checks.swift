import Foundation
import SevraVoice

private struct Failure: Error, CustomStringConvertible {
  let description: String
  init(_ description: String) { self.description = description }
}
private func expect(_ value: @autoclosure () -> Bool, _ message: String) throws {
  if !value() { throw Failure(message) }
}

@MainActor private final class Driver: DictationDriver {
  var speech: ((Bool) -> Void)?
  var microphone: ((Bool) -> Void)?
  var result: ((String, Bool) -> Void)?
  var failure: ((String) -> Void)?
  var speechRequests = 0
  var microphoneRequests = 0
  var starts = 0
  var stops = 0
  var beginError = false
  var immediateFinal = false
  var immediateError = false
  var callbacksOnStop = false
  func requestSpeechPermission(_ completion: @escaping @MainActor (Bool) -> Void) {
    speechRequests += 1
    speech = completion
  }
  func requestMicrophonePermission(_ completion: @escaping @MainActor (Bool) -> Void) {
    microphoneRequests += 1
    microphone = completion
  }
  func begin(
    result: @escaping @MainActor (String, Bool) -> Void,
    failure: @escaping @MainActor (String) -> Void
  ) throws {
    starts += 1
    self.result = result
    self.failure = failure
    if immediateFinal { result("Finished during startup", true) }
    if immediateError { failure("Recognition refused") }
    if beginError { throw Failure("Capture refused") }
  }
  func stop() {
    stops += 1
    if callbacksOnStop {
      result?("Late cancellation result", true)
      failure?("Cancellation callback")
    }
  }
  func allow() {
    speech?(true)
    microphone?(true)
  }
}

@MainActor private final class Player: PlaybackParticipant {
  var pauses = 0
  func pause() { pauses += 1 }
}

@main private struct VoiceChecks {
  @MainActor static func main() async {
    setbuf(stdout, nil)
    var passed = 0
    var failures: [String] = []
    func check(_ name: String, _ body: () throws -> Void) {
      do {
        try body()
        passed += 1
        print("PASS \(name)")
      } catch {
        failures.append(name + ": " + String(describing: error))
        print("FAIL \(name): \(error)")
      }
    }

    check("Stop invalidates speech permission before microphone access") {
      let driver = Driver()
      let input = SpeechInput(driverFactory: { driver })
      var errors: [String] = []
      input.start(result: { _ in }, failure: { errors.append($0) })
      try expect(
        input.active && input.phase == .speechPermission, "Pending setup cannot be stopped")
      input.stop()
      driver.speech?(true)
      try expect(
        !input.active && driver.microphoneRequests == 0 && driver.starts == 0,
        "Late permission started capture")
      try expect(errors.isEmpty, "Cancelled setup displayed an error")
    }
    check("Stop invalidates microphone permission before capture") {
      let driver = Driver()
      let input = SpeechInput(driverFactory: { driver })
      input.start(result: { _ in }, failure: { _ in })
      driver.speech?(true)
      try expect(input.phase == .microphonePermission, "Wrong pending phase")
      input.stop()
      driver.microphone?(true)
      try expect(!input.active && driver.starts == 0, "Late microphone permission started capture")
    }
    check("Repeated taps and duplicated callbacks create one capture") {
      let driver = Driver()
      let input = SpeechInput(driverFactory: { driver })
      input.start(result: { _ in }, failure: { _ in })
      input.start(result: { _ in }, failure: { _ in })
      driver.speech?(true)
      driver.speech?(true)
      driver.microphone?(true)
      driver.microphone?(true)
      try expect(
        driver.speechRequests == 1 && driver.microphoneRequests == 1 && driver.starts == 1,
        "Duplicate capture")
      try expect(input.phase == .recording, "Capture did not become active")
      input.stop()
    }
    check("Denied permissions never capture and allow an explicit retry") {
      for speechAllowed in [false, true] {
        let first = Driver()
        let second = Driver()
        var drivers = [first, second]
        let input = SpeechInput(driverFactory: { drivers.removeFirst() })
        var errors: [String] = []
        input.start(result: { _ in }, failure: { errors.append($0) })
        first.speech?(speechAllowed)
        if speechAllowed { first.microphone?(false) }
        try expect(
          !input.active && first.starts == 0 && errors.count == 1,
          "Denied permission left active capture")
        input.start(result: { _ in }, failure: { errors.append($0) })
        first.speech?(false)
        first.microphone?(true)
        second.allow()
        try expect(
          input.phase == .recording && second.starts == 1 && errors.count == 1,
          "Old permission damaged retry")
        input.stop()
      }
    }
    check("Previous recognition cannot edit or stop a new session") {
      let first = Driver()
      let second = Driver()
      var drivers = [first, second]
      let input = SpeechInput(driverFactory: { drivers.removeFirst() })
      var text = ""
      var errors: [String] = []
      input.start(result: { text = $0 }, failure: { errors.append($0) })
      first.allow()
      input.stop()
      input.start(result: { text = $0 }, failure: { errors.append($0) })
      second.allow()
      first.result?("Stale final", true)
      first.failure?("Stale error")
      second.result?("Current", false)
      try expect(
        input.active && text == "Current" && errors.isEmpty && second.stops == 0,
        "Old callback touched current session")
      second.result?("Current final", true)
      try expect(
        !input.active && text == "Current final", "Final result did not stop its own session")
    }
    check("Cancellation callbacks cannot publish errors or text") {
      let driver = Driver()
      driver.callbacksOnStop = true
      let input = SpeechInput(driverFactory: { driver })
      var text = ""
      var errors: [String] = []
      input.start(result: { text = $0 }, failure: { errors.append($0) })
      driver.allow()
      input.stop()
      input.stop()
      try expect(
        !input.active && text.isEmpty && errors.isEmpty && driver.stops == 1,
        "Cancellation reentered the live session")
    }
    check("Synchronous terminal callbacks cannot leave startup recording") {
      for final in [true, false] {
        let driver = Driver()
        driver.immediateFinal = final
        driver.immediateError = !final
        let input = SpeechInput(driverFactory: { driver })
        var text = ""
        var errors: [String] = []
        input.start(result: { text = $0 }, failure: { errors.append($0) })
        driver.allow()
        try expect(
          !input.active && driver.stops > 0, "Terminal callback was overwritten by recording state")
        try expect(
          final
            ? text == "Finished during startup" && errors.isEmpty
            : errors == ["Recognition refused"], "Terminal output changed")
      }
    }
    check("Capture failure releases and ignores later recognition") {
      let driver = Driver()
      driver.beginError = true
      let input = SpeechInput(driverFactory: { driver })
      var text = ""
      var errors: [String] = []
      input.start(result: { text = $0 }, failure: { errors.append($0) })
      driver.allow()
      driver.result?("Late text", false)
      try expect(
        !input.active && driver.stops > 0 && text.isEmpty && errors.count == 1,
        "Failed capture stayed active")
    }
    check("New workbook recording stops the prior owner without accepting its callbacks") {
      let oldDriver = Driver()
      let newDriver = Driver()
      let oldInput = SpeechInput(driverFactory: { oldDriver })
      let newInput = SpeechInput(driverFactory: { newDriver })
      var oldText = ""
      var newText = ""
      oldInput.start(result: { oldText = $0 }, failure: { _ in })
      oldDriver.allow()
      newInput.start(result: { newText = $0 }, failure: { _ in })
      newDriver.allow()
      oldInput.stop()
      oldDriver.result?("Old", true)
      oldDriver.failure?("Old")
      newDriver.result?("New", false)
      try expect(
        !oldInput.active && newInput.active && oldText.isEmpty && newText == "New",
        "Cross-window recording ownership failed")
      try expect(oldDriver.stops == 1 && newDriver.stops == 0, "Wrong capture stopped")
      newInput.stop()
    }
    check("Dictation preserves existing drafts and replaces only its own partial text") {
      for prefix in [
        "", "Existing draft", "Existing draft ", "Existing line\n", "Precio €", "Café 👩🏽‍💻",
      ] {
        var draft = DictationDraft(prefix)
        let first = draft.apply("first", to: prefix)!
        let second = draft.apply("first and second", to: first)!
        let separator = prefix.isEmpty || prefix.last?.isWhitespace == true ? "" : " "
        try expect(
          second == prefix + separator + "first and second", "Draft or whitespace was lost")
        try expect(draft.apply("", to: second) == second, "Empty partial erased dictation")
        try expect(
          draft.apply("late", to: "Human correction") == nil, "Late partial overwrote human text")
      }
    }
    check("A manual edit ends dictation instead of accepting a later partial") {
      let driver = Driver()
      let recording = SpeechInput(driverFactory: { driver })
      var text = "Typed prefix"
      var draft = DictationDraft(text)
      recording.start(
        result: { value in
          guard let next = draft.apply(value, to: text) else {
            recording.stop()
            return
          }
          text = next
        }, failure: { _ in })
      driver.allow()
      driver.result?("spoken", false)
      text = "User edited the draft"
      driver.result?("late recognition", false)
      try expect(text == "User edited the draft" && !recording.active, "Manual edit was lost")
    }
    check("Dictation pauses every live player and window close affects only its owner") {
      let registry = PlaybackRegistry()
      let first = Player()
      let second = Player()
      let owner = UUID()
      let other = UUID()
      registry.register(first, owner: owner)
      registry.register(second, owner: other)
      registry.register(first, owner: owner)
      let driver = Driver()
      let input = SpeechInput(driverFactory: { driver }, pausePlayback: { registry.pauseAll() })
      input.start(result: { _ in }, failure: { _ in })
      driver.allow()
      try expect(
        first.pauses == 1 && second.pauses == 1, "Background player continued through dictation")
      registry.close(owner: owner)
      try expect(first.pauses == 2 && second.pauses == 1, "Closing one window paused another")
      registry.pauseAll()
      try expect(first.pauses == 2 && second.pauses == 2, "Closed owner remained registered")
      input.stop()
    }
    check("Playback tracking does not retain closed viewers") {
      let registry = PlaybackRegistry()
      var player: Player? = Player()
      weak var reference = player
      registry.register(player!, owner: UUID())
      player = nil
      try expect(reference == nil, "Registry retained its player")
      registry.pauseAll()
    }
    let abandonedDriver = Driver()
    var abandoned: SpeechInput? = SpeechInput(driverFactory: { abandonedDriver })
    weak var abandonedReference = abandoned
    abandoned?.start(result: { _ in }, failure: { _ in })
    abandonedDriver.allow()
    abandoned = nil
    // Deinitialization schedules main-actor cleanup; give that owned task a
    // bounded opportunity to run without retaining the input in the test.
    for _ in 0..<100 where abandonedDriver.stops == 0 {
      try? await Task.sleep(nanoseconds: 10_000_000)
    }
    check("Releasing a recording owner stops its driver") {
      try expect(
        abandonedReference == nil && abandonedDriver.stops == 1, "Released input left capture alive"
      )
    }
    print(
      "\(passed) passed; \(failures.count) failed. Synthetic lifecycle checks do not qualify speech hardware or recognition accuracy."
    )
    exit(failures.isEmpty ? 0 : 1)
  }
}
