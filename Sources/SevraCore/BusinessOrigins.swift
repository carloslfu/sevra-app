import Foundation

extension Workbook {
  /// Historical dependencies to authoritative automatic producers. A complete
  /// inspection establishes neither independent business roots nor permission.
  public func businessOrigins(inputs: [String], cancellation: Cancellation = .init()) throws
    -> Value
  {
    try require(
      (1...16).contains(inputs.count)
        && inputs.allSatisfy { !$0.isEmpty && $0.utf8.count <= 256 },
      "origin_input", "Inspect 1 to 16 exact item versions, each up to 256 UTF-8 bytes.")
    let control = Cancellation(parent: cancellation, deadlineAfterSeconds: 3)
    return try readBusinessFeed(cancellation: control) {
      var report = BusinessOriginReport()
      var queue = Array(Set(inputs)).sorted()
      var discovered = Set(queue)
      var index = 0
      while index < queue.count {
        try control.check()
        let id = queue[index]
        index += 1
        let item = try businessOriginItem(id)
        let edges = try businessOriginEdges(item, remaining: 4096 - report.edgeCount)
        report.edgeCount += edges.count
        let producer = try businessOriginProducer(
          item, edges: edges, admissions: &report.admissions, cancellation: control)
        if let producer {
          try report.charge(producer)
          report.graph.runs.append(producer)
        }
        let business = edges.filter { ($0["roles"]!.int! & DerivationRole.business) != 0 }
        report.graph.parents[id] = producer == nil ? Set(business.map { $0["parent"]!.text }) : []
        for edge in edges {
          try control.check()
          var fields = try ItemDerivation.publicEdge(edge).object
          let follows = producer == nil && (edge["roles"]!.int! & DerivationRole.business) != 0
          fields["traversed"] = .bool(follows)
          let visible = Value.object(fields)
          try report.charge(visible)
          report.graph.edges.append(visible)
          if (edge["roles"]!.int! & DerivationRole.control) != 0 {
            let link: Value = .object([
              "child": edge["child"]!, "parent": edge["parent"]!, "roles": fields["roles"]!,
            ])
            try report.charge(link)
            report.controls.append(link)
          }
          if follows, discovered.insert(edge["parent"]!.text).inserted {
            try require(
              discovered.count <= 1024, "origin_limit",
              "The business graph exceeds 1,024 item versions. No partial origin was returned.")
            queue.append(edge["parent"]!.text)
          }
        }
        var summary = item
        summary.removeValue(forKey: "derivation")
        summary["automaticBoundary"] = .bool(producer != nil)
        try report.charge(.object(summary))
        report.items.append(.object(summary))
        if producer == nil && business.isEmpty {
          if item["category"] == .string("source") && edges.isEmpty
            && !Item.technicalKinds.contains(item["kind"]!.text)
          {
            report.originals.append(.string(id))
          } else {
            report.unclassified.append(
              .object([
                "itemID": .string(id), "reason": .string("no-retained-business-inputs"),
              ]))
          }
        }
      }
      let depth = try report.graph.depth(cancellation: control)
      let result = report.value(workbookID: self.id, inputs: inputs, depth: depth)
      try boundedBusinessOutput(result)
      try control.check()
      return result
    }
  }

  private func businessOriginItem(_ id: String) throws -> [String: Value] {
    guard
      let row = try db.execute(
        "SELECT id,category,kind,meaning,status,scenario,supersedes,CASE WHEN length(CAST(derivation AS BLOB))<=4096 THEN derivation END AS derivation FROM items WHERE id=?",
        [.string(id)], maxRows: 1, maxBytes: 65_536
      ).first
    else { throw SevraError("origin_item", "An exact business input version is missing.") }
    try require(row["derivation"] != .null, "origin_limit", "An item seal exceeds 4 KiB.")
    return row
  }

  private func businessOriginEdges(_ item: [String: Value], remaining: Int) throws
    -> [[String: Value]]
  {
    let id = item["id"]!.text
    let rows = try db.execute(
      "SELECT l.child,l.parent,l.relation,l.transformation,l.roles,p.id AS retained_parent FROM lineage l LEFT JOIN items p ON p.id=l.parent WHERE l.child=? ORDER BY l.parent,l.relation LIMIT ?",
      [.string(id), .number(Double(remaining + 1))], maxRows: remaining + 1, maxBytes: 2_097_152)
    try require(
      rows.count <= remaining, "origin_limit",
      "The business graph exceeds 4,096 inspected edges. No partial origin was returned.")
    let edges = try rows.map { row in
      try require(
        row["parent"] == row["retained_parent"], "origin_item", "A retained input is missing.")
      var edge = row
      edge.removeValue(forKey: "retained_parent")
      return edge
    }
    let revisions = edges.filter { $0["relation"] == .string("supersedes") }.map { $0["parent"]! }
    let expected = item["supersedes"] == .null ? [] : [item["supersedes"]!]
    try require(
      revisions == expected, "derivation_integrity", "The exact revision edge is inconsistent.")
    guard let retained = try? Value.parse(item["derivation"]!.text) else {
      throw SevraError("derivation_integrity", "The retained item seal is malformed.")
    }
    try require(
      retained == ItemDerivation.seal(id, edges: edges), "derivation_integrity",
      "The item lost its complete retained input roles or derivation seal.")
    return edges
  }
}

private struct BusinessOriginReport {
  var graph = DerivationInspectionGraph()
  var admissions: [String: AutomationCausalNode] = [:]
  var edgeCount = 0
  var bytes = 0
  var items: [Value] = []
  var controls: [Value] = []
  var originals: [Value] = []
  var unclassified: [Value] = []

  mutating func charge(_ value: Value) throws {
    bytes += try value.json().utf8.count
    try require(bytes <= 8_388_608, "origin_limit", "The retained origin output exceeds 8 MiB.")
  }

  func value(workbookID: String, inputs: [String], depth: Int) -> Value {
    .object([
      "workbookID": .string(workbookID), "policy": .string("business-origins-v1"),
      "inputs": .array(Set(inputs).sorted().map(Value.string)),
      "itemCount": .number(Double(items.count)), "edgeCount": .number(Double(edgeCount)),
      "maximumLineageDepth": .number(Double(depth)),
      "items": .array(items.sorted { $0["id"].text < $1["id"].text }),
      "edges": .array(graph.edges), "controlLinks": .array(controls),
      "automaticProducers": .array(graph.runs.sorted { $0["runID"].text < $1["runID"].text }),
      "originalInputCandidates": .array(originals.sorted { $0.text < $1.text }),
      "unclassifiedOrigins": .array(unclassified.sorted { $0["itemID"].text < $1["itemID"].text }),
      "coverage": .string("retained-business-dependencies-to-automatic-producers"),
      "minimalCauseSet": .bool(false), "independentBusinessRoots": .string("not-established"),
      "dispatchEligibility": .string("not-evaluated"), "execution": .string("none"),
      "enabled": .bool(false),
    ])
  }
}
