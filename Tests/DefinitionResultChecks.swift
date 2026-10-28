import Foundation

@testable import SevraCore

func checkDefinitionResults(at root: URL) {
  func book(_ name: String) throws -> Workbook {
    try Workbook.create(at: root.appendingPathComponent("Results-" + name + ".sevra"), title: name)
  }
  func function(_ formula: String, calls: [Value] = []) -> Value {
    .object([
      "kind": .string("function"), "title": .string("Case count"),
      "description": .string("Synthetic"),
      "parameters": .array([
        .object([
          "id": .string("x"), "label": .string("Cases"), "type": .string("decimal"),
          "required": .bool(true),
        ])
      ]),
      "payload": .object([
        "expression": .string(formula), "calls": .array(calls), "unit": .string("items"),
      ]),
    ])
  }
  func save(_ b: Workbook, _ content: Value) throws -> ApplicationDefinition {
    try b.saveApplicationDefinition(logicalID: identifier(), content: content)
  }
  func binding(_ definition: ApplicationDefinition) -> Value {
    .object(["mode": .string("live"), "logicalID": .string(definition.logicalID)])
  }
  func query(_ table: Dataset, limit: Int = 10, grouped: Bool = false) -> Value {
    let column: Value = .object(["source": .number(0), "column": .string("quantity")])
    var selection: [String: Value] = ["id": .string("quantity"), "column": column]
    if grouped { selection["aggregate"] = .string("sum") }
    return .object([
      "kind": .string("query"), "title": .string("Observed quantities"),
      "description": .string("Synthetic"),
      "parameters": .array([]),
      "payload": .object([
        "dataMode": .string("live"),
        "query": .object([
          "sources": .array([
            .object(["datasetID": .string(table.id), "definitionID": .string(table.definitionID)])
          ]),
          "select": .array([.object(selection)]), "limit": .number(Double(limit)),
        ]),
      ]),
    ])
  }
  func fixture(_ b: Workbook) throws -> Dataset {
    let source = try b.addItem(category: "source", kind: "observation", title: "Synthetic counts")
    return try b.createDataset(
      title: "Counts",
      columns: [.init(id: "quantity", title: "Quantity", type: "decimal", unit: "items")],
      rows: [["quantity": .string("2")], ["quantity": .string("5")]], sourceID: source.id)
  }
  let args: Value = .object(["x": .string("3")])

  check(
    "two native calculation spaces refresh a live called function while pinned values stay exact"
  ) {
    let b = try book("Live")
    let base = try save(b, function("x*2"))
    let wrapper = try save(
      b,
      function(
        "units",
        calls: [
          .object([
            "alias": .string("units"), "binding": binding(base),
            "arguments": .object(["x": .object(["parameter": .string("x")])]),
          ])
        ]))
    let component = Component(
      id: "count", type: "calculation", title: "Case count", definitionBinding: binding(wrapper),
      arguments: args)
    for name in ["Stock", "Report"] {
      _ = try b.saveSpace(id: name, title: name, definition: .init(components: [component]))
      try expect(
        try b.componentDefinitionResult(b.space(name).definition.components[0])["result"]
          == .string("6"))
    }
    let pinned = try b.pinSpace("Report")
    let old = try b.space(pinned).definition.components[0]
    _ = try b.saveApplicationDefinition(
      logicalID: base.logicalID, content: function("x*3"), expectedDefinitionID: base.id)
    for name in ["Stock", "Report"] {
      try expect(
        try b.componentDefinitionResult(b.space(name).definition.components[0])["result"]
          == .string("9"))
    }
    try expect(try b.componentDefinitionResult(old)["result"] == .string("6"))
    try expect(
      try b.componentDefinitionResult(old)["resolvedDefinitions"].array.contains {
        $0["id"] == .string(base.id)
      })
    _ = try b.editSpace(
      pinned, expectedVersion: 1,
      edits: [.init(operation: "title", componentID: "count", title: "Earlier count")])
    try expect(
      try b.componentDefinitionResult(b.space(pinned).definition.components[0])["result"]
        == .string("6"))
    try refuses("view_snapshot") {
      _ = try b.saveSpace(title: "Forged capture", definition: b.space(pinned).definition)
    }
    try refuses("view_snapshot") { _ = try b.componentDefinitionResult(old, cursor: "anything") }
    var changed = old
    changed.arguments = .object(["x": .string("4")])
    try refuses("space_snapshot") {
      _ = try b.editSpace(
        pinned, expectedVersion: 2,
        edits: [.init(operation: "replace", componentID: "count", component: changed)])
    }
    var invalid = component
    invalid.type = "query"
    try refuses("view") {
      _ = try b.saveSpace(title: "Wrong kind", definition: .init(components: [invalid]))
    }
  }

  check("native query pages retain exact row meaning and pinned first-page coverage after changes")
  {
    let b = try book("Pages")
    let table = try fixture(b)
    let definition = try save(b, query(table, limit: 1))
    let c = Component(
      type: "query", title: "Counts", definitionBinding: binding(definition),
      arguments: .object([:]))
    let space = try b.saveSpace(title: "Counts", definition: .init(components: [c]))
    let first = try b.componentDefinitionResult(c)
    try expect(first["result"]["hasMore"] == .bool(true))
    try expect(first["result"]["rows"].array[0]["inputs"].array[0]["meaning"] == .string("actual"))
    let next = try b.componentDefinitionResult(c, cursor: first["nextCursor"].text)
    try expect(next["result"]["rows"].array[0]["values"]["quantity"] == .string("5"))
    let pinned = try b.pinSpace(space)
    try expect(
      try b.space(pinned).definition.components[0].evaluationSnapshot?.inputPopulation?.first?[
        "rows"
      ].array.count == 2)
    let original = try b.rows(table.id)[0]
    _ = try b.addItem(
      category: "record", kind: "row", title: original.title,
      data: .object(["quantity": .string("8")]), meaning: "estimate", status: "accepted",
      inputs: [original.id], supersedes: original.id)
    try refuses("stale_query") {
      _ = try b.componentDefinitionResult(c, cursor: first["nextCursor"].text)
    }
    let frozen = try b.componentDefinitionResult(b.space(pinned).definition.components[0])
    try expect(frozen["result"]["rows"].array[0]["values"]["quantity"] == .string("2"))
    try expect(frozen["result"]["hasMore"] == .bool(true))
    let fresh = try b.componentDefinitionResult(c)
    try expect(
      fresh["result"]["rows"].array[0]["inputs"].array[0]["meaning"] == .string("estimate"))
  }

  check(
    "published calculation is draft with exact actor/input lineage and acceptance keeps its meaning"
  ) {
    let b = try book("Publish")
    let definition = try save(b, function("x*12"))
    let evidence = try b.addItem(
      category: "source", kind: "observation", title: "Three expected cases", meaning: "estimate")
    let evaluation = try b.evaluateApplicationDefinition(definition.id, arguments: args)
    let item = try b.publishApplicationResult(
      definition.id, arguments: args, evaluation: evaluation, title: "Expected items",
      meaning: "estimate", inputs: [evidence.id], token: "publish", actor: .human("native-test"))
    try expect(
      item.status == "draft" && item.meaning == "estimate"
        && item.data["evaluation"]["result"] == .string("36"))
    let parents = try b.lineage(item.id).map { $0["parent"].text }
    try expect(parents.contains(evidence.id) && parents.contains(definition.sourceID))
    let invocation = try parents.map { try b.item($0) }.first {
      $0.kind == "application_invocation"
    }!
    try expect(invocation.data["actor"]["kind"] == .string("human"))
    try expect(
      try b.componentDefinitionResult(item.applicationResultComponent!)["result"] == .string("36"))
    try expect(try b.publishedApplicationResultComponent(item.id) != nil)
    let claim = try b.addItem(
      category: "record", kind: "calculation", title: "Unverified copied claim", data: item.data,
      inputs: [definition.sourceID])
    try expect(try b.publishedApplicationResultComponent(claim.id) == nil)
    _ = try b.accept(item.id)
    try expect(try b.item(item.logicalID).meaning == "estimate")
    try expect(try b.publishedApplicationResultComponent(b.item(item.logicalID).id) != nil)
    try expect(
      try b.componentDefinitionResult(b.item(item.logicalID).applicationResultComponent!)["result"]
        == .string("36"))
    _ = try b.saveApplicationDefinition(
      logicalID: definition.logicalID, content: function("x*13"),
      expectedDefinitionID: definition.id)
    let count = try b.committedHistory(limit: 1000).count
    let retry = try b.publishApplicationResult(
      definition.id, arguments: args, evaluation: evaluation, title: "Expected items",
      meaning: "estimate", inputs: [evidence.id], token: "publish", actor: .human("native-test"))
    try expect(retry.id == item.id && retry.data["evaluation"]["result"] == .string("36"))
    try expect(try b.committedHistory(limit: 1000).count == count)
  }

  check(
    "grouped query publication retains its exact scoped candidate population without fabricated group members"
  ) {
    let b = try book("Population")
    let table = try fixture(b)
    var content = query(table, grouped: true).object
    var payload = content["payload"]!.object
    var raw = payload["query"]!.object
    raw["filters"] = .array([
      .object([
        "column": .object(["source": .number(0), "column": .string("quantity")]),
        "op": .string("gte"), "value": .string("4"),
      ])
    ])
    payload["query"] = .object(raw)
    content["payload"] = .object(payload)
    let definition = try save(b, .object(content))
    let evaluation = try b.evaluateApplicationDefinition(definition.id)
    try expect(evaluation["result"]["rows"].array[0]["values"]["quantity"] == .string("5"))
    try expect(evaluation["result"]["rows"].array[0]["inputs"] == .null)
    let published = try b.publishApplicationResult(
      definition.id, arguments: .object([:]), evaluation: evaluation, title: "Filtered count",
      meaning: "estimate", token: "population")
    let population = published.data["inputPopulation"].array[0]["rows"].array
    try expect(population.count == 2)
    for row in try b.rows(table.id) {
      try expect(try b.lineage(published.id).contains { $0["parent"] == .string(row.id) })
    }
    try expect(published.data["populationScope"].text.contains("Not per-group membership"))
    let saved = published.applicationResultComponent!
    try expect(try b.componentDefinitionResult(saved)["result"] == evaluation["result"])
    try expect(saved.evaluationSnapshot?.inputPopulation?.first?["rows"].array.count == 2)
    try expect(try b.search("quantity").hits.contains { $0.itemID == published.id })
  }

  check(
    "partial stale forged read-only cancelled and faulted publications leave no partial effects"
  ) {
    let b = try book("Refusals")
    let table = try fixture(b)
    let partial = try save(b, query(table, limit: 1))
    let arguments: Value = .object([:])
    let first = try b.evaluateApplicationDefinition(partial.id)
    let before = try b.committedHistory(limit: 1000).count
    try refuses("partial_evaluation") {
      _ = try b.publishApplicationResult(
        partial.id, arguments: arguments, evaluation: first, title: "Partial", meaning: "actual",
        token: "partial")
    }
    let definition = try save(b, function("x*2"))
    let old = try b.evaluateApplicationDefinition(definition.id, arguments: args)
    var forged = old.object
    forged["result"] = .string("999")
    try refuses("stale_evaluation") {
      _ = try b.publishApplicationResult(
        definition.id, arguments: args, evaluation: .object(forged), title: "Forged",
        meaning: "actual", token: "forged")
    }
    try refuses("read_only_request") {
      _ = try b.publishApplicationResult(
        definition.id, arguments: args, evaluation: old, title: "Read", meaning: "actual",
        token: "read", readOnly: true)
    }
    let cancel = Cancellation()
    cancel.cancel()
    try refuses {
      _ = try b.publishApplicationResult(
        definition.id, arguments: args, evaluation: old, title: "Cancel", meaning: "actual",
        token: "cancel", cancellation: cancel)
    }
    try b.db.execute(
      "CREATE TEMP TRIGGER fail_result BEFORE INSERT ON main.committed_changes BEGIN SELECT RAISE(ABORT,'publication fault'); END;"
    )
    try refuses {
      _ = try b.publishApplicationResult(
        definition.id, arguments: args, evaluation: old, title: "Fault", meaning: "actual",
        token: "fault")
    }
    try b.db.execute("DROP TRIGGER fail_result")
    try expect(
      try b.db.scalar("SELECT count(*) FROM items WHERE kind='application_invocation'").int == 0)
    try expect(try b.committedHistory(limit: 1000).count == before + 1)
    _ = try b.publishApplicationResult(
      definition.id, arguments: args, evaluation: old, title: "Fault", meaning: "actual",
      token: "fault")
    try refuses("stale_evaluation") {
      _ = try b.publishApplicationResult(
        definition.id, arguments: args, evaluation: old, title: "Stale", meaning: "actual",
        token: "stale")
    }
  }

  check("one-row aggregate publication refuses an oversized scoped input population atomically") {
    let b = try book("PopulationLimit")
    let original = try b.addItem(
      category: "source", kind: "observation", title: "Synthetic large population")
    let table = try b.createDataset(
      title: "Many counts",
      columns: [.init(id: "quantity", title: "Quantity", type: "decimal", unit: "items")],
      rows: (0..<5001).map { _ in ["quantity": .string("1")] }, sourceID: original.id)
    let definition = try save(b, query(table, grouped: true))
    let evaluation = try b.evaluateApplicationDefinition(definition.id)
    try expect(evaluation["result"]["rows"].array.count == 1)
    let before = try b.committedHistory(limit: 1000)
    try refuses("definition_limit") {
      _ = try b.publishApplicationResult(
        definition.id, arguments: .object([:]), evaluation: evaluation, title: "Large count",
        meaning: "estimate", token: "large")
    }
    try expect(try b.committedHistory(limit: 1000) == before)
    try expect(
      try b.db.scalar("SELECT count(*) FROM items WHERE kind='application_invocation'").int == 0)
  }

  check(
    "computed snapshots and published results reconstruct and reopen portably without execution"
  ) {
    let b = try book("Replay")
    let definition = try save(b, function("x*2"))
    let c = Component(
      type: "calculation", title: "Count", definitionBinding: binding(definition), arguments: args)
    let space = try b.saveSpace(title: "Results", definition: .init(components: [c]))
    let pinned = try b.pinSpace(space)
    let evaluation = try b.componentDefinitionResult(c)
    let published = try b.publishApplicationResult(
      definition.id, arguments: args, evaluation: evaluation, title: "Count result",
      meaning: "actual", token: "result")
    let copy = try b.reconstruct(to: root.appendingPathComponent("Result-replayed.sevra"))
    try expect(try copy.item(published.id).data == published.data)
    try expect(
      try copy.componentDefinitionResult(copy.space(pinned).definition.components[0])["result"]
        == .string("6"))
    try expect(try copy.committedHistory(limit: 1000) == b.committedHistory(limit: 1000))
    let archive = root.appendingPathComponent("Result.sevraz")
    try b.export(to: archive)
    let portable = try Workbook.openArchive(
      archive, at: root.appendingPathComponent("Result-portable.sevra"))
    try expect(try portable.item(published.id).data == published.data)
    try expect(try portable.space(pinned).definition == b.space(pinned).definition)
    _ = try portable.verify()
  }
}
