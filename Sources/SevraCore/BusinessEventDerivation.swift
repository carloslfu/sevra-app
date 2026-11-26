import Foundation

/// Projection of immutable versions and captured before/after images. Reading
/// this feed does not interpret prose, grant authority or run automation.
struct BusinessEventEntry: Equatable {
  let family: String
  let scopeKind: String
  let scopeKey: String
  let recordKind: String
  let logicalID: String?
  let beforeID: String?
  let afterID: String?
  let payload: Value

  var value: Value {
    .object([
      "family": .string(family), "scopeKind": .string(scopeKind), "scopeKey": .string(scopeKey),
      "recordKind": .string(recordKind), "logicalID": logicalID.map(Value.string) ?? .null,
      "beforeID": beforeID.map(Value.string) ?? .null,
      "afterID": afterID.map(Value.string) ?? .null,
      "payload": payload,
    ])
  }
  static func identity(batch: String, ordinal: Int) throws -> String {
    "business_"
      + ChangeFormat.hash(try Value.array([.string(batch), .string(String(ordinal))]).json())
  }
}

extension ChangeRow {
  func businessText(_ index: Int) throws -> String {
    guard values.indices.contains(index), let text = values[index].string else {
      throw SevraError("business_integrity", "A business row has invalid text.")
    }
    return text
  }
  func businessInteger(_ index: Int) throws -> String {
    guard values.indices.contains(index), case .integer(let text) = values[index],
      Int64(text) != nil
    else { throw SevraError("business_integrity", "A business row has invalid integer data.") }
    return text
  }
}

extension Database {
  func deriveBusinessEvents(_ changes: [RowChange]) throws -> [BusinessEventEntry] {
    var entries: [BusinessEventEntry] = []
    var settled: [String: [ChangeRow]] = [:]
    var schemas: [String: [ChangeRow]] = [:]
    var mappings: [String: (before: ChangeRow?, after: ChangeRow?)] = [:]
    for change in changes {
      if change.table == "items", change.before == nil, let row = change.after,
        try row.businessText(3) == "record",
        try ["accepted", "rejected"].contains(row.businessText(7)),
        try !Item.technicalKinds.contains(row.businessText(4))
      {
        settled[try row.businessText(1), default: []].append(row)
      } else if change.table == "column_versions", change.before == nil, let row = change.after {
        schemas[try row.businessText(1), default: []].append(row)
      } else if change.table == "dataset_rows" {
        guard let row = change.after ?? change.before else {
          throw SevraError("business_integrity", "A captured mapping has no row.")
        }
        let key = try Value.array([
          .string(change.table), .string(row.businessText(0)), .string(row.businessText(1)),
        ]).json()
        let first = mappings[key]
        mappings[key] = (first == nil ? change.before : first!.before, change.after)
      }
    }
    for logicalID in settled.keys.sorted() {
      let rows = try settled[logicalID]!.sorted {
        Int64(try $0.businessInteger(2))! < Int64(try $1.businessInteger(2))!
      }
      let first = rows.first!
      let final = rows.last!
      let previous = try execute(
        "SELECT id,logical_id,kind,meaning,status,scenario FROM items WHERE logical_id=? AND version<CAST(? AS INTEGER) AND status IN ('accepted','rejected') ORDER BY version DESC LIMIT 1",
        [.string(logicalID), .string(first.businessInteger(2))]
      ).first
      if previous == nil, try final.businessText(7) == "rejected" { continue }
      let after: Value = .object([
        "id": .string(try final.businessText(0)), "logicalID": .string(logicalID),
        "kind": .string(try final.businessText(4)), "meaning": .string(try final.businessText(6)),
        "status": .string(try final.businessText(7)),
        "scenario": .string(try final.businessText(8)),
      ])
      let before =
        previous.map { row in
          Value.object([
            "id": row["id"]!, "logicalID": row["logical_id"]!, "kind": row["kind"]!,
            "meaning": row["meaning"]!, "status": row["status"]!, "scenario": row["scenario"]!,
          ])
        } ?? .null
      entries.append(
        .init(
          family: "record-settled", scopeKind: "record",
          scopeKey: logicalID, recordKind: after["kind"].text, logicalID: logicalID,
          beforeID: before["id"].string, afterID: after["id"].string,
          payload: .object(["before": before, "after": after])))
    }
    for key in mappings.keys.sorted() {
      let mapping = mappings[key]!
      if mapping.before?.values == mapping.after?.values { continue }
      let row = (mapping.after ?? mapping.before)!
      entries.append(
        .init(
          family: "dataset-membership", scopeKind: "dataset", scopeKey: try row.businessText(0),
          recordKind: "row-membership", logicalID: nil, beforeID: nil, afterID: nil,
          payload: .object([
            "before": try businessMembership(mapping.before),
            "after": try businessMembership(mapping.after),
          ])))
    }
    for dataset in schemas.keys.sorted() {
      let rows = try schemas[dataset]!.sorted {
        Int64(try $0.businessInteger(2))! < Int64(try $1.businessInteger(2))!
      }
      let previous = try execute(
        "SELECT id,source_id FROM column_versions WHERE dataset_id=? AND version<CAST(? AS INTEGER) ORDER BY version DESC LIMIT 1",
        [.string(dataset), .string(rows.first!.businessInteger(2))]
      ).first
      let final = rows.last!
      entries.append(
        .init(
          family: "dataset-schema", scopeKind: "dataset", scopeKey: dataset,
          recordKind: "dataset-schema", logicalID: nil, beforeID: previous?["source_id"]?.string,
          afterID: try final.businessText(7),
          payload: .object([
            "before": previous.map {
              .object(["versionID": $0["id"]!, "sourceID": $0["source_id"]!])
            } ?? .null,
            "after": .object([
              "versionID": .string(try final.businessText(0)),
              "sourceID": .string(try final.businessText(7)),
            ]),
          ])))
    }
    // Fixed family order and sorted source keys above are pagination order,
    // never an asserted temporal order inside this atomic business commit.
    return entries
  }

  private func businessMembership(_ row: ChangeRow?) throws -> Value {
    guard let row else { return .null }
    return .object([
      "datasetID": .string(try row.businessText(0)), "rowID": .string(try row.businessText(1)),
      "ordinal": .string(try row.businessInteger(2)), "logicalID": .string(try row.businessText(3)),
    ])
  }
}
