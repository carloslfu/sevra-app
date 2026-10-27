import Darwin
import Foundation
import SevraAI
import SevraCore
import SevraNativeAI
import SevraProduct
import SevraSplash
import SevraSplashText

#if !SEVRA_NATIVE_CANDIDATE
  import SevraBaseline
#endif

private func helperPIDs() throws -> [Int32] {
  let process = Process()
  process.executableURL = URL(fileURLWithPath: "/bin/ps")
  process.arguments = ["-ww", "-axo", "pid=,ppid=,comm="]
  let pipe = Pipe()
  process.standardOutput = pipe
  try process.run()
  let data = pipe.fileHandleForReading.readDataToEndOfFile()
  process.waitUntilExit()
  try expect(process.terminationStatus == 0, "Could not inspect helper process lifetime")
  return String(decoding: data, as: UTF8.self).split(separator: "\n").compactMap { line in
    let fields = line.split(maxSplits: 2, whereSeparator: { $0.isWhitespace })
    guard fields.count == 3, Int32(fields[1]) == getpid(), fields[2].hasSuffix("/splash") else {
      return nil
    }
    return Int32(fields[0])
  }
}
private func checkReleased(_ pids: [Int32], native: Bool) throws {
  try expect(!native || !pids.isEmpty, "No loaded helper was observed before pressure")
  for pid in pids {
    try expect(kill(pid, 0) == -1 && errno == ESRCH, "Native helper survived release")
  }
  let lock = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
    "Library/Application Support/Sevra/inference.lock")
  let fd = Darwin.open(lock.path, O_RDWR | O_NOFOLLOW | O_CLOEXEC)
  try expect(fd >= 0, "Inference lease is missing")
  defer { Darwin.close(fd) }
  try expect(flock(fd, LOCK_EX | LOCK_NB) == 0, "Inference lease was not released")
  flock(fd, LOCK_UN)
}

/// Inject the same policy event as the app's OS observer, without exhausting RAM.
private actor PressureTrigger {
  let service: ProductAI
  let critical: Bool
  let native: Bool
  var fired = false
  var response: ProductAI.PressureResponse?
  var pids: [Int32] = []
  var failure: String?
  init(_ service: ProductAI, critical: Bool, native: Bool) {
    self.service = service
    self.critical = critical
    self.native = native
  }
  func observe(_ message: String) async {
    guard message == "Thinking locally", !fired else { return }
    fired = true
    do {
      if native { pids = try helperPIDs() }
      try await Task.sleep(nanoseconds: 200_000_000)
      response = await service.handleMemoryPressure(critical: critical)
    } catch { failure = error.localizedDescription }
  }
  func receipt() -> (Bool, ProductAI.PressureResponse?, [Int32], String?) {
    (fired, response, pids, failure)
  }
}

func nativePressureChecks(modelsRoot: String, packagedBin: String) async throws {
  try SplashModelSetup.checkHardware()
  let resources = URL(fileURLWithPath: packagedBin).standardizedFileURL
  let manifest = try Value.parse(
    String(contentsOf: resources.appendingPathComponent("native-runtime.json")))
  try expect(
    manifest["commit"].text == "1744cfafee415fb463b289449cec59a864e768e9", "Unexpected engine")
  let model = NativeWorkbookModel(
    configuration: .init(
      engine: resources.appendingPathComponent("NativeRuntime/engine/splash"),
      engineFiles: manifest["engineFiles"].object.mapValues(\.text),
      grammarLibrary: resources.appendingPathComponent("NativeRuntime/libllguidance.dylib"),
      grammarSHA256: manifest["grammarSHA256"].text,
      modelsRoot: URL(fileURLWithPath: modelsRoot), memoryBytes: 12_884_901_888,
      contextBudget: .init(profile: .evaluation32K), reasoning: .bounded512,
      modelLayout: .installed, contextMaintenanceEnabled: false))
  try await runModelPressureChecks(
    model: model, directory: URL(fileURLWithPath: modelsRoot), native: true)
}

#if !SEVRA_NATIVE_CANDIDATE
  func baselinePressureChecks(modelFolder: String) async throws {
    try await runModelPressureChecks(
      model: LocalModel(), directory: URL(fileURLWithPath: modelFolder), native: false)
  }
#endif

