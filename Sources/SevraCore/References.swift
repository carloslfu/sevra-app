import Foundation

public enum ReferenceTargetMode: String, Codable, Sendable { case live, pinned }
public enum ReferenceResolutionState: String, Codable, Sendable { case unresolved, bound, external }

/// Names are lookup hints. Only a selected stable identity establishes a binding.
/// A foreign workbook identity is retained without opening files or the network.
public struct ReferenceTarget: Codable, Equatable, Sendable {
  public let workbookID: String?
  public let mode: ReferenceTargetMode
  public let identity: String
  public init(mode: ReferenceTargetMode, identity: String, workbookID: String? = nil) {
    self.workbookID = workbookID
    self.mode = mode
    self.identity = identity
  }
}

/// Scalar coordinates address a visible label in the exact immutable item body.
/// Nil target preserves an unresolved mention, never a guessed title match.
public struct ReferenceSelection: Codable, Equatable, Sendable {
  public let id: String?
  public let startScalar: Int
  public let scalarCount: Int
  public let lookup: String?
  public let target: ReferenceTarget?
  public init(
    startScalar: Int, scalarCount: Int, target: ReferenceTarget? = nil,
    lookup: String? = nil, id: String? = nil
  ) {
    self.id = id
    self.startScalar = startScalar
    self.scalarCount = scalarCount
    self.lookup = lookup
    self.target = target
  }
}

public struct WorkbookReference: Codable, Identifiable, Equatable, Sendable {
  public let id: String
  public let startScalar: Int
  public let scalarCount: Int
  public let label: String
  public let lookup: String
  public let targetWorkbookID: String?
  public let targetMode: ReferenceTargetMode?
  public let targetLogicalID: String?
  public let targetVersionID: String?
  public let resolution: ReferenceResolutionState
  public var locator: String { "body; scalar=\(startScalar); count=\(scalarCount)" }
}

public struct ReferenceSnapshot: Codable, Equatable, Sendable {
  public let id: String?
  public let originVersionID: String
  public let version: Int
  public let previousID: String?
  public let inheritedFrom: String?
  public let bodyHash: String?
  public let parser: String?
  public let coverage: String
  public let detail: String
  public let sourceID: String?
  public let references: [WorkbookReference]
}

extension Workbook {
  static let referenceLimit = 128
  static let referenceBodyLimit = 1_000_000

