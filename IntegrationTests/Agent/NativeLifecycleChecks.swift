import CryptoKit
import Darwin
import Foundation
import SevraAI
import SevraCore
import SevraNativeAI
import SevraSplash

/// Runs as a child with its own home, so the check never touches this Mac's real inference lock.
func checkInferenceLease() throws {
  let home = FileManager.default.temporaryDirectory.appendingPathComponent(
    "sevra-lease-" + identifier())
  try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: home) }
  let child = Process()
  child.executableURL = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
  child.arguments = ["--inference-lease"]
  child.environment = ProcessInfo.processInfo.environment.merging([
    "CFFIXED_USER_HOME": home.path
  ]) { $1 }
  try child.run()
  child.waitUntilExit()
  try expectEqual(child.terminationStatus, 0)
  print("PASS a run that never started a helper frees the inference lock at once")
}

func inferenceLeaseChild() async throws {
  let files = FileManager.default
  let home = files.homeDirectoryForCurrentUser
  guard home.path.contains("sevra-lease-") else { throw SplashError("Expected a private home") }
  let engine = home.appendingPathComponent("engine")
  try files.createDirectory(at: engine, withIntermediateDirectories: true)
  var digests: [String: String] = [:]
  for name in ["splash", "splash.metallib", "host-step.metallib"] {
    let data = Data("#!/bin/sh\nexit 0\n".utf8)
    try data.write(to: engine.appendingPathComponent(name))
    digests[name] = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }
  let model = NativeWorkbookModel(
    configuration: .init(
      engine: engine.appendingPathComponent("splash"), engineFiles: digests,
      grammarLibrary: engine.appendingPathComponent("missing.dylib"),
      grammarSHA256: String(repeating: "0", count: 64), modelsRoot: home,
      memoryBytes: 12 * 1024 * 1024 * 1024, contextBudget: .init(profile: .evaluation32K),
      reasoning: .bounded512, modelLayout: .installed))
  func free() throws -> Bool {
    let lock = home.appendingPathComponent("Library/Application Support/Sevra/inference.lock")
    let descriptor = open(lock.path, O_RDWR)
    guard descriptor >= 0 else { throw SplashError("The lock file is missing") }
    defer { close(descriptor) }
    return flock(descriptor, LOCK_EX | LOCK_NB) == 0
  }
  try await model.beginRun()
  try expectEqual(try free(), false)
  do {
    _ = try await model.respond(
      messages: [InferenceMessage(role: "user", content: "Hello")], directory: home,
      cancellation: Cancellation(), progress: { _ in }, toolScope: .finish, citationIDs: [])
    throw SplashError("Expected a refused start")
  } catch let error as SevraError {
    try expectEqual(error.code, "model_setup")
  }
  await model.endRun()
  try expectEqual(try free(), true)
}

func checkNativeFailures() throws {
  func frame(_ hex: String) throws -> Error {
    let bytes = stride(from: 0, to: hex.count, by: 2).map { offset -> UInt8 in
      let start = hex.index(hex.startIndex, offsetBy: offset)
      return UInt8(hex[start..<hex.index(start, offsetBy: 2)], radix: 16)!
    }
    var decoder = SplashWire.Decoder()
    guard case .error(let failure)? = try decoder.consume(Data(bytes)).first else {
      throw SplashError("Expected a failure frame")
    }
    return failure
  }
  func typed(_ error: Error, stopped: Bool = true) throws -> SevraError {
    guard
      let result = nativeFailure(error, helperStopped: stopped, diagnostic: "no device")
        as? SevraError
    else { throw SplashError("Expected a typed failure") }
    return result
  }
  // From IntegrationTests/Splash/protocol_golden.txt.
  let retry = try typed(
    frame(
      "53504c480b0005014a000000000000000101605400005b000000000000000f000000250000006b765f77726974655f62756467657474686520535344206361636865277320777269746520627564676574206973207370656e74"
    ))
  try expectEqual(retry.code, "model_retry")
  try expectEqual(retry.message.hasSuffix("Try again in about 361 minutes."), true)
  let engine = try typed(
    frame(
      "53504c480b0005013a000000000000000200000000000000000000000000090000001b0000006770755f6661756c744d6574616c20636f6d6d616e6420627566666572206661696c6564"
    ))
  try expectEqual(engine.code, "model_engine")
  try expectEqual(engine.message.contains("gpu_fault"), true)
  try expectEqual(engine.message.hasSuffix("Last engine output: no device"), true)
  try expectEqual(try typed(SplashError("Native engine closed its output")).code, "model_stopped")
  // What the helper survives keeps its own meaning, and so does an already typed error.
  let kept = nativeFailure(
    SplashError("Prompt exceeds native context"), helperStopped: false, diagnostic: "")
  try expectEqual(kept is SplashError, true)
  let refused = nativeFailure(
    SevraError("context_limit", "Too long"), helperStopped: true, diagnostic: "")
  try expectEqual((refused as? SevraError)?.code, "context_limit")
  print("PASS engine and transport failures reach the app typed, with the engine's last line")
}
