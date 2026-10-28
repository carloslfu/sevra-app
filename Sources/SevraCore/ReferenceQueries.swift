import Foundation

public enum ReferenceDirection: String, Sendable { case incoming, outgoing }
public enum ReferenceTargetScope: String, Sendable { case logical, exact }
public enum ReferenceContentScope: String, Sendable { case all, body, extracted }

extension Workbook {
  // Metadata only. A navigation result cannot be used as a read/citation receipt.
  static let referenceMetadata =
    "i.id,i.logical_id,i.version,i.category,i.kind,substr(i.title,1,1024) AS title,i.meaning,i.status,i.scenario,(i.id=h.item_id) AS is_current"

  /// One-hop, deduplicated discovery over saved bindings. This owner-facing API
  /// does not grant a model access to a conversation or broaden its read scope.
  public func referenceLinks(
    _ exactVersionID: String, direction: ReferenceDirection = .outgoing,
    targetScope: ReferenceTargetScope = .logical, historicalOrigins: Bool = false,
    contentScope: ReferenceContentScope = .all,
    kind: String? = nil, meaning: String? = nil, status: String? = nil, scenario: String? = nil,
    limit: Int = 20, cursor: String? = nil, cancellation: Cancellation = .init(),
    deadlineSeconds: TimeInterval = 3, businessOnly: Bool = false
  ) throws -> Value {
    try require(limit > 0 && limit <= 50, "reference_limit", "Choose 1 to 50 reference results.")
    try require(
      deadlineSeconds.isFinite && deadlineSeconds <= 3, "reference_limit",
      "Reference queries have a maximum three-second deadline.")
    let filters = [
      ("kind", kind), ("meaning", meaning), ("status", status), ("scenario", scenario),
    ]
    for (_, value) in filters {
      try require(
        (value?.utf8.count ?? 0) <= 256, "reference_limit",
        "Reference filters are limited to 256 bytes.")
    }
    return try synchronized(cancellation: cancellation) {
      try db.budget(cancellation: cancellation, seconds: deadlineSeconds) {
        try db.readTransaction {
          try exactReferenceOrigin(exactVersionID)
          let anchor = try db.execute(
            "SELECT \(Self.referenceMetadata) FROM items i JOIN heads h ON h.logical_id=i.logical_id WHERE i.id=?",
            [.string(exactVersionID)]
          ).first!
          try require(
            !businessOnly || !["request", "annotation"].contains(anchor["kind"]!.text),
            "reference_scope",
            "Use scoped conversation history for requests. Technical annotations are not business evidence."
          )
          let revision = try revision()
          let journal = try db.execute(
            "SELECT rowid,id,revision FROM operations ORDER BY rowid DESC LIMIT 1"
          ).first
          let identity = try Value.object([
            "workbook": .string(id), "origin": .string(exactVersionID),
            "direction": .string(direction.rawValue),
            "targetScope": .string(targetScope.rawValue),
            "historicalOrigins": .bool(historicalOrigins),
            "kind": kind.map(Value.string) ?? .null, "meaning": meaning.map(Value.string) ?? .null,
            "status": status.map(Value.string) ?? .null,
            "scenario": scenario.map(Value.string) ?? .null,
            "parser": .string(InlineReferenceParser.identity),
            "contentScope": .string(contentScope.rawValue), "queryVersion": .number(2),
            "businessOnly": .bool(businessOnly),
          ]).json()
          var after: Value = direction == .incoming ? .string("") : .number(-1)
          if let cursor {
            guard cursor.utf8.count <= 8192, let data = Data(base64Encoded: cursor),
              let token = try? JSONDecoder().decode(Value.self, from: data)
            else { throw SevraError("cursor", "Invalid reference cursor.") }
            try require(
              token["query"].text == identity
                && searchCursorIsCurrent(token, revision: revision, journal: journal),
              "stale_cursor", "The workbook or reference query changed. Start a fresh page.")
            after = token["after"]
            if direction == .incoming {
              guard let value = after.string else {
                throw SevraError("cursor", "Invalid reference position.")
              }
              try Self.validateReferenceIdentity(value)
            } else {
              guard let value = after.int, value >= 0, value < Self.referenceLimit * 2,
                after == .number(Double(value))
              else { throw SevraError("cursor", "Invalid reference position.") }
            }
          }
          let results: [(Value, Value)]
          if direction == .incoming {
            let body =
              contentScope == .extracted
              ? []
              : try incomingReferenceLinks(
                anchor, targetScope: targetScope, historical: historicalOrigins, filters: filters,
                after: after, limit: limit, cancellation: cancellation)
            let file =
              contentScope == .body
              ? []
              : try incomingFileReferenceLinks(
                anchor, targetScope: targetScope, historical: historicalOrigins, filters: filters,
                after: after, limit: limit, cancellation: cancellation)
            var unique: [String: Value] = [:]
            for (value, key) in body + file {
              if let existing = unique[key.text] {
                var hit = existing.object
                hit["mentionCount"] = .number(
                  Double((existing["mentionCount"].int ?? 0) + (value["mentionCount"].int ?? 0)))
                hit["discoveryScopes"] = .array([.string("item_body"), .string("extracted_text")])
                unique[key.text] = .object(hit)
              } else {
                unique[key.text] = value
              }
            }
            results = unique.keys.sorted().map { (unique[$0]!, .string($0)) }
          } else {
            results = try outgoingReferenceLinks(
              exactVersionID, filters: filters, after: after.int ?? -1, contentScope: contentScope,
              cancellation: cancellation, businessOnly: businessOnly)
          }
          let page = Array(results.prefix(limit))
          let next: Value
          if results.count > limit, let last = page.last {
            next = .string(
              Data(
                try Value.object([
                  "query": .string(identity), "revision": .number(Double(revision)),
                  "journal": journal.map(Value.object) ?? .null,
                  "after": last.1,
                ]).json().utf8
              ).base64EncodedString())
          } else {
            next = .null
          }
          return .object([
            "direction": .string(direction.rawValue), "anchor": .object(anchor),
            "hits": .array(page.map { $0.0 }), "nextCursor": next,
            "discoveryReason": .string("mention"), "scope": .string(contentScope.rawValue),
            "fileCoverage": try fileReferenceCoverageStatus(exactVersionID),
            "originCoverage": .string(
              try readReferenceSnapshot(exactVersionID, snapshotID: nil).coverage),
            "notice": .string(
              "Saved body and retained extracted-text mentions only. Unsupported syntax, embedded hyperlinks, unindexed versions and unextracted content can contain other mentions. A mention establishes no business relationship, acceptance or action authority. Read the exact version before citing it."
            ),
          ])
        }
      }
    }
  }

