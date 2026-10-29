import CryptoKit
import Foundation

enum DerivationRole {
  static let data = 1
  static let control = 2
  static let producer = 4
  static let revision = 8
  static let business = data | producer | revision

  static func names(_ roles: Int) -> Value {
    .array(
      [(data, "data"), (control, "control"), (producer, "producer"), (revision, "revision")]
        .filter { roles & $0.0 != 0 }.map { .string($0.1) })
  }
}

enum ItemDerivation {
  static let policy = "item-derivation-v1"

  static func publicEdge(_ edge: [String: Value]) throws -> Value {
    _ = try tuple(edge)
    var fields = edge
    fields["roles"] = DerivationRole.names(edge["roles"]!.int!)
    return .object(fields)
  }

  static func tuple(_ edge: [String: Value]) throws -> Value {
    let relation = edge["relation"]!.text
    let roles = edge["roles"]?.int ?? 0
    try require(
      edge["roles"] == .number(Double(roles))
        && ((relation == "derives-from" && (1...7).contains(roles))
          || (relation == "supersedes" && roles == DerivationRole.revision)
          || (relation == "definition-input" && roles == DerivationRole.control)),
      "derivation_integrity", "A lineage edge has inconsistent relation roles.")
    return .array([
      edge["parent"]!, edge["relation"]!, edge["transformation"]!, .number(Double(roles)),
    ])
  }

  static func seal(_ id: String, count: Int, hash: String, business: Bool) -> Value {
    .object([
      "policy": .string(policy), "itemID": .string(id), "edgeCount": .number(Double(count)),
      "edgeHash": .string(hash),
      "classification": .string(business ? "retained-derivation" : "unclassified-original"),
    ])
  }

  static func seal(_ id: String, edges: [[String: Value]]) throws -> Value {
    let values = try edges.map(tuple)
    return seal(
      id, count: edges.count, hash: ChangeFormat.hash(try Value.array(values).json()),
      business: edges.contains { ($0["roles"]!.int! & DerivationRole.business) != 0 })
  }
}

extension Workbook {
  func prepareDerivationEdges(
    inputs: [String], controls: [String], producers: [String],
    supersedes: String?, transformation: String
  ) throws -> [[String: Value]] {
    var roles: [String: Int] = [:]
    for (values, role) in [
      (inputs, DerivationRole.data), (controls, DerivationRole.control),
      (producers, DerivationRole.producer),
    ] {
      for parent in values { roles[parent, default: 0] |= role }
    }
    for parent in Set(roles.keys).union(supersedes.map { [$0] } ?? []) {
      try require(
        try item(parent).id == parent, "derivation_input", "Use exact retained input versions.")
    }
    var edges = roles.map { parent, value in
      [
        "parent": Value.string(parent), "relation": .string("derives-from"),
        "transformation": .string(transformation), "roles": .number(Double(value)),
      ]
    }
    if let supersedes {
      edges.append([
        "parent": .string(supersedes), "relation": .string("supersedes"),
        "transformation": .string(transformation),
        "roles": .number(Double(DerivationRole.revision)),
      ])
    }
    return edges.sorted {
      $0["parent"]!.text == $1["parent"]!.text
        ? $0["relation"]!.text < $1["relation"]!.text : $0["parent"]!.text < $1["parent"]!.text
    }
  }

  /// Definition dependencies can be added only while creating this exact item.
  /// Capture state is connection-local and is discarded at commit or rollback.
  func insertDefinitionDerivation(_ child: String, parent: String, transformation: String) throws {
    try require(
      db.changes?.publishing == false
        && db.changes?.pending?.contains(where: {
          $0.table == "items" && $0.before == nil && $0.after?.values.first?.string == child
        }) == true, "derivation_transaction", "Historical derivations cannot be resealed.")
    try require(
      try item(parent).id == parent, "derivation_input", "Use an exact definition dependency.")
    try db.execute(
      "INSERT OR IGNORE INTO lineage VALUES(?,?,?,?,?)",
      [
        .string(child), .string(parent),
        .string("definition-input"), .string(transformation),
        .number(Double(DerivationRole.control)),
      ])
  }

  func sealNewDefinitionDerivation(_ id: String) throws {
    try require(
      db.changes?.publishing == false
        && db.changes?.pending?.contains(where: {
          $0.table == "items" && $0.before == nil && $0.after?.values.first?.string == id
        }) == true, "derivation_transaction", "Historical derivations cannot be resealed.")
    let row = try db.execute(
      "SELECT id,supersedes,derivation FROM items WHERE id=?", [.string(id)], maxRows: 1
    ).first!
    let seal = try calculatedItemDerivation(row)
    try db.execute(
      "UPDATE items SET derivation=? WHERE id=?", [.string(try seal.json()), .string(id)])
  }

  /// Reads edge pages without selecting original bodies or structured item data.
  func calculatedItemDerivation(_ row: [String: Value]) throws -> Value {
    let id = row["id"]!.text
    var digest = SHA256()
    digest.update(data: Data("[".utf8))
    var count = 0
    var business = false
    var revision = false
    var parent = ""
    var relation = ""
    while true {
      let edges = try db.execute(
        "SELECT parent,relation,transformation,roles FROM lineage WHERE child=? AND (parent,relation)>(?,?) ORDER BY parent,relation LIMIT 100",
        [.string(id), .string(parent), .string(relation)], maxRows: 100)
      if edges.isEmpty { break }
      for edge in edges {
        let value = try ItemDerivation.tuple(edge)
        if count > 0 { digest.update(data: Data(",".utf8)) }
        digest.update(data: Data(try value.json().utf8))
        count += 1
        business = business || (edge["roles"]!.int! & DerivationRole.business) != 0
        if edge["relation"] == .string("supersedes") {
          try require(
            !revision && edge["parent"] == row["supersedes"], "derivation_integrity",
            "The exact prior version is inconsistent.")
          revision = true
        }
        parent = edge["parent"]!.text
        relation = edge["relation"]!.text
      }
    }
    digest.update(data: Data("]".utf8))
    let hash = digest.finalize().map { String(format: "%02x", $0) }.joined()
    let expected = ItemDerivation.seal(id, count: count, hash: hash, business: business)
    try require(
      revision == (row["supersedes"] != .null), "derivation_integrity",
      "The exact prior version edge is missing.")
    return expected
  }

  func verifiedItemDerivation(_ row: [String: Value]) throws -> Value {
    let retained = try Value.parse(row["derivation"]!.text)
    try require(
      retained == calculatedItemDerivation(row), "derivation_integrity",
      "The item lost its complete retained input roles or derivation seal.")
    return retained
  }

  func verifyItemDerivations() throws {
    var cursor = ""
    while true {
      let rows = try db.execute(
        "SELECT id,supersedes,derivation FROM items WHERE id>? ORDER BY id LIMIT 100",
        [.string(cursor)], maxRows: 100)
      if rows.isEmpty { break }
      for row in rows {
        _ = try verifiedItemDerivation(row)
        cursor = row["id"]!.text
      }
    }
  }
}
