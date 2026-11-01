import Darwin
import Foundation
import SevraCore

/// Device permission lives here, never in a portable workbook or archive.
public struct AutomationDeviceGrant: Codable, Equatable, Identifiable, Sendable {
  public var id: String { activationID }
  public let workbookID: String
  public let definitionID: String
  public let activationID: String
  public let generation: Int
  public let sourceID: String
  public let allowAI: Bool
  public let title: String
  public let workbookTitle: String
  public let bookmark: Data
  let physical: AutomationPhysicalIdentity

  /// What a stored entry may hold. A definition title can run to 2,048 bytes, so titles are cut
  /// before they get here.
  fileprivate var isStorable: Bool {
    (1...1_000_000_000).contains(generation) && bookmark.count <= 32_768
      && title.utf8.count <= 1024 && workbookTitle.utf8.count <= 1024
  }
  fileprivate static func storedTitle(_ text: String) -> String {
    var title = text
    while title.utf8.count > 1024 { title.removeLast() }
    return title
  }
}

/// What a saved version's page says about the version enabled on this Mac. Opening an old version
/// while a newer one runs is as likely as the reverse.
public enum AutomationGrantNotice {
  public static func text(enabled: Int?, shown: Int) -> String {
    guard let enabled else {
      return "Another saved version is enabled on this Mac. Enable this version to replace it."
    }
    if enabled == shown { return "This version is enabled on this Mac." }
    return (enabled < shown ? "An older" : "A newer")
      + " saved version is enabled on this Mac. Enable this version to replace it."
  }
}

struct AutomationPhysicalIdentity: Codable, Equatable, Sendable {
  let package: FileIdentity
  let database: FileIdentity
  struct FileIdentity: Codable, Equatable, Sendable {
    let device: String
    let inode: String
    let birthSeconds: String
    let birthNanoseconds: String
    init(_ url: URL, directory: Bool) throws {
      var info = stat()
      try require(
        lstat(url.path, &info) == 0
          && info.st_mode & S_IFMT == (directory ? S_IFDIR : S_IFREG),
        "automation_file",
        "The registered workbook is missing, replaced or linked. Select it again.")
      device = String(info.st_dev)
      inode = String(info.st_ino)
      birthSeconds = String(info.st_birthtimespec.tv_sec)
      birthNanoseconds = String(info.st_birthtimespec.tv_nsec)
    }
  }
  init(_ url: URL) throws {
    try require(
      url.isFileURL && url.standardizedFileURL.path == url.resolvingSymlinksInPath().path,
      "automation_file", "Select a physical workbook without a symbolic-link path.")
    package = try FileIdentity(url, directory: true)
    database = try FileIdentity(url.appendingPathComponent("workbook.sqlite"), directory: false)
  }
}

