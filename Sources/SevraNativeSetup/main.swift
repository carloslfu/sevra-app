import Darwin
import Foundation
import SevraSplash

final class SetupCancellation: @unchecked Sendable {
  private let lock = NSLock()
  private var value = false
  func cancel() {
    lock.lock()
    value = true
    lock.unlock()
  }
  var cancelled: Bool {
    lock.lock()
    defer { lock.unlock() }
    return value
  }
}

let cancellation = SetupCancellation()
var signals: [DispatchSourceSignal] = []
for number in [SIGINT, SIGTERM] {
  signal(number, SIG_IGN)
  let source = DispatchSource.makeSignalSource(signal: number, queue: .global())
  source.setEventHandler { cancellation.cancel() }
  source.resume()
  signals.append(source)
}
do {
  let args = Array(CommandLine.arguments.dropFirst())
  let usage =
    "Usage: sevra-native-setup MODELS_ROOT [--reuse TARGET_FOLDER DRAFT_FOLDER]. Candidate setup only; does not change the installed app."
  if args == ["--help"] || args == ["-h"] {
    print(usage)
    exit(0)
  }
  guard args.count == 1 || (args.count == 4 && args[1] == "--reuse"),
    !args[0].hasPrefix("-"), !args[0].isEmpty
  else {
    throw SplashError(usage)
  }
  var last = ""
  var lastUpdate = Date.distantPast
  let result = try SplashModelSetup.install(
    modelsRoot: URL(fileURLWithPath: args[0]),
    reusingTarget: args.count == 4 ? URL(fileURLWithPath: args[2]) : nil,
    reusingDraft: args.count == 4 ? URL(fileURLWithPath: args[3]) : nil,
    cancelled: { cancellation.cancelled }
  ) { state in
    let label = state.phase + ": " + state.file
    if label != last || Date().timeIntervalSince(lastUpdate) >= 1 {
      last = label
      lastUpdate = Date()
      fputs("\(label) (\(state.completedBytes)/\(state.totalBytes) bytes)\n", stderr)
    }
  }
  let bytes = try JSONSerialization.data(
    withJSONObject: ["assembly": result.path, "state": "candidate"],
    options: [.sortedKeys, .withoutEscapingSlashes])
  try FileHandle.standardOutput.write(contentsOf: bytes + Data([10]))
} catch {
  fputs("\(error)\n", stderr)
  exit(cancellation.cancelled ? 130 : 1)
}
