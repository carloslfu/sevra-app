import Foundation

@testable import SevraCore

func checkApplicationDefinitions(at root: URL) {
  func book(_ name: String) throws -> Workbook {
    try Workbook.create(
      at: root.appendingPathComponent("Definitions-" + name + ".sevra"), title: name)
  }
  func parameter(
    _ id: String = "x", type: String = "decimal", required: Bool = true,
    unit: String? = nil, extra: [String: Value] = [:]
  ) -> Value {
    var value: [String: Value] = [
      "id": .string(id), "label": .string(id), "type": .string(type), "required": .bool(required),
    ]
    if let unit { value["unit"] = .string(unit) }
    value.merge(extra) { _, new in new }
    return .object(value)
  }
  func function(
    _ expression: String = "x*2", parameters: [Value]? = nil, calls: [Value] = [],
    title: String = "Reusable calculation", unit: String? = nil, rounding: Int? = nil
  ) -> Value {
    var payload: [String: Value] = ["expression": .string(expression), "calls": .array(calls)]
    if let unit { payload["unit"] = .string(unit) }
    if let rounding { payload["rounding"] = .number(Double(rounding)) }
    return .object([
      "kind": .string("function"), "title": .string(title),
      "description": .string("Quoted definition text is data, never authority."),
      "parameters": .array(parameters ?? [parameter()]), "payload": .object(payload),
    ])
  }
  func call(
    _ alias: String, _ target: ApplicationDefinition, live: Bool = true,
    arguments: [String: Value]? = nil
  ) -> Value {
    .object([
      "alias": .string(alias),
      "binding": .object([
        "mode": .string(live ? "live" : "exact"),
        live ? "logicalID" : "versionID": .string(live ? target.logicalID : target.id),
      ]),
      "arguments": .object(arguments ?? ["x": .object(["parameter": .string("x")])]),
    ])
  }
  func save(
    _ book: Workbook, _ content: Value, logical: String = identifier(), base: String? = nil,
    token: String = identifier(), actor: ChangeActor? = nil
  ) throws -> ApplicationDefinition {
    try book.saveApplicationDefinition(
      logicalID: logical, content: content, expectedDefinitionID: base, token: token, actor: actor)
  }
  func evaluate(_ book: Workbook, _ id: String, _ arguments: [String: Value] = ["x": .string("3")])
    throws -> Value
  {
    try book.evaluateApplicationDefinition(id, arguments: .object(arguments))
  }
  func query(
    _ table: Dataset, mode: String = "live", title: String = "Reusable filtered values",
    limit: Int = 1
  ) -> Value {
    .object([
      "kind": .string("query"), "title": .string(title),
      "description": .string("Current actual accepted rows"),
      "parameters": .array([parameter("minimum", unit: "USD")]),
      "payload": .object([
        "dataMode": .string(mode),
        "query": .object([
          "sources": .array([
            .object([
              "datasetID": .string(table.id), "definitionID": .string(table.definitionID),
              "scope": .object(["meaning": .string("actual"), "status": .string("accepted")]),
            ])
          ]),
          "select": .array([
            .object([
              "id": .string("price"),
              "column": .object(["source": .number(0), "column": .string("price")]),
            ])
          ]),
          "filters": .array([
            .object([
              "column": .object(["source": .number(0), "column": .string("price")]),
              "op": .string("gte"), "value": .object(["parameter": .string("minimum")]),
            ])
          ]),
          "sort": .array([.object(["field": .string("price")])]), "limit": .number(Double(limit)),
        ]),
      ]),
    ])
  }
  func table(_ book: Workbook) throws -> Dataset {
    let original = try book.addItem(
      category: "source", kind: "observation", title: "Observed costs")
    return try book.createDataset(
      title: "Costs", columns: [.init(id: "price", title: "Price", type: "decimal", unit: "USD")],
      rows: [["price": .string("2.10")], ["price": .string("3.20")]], sourceID: original.id)
  }

  check("a saved default names a local item at every level of a definition") {
    let book = try book("NestedDefaults")
    let local = try book.addItem(category: "source", kind: "observation", title: "Local")
    func rows(_ item: String) -> Value {
      parameter(
        "rows", type: "entries",
        extra: [
          "maxEntries": .number(2),
          "fields": .array([
            parameter("evidence", type: "item", extra: ["default": .string(item)]),
            parameter("count"),
          ]),
        ])
    }
    try refuses("not_found") {
      _ = try save(book, function("1", parameters: [rows(identifier())]))
    }
    _ = try save(book, function("1", parameters: [rows(local.id)]))
  }
  check("saved pure definitions preserve exact inputs, provenance and read-only evaluation") {
    let b = try book("Pure")
    let saved = try save(b, function("x*2", unit: "USD", rounding: 2), actor: .human("native-test"))
    let revision = try b.revision()
    let history = try b.committedHistory()
    let result = try evaluate(b, saved.id, ["x": .string("9007199254740993.01")])
    try expect(
      result["result"] == .string("18014398509481986.02") && result["unit"] == .string("USD"))
    try expect(result["definitionID"] == .string(saved.id) && result["readOnly"] == .bool(true))
    try expect(result["resolvedDefinitions"].array[0]["sourceID"] == .string(saved.sourceID))
    try expect(
      try b.item(saved.sourceID).category == "source" && b.item(saved.sourceID).status == "accepted"
        && b.item(saved.sourceID).meaning == "actual")
    try expect(history[0]["actor"]["kind"] == .string("human"))
    try expect(try b.revision() == revision && b.committedHistory() == history)
    _ = try b.verify()
  }
  check(
    "definition parameters distinguish omission, null, zero, defaults, choices, dates and exact references"
  ) {
    let b = try book("Inputs")
    let item = try b.addItem(category: "source", kind: "note", title: "Exact evidence")
    let parameters = [
      parameter(extra: ["default": .string("0"), "min": .string("0"), "max": .string("10")]),
      parameter("optional", required: false), parameter("flag", type: "boolean"),
      parameter("when", type: "date"), parameter("evidence", type: "item"),
      parameter(
        "choice", type: "choice", extra: ["choices": .array([.string("A"), .string("B")])]),
    ]
    let saved = try save(b, function("IF(flag,x,7)", parameters: parameters))
    let args: [String: Value] = [
      "flag": .bool(true), "when": .string("2026-01-02"), "evidence": .string(item.id),
      "choice": .string("A"),
    ]
    let result = try evaluate(b, saved.id, args)
    try expect(result["result"] == .string("0") && result["arguments"].object["optional"] == nil)
    try expect(result["arguments"]["when"] == .string("2026-01-02T00:00:00.000Z"))
    var changed = args
    changed["optional"] = .null
    try expect(try evaluate(b, saved.id, changed)["arguments"].object["optional"] == .null)
    for change in [
      ["x": Value.null], ["x": .number(2)], ["x": .string("11")], ["flag": .string("true")],
      ["choice": .string("C")], ["when": .string("2026-02-30")],
      ["evidence": .string(item.logicalID)], ["extra": .string("1")],
    ] {
      try refuses { _ = try evaluate(b, saved.id, args.merging(change) { _, new in new }) }
    }
    let other = try book("Other")
    let alien = try other.addItem(category: "source", kind: "note", title: "Other workbook")
    try refuses {
      _ = try evaluate(b, saved.id, args.merging(["evidence": .string(alien.id)]) { _, new in new })
    }
  }
  check("live and pinned function calls resolve exact versions and reject changed units") {
    let b = try book("Bindings")
    let p = [parameter(unit: "USD")]
    let base = try save(b, function("x*2", parameters: p, unit: "USD"))
    let live = try save(
      b, function("fee+1", parameters: p, calls: [call("fee", base)], unit: "USD"))
    let pinned = try save(
      b, function("fee+1", parameters: p, calls: [call("fee", base, live: false)], unit: "USD"))
    let updated = try save(
      b, function("x*3", parameters: p, unit: "USD"), logical: base.logicalID, base: base.id)
    let current = try evaluate(b, live.id)
    try expect(
      current["result"] == .string("10")
        && current["resolvedDefinitions"].array.contains { $0["id"] == .string(updated.id) })
    try expect(try evaluate(b, pinned.id)["result"] == .string("7"))
    _ = try save(
      b, function("x*3", parameters: [parameter(unit: "EUR")], unit: "EUR"),
      logical: base.logicalID, base: updated.id)
    try refuses("definition_unit") { _ = try evaluate(b, live.id) }
    try expect(try evaluate(b, pinned.id)["result"] == .string("7"))
    _ = try b.verify()
  }
  check("function calls evaluate lazily and missing optional inputs never become zero") {
    let b = try book("Lazy")
    let bad = try save(b, function("1/0", parameters: []))
    let saved = try save(
      b,
      function(
        "IF(flag,bad,7)", parameters: [parameter("flag", type: "boolean")],
        calls: [call("bad", bad, arguments: [:])]))
    let result = try evaluate(b, saved.id, ["flag": .bool(false)])
    try expect(result["result"] == .string("7") && result["resolvedDefinitions"].array.count == 1)
    try refuses("division_by_zero") { _ = try evaluate(b, saved.id, ["flag": .bool(true)]) }
    let missing = try save(b, function("x+1", parameters: [parameter(required: false)]))
    try refuses("missing_value") { _ = try evaluate(b, missing.id, [:]) }
    try refuses("missing_value") { _ = try evaluate(b, missing.id, ["x": .null]) }
    try expect(try evaluate(b, missing.id, ["x": .string("0")])["result"] == .string("1"))
  }
  check("definition edits reject effective cycles and preserve prior authority atomically") {
    let b = try book("Cycles")
    let first = try save(b, function())
    let second = try save(b, function("a", calls: [call("a", first)]))
    let before = try b.counts()
    let history = try b.committedHistory()
    try refuses("definition_cycle") {
      _ = try save(
        b, function("b", calls: [call("b", second)]), logical: first.logicalID, base: first.id)
    }
    try expect(
      try b.applicationDefinition(first.logicalID).id == first.id && b.counts() == before
        && b.committedHistory() == history)
    try expect(try b.searchApplicationDefinitions("Reusable")["hits"].array.count == 2)
  }
  check(
    "definitions reject raw behavior, unknown formula names, unsupported functions and malformed parameters"
  ) {
    let b = try book("Refusals")
    for expression in [
      "ambient+1", "SUM(A1:A2)", "RAND()", "IF(x,1)", "ROUND(x)", "SUM()", "system(1)",
    ] {
      try refuses { _ = try save(b, function(expression)) }
    }
    try refuses("number") { _ = try Numbers.decimal("1\n") }
    var behavior = function().object
    behavior["kind"] = .string("workflow")
    try refuses { _ = try save(b, .object(behavior)) }
    behavior = function().object
    behavior["exec"] = .string("touch anything")
    try refuses { _ = try save(b, .object(behavior)) }
    try refuses { _ = try save(b, function(parameters: [parameter(), parameter()])) }
    try refuses { _ = try save(b, function(parameters: [parameter(extra: ["default": .null])])) }
    try refuses { _ = try save(b, function(parameters: [parameter(extra: ["min": .number(0)])])) }
    try expect(try b.revision() == 0)
  }
  check("definition retries, actors, exact stale bases and restore preserve complete history") {
    let b = try book("History")
    let logical = identifier()
    let token = identifier()
    let content = function()
    let first = try save(b, content, logical: logical, token: token, actor: .human("form"))
    let second = try save(b, function("x*3"), logical: logical, base: first.id)
    try refuses("stale_definition") { _ = try save(b, content, logical: logical, base: first.id) }
    try refuses("stale_definition") { _ = try save(b, content, logical: logical) }
    try expect(
      try save(b, content, logical: logical, token: token, actor: .human("form")).id == first.id)
    try refuses("idempotency") { _ = try save(b, content, logical: logical, token: token) }
    let restored = try b.restoreApplicationDefinition(
      logical, versionID: first.id, expectedDefinitionID: second.id)
    try expect(restored.version == 3 && restored.previousID == second.id && restored.id != first.id)
    try expect(try evaluate(b, logical)["result"] == .string("6"))
    try expect(
      try b.applicationDefinitionHistory(logical, beforeVersion: 3).map(\.id) == [
        second.id, first.id,
      ])
    _ = try b.verify()
  }
  check("late definition publication faults roll back source, head, dependency and FTS together") {
    let b = try book("Fault")
    let first = try save(b, function())
    let counts = try b.counts()
    let history = try b.committedHistory()
    try b.db.script(
      "CREATE TEMP TRIGGER fail_definition_publish BEFORE INSERT ON main.committed_changes BEGIN SELECT RAISE(ABORT,'injected publication fault'); END;"
    )
    try refuses {
      _ = try save(
        b, function("x+7", calls: [call("unused", first)], title: "Never published"),
        logical: first.logicalID, base: first.id)
    }
    try b.db.script("DROP TRIGGER temp.fail_definition_publish")
    try expect(
      try b.counts() == counts && b.committedHistory() == history
        && b.applicationDefinition(first.logicalID).id == first.id)
    try expect(try b.searchApplicationDefinitions("Never published")["hits"].array.isEmpty)
    _ = try b.verify()
  }
  check(
    "definition discovery indexes parameter labels, filters heads and refuses stale/cross-query continuations"
  ) {
    let b = try book("Search")
    let first = try save(
      b, function(parameters: [parameter("x", extra: ["label": .string("Quantity citrus")])]))
    _ = try save(b, function(title: "Another citrus"))
    let page = try b.searchApplicationDefinitions("citrus", limit: 1)
    try expect(page["hits"].array.count == 1 && page["nextCursor"].string != nil)
    let second = try b.searchApplicationDefinitions(
      "citrus", limit: 1, cursor: page["nextCursor"].text)
    try expect(
      second["hits"].array.count == 1
        && second["hits"].array[0]["id"] != page["hits"].array[0]["id"])
    try refuses("definition_cursor") {
      _ = try b.searchApplicationDefinitions("other", limit: 1, cursor: page["nextCursor"].text)
    }
    _ = try save(b, function(title: "Updated title"), logical: first.logicalID, base: first.id)
    try refuses("stale_definition_search") {
      _ = try b.searchApplicationDefinitions("citrus", limit: 1, cursor: page["nextCursor"].text)
    }
    try expect(try b.searchApplicationDefinitions("citrus")["hits"].array.count == 1)
    try expect(
      try b.searchApplicationDefinitions("citrus", historical: true)["hits"].array.count == 2)
  }
  check(
    "saved typed queries bind parameters, current rows and exact root continuations without business writes"
  ) {
    let b = try book("Query")
    let t = try table(b)
    let saved = try save(b, query(t))
    let history = try b.committedHistory()
    let result = try evaluate(b, saved.logicalID, ["minimum": .string("2.00")])
    try expect(
      result["result"]["rows"].array.count == 1
        && result["result"]["rows"].array[0]["values"]["price"] == .string("2.1"))
    let next = result["nextCursor"].text
    let continued = try b.evaluateApplicationDefinition(
      saved.id, arguments: .object(["minimum": .string("2.00")]), cursor: next)
    try expect(continued["result"]["rows"].array[0]["values"]["price"] == .string("3.2"))
    try expect(try b.committedHistory() == history)
    let updated = try save(b, query(t, title: "Changed"), logical: saved.logicalID, base: saved.id)
    try refuses("definition_cursor") {
      _ = try b.evaluateApplicationDefinition(
        updated.id, arguments: .object(["minimum": .string("2.00")]), cursor: next)
    }
    try refuses("definition_input") { _ = try evaluate(b, updated.id, [:]) }
    try refuses("definition_input") { _ = try evaluate(b, updated.id, ["minimum": .number(2)]) }
  }
  check(
    "live query schema bindings tolerate rename but reject changed meaning while exact mode refuses change"
  ) {
    let b = try book("QuerySchema")
    let t = try table(b)
    let live = try save(b, query(t))
    let exact = try save(b, query(t, mode: "exact"))
    let renamed = try b.updateDatasetDefinition(
      t.id, expectedVersion: t.version, expectedDefinitionID: t.definitionID,
      title: "Renamed costs",
      columns: [.init(id: "price", title: "Price renamed", type: "decimal", unit: "USD")])
    try expect(
      try evaluate(b, live.id, ["minimum": .string("1")])["result"]["sources"].array[0][
        "definitionID"] == .string(renamed.id))
    try refuses("stale_schema") { _ = try evaluate(b, exact.id, ["minimum": .string("1")]) }
    _ = try b.updateDatasetDefinition(
      t.id, expectedVersion: renamed.version, expectedDefinitionID: renamed.id,
      columns: [.init(id: "price", title: "Euro", type: "decimal", unit: "EUR")])
    try refuses("definition_schema") { _ = try evaluate(b, live.id, ["minimum": .string("1")]) }
    // Retained queries remain valid history even when current data meanings changed.
    _ = try b.verify()
  }
  check("definition saves and evaluation respect cancellation and graph depth bounds") {
    let b = try book("Limits")
    let first = try save(b, function())
    let cancelled = Cancellation()
    cancelled.cancel()
    let history = try b.committedHistory()
    try refuses {
      _ = try b.evaluateApplicationDefinition(
        first.id, arguments: .object(["x": .string("1")]), cancellation: cancelled)
    }
    try refuses { _ = try b.searchApplicationDefinitions("", cancellation: cancelled) }
    try refuses {
      _ = try b.saveApplicationDefinition(
        logicalID: identifier(), content: function(), cancellation: cancelled)
    }
    try expect(try b.committedHistory() == history)
    var previous = first
    for _ in 1..<16 { previous = try save(b, function("next", calls: [call("next", previous)])) }
    try refuses("definition_limit") {
      _ = try save(b, function("next", calls: [call("next", previous)]))
    }
    try expect(try evaluate(b, previous.id)["result"] == .string("6"))
  }
  check(
    "definition authority reconstructs inertly with FTS, exact dependencies, actors and portable reopen"
  ) {
    let b = try book("Replay")
    let first = try save(b, function(title: "Citrus exact function"))
    let caller = try save(b, function("call+1", calls: [call("call", first, live: false)]))
    let t = try table(b)
    let q = try save(b, query(t))
    let dependencies = try b.applicationDefinitionDependencies(caller.id)
    let history = try b.committedHistory(limit: 1000)
    let restored = try b.reconstruct(to: root.appendingPathComponent("Definitions-replayed.sevra"))
    try expect(try encoded(restored.applicationDefinition(caller.id)) == encoded(caller))
    try expect(
      try restored.applicationDefinitionDependencies(caller.id) == dependencies
        && restored.committedHistory(limit: 1000) == history)
    try expect(try restored.searchApplicationDefinitions("citrus")["hits"].array.count == 1)
    try expect(try evaluate(restored, caller.id)["result"] == .string("7"))
    try expect(
      try evaluate(restored, q.id, ["minimum": .string("3")])["result"]["rows"].array.count == 1)
    try b.rebuildSearch()
    try expect(try b.searchApplicationDefinitions("citrus")["hits"].array.count == 1)
    _ = try restored.verify()
  }
  check(
    "strict business dates reject calendar/clock rollover while preserving leap dates and explicit offsets"
  ) {
    try expect(try BusinessTime.normalized("2024-02-29") == "2024-02-29T00:00:00.000Z")
    try expect(
      try BusinessTime.normalized("2026-01-02T03:04:05-05:00") == "2026-01-02T08:04:05.000Z")
    for bad in [
      "2026-02-29", "2026-02-30", "2026-04-31", "2026-13-01", "2026-00-01", "0000-01-01",
      "2026-01-01T24:00:00Z", "2026-01-01T03:60:00Z", "2026-01-01T03:00:60Z",
      "2026-01-01T03:00:00+24:00", "2026-01-01T03:00:00+01:60", "2026-01-01T03:00:00",
      "2026-01-01 trailing", "2026-01-01\n", "2026-01-01\r\n",
    ] {
      try refuses("date") { _ = try BusinessTime.normalized(bad) }
    }
    let b = try book("InvalidEventDate")
    let source = try b.addItem(category: "source", kind: "observation", title: "Count")
    let history = try b.committedHistory()
    try refuses("date") {
      try b.setOpeningBalance(
        subject: "stock", quantity: "2", effective: "2026-02-30", sourceID: source.id)
    }
    try refuses("date") {
      _ = try b.movement(
        subject: "stock", quantity: "1", occurrence: "invalid", effective: "2026-02-30",
        input: source.id)
    }
    try expect(try b.committedHistory() == history)
  }
  check("definition logical IDs cannot collide with exact version IDs") {
    let b = try book("Identity")
    let saved = try save(b, function())
    let history = try b.committedHistory()
    try refuses("definition_identity") { _ = try save(b, function("x+3"), logical: saved.id) }
    try expect(
      try b.committedHistory() == history
        && b.applicationDefinition(saved.id).logicalID == saved.logicalID)
  }
  check("authoring Sources record actual saves without creating business approval tasks") {
    let b = try book("ReviewScope")
    let evidence = try b.addItem(
      category: "source", kind: "observation", title: "Evidence", status: "accepted")
    let pending = try b.addItem(
      category: "record", kind: "analysis", title: "Unreviewed forecast", meaning: "estimate",
      inputs: [evidence.id])
    let before = try b.reviewQueue()
    let saved = try save(
      b, function(), actor: .ai("synthetic-author", model: "test", policy: "draft-only"))
    let source = try b.item(saved.sourceID)
    try expect(source.meaning == "actual" && source.status == "accepted")
    try expect(
      source.data["actor"]["kind"] == .string("ai")
        && source.data["submitted"]["content"] == saved.content)
    try expect(try b.reviewQueue() == before && b.item(pending.id).status == "draft")
    _ = try evaluate(b, saved.id)
    try expect(try b.reviewQueue() == before && b.item(pending.id).meaning == "estimate")
  }
  check(
    "saved query integrity validation uses retained schemas without retargeting current meaning"
  ) {
    let b = try book("Integrity")
    let t = try table(b)
    let q = try save(b, query(t))
    _ = try b.updateDatasetDefinition(
      t.id, expectedVersion: t.version, expectedDefinitionID: t.definitionID,
      columns: [.init(id: "price", title: "Changed", type: "text")])
    _ = try b.verify()
    _ = try b.db.transaction {
      try b.db.execute(
        "UPDATE app_definition_dependencies SET ordinal=7 WHERE definition_id=?", [.string(q.id)])
    }
    try refuses("definition_integrity") { _ = try b.verify() }
  }
}
