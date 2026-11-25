import Darwin
import Foundation
import SevraAI
import SevraCore
import SevraNativeAI

/// With the model: an engine started at 8 GiB grows to 12 GiB through a resizing start, which
/// stops and starts it under one lock, and the next request runs on the larger engine. Its sizes
/// are bounded by the memory this Mac reports free before it starts.
func runResizeProbe(configPath: String, output: String) async throws {
  let gibibyte: UInt64 = 1024 * 1024 * 1024
  let config = try Value.parse(String(contentsOfFile: configPath))
  let reclaimable = try expectValue(freeBytes())
  try require(
    reclaimable >= 16 * gibibyte, "model_capacity",
    "The resize check needs 16 GiB free; this Mac has \(reclaimable / gibibyte) GiB.")
  let root = URL(fileURLWithPath: output)
  try require(!FileManager.default.fileExists(atPath: output), "fixture", "Output exists")
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  let models = URL(fileURLWithPath: config["modelsRoot"].text)
  let pin = try Value.parse(String(contentsOfFile: "integration/splash.json"))
  let guidance = try Value.parse(String(contentsOfFile: ".build/llguidance-receipt.json"))
  let starts = Counter()
  let choice = NativeWorkbookModel.Configuration.MemoryChoice(
    rule: "resize check", choose: { starts.next() == 0 ? 8 * gibibyte : 12 * gibibyte },
    grows: { $0 < 12 * gibibyte })
  let model = NativeWorkbookModel(
    configuration: .init(
      engine: URL(fileURLWithPath: config["engine"].text),
      engineFiles: Dictionary(
        uniqueKeysWithValues: pin["runtime"]["files"].object.filter { $0.key.hasPrefix("engine/") }
          .map { (String($0.key.dropFirst(7)), $0.value.text) }),
      grammarLibrary: URL(fileURLWithPath: config["grammarLibrary"].text),
      grammarSHA256: guidance["librarySHA256"].text, modelsRoot: models,
      memoryBytes: 12 * gibibyte, memoryChoice: choice,
      contextBudget: .init(profile: .evaluation64K), reasoning: .bounded512,
      modelLayout: .installed))
  var outcome: [String: Value] = [:]
  do {
    let first = await model.prewarm(directory: models, cancellation: .init(), progress: { _ in })
    let kept = await model.prewarm(directory: models, cancellation: .init(), progress: { _ in })
    let keptStarts = starts.value
    let resized = await model.prewarm(
      directory: models, size: .growing, cancellation: .init(), progress: { _ in })
    let path = root.appendingPathComponent("Inventory.sevra")
    _ = try Demo.create(at: path)
    let book = try Workbook(path)
    let result = try await WorkbookAgent.run(
      "What is the current stock of brass bolts? Use the balance tool and cite the evidence. Do not change the workbook.",
      workbook: book, modelDirectory: models,
      cancellation: .init(deadlineAfterSeconds: 300), model: model)
    let size = Double(await model.lastMetrics["requestedMemoryBytes"].int ?? 0)
    outcome = [
      "firstStart": .bool(first), "plainStartKept": .bool(kept && keptStarts == 1),
      "resized": .bool(resized), "sizesChosen": .number(Double(starts.value)),
      "requestMemoryGiB": .number(size / Double(gibibyte)), "state": .string(result.state),
      "answerHas18": .bool(result.answer.contains("18")),
    ]
  } catch { outcome["error"] = .string(error.localizedDescription) }
  outcome["released"] = .bool(await model.unload())
  let report = Value.object(outcome)
  try Data((try report.json() + "\n").utf8).write(to: root.appendingPathComponent("result.json"))
  print(try report.json())
  let passed =
    outcome["plainStartKept"] == .bool(true) && outcome["resized"] == .bool(true)
    && outcome["sizesChosen"] == .number(2) && outcome["requestMemoryGiB"] == .number(12)
    && outcome["state"] == .string("complete") && outcome["released"] == .bool(true)
  try require(passed, "resize_check", "The engine did not grow as expected.")
}

private final class Counter: @unchecked Sendable {
  private let lock = NSLock()
  private var count = 0
  var value: Int { lock.withLock { count } }
  func next() -> Int {
    lock.withLock {
      defer { count += 1 }
      return count
    }
  }
}

/// Free, inactive, purgeable and speculative memory, as the app reads it.
private func freeBytes() -> UInt64? {
  var stats = vm_statistics64()
  var count = mach_msg_type_number_t(
    MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
  let result = withUnsafeMutablePointer(to: &stats) {
    $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
      host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
    }
  }
  guard result == KERN_SUCCESS else { return nil }
  return (UInt64(stats.free_count) + UInt64(stats.inactive_count)
    + UInt64(stats.purgeable_count) + UInt64(stats.speculative_count))
    * UInt64(vm_kernel_page_size)
}