  static func validateReferenceIdentity(_ value: String) throws {
    let allowed = CharacterSet(
      charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-")
    try require(
      !value.isEmpty && value.utf8.count <= 256
        && value.unicodeScalars.allSatisfy { allowed.contains($0) },
      "reference_identity", "Use a bounded stable identity, not a name, path or URL.")
  }

  static func referenceSelectionsValue(_ selections: [ReferenceSelection]) throws -> Value {
    try require(
      selections.count <= referenceLimit, "reference_limit", "Too many references in one body.")
    // Preflight before serializing caller-supplied strings into the operation journal.
    for selection in selections {
      if let id = selection.id { try validateReferenceIdentity(id) }
      if let target = selection.target {
        try validateReferenceIdentity(target.identity)
        if let workbookID = target.workbookID { try validateReferenceIdentity(workbookID) }
      }
      try require(
        (selection.lookup?.utf8.count ?? 0) <= 1024, "reference_limit",
        "Reference lookup text is limited to 1024 bytes.")
    }
    return try JSONDecoder().decode(Value.self, from: JSONEncoder().encode(selections))
  }

  /// A nil snapshot is explicit missing coverage. It never means no mentions exist.
  public func referenceSnapshot(
    _ originVersionID: String, snapshotID: String? = nil, cancellation: Cancellation = .init()
  ) throws -> ReferenceSnapshot {
    try synchronized(cancellation: cancellation) {
      try db.budget(cancellation: cancellation, seconds: 3) {
        try db.readTransaction {
          try exactReferenceOrigin(originVersionID)
          return try readReferenceSnapshot(originVersionID, snapshotID: snapshotID)
        }
      }
    }
  }

  func exactReferenceOrigin(_ origin: String) throws {
    try Self.validateReferenceIdentity(origin)
    try require(
      try db.scalar("SELECT count(*) FROM items WHERE id=?", [.string(origin)]).int == 1,
      "reference_origin", "References require an existing exact item version.")
  }

  func currentReferenceSet(_ origin: String) throws -> String? {
    try db.scalar("SELECT set_id FROM reference_heads WHERE origin_id=?", [.string(origin)]).string
  }

  func readReferenceSnapshot(_ origin: String, snapshotID: String?) throws -> ReferenceSnapshot {
    let set = try snapshotID ?? currentReferenceSet(origin)
    guard let set else {
      let coverage = try db.execute(
        "SELECT * FROM reference_coverage WHERE origin_id=?", [.string(origin)]
      ).first
      return ReferenceSnapshot(
        id: nil, originVersionID: origin, version: 0, previousID: nil, inheritedFrom: nil,
        bodyHash: coverage?["body_hash"]?.string, parser: coverage?["parser"]?.string,
        coverage: coverage?["state"]?.text ?? "not_indexed",
        detail: coverage?["detail"]?.text ?? "Reference parsing has not run for this version.",
        sourceID: nil, references: [])
    }
    try Self.validateReferenceIdentity(set)
    guard
      let row = try db.execute(
        "SELECT * FROM reference_sets WHERE id=? AND origin_id=?", [.string(set), .string(origin)]
      ).first
    else {
      throw SevraError("reference_snapshot", "This annotation version does not belong to the item.")
    }
    guard let version = row["version"]?.int, version > 0,
      row["version"] == .number(Double(version))
    else { throw SevraError("integrity", "Invalid reference annotation version.") }
    let bounds = try db.execute(
      "SELECT count(*) AS n,coalesce(sum(length(CAST(label AS BLOB))+length(CAST(lookup_text AS BLOB))+length(CAST(reference_id AS BLOB))+coalesce(length(CAST(target_workbook AS BLOB)),0)+coalesce(length(CAST(target_logical AS BLOB)),0)+coalesce(length(CAST(target_version AS BLOB)),0)),0) AS bytes FROM reference_bindings WHERE set_id=?",
      [.string(set)]
    ).first!
    try require(
      (bounds["n"]?.int ?? Int.max) <= Self.referenceLimit
        && (bounds["bytes"]?.int ?? Int.max) <= 400_000,
      "integrity", "Reference annotations exceed their stored bounds.")
    let references = try db.execute(
      "SELECT * FROM reference_bindings WHERE set_id=? ORDER BY ordinal", [.string(set)]
    ).enumerated().map { index, row in
      try require(
        row["ordinal"] == .number(Double(index)), "integrity",
        "Reference occurrence order is inconsistent.")
      return try decodeReference(row)
    }
    return ReferenceSnapshot(
      id: set, originVersionID: origin, version: version,
      previousID: row["previous_id"]?.string, inheritedFrom: row["inherited_from"]?.string,
      bodyHash: row["body_hash"]?.string, parser: row["parser"]?.string,
      coverage: row["coverage"]!.text, detail: row["detail"]!.text,
      sourceID: row["source_id"]?.string, references: references)
  }

  func decodeReference(_ row: [String: Value]) throws -> WorkbookReference {
    guard let start = row["start_scalar"]?.int, let count = row["scalar_count"]?.int,
      let resolution = ReferenceResolutionState(rawValue: row["resolution"]!.text),
      start >= 0, start <= Self.referenceBodyLimit, count > 0, count <= 1024,
      row["start_scalar"] == .number(Double(start)), row["scalar_count"] == .number(Double(count))
    else { throw SevraError("integrity", "Invalid reference annotation.") }
    let workbook = row["target_workbook"]?.string
    let mode = row["target_mode"]?.string.flatMap(ReferenceTargetMode.init(rawValue:))
    let logical = row["target_logical"]?.string
    let version = row["target_version"]?.string
    let shape =
      resolution == .unresolved
      ? workbook == nil && mode == nil && logical == nil && version == nil
      : workbook != nil && mode != nil
        && (mode == .live ? logical != nil && version == nil : version != nil)
        && (resolution == .bound ? workbook == id && logical != nil : workbook != id)
    try require(shape, "integrity", "Invalid reference target binding.")
    for identity in [row["reference_id"]?.string, workbook, logical, version].compactMap({ $0 }) {
      try require(
        (try? Self.validateReferenceIdentity(identity)) != nil, "integrity",
        "Invalid saved reference identity.")
    }
    return WorkbookReference(
      id: row["reference_id"]!.text, startScalar: start, scalarCount: count,
      label: row["label"]!.text, lookup: row["lookup_text"]!.text,
      targetWorkbookID: workbook, targetMode: mode,
      targetLogicalID: logical, targetVersionID: version, resolution: resolution)
  }

  /// Resolve for navigation only. The returned exact version has not been read,
  /// and a mention grants neither evidence nor business-action authority.
  public func resolveReference(
    _ referenceID: String, originVersionID: String, snapshotID: String? = nil,
    cancellation: Cancellation = .init()
  ) throws -> Value {
    try Self.validateReferenceIdentity(referenceID)
    return try synchronized(cancellation: cancellation) {
      try db.budget(cancellation: cancellation, seconds: 3) {
        try db.readTransaction {
          try exactReferenceOrigin(originVersionID)
          let snapshot = try readReferenceSnapshot(originVersionID, snapshotID: snapshotID)
          guard let reference = snapshot.references.first(where: { $0.id == referenceID }) else {
            throw SevraError(
              "reference_not_found", "The reference is absent from this annotation version.")
          }
          var result: [String: Value] = [
            "referenceID": .string(reference.id), "snapshotID": .string(snapshot.id!),
            "originVersionID": .string(originVersionID), "label": .string(reference.label),
            "locator": .string(reference.locator),
            "resolution": .string(reference.resolution.rawValue),
            "coverage": .string(snapshot.coverage), "destination": .null,
          ]
          guard reference.resolution == .bound else {
            result["detail"] = .string(
              reference.resolution == .external
                ? "This reference belongs to another workbook. It has not been opened."
                : "Choose a target explicitly. A matching name does not establish a binding.")
            return .object(result)
          }
          try require(
            reference.targetWorkbookID == id, "integrity",
            "A local reference changed workbook identity.")
          let column = reference.targetMode == .live ? "h.logical_id" : "i.id"
          let identity =
            reference.targetMode == .live ? reference.targetLogicalID : reference.targetVersionID
          let target = try db.execute(
            "SELECT i.id,i.logical_id,i.version,i.category,i.kind,i.title,i.meaning,i.status,i.scenario,(i.id=h.item_id) AS is_current FROM items i JOIN heads h ON h.logical_id=i.logical_id WHERE \(column)=? \(reference.targetMode == .live ? "AND i.id=h.item_id" : "")",
            [identity.map(Value.string) ?? .null]
          ).first
          result["destination"] = target.map(Value.object) ?? .null
          result["detail"] = .string(
            target == nil
              ? "The saved target is unavailable."
              : "Navigation target only. Inspect this exact version before citing it.")
          return .object(result)
        }
      }
    }
  }

  /// Annotation history is independent of Source/item history and is keyset paged.
  public func referenceHistory(
    _ originVersionID: String, beforeVersion: Int? = nil, limit: Int = 30,
    cancellation: Cancellation = .init()
  ) throws -> Value {
    try require(
      limit > 0 && limit <= 100 && (beforeVersion ?? 1) > 0, "reference_limit",
      "Choose a bounded annotation-history page.")
    return try synchronized(cancellation: cancellation) {
      try db.budget(cancellation: cancellation, seconds: 3) {
        try db.readTransaction {
          try exactReferenceOrigin(originVersionID)
          let rows = try db.execute(
            "SELECT id,version,previous_id,inherited_from,source_id,coverage,created FROM reference_sets WHERE origin_id=? AND version<? ORDER BY version DESC LIMIT ?",
            [
              .string(originVersionID), .number(Double(beforeVersion ?? Int.max)),
              .number(Double(limit + 1)),
            ])
          return .object([
            "versions": .array(rows.prefix(limit).map(Value.object)),
            "nextBeforeVersion": rows.count > limit ? rows[limit - 1]["version"]! : .null,
          ])
        }
      }
    }
  }
}
