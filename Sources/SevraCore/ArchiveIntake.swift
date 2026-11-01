import CryptoKit
import Foundation
import ZIPFoundation

public struct ArchiveMember: Codable, Identifiable, Sendable {
  public var id: String { path }
  public let path: String
  public let bytes: UInt64
}

/// One line of a ZIP listing, read by the extraction helper.
public struct ZIPMember: Codable, Sendable {
  public let path: String
  public let kind: String
  public let bytes: UInt64
}

/// ZIPFoundation converts a file's 64-bit offsets with trapping casts, and its listing ends
/// silently at an entry it cannot represent, such as a password-protected one. So the central
/// directory is walked first with checked reads, and a listing must then reach the count declared.
enum ZIPDirectory {
  static let damaged = SevraError("archive_format", "This file is damaged or is not a ZIP archive.")

  /// The entries the directory declares, after walking them up to the largest listing Sevra reads.
  static func entryCount(_ file: URL, cancellation: Cancellation) throws -> UInt64 {
    // Read, not mapped: a file that vanishes under a mapping ends the process.
    let input = try FileHandle(forReadingFrom: file)
    defer { try? input.close() }
    let length = Int(try input.seekToEnd())
    var window = Data()
    var windowStart = max(0, length - 66_000)
    func load(_ offset: Int) throws {
      try input.seek(toOffset: UInt64(offset))
      window = try input.read(upToCount: 1 << 20) ?? Data()
      windowStart = offset
    }
    try load(windowStart)
    func integer(_ offset: Int, _ size: Int) throws -> UInt64 {
      guard offset >= 0, offset <= length - size else { throw damaged }
      if offset < windowStart || offset + size > windowStart + window.count { try load(offset) }
      guard offset + size <= windowStart + window.count else { throw damaged }
      let first = window.startIndex + offset - windowStart
      return (0..<size).reversed().reduce(0) { $0 << 8 | UInt64(window[first + $1]) }
    }
    var end = length - 22
    let earliest = max(0, end - 65_535)
    while end >= earliest, try integer(end, 4) != 0x0605_4B50 { end -= 1 }
    guard end >= earliest, try integer(end + 20, 2) + 22 <= UInt64(length - end) else {
      throw damaged
    }
    var count = try integer(end + 10, 2)
    var position = try integer(end + 16, 4)
    // ZIPFoundation prefers a ZIP64 record found immediately before these fields.
    if end > 76, try integer(end - 20, 4) == 0x0706_4B50, try integer(end - 76, 4) == 0x0606_4B50,
      try integer(end - 62, 2) >= 45
    {
      count = try integer(end - 44, 8)
      position = try integer(end - 28, 8)
    }
    var walked: UInt64 = 0
    while walked < min(count, 100_001) {
      if walked % 1024 == 0 { try cancellation.check() }
      guard position <= UInt64(length) else { throw damaged }
      let header = Int(position)
      guard try integer(header, 4) == 0x0201_4B50 else { throw damaged }
      try require(
        try integer(header + 8, 2) & 1 == 0, "archive_encrypted",
        "This ZIP has password-protected files. Remove the password and add it again.")
      let name = Int(try integer(header + 28, 2))
      let extra = Int(try integer(header + 30, 2))
      let comment = Int(try integer(header + 32, 2))
      var compressed = try integer(header + 20, 4)
      var expanded = try integer(header + 24, 4)
      var offset = try integer(header + 42, 4)
      let disk = try integer(header + 34, 2)
      // A field at its maximum continues in the ZIP64 extra field, in this order.
      var field = header + 46 + name
      let fieldsEnd = field + extra
      guard fieldsEnd + comment <= length else { throw damaged }
      while field + 4 < fieldsEnd {
        let size = Int(try integer(field + 2, 2))
        guard field + 4 + size <= fieldsEnd else { break }
        if try integer(field, 2) == 1 {
          var cursor = field + 4
          let wide = [expanded, compressed, offset].filter { $0 == 0xFFFF_FFFF }.count
          if size == wide * 8 + (disk == 0xFFFF ? 4 : 0) {
            func extended(_ value: UInt64) throws -> UInt64 {
              guard value == 0xFFFF_FFFF else { return value }
              defer { cursor += 8 }
              return try integer(cursor, 8)
            }
            expanded = try extended(expanded)
            compressed = try extended(compressed)
            offset = try extended(offset)
          }
          break
        }
        field += 4 + size
      }
      guard compressed <= UInt64(length), offset <= UInt64(length), expanded < 1 << 62 else {
        throw damaged
      }
      position += UInt64(46 + name + extra + comment)
      walked += 1
    }
    return count
  }

