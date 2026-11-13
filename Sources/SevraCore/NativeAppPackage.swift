import CryptoKit
import Foundation

/// A portable program is inert data until a native host grants its exact saved version access.
public struct NativeAppDataset: Codable, Equatable, Sendable {
  public var title: String
  public var columns: [Column]
  public var writable: Bool
  public var datasetID: String?
  public init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    title = try values.decode(String.self, forKey: .title)
    columns = try values.decode([Column].self, forKey: .columns)
    writable = try values.decodeIfPresent(Bool.self, forKey: .writable) ?? false
    datasetID = try values.decodeIfPresent(String.self, forKey: .datasetID)
  }
  public init(title: String, columns: [Column], writable: Bool = false, datasetID: String? = nil) {
    self.title = title
    self.columns = columns
    self.writable = writable
    self.datasetID = datasetID
  }
}

public struct NativeAppPackage: Codable, Equatable, Sendable {
  public var sdkVersion: Int
  public var name: String
  public var source: String
  public var datasets: [String: NativeAppDataset]
  public init(name: String, source: String, datasets: [String: NativeAppDataset] = [:]) {
    sdkVersion = 1
    self.name = name
    self.source = source
    self.datasets = datasets
  }
  public var digest: String {
    let data = (try? encoded(self).json()) ?? ""
    return SHA256.hash(data: Data(data.utf8)).map { String(format: "%02x", $0) }.joined()
  }
  public func validate() throws {
    try require(sdkVersion == 1, "app_sdk", "This app requires an unsupported Sevra SDK.")
    try require(
      !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && name.utf8.count <= 200,
      "app_package", "Use an app name of 1 to 200 bytes.")
    try require(
      !source.isEmpty && source.utf8.count <= 524_288 && !source.contains("\0"),
      "app_package", "Use bundled JavaScript source up to 512 KiB.")
    try require(datasets.count <= 16, "app_package", "An app can bind up to 16 tables.")
    for (alias, binding) in datasets {
      try require(
        alias.range(of: "^[a-z][a-zA-Z0-9_]{0,63}$", options: .regularExpression) != nil,
        "app_package", "Use short letter-based dataset aliases.")
      try require(
        !binding.title.isEmpty && binding.title.utf8.count <= 200,
        "app_package", "Each table needs a bounded title.")
      try ManagedDatasetSchema.validateColumns(binding.columns)
      try require(
        !binding.columns.isEmpty && binding.columns.count <= 50,
        "app_package", "Declare 1 to 50 columns per binding.")
      if let id = binding.datasetID {
        try require(!id.isEmpty && id.utf8.count <= 256, "app_package", "Invalid bound table ID.")
      }
    }
  }
  public static func load(from url: URL) throws -> Self {
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }
    let data = try handle.read(upToCount: 1_048_577) ?? Data()
    return try decode(data)
  }
  public static func decode(_ data: Data) throws -> Self {
    try require(data.count <= 1_048_576, "app_package", "App package exceeds 1 MiB.")
    try Value.requireDepth(String(decoding: data, as: UTF8.self))
    let package = try JSONDecoder().decode(Self.self, from: data)
    try package.validate()
    return package
  }
}

/// Unforgeable by script. The native owner must hold this object for every operation.
/// Revocation is nonblocking for the UI. Admission and the final commit guard check this grant.
public final class NativeAppAccess: @unchecked Sendable {
  public let spaceID: String
  public let version: Int
  public let package: NativeAppPackage
  public let workbookID: String
  private let physicalID: String
  private let permission: @Sendable () -> Bool
  private let lock = NSRecursiveLock()
  private var enabled = true
  public init(
    workbook: Workbook, space: Space, permission: @escaping @Sendable () -> Bool = { true }
  ) throws {
    guard let package = space.definition.app else {
      throw SevraError("app", "This space is not an app.")
    }
    try package.validate()
    self.spaceID = space.id
    self.version = space.version
    self.package = package
    self.workbookID = workbook.id
    self.physicalID = try Self.physicalIdentity(workbook)
    self.permission = permission
  }
  public static func physicalIdentity(_ book: Workbook) throws -> String {
    let url = book.url.appendingPathComponent("workbook.sqlite").resolvingSymlinksInPath()
    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
    return "\(url.path):\(attributes[.systemNumber] ?? ""):\(attributes[.systemFileNumber] ?? "")"
  }
  public func revoke() {
    lock.lock()
    enabled = false
    lock.unlock()
  }
  func authorized<T>(_ book: Workbook, allowRevokedDraft: Bool = false, _ body: () throws -> T)
    throws -> T
  {
    lock.lock()
    let permitted = enabled || allowRevokedDraft
    lock.unlock()
    try require(
      permitted && (allowRevokedDraft || permission()) && book.id == workbookID
        && Self.physicalIdentity(book) == physicalID, "app_permission", "App access was revoked.")
    let current = try book.space(spaceID)
    try require(
      current.version == version && current.definition.app?.digest == package.digest,
      "app_changed", "This app changed. Review and enable the new version.")
    return try body()
  }
  func binding(_ alias: String, write: Bool = false) throws -> NativeAppDataset {
    guard let binding = package.datasets[alias], binding.datasetID != nil,
      !write || binding.writable
    else {
      throw SevraError("app_permission", "The app has no access to this table or operation.")
    }
    return binding
  }
}

