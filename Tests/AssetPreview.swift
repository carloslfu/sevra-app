import Foundation
import SevraCore

private final class AssetReadResult: @unchecked Sendable {
  private let lock = NSLock()
  private var value = false
  func set(_ result: Bool) {
    lock.lock()
    value = result
    lock.unlock()
  }
  func get() -> Bool {
    lock.lock()
    defer { lock.unlock() }
    return value
  }
}

func checkAssetPreview(at root: URL) {
  check("linked-file verification releases the workbook lock during hashing") {
    let book = try Workbook.create(
      at: root.appendingPathComponent("Preview.sevra"), title: "Preview")
    let source = root.appendingPathComponent("linked-preview.bin")
    try Data(repeating: 0x41, count: 4_194_304).write(to: source)
    let item = try book.importFile(source, linked: true)
    let assetID = item.assetID!
    let done = DispatchSemaphore(value: 0)
    let result = AssetReadResult()
    var readFinishedBeforeHashContinued = false
    _ = try book.assetURL(assetID) { bytes, total in
      guard bytes == 1_048_576 else { return }
      DispatchQueue.global().async {
        result.set((try? book.revision()) != nil)
        done.signal()
      }
      readFinishedBeforeHashContinued =
        total == 4_194_304 && done.wait(timeout: .now() + 2) == .success
    }
    // If the old lock behavior returns, release and join the read before failing.
    if !readFinishedBeforeHashContinued { _ = done.wait(timeout: .now() + 2) }
    try expect(readFinishedBeforeHashContinued && result.get(), "Hashing held the workbook lock")

    let cancel = Cancellation()
    var progress: [Int64] = []
    try refuses("cancelled") {
      _ = try book.assetURL(assetID, cancellation: cancel) { bytes, _ in
        progress.append(bytes)
        cancel.cancel()
      }
    }
    try expect(progress == [1_048_576], "Cancellation read additional file chunks")
    _ = try book.assetURL(assetID)

    let candidate = root.appendingPathComponent("reconnected-preview.bin")
    try FileManager.default.copyItem(at: source, to: candidate)
    let before = try book.revision()
    let cancelledRelink = Cancellation()
    try refuses("cancelled") {
      try book.relinkAsset(assetID, to: candidate, cancellation: cancelledRelink) { _, _ in
        cancelledRelink.cancel()
      }
    }
    try expect(
      try book.asset(assetID).path == source.path && book.revision() == before,
      "Cancelled verification changed the reference")
    try expect(try book.relinkAsset(assetID, to: candidate) == candidate)
    try expect(try book.asset(assetID).path == candidate.path)
    try Data("different".utf8).write(to: candidate)
    try refuses("changed_asset") { _ = try book.assetURL(assetID) }
    try refuses("file_type") { _ = try Workbook.hashFile(root) }
  }
}
