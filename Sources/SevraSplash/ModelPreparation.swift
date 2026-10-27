import CryptoKit
import Darwin
import Foundation

/// The selected pack, not an arbitrary model catalog. Digests pin original bytes.
public struct SplashModelPack: Codable {
  public struct File: Codable {
    public let path: String
    public let bytes: Int64
    public let sha256: String
    public let destinations: [String]
  }
  public struct Source: Codable {
    public let repository: String
    public let revision: String
    public let files: [File]
  }
  public let schemaVersion: Int
  public let name: String
  public let family: String
  public let target: Source
  public let draft: Source

  public static func selected() throws -> Self {
    guard let url = Bundle.module.url(forResource: "selected-model", withExtension: "json") else {
      throw SplashError("Selected model manifest is missing")
    }
    return try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
  }

  public func validate() throws {
    func hex(_ value: String, _ count: Int) -> Bool {
      value.count == count
        && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }
    guard schemaVersion == 1, safeComponent(name), !family.isEmpty else {
      throw SplashError("Invalid selected model manifest")
    }
    var destinations = Set<String>()
    for source in [target, draft] {
      let repo = source.repository.split(separator: "/", omittingEmptySubsequences: false)
      guard repo.count == 2, repo.allSatisfy({ safeComponent(String($0)) }),
        hex(source.revision, 40), !source.files.isEmpty
      else {
        throw SplashError("Invalid model source identity")
      }
      var names = Set<String>()
      for file in source.files {
        guard safeComponent(file.path), names.insert(file.path).inserted,
          file.bytes > 0, file.bytes <= 64 * 1024 * 1024 * 1024, hex(file.sha256, 64)
        else {
          throw SplashError("Invalid pinned model file")
        }
        for path in file.destinations {
          guard safeRelativePath(path), path != "model.json", destinations.insert(path).inserted
          else {
            throw SplashError("Invalid or duplicated model assembly path")
          }
        }
      }
    }
    guard
      Set([
        "config.json", "target/config.json", "tokenizer/config.json", "tokenizer/tokenizer.json",
        "tokenizer/tokenizer_config.json", "draft/config.json",
      ]).isSubset(of: destinations),
      destinations.contains(where: { $0.hasPrefix("target/") && $0.hasSuffix(".safetensors") }),
      destinations.contains(where: { $0.hasPrefix("draft/") && $0.hasSuffix(".safetensors") })
    else {
      throw SplashError("Selected model is missing required assembly files")
    }
  }
}

private func safeComponent(_ value: String) -> Bool {
  !value.isEmpty && value != "." && value != ".." && !value.contains("/")
    && !value.contains("\\")
    && !value.unicodeScalars.contains(where: { $0.value < 32 || $0.value == 127 })
}
private func safeRelativePath(_ value: String) -> Bool {
  value.split(separator: "/", omittingEmptySubsequences: false).allSatisfy {
    safeComponent(String($0))
  }
}

/// Matches Splash 1.4.1's immutable text-only MLX-affine assembly contract.
/// This verifies/links original weights; it never changes or deletes their source.
public enum SplashModelPreparation {
  public struct Progress {
    public let file: String
    public let verifiedBytes: Int64
    public let totalBytes: Int64
  }
  private struct Fingerprint: Codable, Equatable {
    let path: String
    let bytes: Int64
    let mtime_ns: Int64
    let ctime_ns: Int64
    let digest: String
  }
  private struct Identity: Codable {
    let repo: String
    let revision: String?
  }
  private struct Record: Codable {
    let version: Int
    let model: String
    let family: String
    let target_format: String
    let vision_format: String
    let sources: [String: Identity]
    let files: [String: Fingerprint]
  }

