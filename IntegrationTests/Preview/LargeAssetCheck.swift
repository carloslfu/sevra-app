import Foundation
import SevraCore
import SevraPreviewUI

private final class HashProgress: @unchecked Sendable {
  private let lock = NSLock()
  private var value: Int64 = 0
  func record(_ bytes: Int64) {
    lock.lock()
    value = bytes
    lock.unlock()
  }
  func read() -> Int64 {
    lock.lock()
    defer { lock.unlock() }
    return value
  }
}

/// Real large-file IO through the production preview session, without a renderer
/// or a model. The parent samples lifetime peak footprint before releasing us.
@MainActor func checkLargePreview(at root: URL) async throws {
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
  let source = root.appendingPathComponent("Synthetic.bin")
  defer { try? FileManager.default.removeItem(at: source) }
  let size: Int64 = 2_148_532_224
  FileManager.default.createFile(atPath: source.path, contents: nil)
  let handle = try FileHandle(forWritingTo: source)
  try handle.write(contentsOf: Data("Synthetic sparse file for verification, not media.\n".utf8))
  try handle.seek(toOffset: UInt64(size - 1))
  try handle.write(contentsOf: Data([0]))
  try handle.synchronize()
  try handle.close()
  let book = try Workbook.create(
    at: root.appendingPathComponent("Large.sevra"), title: "Large preview")
  let item = try await Task.detached { try book.importFile(source, linked: true) }.value
  let assetID = item.assetID!
  let revision = try book.revision()
  let expected = try book.asset(assetID)
  let session = AssetPreviewSession()
  let cancelledBytes = HashProgress()
  let cancelAt: Int64 = 8_388_608
  let cancelled = await session.load { token, progress in
    try await Task.detached {
      try book.assetURL(assetID, cancellation: token) { bytes, total in
        cancelledBytes.record(bytes)
        progress(bytes, total)
        if bytes >= cancelAt { token.cancel() }
      }
    }.value
  }
  try require(
    !cancelled && session.file == nil && !session.loading && cancelledBytes.read() == cancelAt,
    "preview_check", "Large-file cancellation read beyond its bounded chunk or published a URL.")
  let completeBytes = HashProgress()
  let completed = await session.load { token, progress in
    try await Task.detached {
      try book.assetURL(assetID, cancellation: token) { bytes, total in
        completeBytes.record(bytes)
        progress(bytes, total)
      }
    }.value
  }
  try require(
    completed && session.file == source && completeBytes.read() == size && session.failure == nil,
    "preview_check", "Retry did not verify every byte of the original file.")

  let changed = try FileHandle(forWritingTo: source)
  try changed.seek(toOffset: UInt64(size / 2))
  try changed.write(contentsOf: Data("CHANGED".utf8))
  try changed.close()
  let acceptedChanged = await session.load { token, progress in
    try await Task.detached {
      try book.assetURL(assetID, cancellation: token, progress: progress)
    }.value
  }
  try require(
    !acceptedChanged && session.file == nil
      && session.failure?.contains("original has changed") == true,
    "preview_check", "A same-size changed original was presented as the saved evidence.")
  try require(
    try book.revision() == revision && book.asset(assetID).hash == expected.hash
      && book.asset(assetID).bytes == size,
    "preview_check", "Verification changed the saved workbook evidence.")
  print(
    try Value.object([
      "passed": .bool(true), "assetBytes": .string(String(size)),
      "cancelledAfterBytes": .string(String(cancelledBytes.read())),
      "fullyVerifiedBytes": .string(String(completeBytes.read())),
      "changedOriginalRefused": .bool(true), "workbookUnchanged": .bool(true),
      "scope": .string(
        "Large linked-file verification and cancellation, without media rendering or inference."),
    ]).json())
  fflush(stdout)
  try require(readLine() == "finish", "preview_check", "Missing measurement acknowledgement.")
}
