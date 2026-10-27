import CryptoKit
import Foundation
import ZIPFoundation

public struct ArchiveMember: Codable, Identifiable, Sendable {
  public var id: String { path }
  public let path: String
  public let bytes: UInt64
}

extension Workbook {
  public func archiveMembers(_ sourceID: String, cancellation: Cancellation = .init()) throws
    -> [ArchiveMember]
  {
    let source = try item(sourceID)
    guard let assetID = source.assetID else {
      throw SevraError("archive", "Choose an included or linked ZIP file.")
    }
    let file = try assetURL(assetID, verify: true, cancellation: cancellation)
    try require(
      file.pathExtension.lowercased() == "zip", "archive",
      "Member selection currently supports ZIP files.")
    let archive = try Archive(url: file, accessMode: .read)
    var entries: [ArchiveMember] = []
    var names = Set<String>()
    var count = 0
    for entry in archive {
      try cancellation.check()
      count += 1
      try require(count <= 10_000, "archive_limit", "ZIP listing is limited to 10,000 entries.")
      let parts = entry.path.split(separator: "/", omittingEmptySubsequences: false)
      try require(
        entry.path.utf8.count <= 1024 && parts.count <= 16 && !entry.path.hasPrefix("/")
          && !entry.path.contains("\\") && !entry.path.contains("\0") && !parts.contains("..")
          && !parts.contains(".") && !parts.dropLast().contains(""), "archive_path",
        "This archive contains an unsafe member path.")
      try require(entry.type != .symlink, "archive_path", "Archive symlinks are not supported.")
      let name = entry.path.precomposedStringWithCanonicalMapping.lowercased().trimmingCharacters(
        in: CharacterSet(charactersIn: "/"))
      try require(
        names.insert(name).inserted, "archive_path",
        "The archive contains duplicate or case-conflicting names.")
      if entry.type == .file {
        entries.append(.init(path: entry.path, bytes: UInt64(entry.uncompressedSize)))
      }
    }
    return entries.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
  }

  @discardableResult public func includeArchiveMembers(
    _ sourceID: String, paths: [String], cancellation: Cancellation = .init()
  ) throws -> [Item] {
    try require(
      !paths.isEmpty && paths.count <= 50 && Set(paths).count == paths.count, "archive_limit",
      "Choose 1 to 50 distinct files.")
    let available = try archiveMembers(sourceID, cancellation: cancellation)
    let sizes = Dictionary(uniqueKeysWithValues: available.map { ($0.path, $0.bytes) })
    var total: UInt64 = 0
    for path in paths {
      guard let bytes = sizes[path] else {
        throw SevraError("archive_member", "A selected member is missing.")
      }
      try require(
        bytes <= 1_000_000_000 - total, "archive_limit",
        "Selected ZIP members exceed the 1 GB expanded intake limit.")
      total += bytes
    }
    let source = try item(sourceID)
    let assetID = source.assetID!
    let archive = try Archive(url: assetURL(assetID, cancellation: cancellation), accessMode: .read)
    let folder = url.appendingPathComponent("staging/archive-" + identifier())
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    var imported: [Item] = []
    for path in paths {
      try cancellation.check()
      guard let entry = archive[path] else {
        throw SevraError("archive_member", "The ZIP changed during intake.")
      }
      try require(
        entry.uncompressedSize < 1_000_000
          || (entry.compressedSize > 0 && entry.uncompressedSize / entry.compressedSize <= 1000),
        "archive_limit", "ZIP member compression ratio exceeds the intake limit.")
      let memberFolder = folder.appendingPathComponent(identifier())
      try FileManager.default.createDirectory(at: memberFolder, withIntermediateDirectories: true)
      let target = memberFolder.appendingPathComponent(URL(fileURLWithPath: path).lastPathComponent)
      let progress = Progress()
      cancellation.track(progress)
      defer { cancellation.untrack(progress) }
      let crc = try archive.extract(entry, to: target, progress: progress)
      try require(crc == entry.checksum, "archive_checksum", "A ZIP member failed its checksum.")
      let digest = SHA256.hash(data: Data((sourceID + "\n" + path).utf8)).map {
        String(format: "%02x", $0)
      }.joined()
      if try asset(assetID).mode == "linked" {
        _ = try assetURL(assetID, verify: true, cancellation: cancellation)
      }
      let member = try importFile(
        target, origin: "Member " + path + " in " + source.title, cancellation: cancellation,
        token: "archive-member-" + digest, inputs: [sourceID])
      imported.append(member)
      // Completed members remain durable on cancellation. A retry reuses their identity.
      try resumeIntake(member.id, cancellation: cancellation)
    }
    if try asset(assetID).mode == "linked" {
      _ = try assetURL(assetID, verify: true, cancellation: cancellation)
    }
    return imported
  }
}
