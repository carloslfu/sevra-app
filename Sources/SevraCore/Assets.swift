import CryptoKit
import Darwin
import Foundation
import UniformTypeIdentifiers

extension Workbook {
  @discardableResult public func importFile(
    _ source: URL, linked: Bool = false, origin: String? = nil,
    cancellation: Cancellation = .init(), progress: @escaping (Int64, Int64) -> Void = { _, _ in }
  ) throws -> Item {
    let info = try source.resourceValues(forKeys: [
      .isRegularFileKey, .fileSizeKey, .isSymbolicLinkKey, .contentModificationDateKey,
    ])
    try require(
      info.isRegularFile == true, "file_type",
      "Choose a regular file. Folder import is not yet supported.")
    let count = Int64(info.fileSize ?? 0)
    if !linked {
      let free =
        try url.resourceValues(forKeys: [.volumeAvailableCapacityKey]).volumeAvailableCapacity ?? 0
      try require(
        Int64(free) > count + 16_777_216, "disk_full",
        "There is not enough room to include this file. Free space or explicitly link it.")
    }
    let temp = url.appendingPathComponent("staging/\(identifier())")
    defer { try? FileManager.default.removeItem(at: temp) }
    let read = try FileHandle(forReadingFrom: source)
    defer { try? read.close() }
    var write: FileHandle?
    if !linked {
      FileManager.default.createFile(atPath: temp.path, contents: nil)
      write = try FileHandle(forWritingTo: temp)
    }
    defer { try? write?.close() }
    var sha = SHA256()
    var copied: Int64 = 0
    while true {
      let readMore = try autoreleasepool {
        try cancellation.check()
        guard let data = try read.read(upToCount: 1_048_576), !data.isEmpty else { return false }
        sha.update(data: data)
        try write?.write(contentsOf: data)
        copied += Int64(data.count)
        progress(copied, count)
        return true
      }
      if !readMore { break }
    }
    try require(
      copied == count, "changed_file", "The file changed during import. Please try again.")
    let after = try source.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
    try require(
      after.fileSize == info.fileSize
        && after.contentModificationDate == info.contentModificationDate, "changed_file",
      "The original changed during import. Please retry.")
    try write?.synchronize()
    try write?.close()
    write = nil
    let hash = sha.finalize().map { String(format: "%02x", $0) }.joined()
    let assetID = identifier()
    let ext = source.pathExtension.lowercased().filter { $0.isLetter || $0.isNumber }.prefix(16)
    let relative = "assets/\(hash.prefix(2))/\(hash)" + (ext.isEmpty ? "" : ".\(ext)")
    let bookmark =
      linked
      ? try source.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        .base64EncodedString() : nil
    let media =
      UTType(filenameExtension: source.pathExtension)?.preferredMIMEType
      ?? "application/octet-stream"
    let result = try mutation(
      "import", request: .object(["hash": .string(hash), "linked": .bool(linked)])
    ) {
      try cancellation.check()
      if !linked {
        let dest = try safePath(relative, mayNotExist: true)
        try FileManager.default.createDirectory(
          at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: dest.path) {
          try FileManager.default.moveItem(at: temp, to: dest)
        } else {
          try require(try Self.hashFile(dest) == hash, "integrity", "An included asset is corrupt.")
        }
        let fd = Darwin.open(dest.deletingLastPathComponent().path, O_RDONLY)
        if fd >= 0 {
          _ = fsync(fd)
          close(fd)
        }
      }
      try db.execute(
        "INSERT INTO assets VALUES(?,?,?,?,?,?,?,?,?,?)",
        [
          .string(assetID), .string(source.lastPathComponent),
          .string(linked ? source.path : relative), .string(hash), .number(Double(copied)),
          .string(media), .string(linked ? "linked" : "included"),
          origin.map(Value.string) ?? .null, bookmark.map(Value.string) ?? .null,
          .string(timestamp()),
        ])
      let id = try insertItem(
        category: "source", kind: "document", title: source.lastPathComponent, text: "",
        data: .object(["bytes": .string(String(copied)), "mediaType": .string(media)]),
        meaning: "actual", status: "accepted", scenario: "actual", inputs: [],
        transformation: "import-v1", assetID: assetID)
      try db.execute(
        "INSERT INTO extraction VALUES(?,?,?,?,?)",
        [
          .string(id), .string("queued"), .string("Content extraction pending"),
          .string("native-v1"), .string(timestamp()),
        ])
      return .string(id)
    }
    return try item(result.text)
  }
  public func asset(_ id: String) throws -> Asset {
    try synchronized {
      guard let a = try db.execute("SELECT * FROM assets WHERE id=?", [.string(id)]).first else {
        throw SevraError("not_found", "Asset not found.")
      }
      return Asset(
        id: a["id"]!.text, name: a["name"]!.text, path: a["path"]!.text, hash: a["hash"]!.text,
        bytes: Int64(a["bytes"]!.text) ?? Int64(a["bytes"]!.int ?? 0),
        mediaType: a["media_type"]!.text, mode: a["mode"]!.text, origin: a["origin"]?.string)
    }
  }
  public func assetURL(_ id: String, verify: Bool = false) throws -> URL {
    try synchronized {
      let a = try asset(id)
      let file: URL
      if a.mode == "included" {
        file = try safePath(a.path)
      } else {
        try require(
          !a.path.isEmpty, "missing_asset",
          "This workbook references an external file. Choose its original to reconnect it.")
        let b = try db.scalar("SELECT bookmark FROM assets WHERE id=?", [.string(id)]).text
        var stale = false
        if let data = Data(base64Encoded: b),
          let resolved = try? URL(
            resolvingBookmarkData: data, options: [.withoutUI], relativeTo: nil,
            bookmarkDataIsStale: &stale)
        {
          file = resolved
        } else {
          file = URL(fileURLWithPath: a.path)
        }
      }
      try require(
        FileManager.default.fileExists(atPath: file.path), "missing_asset",
        "\(a.name) is unavailable. Reconnect or relink its original.")
      if verify || a.mode == "linked" {
        try require(
          try Self.hashFile(file) == a.hash, "changed_asset",
          "The original has changed. Capture it as a new source version.")
      }
      return file
    }
  }
  public func safePath(_ relative: String, mayNotExist: Bool = false) throws -> URL {
    try require(
      !relative.hasPrefix("/") && !relative.split(separator: "/").contains("..")
        && !relative.contains("\\"), "path", "Unsafe package path.")
    let base = url.resolvingSymlinksInPath().standardizedFileURL
    let file = base.appendingPathComponent(relative).standardizedFileURL
    try require(
      file.resolvingSymlinksInPath().path.hasPrefix(base.path + "/"), "path",
      "Package path leaves its workbook.")
    var cursor = file
    while cursor.path != base.path {
      if let info = try? cursor.resourceValues(forKeys: [.isSymbolicLinkKey]),
        info.isSymbolicLink == true
      {
        throw SevraError("path", "Symbolic links are not allowed inside a workbook.")
      }
      cursor.deleteLastPathComponent()
    }
    return file
  }
  public static func hashFile(_ file: URL, cancellation: Cancellation = .init()) throws -> String {
    let handle = try FileHandle(forReadingFrom: file)
    defer { try? handle.close() }
    var sha = SHA256()
    while true {
      let readMore = try autoreleasepool {
        try cancellation.check()
        guard let data = try handle.read(upToCount: 1_048_576), !data.isEmpty else { return false }
        sha.update(data: data)
        return true
      }
      if !readMore { break }
    }
    return sha.finalize().map { String(format: "%02x", $0) }.joined()
  }
  public func verify() throws -> Value {
    try synchronized {
      let check = try db.scalar("PRAGMA integrity_check").text
      try require(check == "ok", "integrity", check)
      try require(
        try db.execute("PRAGMA foreign_key_check").isEmpty, "integrity",
        "Invalid workbook references.")
      var missing: [Value] = []
      for row in try db.execute("SELECT id,name FROM assets") {
        do { _ = try assetURL(row["id"]!.text, verify: true) } catch {
          missing.append(
            .object(["name": row["name"]!, "error": .string(error.localizedDescription)]))
        }
      }
      try db.execute("INSERT INTO search_fts(search_fts,rank) VALUES('integrity-check',1)")
      try db.execute("INSERT INTO names_fts(names_fts,rank) VALUES('integrity-check',1)")
      return .object([
        "database": .string("ok"), "assetIssues": .array(missing), "ok": .bool(missing.isEmpty),
      ])
    }
  }
}
