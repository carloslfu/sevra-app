import CoreServices
import CryptoKit
import Darwin
import Foundation

extension Workbook {
  /// A workbook can hold anything someone sent. macOS checks a quarantined file before it runs,
  /// so a copy that goes to another app carries the same flag as a download.
  public static func quarantineCopy(_ file: URL) throws {
    var copy = file
    var values = URLResourceValues()
    values.quarantineProperties = [
      kLSQuarantineAgentNameKey as String: "Sevra",
      kLSQuarantineTypeKey as String: kLSQuarantineTypeOtherDownload as String,
    ]
    do { try copy.setResourceValues(values) } catch {
      throw SevraError(
        "copy_quarantine",
        "The copy was saved, but macOS could not mark it as a download, so Sevra did not open it. You can find it in the folder you chose."
      )
    }
  }

  /// External editors receive a user-owned copy, never the workbook's evidence.
  /// This validates a destination for a native save panel; copying revalidates it.
  public func assetCopyDestination(_ destination: URL) throws -> URL {
    try require(destination.isFileURL, "path", "Choose a local file destination.")
    let parent = destination.deletingLastPathComponent().resolvingSymlinksInPath()
      .standardizedFileURL
    try require(
      try parent.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true,
      "path", "Choose an existing folder for the copy.")
    let target = parent.appendingPathComponent(destination.lastPathComponent).standardizedFileURL
    let package = url.resolvingSymlinksInPath().standardizedFileURL
    var ancestor = parent
    while true {
      try require(
        ancestor.path != package.path && ancestor.pathExtension.lowercased() != "sevra",
        "path", "Save the copy outside a workbook so its original evidence stays intact.")
      if ancestor.path == "/" { break }
      ancestor.deleteLastPathComponent()
    }
    var info = stat()
    let exists = lstat(target.path, &info) == 0
    let code = errno
    try require(
      !exists, "file_exists", "A file already has this name. Choose a new name for the copy.")
    if code != ENOENT { throw NSError(domain: NSPOSIXErrorDomain, code: Int(code)) }
    return target
  }

  @discardableResult public func copyAsset(
    _ id: String, to destination: URL, cancellation: Cancellation = .init(),
    progress: (Int64, Int64) -> Void = { _, _ in }
  ) throws -> URL {
    try cancellation.check()
    let target = try assetCopyDestination(destination)
    let (asset, source) = try resolvedAsset(id)
    try require(
      try source.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true,
      "file_type", "The original must be a regular file.")
    let parent = target.deletingLastPathComponent()
    let free = try parent.resourceValues(forKeys: [.volumeAvailableCapacityKey])
      .volumeAvailableCapacity
    if let free {
      try require(
        Int64(free) > asset.bytes && Int64(free) - asset.bytes > 16_777_216,
        "disk_full", "There is not enough room for this copy. Choose another folder or free space.")
    }
    let temporary = parent.appendingPathComponent(".sevra-copy-" + identifier())
    let descriptor = Darwin.open(temporary.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
    guard descriptor >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
    let output = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
    defer {
      try? output.close()
      try? FileManager.default.removeItem(at: temporary)
    }
    let input = try FileHandle(forReadingFrom: source)
    defer { try? input.close() }
    var sha = SHA256()
    var copied: Int64 = 0
    while true {
      let more = try autoreleasepool {
        try cancellation.check()
        guard let data = try input.read(upToCount: 1_048_576), !data.isEmpty else { return false }
        copied += Int64(data.count)
        try require(
          copied <= asset.bytes, "changed_asset",
          "The original has changed. Capture it as a new source version.")
        sha.update(data: data)
        try output.write(contentsOf: data)
        progress(copied, asset.bytes)
        return true
      }
      if !more { break }
    }
    try cancellation.check()
    let hash = sha.finalize().map { String(format: "%02x", $0) }.joined()
    try require(
      copied == asset.bytes && hash == asset.hash, "changed_asset",
      "The original has changed. Capture it as a new source version.")
    try output.synchronize()
    try output.close()
    try cancellation.check()
    // Recheck aliases and refuse existing destinations again. RENAME_EXCL also
    // closes the race with another writer creating the destination after this.
    try require(
      try assetCopyDestination(target) == target, "path",
      "The destination folder changed. Please try again.")
    if renamex_np(temporary.path, target.path, UInt32(RENAME_EXCL)) != 0 {
      let code = errno
      if code == EEXIST {
        throw SevraError(
          "file_exists", "A file already has this name. Choose a new name for the copy.")
      }
      throw NSError(domain: NSPOSIXErrorDomain, code: Int(code))
    }
    let folder = Darwin.open(parent.path, O_RDONLY)
    if folder >= 0 {
      _ = fsync(folder)
      close(folder)
    }
    // Publication is complete. A subsequent Stop must not remove the saved copy.
    return target
  }
}