private func runModelPressureChecks(model: any WorkbookInference, directory: URL, native: Bool)
  async throws
{
  let service = ProductAI(qualifying: model)
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(
    "sevra-native-pressure-" + identifier() + ".sevra")
  defer { try? FileManager.default.removeItem(at: root) }
  _ = try Demo.create(at: root)
  let book = try Workbook(root)
  let original = try book.items()
  let ids = Set(original.map(\.id))
  var semanticFailures: [String] = []
  do {
    for critical in [true, false] {
      let trigger = PressureTrigger(service, critical: critical, native: native)
      let token = Cancellation()
      let began = Date()
      var answer: AgentResult?
      var failure: String?
      do {
        answer = try await service.run(
          critical
            ? "What is the current stock of brass bolts? Use the balance tool and cite the evidence. Do not change the workbook."
            : "Reply with the word Ready. Do not change the workbook.",
          workbook: book, modelDirectory: directory, cancellation: token,
          progress: { message in Task { await trigger.observe(message) } })
      } catch { failure = error.localizedDescription }
      let receipt = await trigger.receipt()
      print(
        try Value.object([
          "backend": .string(native ? "native" : "baseline"),
          "pressureInjected": .bool(true), "level": .string(critical ? "critical" : "warning"),
          "seconds": .number(Date().timeIntervalSince(began)),
          "fired": .bool(receipt.0), "response": receipt.1.map { .string($0.rawValue) } ?? .null,
          "helperPIDs": .array(receipt.2.map { .number(Double($0)) }),
          "answer": answer.map { .string($0.answer) } ?? .null,
          "failure": failure.map(Value.string) ?? .null,
          "triggerFailure": receipt.3.map(Value.string) ?? .null,
          "runs": .array(try book.agentRuns()), "messages": try encoded(book.messages()),
        ]).json())
      try expect(receipt.0 && receipt.3 == nil, "Injected pressure did not run")
      if critical {
        try expect(
          receipt.1 == .stopping && token.isCancelled && answer == nil,
          "Critical event did not interrupt")
        try expect(failure?.contains("low on memory") == true, "Critical failure omitted its cause")
        try expect(
          try book.agentRuns().first?["status"].text == "cancelled",
          "Critical job was not cancelled")
      } else {
        try expect(
          receipt.1 == .deferred && !token.isCancelled && failure == nil,
          "Warning interrupted the operation")
        try expect(answer?.state == "complete", "Warning lost successful completion")
        if answer?.answer != "Ready" {
          semanticFailures.append(
            "The warning trial did not follow the new request to reply Ready.")
        }
      }
      try checkReleased(receipt.2, native: native)
      try expect(
        try book.items().filter { ids.contains($0.id) } == original,
        "Pressure changed original business items")
      try expect(try book.verify()["ok"] == .bool(true), "Pressure broke workbook integrity")
      print(
        "PASS injected \(critical ? "critical" : "warning") pressure with actual model: resources released and lease free"
      )
    }
    let result = try await service.run(
      "What is the current stock of brass bolts? Use the balance tool and cite the evidence. Do not change the workbook.",
      workbook: book, modelDirectory: directory)
    try expect(
      result.state == "complete" && result.answer.contains("18") && !result.citations.isEmpty,
      "Fresh request did not recover after pressure release")
    let recoveryPIDs = native ? try helperPIDs() : []
    let released = await service.unload()
    try expect(released, "Recovery model did not unload")
    try checkReleased(recoveryPIDs, native: native)
    print(
      try Value.object([
        "backend": .string(native ? "native" : "baseline"), "recovery": .bool(true),
        "answer": .string(result.answer),
        "steps": .number(Double(result.steps)), "runs": .array(try book.agentRuns()),
        "integrity": try book.verify(),
      ]).json())
    print("PASS fresh actual-model workbook request after both pressure levels and explicit unload")
    print(
      try Value.object([
        "backend": .string(native ? "native" : "baseline"), "lifecyclePassed": .bool(true),
        "requestSemanticsPassed": .bool(semanticFailures.isEmpty),
        "semanticFailures": .array(semanticFailures.map(Value.string)),
      ]).json())
    try expect(
      semanticFailures.isEmpty,
      "Lifecycle passed but request semantics failed: " + semanticFailures.joined(separator: " "))
  } catch {
    _ = await service.unload()
    throw error
  }
}