  /// Runs in the extraction helper. A trap here costs the helper, not the workbook's process.
  static func members(_ file: URL, cancellation: Cancellation) throws -> [ZIPMember] {
    let count = try entryCount(file, cancellation: cancellation)
    var members: [ZIPMember] = []
    for entry in try Archive(url: file, accessMode: .read) {
      try cancellation.check()
      let kind: String
      switch entry.type {
      case .file: kind = "file"
      case .directory: kind = "directory"
      case .symlink: kind = "symlink"
      }
      members.append(.init(path: entry.path, kind: kind, bytes: UInt64(entry.uncompressedSize)))
      // More than any caller reads. Its own limit refuses the listing.
      if members.count > 100_000 { return members }
    }
    guard UInt64(members.count) == count else { throw damaged }
    return members
  }
}

extension Workbook {
  /// An entry's declared sizes are only what the archive claims. Every limit was checked against
  /// that claim, so a member that inflates past it stops here. The caller's staging folder goes
  /// with whatever was written.
  static func extract(
    _ entry: Entry, from archive: Archive, to target: URL, progress: Progress
  ) throws -> CRC32 {
    guard entry.type == .file else {
      return try archive.extract(entry, to: target, progress: progress)
    }
    FileManager.default.createFile(atPath: target.path, contents: nil)
    let output = try FileHandle(forWritingTo: target)
    defer { try? output.close() }
    var written: UInt64 = 0
    let checksum = try archive.extract(entry, progress: progress) { chunk in
      written += UInt64(chunk.count)
      try require(
        written <= entry.uncompressedSize, "archive_limit",
        "A ZIP member holds more data than it declares, so it was not opened.")
      try output.write(contentsOf: chunk)
    }
    try FileManager.default.setAttributes(entry.fileAttributes, ofItemAtPath: target.path)
    return checksum
  }

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
    var entries: [ArchiveMember] = []
    var names = Set<String>()
    var count = 0
    for entry in try ExtractionWorker().zipMembers(file, cancellation: cancellation) {
      try cancellation.check()
      count += 1
      try require(count <= 10_000, "archive_limit", "ZIP listing is limited to 10,000 entries.")
      let parts = entry.path.split(separator: "/", omittingEmptySubsequences: false)
      try require(
        entry.path.utf8.count <= 1024 && parts.count <= 16 && !entry.path.hasPrefix("/")
          && !entry.path.contains("\\") && !entry.path.contains("\0") && !parts.contains("..")
          && !parts.contains(".") && !parts.dropLast().contains(""), "archive_path",
        "This archive contains an unsafe member path.")
      try require(entry.kind != "symlink", "archive_path", "Archive symlinks are not supported.")
      let name = entry.path.precomposedStringWithCanonicalMapping.lowercased().trimmingCharacters(
        in: CharacterSet(charactersIn: "/"))
      try require(
        names.insert(name).inserted, "archive_path",
        "The archive contains duplicate or case-conflicting names.")
      if entry.kind == "file" { entries.append(.init(path: entry.path, bytes: entry.bytes)) }
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
      let crc = try Self.extract(entry, from: archive, to: target, progress: progress)
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