  private func incomingReferenceLinks(
    _ anchor: [String: Value], targetScope: ReferenceTargetScope, historical: Bool,
    filters: [(String, String?)], after: Value, limit: Int, cancellation: Cancellation
  ) throws -> [(Value, Value)] {
    var predicate = "r.target_workbook=? AND r.target_logical=? AND r.resolution='bound'"
    var args: [Value] = [.string(id), anchor["logical_id"]!]
    if !historical { predicate += " AND r.current_origin=1" }
    if targetScope == .exact {
      predicate += " AND (r.target_version=? OR (r.target_mode='live' AND ?=1))"
      args += [anchor["id"]!, anchor["is_current"]!]
    }
    var metadataFilters = " AND i.kind NOT IN ('request','annotation')"
    var filterArgs: [Value] = []
    for (column, value) in filters {
      if let value {
        metadataFilters += " AND i.\(column)=?"
        filterArgs.append(.string(value))
      }
    }
    let index = historical ? "reference_incoming_history" : "reference_incoming_current"
    let origins = try db.execute(
      "SELECT DISTINCT r.origin_id FROM reference_index r INDEXED BY \(index) JOIN items i ON i.id=r.origin_id WHERE \(predicate) \(metadataFilters) AND r.origin_id>? ORDER BY r.origin_id LIMIT ?",
      args + filterArgs + [after, .number(Double(limit + 1))])
    return try origins.map { row in
      try cancellation.check()
      let origin = row["origin_id"]!
      let metadata = try db.execute(
        "SELECT \(Self.referenceMetadata) FROM items i JOIN heads h ON h.logical_id=i.logical_id WHERE i.id=?",
        [origin]
      ).first!
      let occurrences = try db.execute(
        "SELECT b.*,r.ordinal FROM reference_index r JOIN reference_bindings b ON b.set_id=r.set_id AND b.reference_id=r.reference_id WHERE \(predicate) AND r.origin_id=? ORDER BY r.ordinal LIMIT 129",
        args + [origin])
      try require(
        !occurrences.isEmpty && occurrences.count <= Self.referenceLimit, "integrity",
        "Invalid indexed reference occurrences.")
      let first = try decodeReference(occurrences[0])
      return (
        .object([
          "evidence": .object(metadata), "mentionCount": .number(Double(occurrences.count)),
          "firstReferenceID": .string(first.id), "snapshotID": occurrences[0]["set_id"]!,
          "label": .string(first.label), "locator": .string(first.locator),
          "discoveryReason": .string("mention"), "snapshotKind": .string("body"),
          "discoveryScopes": .array([.string("item_body")]),
        ]), origin
      )
    }
  }

