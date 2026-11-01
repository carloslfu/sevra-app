import Darwin
import Foundation
import ZIPFoundation

extension Workbook {
  public func export(
    to destination: URL, cancellation: Cancellation = .init(),
    progress: @escaping (String) -> Void = { _ in }
  ) throws {
    try require(
      !FileManager.default.fileExists(atPath: destination.path), "exists",
      "Export destination already exists.")
    let fm = FileManager.default
    let temp = fm.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(
      "sevra-export-" + identifier())
    try fm.createDirectory(at: temp, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: temp) }
    let snapshot = temp.appendingPathComponent("workbook")
    try fm.createDirectory(at: snapshot, withIntermediateDirectories: true)
    try synchronized {
      // The backup captures one revision; assets are immutable and retained after unlock.
      try db.backup(
        to: snapshot.appendingPathComponent("workbook.sqlite"), cancellation: cancellation)
      try fm.copyItem(
        at: url.appendingPathComponent("manifest.json"),
        to: snapshot.appendingPathComponent("manifest.json"))
    }
    let copy = try Database(snapshot.appendingPathComponent("workbook.sqlite"))
    let assets = try copy.execute("SELECT * FROM assets")
    try Self.requireExportSpace(
      for: assets, database: snapshot.appendingPathComponent("workbook.sqlite"),
      in: [temp, destination.deletingLastPathComponent()])
    for row in assets {
      try cancellation.check()
      if row["mode"]!.text == "included" {
        let relative = row["path"]!.text
        let source = try safePath(relative)
        let target = snapshot.appendingPathComponent(relative)
        progress(row["name"]!.text)
        try fm.createDirectory(
          at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !fm.fileExists(atPath: target.path) {
          try Self.copyStream(source, to: target, cancellation: cancellation)
        }
        try require(
          try Self.hashFile(target, cancellation: cancellation) == row["hash"]!.text, "integrity",
          "An asset changed during export.")
      }
    }
    try copy.execute("UPDATE assets SET bookmark=NULL,path='' WHERE mode='linked'")
    // A copy that cannot reopen is worse than a refusal while the original still stands.
    // The loop above hashed every included file, so this checks the records.
    _ = try Workbook(snapshot, cancellation: cancellation).verify(
      cancellation: cancellation, assets: false)
    try fm.removeItem(at: snapshot.appendingPathComponent(".write-lock"))
    let stagingArchive = destination.deletingLastPathComponent().appendingPathComponent(
      ".sevra-\(identifier()).zip")
    defer { try? fm.removeItem(at: stagingArchive) }
    let archive = try Archive(url: stagingArchive, accessMode: .create)
    guard let files = fm.enumerator(atPath: snapshot.path) else {
      throw SevraError("export", "Cannot enumerate snapshot.")
    }
    for case let path as String in files {
      let file = snapshot.appendingPathComponent(path)
      try cancellation.check()
      guard try file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else {
        continue
      }
      let compressed = ["mp4", "mov", "mp3", "m4a", "jpg", "jpeg", "png", "heic", "zip", "pdf"]
        .contains(file.pathExtension.lowercased())
      let zipProgress = Progress()
      cancellation.track(zipProgress)
      defer { cancellation.untrack(zipProgress) }
      do {
        try archive.addEntry(
          with: path, relativeTo: snapshot, compressionMethod: compressed ? .none : .deflate,
          progress: zipProgress)
      } catch {
        try cancellation.check()
        throw error
      }
    }
    try cancellation.check()
    try require(Self.flush(stagingArchive), "export", "Cannot persist the exported archive.")
    try fm.moveItem(at: stagingArchive, to: destination)
    Self.flush(destination.deletingLastPathComponent())
  }
  /// The snapshot and its archive can share a volume, and media does not compress.
  private static func requireExportSpace(
    for assets: [[String: Value]], database: URL, in folders: [URL]
  ) throws {
    let fm = FileManager.default
    let included = assets.filter { $0["mode"]?.text == "included" }
    var needed = Int64(try database.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0)
    for row in included { needed += Int64(row["bytes"]?.int ?? 0) }
    let volumes = Set(
      try folders.map { try fm.attributesOfItem(atPath: $0.path)[.systemNumber] as? Int ?? 0 })
    if volumes.count == 1 { needed *= 2 }
    for folder in folders {
      let free =
        try folder.resourceValues(forKeys: [.volumeAvailableCapacityKey]).volumeAvailableCapacity
        ?? 0
      try require(
        Int64(free) - needed > 16_777_216, "disk_full",
        "There is not enough free space to export this workbook.")
    }
  }
  public static func openArchive(
    _ archiveURL: URL, at destination: URL, maxBytes: UInt64 = 1_000_000_000_000,
    cancellation: Cancellation = .init()
  ) throws -> Workbook {
    let fm = FileManager.default
    try require(
      !fm.fileExists(atPath: destination.path), "exists",
      "Choose a new destination for the opened workbook.")
    let declared = try ZIPDirectory.entryCount(archiveURL, cancellation: cancellation)
    let archive = try Archive(url: archiveURL, accessMode: .read)
    var paths = Set<String>()
    var total: UInt64 = 0
    var count = 0
    for entry in archive {
      try cancellation.check()
      count += 1
      let parts = entry.path.split(separator: "/", omittingEmptySubsequences: false)
      try require(
        count <= 100_000 && !entry.path.hasPrefix("/") && !entry.path.contains("\\")
          && !parts.contains("..") && !parts.contains(".") && !entry.path.contains("\0"),
        "archive_path", "Archive contains an unsafe path or too many entries.")
      try require(entry.type != .symlink, "archive_path", "Archive symlinks are not supported.")
      try require(
        parts.count <= 12 && entry.path.utf8.count <= 1024 && !parts.dropLast().contains(""),
        "archive_path", "Archive path exceeds the supported bounds.")
      try require(
        entry.uncompressedSize < 1_000_000 || entry.compressedSize > 0,
        "archive_limit", "Invalid compressed entry size.")
      if entry.compressedSize > 0 {
        try require(
          entry.uncompressedSize / entry.compressedSize <= 10_000,
          "archive_limit", "Archive compression ratio exceeds the safety limit.")
      }
      let key = entry.path.precomposedStringWithCanonicalMapping.lowercased().trimmingCharacters(
        in: CharacterSet(charactersIn: "/"))
      try require(
        paths.insert(key).inserted, "archive_path",
        "Archive contains duplicate or case-conflicting paths.")
      try require(
        entry.path == "manifest.json" || entry.path == "workbook.sqlite"
          || entry.path.hasPrefix("assets/"), "archive_path",
        "Archive contains an unexpected workbook entry.")
      try require(
        UInt64(entry.uncompressedSize) <= maxBytes - total, "archive_limit",
        "Expanded workbook exceeds the allowed size.")
      total += UInt64(entry.uncompressedSize)
    }
    guard UInt64(count) == declared else { throw ZIPDirectory.damaged }
    try require(
      paths.contains("manifest.json") && paths.contains("workbook.sqlite"), "format",
      "Archive is missing workbook metadata.")
    let parent = destination.deletingLastPathComponent()
    let free =
      try parent.resourceValues(forKeys: [.volumeAvailableCapacityKey]).volumeAvailableCapacity ?? 0
    try require(
      UInt64(max(0, free)) > total && UInt64(max(0, free)) - total > 16_777_216, "disk_full",
      "There is not enough free space to open this workbook.")
    let staging = parent.appendingPathComponent(".sevra-open-" + identifier())
    try fm.createDirectory(at: staging, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: staging) }
    for entry in archive {
      try cancellation.check()
      let target = staging.appendingPathComponent(entry.path)
      try fm.createDirectory(
        at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
      let zipProgress = Progress()
      cancellation.track(zipProgress)
      defer { cancellation.untrack(zipProgress) }
      let checksum = try extract(entry, from: archive, to: target, progress: zipProgress)
      try require(
        checksum == entry.checksum, "archive_checksum", "Archive entry failed its checksum.")
    }
    try fm.createDirectory(
      at: staging.appendingPathComponent("staging"), withIntermediateDirectories: true)
    let workbook = try Workbook(staging)
    // Export clears external locations, so one here is the archive choosing what
    // this Mac reads or mounts during verification and later use.
    try require(
      try workbook.db.scalar(
        "SELECT count(*) FROM assets WHERE mode='linked' AND (path!='' OR bookmark IS NOT NULL)"
      ).int == 0, "archive_linked", "This archive names files outside itself and was not opened.")
    _ = try workbook.verify(cancellation: cancellation, assets: false)
    // Missing explicit external dependencies are portable and remain visible.
    let includedIDs = try workbook.db.execute("SELECT id FROM assets WHERE mode='included'")
    for row in includedIDs {
      _ = try workbook.assetURL(row["id"]!.text, verify: true, cancellation: cancellation)
    }
    try fm.moveItem(at: staging, to: destination)
    return try Workbook(destination)
  }
  public static func copyStream(_ source: URL, to destination: URL, cancellation: Cancellation)
    throws
  {
    FileManager.default.createFile(atPath: destination.path, contents: nil)
    let input = try FileHandle(forReadingFrom: source)
    let output = try FileHandle(forWritingTo: destination)
    defer {
      try? input.close()
      try? output.close()
    }
    while true {
      let readMore = try autoreleasepool {
        try cancellation.check()
        guard let data = try input.read(upToCount: 1_048_576), !data.isEmpty else { return false }
        try output.write(contentsOf: data)
        return true
      }
      if !readMore { break }
    }
    try output.synchronize()
  }
}