  public static func prepare(
    pack: SplashModelPack, target: URL, draft: URL, modelsRoot: URL,
    fullVerification: Bool = false, pinnedSources: Bool = false,
    cancelled: () -> Bool = { false }, progress: (Progress) -> Void = { _ in }
  ) throws -> URL {
    try pack.validate()
    let fm = FileManager.default
    let target = target.standardizedFileURL.resolvingSymlinksInPath()
    let draft = draft.standardizedFileURL.resolvingSymlinksInPath()
    try fm.createDirectory(at: modelsRoot, withIntermediateDirectories: true)
    let root = modelsRoot.standardizedFileURL.resolvingSymlinksInPath()
    let lock = try ModelFileLock(
      root.appendingPathComponent(".sevra-prepare.lock"), cancelled: cancelled)
    defer { lock.unlock() }
    let selection = root.appendingPathComponent(pack.name)
    let previous = try? readRecord(selection.appendingPathComponent("model.json"))
    var cached: [String: Fingerprint] = [:]
    for entry in previous?.files.values ?? [:].values { cached[entry.path] = entry }
    var files: [String: Fingerprint] = [:]
    var originals: [String: Fingerprint] = [:]
    let sources = [(pack.target, target), (pack.draft, draft)]
    let total = sources.reduce(Int64(0)) { total, pair in
      total + pair.0.files.filter { !$0.destinations.isEmpty }.reduce(0) { $0 + $1.bytes }
    }
    var verified: Int64 = 0
    for (source, directory) in sources {
      for file in source.files where !file.destinations.isEmpty {
        if cancelled() { throw SplashError("Model preparation cancelled") }
        let url = directory.appendingPathComponent(file.path)
        let entry = try verifyFile(
          url, expected: file, previous: fullVerification ? nil : cached[url.path],
          cancelled: cancelled
        ) { amount in
          progress(.init(file: file.path, verifiedBytes: verified + amount, totalBytes: total))
        }
        verified += file.bytes
        progress(.init(file: file.path, verifiedBytes: verified, totalBytes: total))
        originals[entry.path] = entry
        for path in file.destinations { files[path] = entry }
      }
    }
    // Checking again after hashing prevents publishing a mixture of changed files.
    for entry in originals.values {
      guard try fingerprint(URL(fileURLWithPath: entry.path), digest: entry.digest) == entry else {
        throw SplashError("Model source changed during preparation")
      }
    }
    let record = Record(
      version: 1, model: pinnedSources ? pack.target.repository : target.path,
      family: pack.family, target_format: "mlx-affine", vision_format: "none",
      sources: [
        "target": Identity(
          repo: pinnedSources ? pack.target.repository : target.path,
          revision: pinnedSources ? pack.target.revision : nil),
        "draft": Identity(
          repo: pinnedSources ? pack.draft.repository : draft.path,
          revision: pinnedSources ? pack.draft.revision : nil),
      ], files: files)
    let encoded = try canonicalRecord(record)
    let key = digest(encoded)
    let resolved = root.appendingPathComponent(".resolved", isDirectory: true)
    try fm.createDirectory(at: resolved, withIntermediateDirectories: true)
    let destination = resolved.appendingPathComponent(key, isDirectory: true)
    if fm.fileExists(atPath: destination.path) {
      // Refuse a damaged existing assembly. Never replace one an engine may hold.
      try verifyAssembly(destination, encoded: encoded, files: files)
    } else {
      let stage = resolved.appendingPathComponent(".stage-" + UUID().uuidString, isDirectory: true)
      try fm.createDirectory(at: stage, withIntermediateDirectories: false)
      defer { try? fm.removeItem(at: stage) }
      for (path, entry) in files {
        let link = stage.appendingPathComponent(path)
        try fm.createDirectory(
          at: link.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.createSymbolicLink(atPath: link.path, withDestinationPath: entry.path)
      }
      let recordURL = stage.appendingPathComponent("model.json")
      try encoded.write(to: recordURL, options: .withoutOverwriting)
      let handle = try FileHandle(forWritingTo: recordURL)
      defer { try? handle.close() }
      try handle.synchronize()
      try verifyAssembly(stage, encoded: encoded, files: files)
      if cancelled() { throw SplashError("Model preparation cancelled") }
      try fm.moveItem(at: stage, to: destination)
    }
    if cancelled() { throw SplashError("Model preparation cancelled") }
    // Publish the selection atomically. Refuse to overwrite a real folder or file.
    var st = stat()
    if lstat(selection.path, &st) == 0 && (st.st_mode & S_IFMT) != S_IFLNK {
      throw SplashError("Model selection already exists and is not an assembly link")
    }
    let link = root.appendingPathComponent(".selection-" + UUID().uuidString)
    defer { try? fm.removeItem(at: link) }
    try fm.createSymbolicLink(atPath: link.path, withDestinationPath: destination.path)
    guard rename(link.path, selection.path) == 0 else {
      throw SplashError("Cannot publish model selection")
    }
    return destination
  }

  private static func verifyFile(
    _ url: URL, expected: SplashModelPack.File,
    previous: Fingerprint?, cancelled: () -> Bool, progress: (Int64) -> Void
  ) throws -> Fingerprint {
    let descriptor = open(url.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
    guard descriptor >= 0 else {
      throw SplashError("Missing or unreadable model file: " + expected.path)
    }
    let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
    defer { try? handle.close() }
    var st = stat()
    guard fstat(descriptor, &st) == 0, (st.st_mode & S_IFMT) == S_IFREG,
      st.st_size == expected.bytes
    else { throw SplashError("Model file size mismatch: " + expected.path) }
    let before = makeFingerprint(url, st, expected.sha256)
    if before != previous {
      var hash = SHA256()
      var count: Int64 = 0
      while true {
        if cancelled() { throw SplashError("Model preparation cancelled") }
        let amount: Int = try autoreleasepool {
          let bytes = try handle.read(upToCount: 1024 * 1024) ?? Data()
          hash.update(data: bytes)
          return bytes.count
        }
        if amount == 0 { break }
        count += Int64(amount)
        guard count <= expected.bytes else {
          throw SplashError("Model file grew during verification")
        }
        progress(count)
      }
      guard count == expected.bytes,
        hash.finalize().map({ String(format: "%02x", $0) }).joined() == expected.sha256
      else {
        throw SplashError("Model file hash mismatch: " + expected.path)
      }
    }
    var after = stat()
    guard fstat(descriptor, &after) == 0, makeFingerprint(url, after, expected.sha256) == before,
      try fingerprint(url, digest: expected.sha256) == before
    else {
      throw SplashError("Model file changed during verification: " + expected.path)
    }
    return before
  }

  private static func fingerprint(_ url: URL, digest: String) throws -> Fingerprint {
    var st = stat()
    guard lstat(url.path, &st) == 0, (st.st_mode & S_IFMT) == S_IFREG else {
      throw SplashError("Model source is missing or is not a regular file")
    }
    return makeFingerprint(url, st, digest)
  }
  private static func makeFingerprint(_ url: URL, _ st: stat, _ digest: String) -> Fingerprint {
    Fingerprint(
      path: url.path, bytes: st.st_size,
      mtime_ns: Int64(st.st_mtimespec.tv_sec) * 1_000_000_000 + Int64(st.st_mtimespec.tv_nsec),
      ctime_ns: Int64(st.st_ctimespec.tv_sec) * 1_000_000_000 + Int64(st.st_ctimespec.tv_nsec),
      digest: digest)
  }
  private static func readRecord(_ url: URL) throws -> Record {
    try JSONDecoder().decode(Record.self, from: readRecordBytes(url))
  }
  private static func readRecordBytes(_ url: URL) throws -> Data {
    let fd = open(url.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
    guard fd >= 0 else { throw SplashError("Cannot read model assembly record") }
    let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
    defer { try? handle.close() }
    var st = stat()
    guard fstat(fd, &st) == 0, (st.st_mode & S_IFMT) == S_IFREG,
      st.st_size > 0, st.st_size < 1024 * 1024
    else {
      throw SplashError("Model assembly record is invalid or oversized")
    }
    var data = Data()
    while let bytes = try handle.read(upToCount: 65536), !bytes.isEmpty {
      guard data.count + bytes.count < 1024 * 1024 else {
        throw SplashError("Model assembly record grew during reading")
      }
      data.append(bytes)
    }
    return data
  }
  private static func verifyAssembly(_ url: URL, encoded: Data, files: [String: Fingerprint]) throws
  {
    var st = stat()
    guard lstat(url.path, &st) == 0, (st.st_mode & S_IFMT) == S_IFDIR else {
      throw SplashError("Model assembly is not a directory")
    }
    let recordURL = url.appendingPathComponent("model.json")
    guard try readRecordBytes(recordURL) == encoded else {
      throw SplashError("Model assembly record changed")
    }
    var expected = Set(files.keys).union(["model.json"])
    for path in files.keys {
      var parts = path.split(separator: "/").map(String.init)
      while parts.count > 1 {
        parts.removeLast()
        expected.insert(parts.joined(separator: "/"))
      }
    }
    guard let contents = FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil)
    else {
      throw SplashError("Cannot inspect model assembly")
    }
    for case let entry as URL in contents {
      let name = String(
        entry.standardizedFileURL.path.dropFirst(url.standardizedFileURL.path.count + 1))
      guard expected.remove(name) != nil else {
        throw SplashError("Unexpected file in model assembly: " + name)
      }
    }
    guard expected.isEmpty else { throw SplashError("Incomplete model assembly") }
    for (path, entry) in files {
      let link = url.appendingPathComponent(path)
      guard try FileManager.default.destinationOfSymbolicLink(atPath: link.path) == entry.path,
        try fingerprint(URL(fileURLWithPath: entry.path), digest: entry.digest) == entry
      else {
        throw SplashError("Model assembly source changed: " + path)
      }
    }
  }
  private static func digest(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }
  private static func canonicalRecord(_ record: Record) throws -> Data {
    // Python's json.dumps(sort_keys=True, ensure_ascii=False, indent=2) + newline.
    // JSONEncoder omits nil optionals, whereas upstream requires null revisions.
    let entries: [String: Any] = record.files.mapValues {
      [
        "path": $0.path, "bytes": $0.bytes, "mtime_ns": $0.mtime_ns,
        "ctime_ns": $0.ctime_ns, "digest": $0.digest,
      ]
    }
    let sources: [String: Any] = record.sources.mapValues {
      ["repo": $0.repo, "revision": $0.revision as Any? ?? NSNull()]
    }
    let object: [String: Any] = [
      "version": record.version, "model": record.model,
      "family": record.family, "target_format": record.target_format,
      "vision_format": record.vision_format, "sources": sources, "files": entries,
    ]
    func render(_ value: Any, _ indent: Int) throws -> String {
      if let object = value as? [String: Any] {
        if object.isEmpty { return "{}" }
        let fields = try object.keys.sorted().map { key in
          String(repeating: " ", count: indent + 2) + (try render(key, 0)) + ": "
            + (try render(object[key]!, indent + 2))
        }
        return "{\n" + fields.joined(separator: ",\n") + "\n"
          + String(repeating: " ", count: indent) + "}"
      }
      let bytes = try JSONSerialization.data(
        withJSONObject: value, options: [.fragmentsAllowed, .withoutEscapingSlashes])
      return String(decoding: bytes, as: UTF8.self)
    }
    return Data((try render(object, 0) + "\n").utf8)
  }
}

/// A private per-cache lock, cancellable while another setup operation is active.
final class ModelFileLock {
  private var descriptor: Int32
  init(_ url: URL, cancelled: () -> Bool) throws {
    descriptor = open(url.path, O_CREAT | O_RDWR | O_NOFOLLOW | O_CLOEXEC, 0o600)
    guard descriptor >= 0 else { throw SplashError("Cannot open model preparation lock") }
    let deadline = ProcessInfo.processInfo.systemUptime + 30
    while flock(descriptor, LOCK_EX | LOCK_NB) != 0 {
      if errno != EWOULDBLOCK || cancelled() || ProcessInfo.processInfo.systemUptime >= deadline {
        unlock()
        throw SplashError("Model preparation is busy or cancelled")
      }
      usleep(50_000)
    }
  }
  func unlock() {
    if descriptor >= 0 {
      flock(descriptor, LOCK_UN)
      Darwin.close(descriptor)
      descriptor = -1
    }
  }
  deinit { unlock() }
}
