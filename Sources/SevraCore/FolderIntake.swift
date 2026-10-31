import Foundation

/// What one explicit pass over a chosen folder would do. Nothing watches the folder, and a file
/// that disappeared from it stays in the workbook.
public struct FolderPlan: Codable, Equatable, Sendable {
  public struct File: Codable, Equatable, Sendable {
    public let relative: String
    public let hash: String
  }
  public let folder: String
  public let added: [File]
  public let changed: [File]
  public let unchanged: Int
  public let missing: [String]
  public var files: [File] { added + changed }
  /// Replays a stopped pass without saving a file twice.
  public func token(_ file: File) -> String {
    Workbook.folderOriginPrefix(folder) + file.relative + "#" + file.hash
  }
  public var summary: String {
    var parts = [
      "\(added.count) new", "\(changed.count) changed", "\(unchanged) already in this workbook",
    ]
    if !missing.isEmpty { parts.append("\(missing.count) no longer in the folder") }
    return parts.joined(separator: ", ")
  }
}

extension Workbook {
  public static let folderFileLimit = 200
  public static let folderByteLimit: Int64 = 2 << 30

  static func folderOriginPrefix(_ folder: String) -> String { "folder:" + folder + "/" }

  /// Compares a folder with what earlier passes saved from it, by relative path and content.
  /// A changed file becomes a new Source beside the earlier one. Reads only.
  public func folderPlan(_ folder: URL, cancellation: Cancellation = .init()) throws -> FolderPlan {
    let root = folder.standardizedFileURL.resolvingSymlinksInPath()
    let keys: Set<URLResourceKey> = [.isRegularFileKey, .fileSizeKey, .isSymbolicLinkKey]
    guard
      let walk = FileManager.default.enumerator(
        at: root, includingPropertiesForKeys: Array(keys),
        options: [.skipsHiddenFiles, .skipsPackageDescendants])
    else { throw SevraError("folder_read", "This folder cannot be read.") }
    var found: [(relative: String, url: URL)] = []
    var bytes: Int64 = 0
    for case let file as URL in walk {
      try cancellation.check()
      let info = try file.resourceValues(forKeys: keys)
      guard info.isRegularFile == true, info.isSymbolicLink != true else { continue }
      let relative = String(file.resolvingSymlinksInPath().path.dropFirst(root.path.count + 1))
      bytes += Int64(info.fileSize ?? 0)
      found.append((relative, file))
      try require(
        found.count <= Self.folderFileLimit, "folder_limit",
        "This folder has more than \(Self.folderFileLimit) files. Nothing was added. Choose a smaller folder."
      )
      try require(
        bytes <= Self.folderByteLimit, "folder_limit",
        "This folder holds more than 2 GB. Nothing was added. Choose a smaller folder.")
    }
    let prefix = Self.folderOriginPrefix(root.lastPathComponent)
    var saved: [String: Set<String>] = [:]
    var hashes = Set<String>()
    try synchronized {
      for row in try db.execute("SELECT origin,hash FROM assets") {
        hashes.insert(row["hash"]!.text)
        // captureIntake prefixes its token, which is how a pass labels each file.
        guard let origin = row["origin"]?.string, origin.hasPrefix("intake:" + prefix),
          let mark = origin.lastIndex(of: "#")
        else { continue }
        let relative = String(origin[origin.index(origin.startIndex, offsetBy: 7 + prefix.count)..<mark])
        saved[relative, default: []].insert(row["hash"]!.text)
      }
    }
    var added: [FolderPlan.File] = []
    var changed: [FolderPlan.File] = []
    var unchanged = 0
    for (relative, url) in found.sorted(by: { $0.relative < $1.relative }) {
      try cancellation.check()
      let hash = try Self.hashFile(url, cancellation: cancellation)
      let file = FolderPlan.File(relative: relative, hash: hash)
      if saved[relative]?.contains(hash) == true || hashes.contains(hash) {
        unchanged += 1
      } else if saved[relative] != nil {
        changed.append(file)
      } else {
        added.append(file)
      }
    }
    let present = Set(found.map(\.relative))
    return FolderPlan(
      folder: root.lastPathComponent, added: added, changed: changed, unchanged: unchanged,
      missing: saved.keys.filter { !present.contains($0) }.sorted())
  }
}