public final class AutomationDeviceRegistry: @unchecked Sendable {
  private struct Registry: Codable {
    let version: Int
    var grants: [AutomationDeviceGrant]
    /// Entries that cannot be used. They never run, and the next save leaves them out.
    var unreadable = 0
    private enum CodingKeys: String, CodingKey { case version, grants }
    private struct Entry: Decodable {
      let grant: AutomationDeviceGrant?
      init(from decoder: Decoder) throws {
        grant = (try? AutomationDeviceGrant(from: decoder)).flatMap { $0.isStorable ? $0 : nil }
      }
    }
    init(version: Int, grants: [AutomationDeviceGrant]) {
      self.version = version
      self.grants = grants
    }
    init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      version = try container.decode(Int.self, forKey: .version)
      let entries = try container.decode([Entry].self, forKey: .grants)
      grants = entries.compactMap(\.grant)
      unreadable = entries.count - grants.count
    }
  }
  public let directory: URL
  private var file: URL { directory.appendingPathComponent("automations.json") }
  public init(directory: URL) { self.directory = directory.standardizedFileURL }

  public func grants() throws -> [AutomationDeviceGrant] { try locked { try read().grants } }
  /// The usable grants, and how many stored entries could not be used.
  public func inventory() throws -> (grants: [AutomationDeviceGrant], unreadable: Int) {
    try locked {
      let registry = try read()
      return (registry.grants, registry.unreadable)
    }
  }

  /// Only an explicit native Enable calls this, after the exact workbook grant.
  public func register(_ book: Workbook, session: AutomationExecutionSession) throws
    -> AutomationDeviceGrant
  {
    let physical = try AutomationPhysicalIdentity(book.url)
    let state = try book.deviceAutomationScope(session)
    try require(
      state["state"] == .string("armed") && state["generation"].int == session.planning.generation
        && [.string("foreground-drafts-v1"), .string("condition-drafts-v1")].contains(
          state["policy"])
        && state["allowAI"] == .bool(session.allowAI),
      "automation_authority", "This workbook permission was superseded.")
    let definition = try book.applicationDefinition(state["definition_id"].text)
    let grant = AutomationDeviceGrant(
      workbookID: book.id, definitionID: definition.id, activationID: session.planning.activationID,
      generation: session.planning.generation, sourceID: state["source_id"].text,
      allowAI: session.allowAI, title: AutomationDeviceGrant.storedTitle(definition.title),
      workbookTitle: AutomationDeviceGrant.storedTitle(String(book.title.prefix(256))),
      bookmark: try book.url.bookmarkData(
        options: [], includingResourceValuesForKeys: nil,
        relativeTo: nil), physical: physical)
    return try locked {
      var registry = try read()
      try require(
        !registry.grants.contains { $0.workbookID == grant.workbookID && $0.physical != physical },
        "automation_copy",
        "Another physical copy is enabled on this Mac. Pause it before enabling this copy.")
      registry.grants.removeAll { $0.id == grant.id && $0.workbookID == grant.workbookID }
      try require(
        registry.grants.count < 32, "automation_limit", "Enable at most 32 schedules on this Mac.")
      registry.grants.append(grant)
      try write(registry)
      return grant
    }
  }

  /// Compare-and-remove cannot revoke a concurrently replaced registration.
  @discardableResult public func remove(_ grant: AutomationDeviceGrant) throws -> Bool {
    try locked {
      var registry = try read()
      guard let index = registry.grants.firstIndex(of: grant) else { return false }
      registry.grants.remove(at: index)
      try write(registry)
      return true
    }
  }

  public func matches(_ grant: AutomationDeviceGrant, workbook: Workbook) throws -> Bool {
    guard workbook.id == grant.workbookID else { return false }
    return try AutomationPhysicalIdentity(workbook.url) == grant.physical
  }

  public func resolvedURL(_ grant: AutomationDeviceGrant) throws -> URL {
    var stale = false
    let url = try URL(
      resolvingBookmarkData: grant.bookmark,
      options: [.withoutUI, .withoutMounting], relativeTo: nil, bookmarkDataIsStale: &stale)
    // A stale bookmark can follow a rename, but never substitutes for physical identity.
    try require(
      try AutomationPhysicalIdentity(url) == grant.physical, "automation_file",
      "The enabled workbook was copied or replaced. Select and enable the intended workbook again.")
    return url
  }

  public func restore(_ grant: AutomationDeviceGrant, cancellation: Cancellation = .init()) throws
    -> (Workbook, AutomationExecutionSession)
  {
    try validate(grant, cancellation: cancellation)
    let url = try resolvedURL(grant)
    let book = try Workbook(url)
    try require(book.id == grant.workbookID, "automation_file", "The workbook identity changed.")
    let session = try book.restoreDeviceAutomationExecution(
      activationID: grant.activationID, definitionID: grant.definitionID,
      generation: grant.generation, sourceID: grant.sourceID, allowAI: grant.allowAI,
      fence: { try self.validate(grant, url: url, cancellation: cancellation) })
    return (book, session)
  }

  private func validate(
    _ grant: AutomationDeviceGrant, url: URL? = nil, cancellation: Cancellation
  ) throws {
    try cancellation.check()
    try require(
      try grants().contains(grant), "automation_authority",
      "This device permission was removed. Completed work is preserved.")
    if let url {
      try require(
        try AutomationPhysicalIdentity(url) == grant.physical, "automation_file",
        "The workbook moved or was replaced during this operation. Retry after opening it.")
    } else {
      _ = try resolvedURL(grant)
    }
    try cancellation.check()
  }

  private func locked<T>(_ body: () throws -> T) throws -> T {
    try FileManager.default.createDirectory(
      at: directory.deletingLastPathComponent(), withIntermediateDirectories: true)
    // Foundation may apply attributes after creating the directory. Another
    // process can observe that interim mode. mkdir establishes the private leaf
    // atomically, and an existing unsafe directory still refuses below.
    let created = mkdir(directory.path, 0o700)
    try require(
      created == 0 || errno == EEXIST, "automation_registry",
      "Cannot create the private device registry directory.")
    var info = stat()
    try require(
      lstat(directory.path, &info) == 0 && info.st_mode & S_IFMT == S_IFDIR
        && info.st_uid == getuid() && info.st_mode & 0o077 == 0,
      "automation_registry", "The device registry must be an owned private directory.")
    let fd = Darwin.open(
      directory.appendingPathComponent(".lock").path,
      O_CREAT | O_RDWR | O_NOFOLLOW | O_CLOEXEC, 0o600)
    try require(fd >= 0, "automation_registry", "Cannot open the device registry lock.")
    defer { Darwin.close(fd) }
    let deadline = ProcessInfo.processInfo.systemUptime + 3
    while flock(fd, LOCK_EX | LOCK_NB) != 0 {
      try require(
        (errno == EWOULDBLOCK || errno == EAGAIN)
          && ProcessInfo.processInfo.systemUptime < deadline,
        "automation_registry",
        "The device registry is busy. Retry after its current operation finishes.")
      Thread.sleep(forTimeInterval: 0.005)
    }
    defer { flock(fd, LOCK_UN) }
    return try body()
  }

  private func read() throws -> Registry {
    let fd = Darwin.open(file.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
    if fd < 0 && errno == ENOENT { return Registry(version: 1, grants: []) }
    try require(
      fd >= 0, "automation_registry",
      "Cannot read device permissions. The existing file was preserved.")
    let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
    var info = stat()
    try require(
      fstat(fd, &info) == 0 && info.st_mode & S_IFMT == S_IFREG
        && info.st_uid == getuid() && info.st_mode & 0o077 == 0
        && info.st_size <= 2_097_152, "automation_registry",
      "Invalid or oversized device registry. The file was preserved.")
    let data = try handle.read(upToCount: 2_097_153) ?? Data()
    let registry: Registry
    do { registry = try JSONDecoder().decode(Registry.self, from: data) } catch {
      throw SevraError(
        "automation_registry",
        "The device registry is corrupt. Its file was preserved; scheduling is deferred.")
    }
    try require(
      registry.version == 1 && registry.grants.count + registry.unreadable <= 32
        && Set(registry.grants.map(\.id)).count == registry.grants.count,
      "automation_registry", "Unsupported or malformed device permissions. The file was preserved.")
    return registry
  }

  private func write(_ registry: Registry) throws {
    try require(
      registry.grants.allSatisfy(\.isStorable), "automation_registry",
      "This device permission is outside the stored limits.")
    let data = try JSONEncoder().encode(registry)
    try require(data.count <= 2_097_152, "automation_registry", "The device registry is full.")
    let temp = directory.appendingPathComponent(".write-" + UUID().uuidString)
    let fd = Darwin.open(temp.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
    try require(fd >= 0, "automation_registry", "Cannot save device permission.")
    let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
    defer { try? FileManager.default.removeItem(at: temp) }
    try handle.write(contentsOf: data)
    try handle.synchronize()
    try handle.close()
    AutomationRegistryPublicationProbe.observer?(.prepared)
    try require(
      rename(temp.path, file.path) == 0, "automation_registry", "Cannot publish device permission.")
    let parent = Darwin.open(directory.path, O_RDONLY | O_DIRECTORY | O_CLOEXEC)
    try require(
      parent >= 0, "automation_registry", "Cannot synchronize the device registry directory.")
    defer { Darwin.close(parent) }
    try require(
      fsync(parent) == 0, "automation_registry",
      "Device permission durability could not be confirmed.")
    AutomationRegistryPublicationProbe.observer?(.committed)
  }
}

/// Trusted fixture-only barriers. No product path installs an observer.
package enum AutomationRegistryPublicationProbe {
  package enum Stage { case prepared, committed }
  @TaskLocal package static var observer: (@Sendable (Stage) -> Void)?
}