  private func outgoingReferenceLinks(
    _ origin: String, filters: [(String, String?)], after: Int, contentScope: ReferenceContentScope,
    cancellation: Cancellation, businessOnly: Bool
  ) throws -> [(Value, Value)] {
    let snapshot = try readReferenceSnapshot(origin, snapshotID: nil)
    var groups: [String: (Value, Int, Int)] = [:]
    var occurrences: [(WorkbookReference, Value, String, String)] = []
    if contentScope != .extracted {
      occurrences = snapshot.references.map {
        ($0, snapshot.id.map(Value.string) ?? .null, $0.locator, "body")
      }
    }
    if contentScope != .body, let file = try fileReferenceSet(origin) {
      for row in try fileReferenceRows(file) {
        let reference = try decodeReference(row)
        occurrences.append(
          (
            reference, file["id"]!,
            row["source_locator"]!.text
              + "; scalar=\(reference.startScalar); count=\(reference.scalarCount)", "extracted"
          ))
      }
    }
    for (ordinal, occurrence) in occurrences.enumerated() {
      let (reference, setID, locator, scope) = occurrence
      try cancellation.check()
      var destination: [String: Value]?
      if reference.resolution == .bound {
        try require(
          reference.targetWorkbookID == id, "integrity",
          "A local reference changed workbook identity.")
        let predicate =
          reference.targetMode == .live ? "i.id=h.item_id AND i.logical_id=?" : "i.id=?"
        destination = try db.execute(
          "SELECT \(Self.referenceMetadata) FROM items i JOIN heads h ON h.logical_id=i.logical_id WHERE \(predicate)",
          [
            (reference.targetMode == .live ? reference.targetLogicalID : reference.targetVersionID)
              .map(Value.string) ?? .null
          ]
        ).first
      }
      if businessOnly, let destination,
        ["request", "annotation"].contains(destination["kind"]!.text)
      {
        continue
      }
      if filters.contains(where: { column, value in
        value != nil && destination?[column]?.text != value!
      }) {
        continue
      }
      let key = try
        (destination?["id"]
        ?? .array([
          .string(reference.resolution.rawValue),
          reference.targetWorkbookID.map(Value.string) ?? .null,
          reference.targetMode.map { .string($0.rawValue) } ?? .null,
          reference.targetLogicalID.map(Value.string) ?? .null,
          reference.targetVersionID.map(Value.string) ?? .null,
          .string(reference.lookup),
        ])).json()
      if let (value, count, first) = groups[key] {
        var hit = value.object
        let discovered = scope == "body" ? "item_body" : "extracted_text"
        var scopes = value["discoveryScopes"].array
        if !scopes.contains(.string(discovered)) { scopes.append(.string(discovered)) }
        hit["discoveryScopes"] = .array(scopes)
        groups[key] = (.object(hit), count + 1, first)
      } else {
        groups[key] = (
          .object([
            "evidence": destination.map(Value.object) ?? .null,
            "resolution": .string(reference.resolution.rawValue),
            "firstReferenceID": .string(reference.id),
            "snapshotID": setID, "snapshotKind": .string(scope),
            "discoveryScopes": .array([.string(scope == "body" ? "item_body" : "extracted_text")]),
            "label": .string(reference.label), "lookup": .string(reference.lookup),
            "locator": .string(locator),
            "discoveryReason": .string("mention"),
          ]), 1, ordinal
        )
      }
    }
    return groups.values.filter { $0.2 > after }.sorted { $0.2 < $1.2 }.map {
      value, count, ordinal in
      var result = value.object
      result["mentionCount"] = .number(Double(count))
      return (.object(result), .number(Double(ordinal)))
    }
  }
}
