import Foundation
import SevraSplash

/// Development-only real-engine qualification. It is not bundled with the app.
/// Prompt tokens are independently prepared reference fixtures until I06 passes.
func nativeProbe(_ arguments: [String]) throws -> Bool {
  func json(_ value: Any) throws {
    let bytes = try JSONSerialization.data(
      withJSONObject: value, options: [.sortedKeys, .withoutEscapingSlashes])
    try FileHandle.standardOutput.write(contentsOf: bytes + Data([10]))
  }
  if arguments.first == "--setup-network", arguments.count == 2 {
    let root = URL(fileURLWithPath: arguments[1])
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let pack = try SplashModelPack.selected()
    for (label, source) in [("target", pack.target), ("draft", pack.draft)] {
      let file = source.files.first { $0.path == "config.json" }!
      let url = URL(string: "https://huggingface.co")!.appendingPathComponent(source.repository)
        .appendingPathComponent("resolve").appendingPathComponent(source.revision)
        .appendingPathComponent(file.path)
      let destination = root.appendingPathComponent(label + "-config.json")
      try PinnedModelDownload.fetch(url, to: destination, bytes: file.bytes, sha256: file.sha256)
      let handle = try FileHandle(forWritingTo: destination)
      try handle.truncate(atOffset: UInt64(file.bytes / 2))
      try handle.close()
      try PinnedModelDownload.fetch(url, to: destination, bytes: file.bytes, sha256: file.sha256)
      try json([
        "setupNetwork": label, "bytes": file.bytes, "sha256": file.sha256,
        "completeAndResumed": true,
      ])
    }
    return true
  }
  if arguments.first == "--prepare", arguments.count == 4 {
    var lastFile = ""
    let started = ProcessInfo.processInfo.systemUptime
    let assembly = try SplashModelPreparation.prepare(
      pack: .selected(),
      target: URL(fileURLWithPath: arguments[1]), draft: URL(fileURLWithPath: arguments[2]),
      modelsRoot: URL(fileURLWithPath: arguments[3]),
      progress: { progress in
        if progress.file != lastFile {
          lastFile = progress.file
          try? FileHandle.standardError.write(
            contentsOf: Data(("Verifying " + lastFile + "\n").utf8))
        }
      })
    try json(["assembly": assembly.path, "seconds": ProcessInfo.processInfo.systemUptime - started])
    return true
  }
  if arguments.first == "--run-engine", arguments.count == 4 {
    struct Input: Decodable {
      let prompt: [UInt32]
      let maxOutput: UInt32
      let generationTokens: UInt32
    }
    let input = try JSONDecoder().decode(
      Input.self, from: Data(contentsOf: URL(fileURLWithPath: arguments[3])))
    let started = ProcessInfo.processInfo.systemUptime
    let memory =
      ProcessInfo.processInfo.environment["SEVRA_SPLASH_PROBE_MEMORY_BYTES"] ?? "23622320128"
    try expect(UInt64(memory) != nil, "Invalid probe memory budget")
    let helper = try SplashNativeProcess(
      executable: URL(fileURLWithPath: arguments[1]),
      arguments: [
        "serve-native", arguments[2], "8192", memory,
        "--persistent-cache", "off", "--idle-sleep", "allow", "--verify-rows", "all",
      ], timeout: 180)
    defer { helper.close() }
    try json([
      "readySeconds": ProcessInfo.processInfo.systemUptime - started,
      "context": helper.ready!.context, "vision": helper.ready!.vision,
    ])
    for id: UInt64 in [1, 2, 3, 4, 6] {
      var request = SplashWire.Request(
        id: id, prompt: input.prompt,
        absoluteDeadline: UInt64((Date().timeIntervalSince1970 + 180) * 1e6),
        remainingDeadline: 180_000_000)
      request.maxOutput = input.maxOutput
      request.generationTokens = input.generationTokens
      if id == 6 {
        var oversized = request
        oversized.id = 5
        oversized.prompt = Array(repeating: 1, count: Int(helper.ready!.context) + 1)
        try rejects { _ = try helper.generate(oversized) }
      }
      let result = try helper.generate(request, cancelled: { id == 3 })
      if id == 3 {
        try expect(result.done.reason == .cancelled)
      } else {
        try expect(result.done.reason != .cancelled && !result.tokens.isEmpty)
      }
      try json([
        "request": id, "tokens": result.tokens, "finish": result.done.reason.rawValue,
        "firstTokenSeconds": result.firstTokenSeconds as Any? ?? NSNull(),
        "seconds": result.requestSeconds, "decodeMicros": result.done.decodeMicros,
        "prefillMicros": result.done.prefillMicros, "bounded": result.done.bounded,
        "completionTokens": result.done.completion, "promptTokens": result.done.prompt,
        "drafted": result.done.drafted, "accepted": result.done.accepted,
      ])
    }
    let status = try helper.status(id: 100, release: true)
    try json(["status": try JSONSerialization.jsonObject(with: status)])
    return true
  }
  return false
}