extension Workbook {
  /// Permission labels come from workbook authority, never package-authored display names.
  public func nativeAppTableTitles(_ package: NativeAppPackage) throws -> [String: String] {
    try package.validate()
    return try synchronized {
      try db.readTransaction {
        var titles: [String: String] = [:]
        for (alias, binding) in package.datasets {
          guard let id = binding.datasetID else {
            throw SevraError("app_permission", "This app has an unbound table.")
          }
          let table = try dataset(id)
          try require(
            !table.archived && table.columns == binding.columns, "app_schema",
            "A requested table changed. Update this app before enabling it.")
          titles[alias] = table.title
        }
        return titles
      }
    }
  }

  /// Installs code without evaluating it. Tables and space are captured in one existing transaction.
  @discardableResult public func installNativeApp(
    _ package: NativeAppPackage, spaceID: String = identifier(), expectedVersion: Int? = nil,
    token: String = identifier(), cancellation: Cancellation = .init()
  ) throws -> Space {
    try package.validate()
    let result = try mutation(
      "install_native_app", token: token,
      request: .object([
        "package": try encoded(package), "spaceID": .string(spaceID),
        "expectedVersion": expectedVersion.map { .number(Double($0)) } ?? .null,
      ]), cancellation: cancellation,
      actor: ChangeAttribution.actor ?? .programmatic("Sevra.nativeApp.install")
    ) {
      try insertNativeApp(package, spaceID: spaceID, expectedVersion: expectedVersion)
      return try encoded(space(spaceID))
    }
    return try JSONDecoder().decode(Space.self, from: Data(result.json().utf8))
  }

  /// Shared publication inside an existing captured transaction.
  func insertNativeApp(_ package: NativeAppPackage, spaceID: String, expectedVersion: Int?) throws {
    try package.validate()
    let current = try spaceIfPresent(spaceID)
    try checkSpaceBase(current, expectedVersion: expectedVersion)
    try require(
      current == nil || current?.definition.app != nil, "app_package",
      "Choose an app space to update.")
    var installed = package
    for alias in package.datasets.keys.sorted() {
      var binding = package.datasets[alias]!
      if binding.datasetID == nil {
        binding.datasetID = current?.definition.app?.datasets[alias]?.datasetID
      }
      if let id = binding.datasetID {
        let existing = try dataset(id)
        try require(
          !existing.archived && existing.columns == binding.columns,
          "app_schema", "The bound table does not match the app's declared columns.")
      } else {
        let source = try insertItem(
          category: "source", kind: "observation", title: package.name + ": " + binding.title,
          text: "An empty table created while installing this app.",
          data: .object(["appDigest": .string(package.digest)]),
          meaning: "actual", status: "accepted", scenario: "actual", inputs: [],
          transformation: "native-app-table-v1")
        let id = identifier()
        try insertDataset(
          id: id, title: binding.title, columns: binding.columns, rows: [],
          sourceID: source, inputs: [source], meaning: "actual")
        binding.datasetID = id
      }
      installed.datasets[alias] = binding
    }
    var definition = SpaceDefinition(components: [])
    definition.app = installed
    try publishSpace(id: spaceID, title: package.name, definition: definition, current: current)
  }

  func validateNativeApp(_ app: NativeAppPackage) throws {
    try app.validate()
    for binding in app.datasets.values {
      guard let id = binding.datasetID else {
        throw SevraError("app_schema", "Install the app to bind its tables.")
      }
      _ = try dataset(id)
    }
  }

  public func nativeAppDraft(_ access: NativeAppAccess) throws -> Value {
    try synchronized {
      try access.authorized(self) {
        let key = "native-app-draft:" + access.spaceID + ":" + access.package.digest
        let text = try db.scalar("SELECT value FROM meta WHERE key=?", [.string(key)]).string
        return try text.map(Value.parse) ?? .object([:])
      }
    }
  }
  public func saveNativeAppDraft(_ access: NativeAppAccess, values: Value) throws {
    try require(
      values.object.count <= 256 && values.json().utf8.count <= 65_536,
      "app_draft", "App drafts are limited to 256 values and 64 KiB.")
    try presentationMutation {
      try access.authorized(self, allowRevokedDraft: true) {
        let key = "native-app-draft:" + access.spaceID + ":" + access.package.digest
        try db.execute(
          "INSERT INTO meta(key,value) VALUES(?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value",
          [.string(key), .string(try values.json())])
      }
    }
  }
}
