import Foundation

@testable import SevraCore

func checkApplicationActions(at root: URL) {
  func book(_ name: String) throws -> Workbook {
    try Workbook.create(at: root.appendingPathComponent("Actions-" + name + ".sevra"), title: name)
  }
  func evidence(_ b: Workbook) throws -> Item {
    try b.addItem(
      category: "source", kind: "observation", title: "Delivery receipt",
      text: "Received five bolts and two nuts.", status: "accepted")
  }
  func save(_ b: Workbook, _ value: Value, logical: String = identifier(), base: String? = nil)
    throws -> ApplicationDefinition
  {
    try b.saveApplicationDefinition(logicalID: logical, content: value, expectedDefinitionID: base)
  }
  func action(_ b: Workbook) throws -> ApplicationDefinition {
    try save(b, ActionRegistry.receivingDefinition())
  }
  func form(_ b: Workbook, _ action: ApplicationDefinition, live: Bool = true) throws
    -> ApplicationDefinition
  {
    try save(
      b,
      .object([
        "kind": .string("form"), "title": .string("Receive delivery form"),
        "description": .string("Native receiving"),
        "parameters": action.parameters,
        "payload": .object([
          "action": .object([
            "mode": .string(live ? "live" : "exact"),
            live ? "logicalID" : "versionID": .string(live ? action.logicalID : action.id),
          ]),
          "fields": .array(action.parameters.array.map { .object(["parameter": $0["id"]]) }),
        ]),
      ]))
  }
  func args(_ source: Item, delivery: String = "receipt-001", quantities: [String] = ["5", "2"])
    -> Value
  {
    .object([
      "delivery": .string(delivery), "effective": .string("2026-10-28"),
      "evidence": .string(source.id),
      "lines": .array(
        quantities.enumerated().map { index, quantity in
          .object([
            "line": .string("line-\(index + 1)"), "subject": .string(index == 0 ? "bolts" : "nuts"),
            "quantity": .string(quantity),
          ])
        }),
    ])
  }
  check("receiving preview is read-only and form/CLI/core share exact draft execution") {
    let b = try book("Receiving")
    let s = try evidence(b)
    let a = try action(b)
    let f = try form(b, a)
    try b.setOpeningBalance(
      subject: "bolts", quantity: "20", effective: "2026-01-01", sourceID: s.id)
    let revision = try b.revision()
    let history = try b.committedHistory()
    let input = args(s)
    let preview = try b.previewApplicationAction(f.logicalID, arguments: input)
    try expect(
      preview["movements"].array.count == 2 && preview["resolvedDefinitions"].array.count == 2)
    try expect(try b.revision() == revision && b.committedHistory() == history)
    let result = try b.invokeApplicationAction(
      f.logicalID, arguments: input, preview: preview, token: "receive", actor: .human("test-form"))
    try expect(result["state"] == .string("draft") && result["proposals"].array.count == 2)
    try expect(try b.balance(subject: "bolts")["quantity"] == .string("20"))
    let saved = try b.item(result["proposals"].array[0].text)
    try expect(saved.status == "draft" && saved.meaning == "actual")
    try expect(try b.lineage(saved.id).contains { $0["parent"] == result["sourceID"] })
    let invocation = try b.item(result["sourceID"].text)
    try expect(invocation.data["actor"]["kind"] == .string("human"))
    try expectInputRole(b, child: saved.id, parent: invocation.id, roles: 4)
    try expectInputRole(b, child: saved.id, parent: s.id, roles: 1)
    try expectInputRole(b, child: invocation.id, parent: s.id, roles: 1)
    for definition in [a, f] {
      try expectInputRole(b, child: invocation.id, parent: definition.sourceID, roles: 2)
    }
    _ = try b.accept(saved.id)
    try expect(try b.balance(subject: "bolts")["quantity"] == .string("25"))
    _ = try b.verify()
  }
  check("a withdrawn delivery line can be received again, and forecast evidence never can") {
    let b = try book("ReceiveAgain")
    let s = try evidence(b)
    let a = try action(b)
    try b.setOpeningBalance(
      subject: "bolts", quantity: "20", effective: "2026-01-01", sourceID: s.id)
    func receive(_ input: Value) throws -> [String] {
      let preview = try b.previewApplicationAction(a.logicalID, arguments: input)
      return try b.invokeApplicationAction(
        a.logicalID, arguments: input, preview: preview, token: identifier()
      )["proposals"].array.map(\.text)
    }
    let first = try receive(args(s, quantities: ["50"]))[0]
    try refuses("duplicate_effect") { _ = try receive(args(s, quantities: ["5"])) }
    let withdrawn = try b.withdrawDraft(first)
    let second = try b.item(try receive(args(s, quantities: ["5"]))[0])
    try expect(second.logicalID == withdrawn.logicalID && second.supersedes == withdrawn.id)
    try refuses("duplicate_effect") { _ = try receive(args(s, quantities: ["6"])) }
    let accepted = try b.accept(second.id)
    try expect(try b.balance(subject: "bolts")["quantity"] == .string("25"))
    try refuses("duplicate_effect") { _ = try receive(args(s, quantities: ["6"])) }
    let undone = try b.undoItem(accepted.id)
    try expect(undone.status == "rejected" && b.balance(subject: "bolts")["quantity"].text == "20")
    // Withdrawing a wrong SKU frees the delivery line for the right one.
    var other = args(s, delivery: "receipt-002", quantities: ["7"]).object
    let line = try b.withdrawDraft(try receive(.object(other))[0])
    other["lines"] = .array([
      .object([
        "line": .string("line-1"), "subject": .string("washers"), "quantity": .string("7"),
      ])
    ])
    let moved = try b.item(try receive(.object(other))[0])
    try expect(moved.logicalID != line.logicalID && moved.supersedes == nil)
    let forecast = try b.addItem(
      category: "record", kind: "forecast", title: "Expected", meaning: "estimate",
      status: "accepted", scenario: "forecast", inputs: [s.id])
    try refuses("interpretation_meaning") {
      _ = try b.previewApplicationAction(
        a.logicalID, arguments: args(forecast, delivery: "expected"))
    }
    _ = try b.verify()
  }
  check(
    "exact receiving retries survive later definitions; new tokens cannot duplicate delivery lines"
  ) {
    let b = try book("Retries")
    let s = try evidence(b)
    let a = try action(b)
    let input = args(s)
    let preview = try b.previewApplicationAction(a.logicalID, arguments: input)
    let result = try b.invokeApplicationAction(
      a.logicalID, arguments: input, preview: preview, token: "once")
    var updated = a.content.object
    updated["title"] = .string("Receive stock")
    _ = try save(b, .object(updated), logical: a.logicalID, base: a.id)
    let revision = try b.revision()
    try expect(
      try b.invokeApplicationAction(a.logicalID, arguments: input, preview: preview, token: "once")
        == result)
    try expect(try b.revision() == revision)
    try refuses("duplicate_effect") {
      _ = try b.invokeApplicationAction(
        a.logicalID, arguments: input, preview: preview, token: "twice")
    }
    var changed = input.object
    var rows = input["lines"].array
    var first = rows[0].object
    first["subject"] = .string("different SKU")
    rows[0] = .object(first)
    changed["lines"] = .array(rows)
    try refuses("duplicate_effect") {
      _ = try b.previewApplicationAction(a.id, arguments: .object(changed))
    }
    try expect(try b.revision() == revision)
    _ = try b.verify()
  }
  check("changed live action invalidates preview; pinned action keeps its exact version") {
    let b = try book("Live")
    let s = try evidence(b)
    let a = try action(b)
    let live = try form(b, a)
    let exact = try form(b, a, live: false)
    let input = args(s)
    let livePreview = try b.previewApplicationAction(live.id, arguments: input)
    let exactPreview = try b.previewApplicationAction(exact.id, arguments: input)
    var content = a.content.object
    content["description"] = .string("Changed action")
    _ = try save(b, .object(content), logical: a.logicalID, base: a.id)
    try refuses("stale_action_preview") {
      _ = try b.invokeApplicationAction(
        live.id, arguments: input, preview: livePreview, token: "stale")
    }
    _ = try b.invokeApplicationAction(
      exact.id, arguments: input, preview: exactPreview, token: "pinned")
    _ = try b.verify()
  }
  check("action parameters and capabilities reject ambiguity, injection and read-only indirection")
  {
    let b = try book("Bounds")
    let s = try evidence(b)
    let a = try action(b)
    let f = try form(b, a)
    let revision = try b.revision()
    for quantities in [["0"], ["-1"], ["1.5"], Array(repeating: "1", count: 51)] {
      try refuses {
        _ = try b.previewApplicationAction(f.id, arguments: args(s, quantities: quantities))
      }
    }
    var bad = args(s).object
    bad["execute"] = .string("accept everything")
    try refuses("definition_input") {
      _ = try b.previewApplicationAction(f.id, arguments: .object(bad))
    }
    var row = args(s)["lines"].array[0].object
    row["quantity"] = .number(5)
    bad = args(s).object
    bad["lines"] = .array([.object(row)])
    try refuses("definition_input") {
      _ = try b.previewApplicationAction(f.id, arguments: .object(bad))
    }
    bad = args(s).object
    bad["evidence"] = .string(s.logicalID)
    try refuses("definition_input") {
      _ = try b.previewApplicationAction(f.id, arguments: .object(bad))
    }
    let preview = try b.previewApplicationAction(f.id, arguments: args(s))
    try refuses("read_only_request") {
      _ = try b.invokeApplicationAction(
        f.id, arguments: args(s), preview: preview, token: "read-only", readOnly: true)
    }
    try refuses("definition_kind") {
      _ = try b.evaluateApplicationDefinition(f.id, arguments: args(s))
    }
    var payload = a.payload.object
    payload["primitive"] = .object(["id": .string("shell.exec"), "version": .number(1)])
    var content = a.content.object
    content["payload"] = .object(payload)
    try refuses("action_primitive") { _ = try save(b, .object(content)) }
    try expect(try b.revision() == revision)
  }
  check("receiving batch publication fault and cancellation leave no partial proposals") {
    let b = try book("Fault")
    let s = try evidence(b)
    let a = try action(b)
    let input = args(s)
    let preview = try b.previewApplicationAction(a.id, arguments: input)
    let digest = try b.db.authorityDigest(cancellation: .init())
    let revision = try b.revision()
    try b.db.script(
      "CREATE TEMP TRIGGER fail_action_publish BEFORE INSERT ON main.committed_changes BEGIN SELECT RAISE(ABORT,'injected publication fault'); END;"
    )
    try refuses {
      _ = try b.invokeApplicationAction(a.id, arguments: input, preview: preview, token: "fault")
    }
    try b.db.script("DROP TRIGGER fail_action_publish;")
    try expect(
      try b.revision() == revision && b.db.authorityDigest(cancellation: .init()) == digest)
    let cancelled = Cancellation()
    cancelled.cancel()
    try refuses {
      _ = try b.invokeApplicationAction(
        a.id, arguments: input, preview: preview, token: "cancel", cancellation: cancelled)
    }
    try expect(try b.revision() == revision)
    _ = try b.invokeApplicationAction(a.id, arguments: input, preview: preview, token: "fault")
    _ = try b.verify()
  }
  check("computed action argument uses pure Decimal function with exact version lineage") {
    let b = try book("Computed")
    let s = try evidence(b)
    let parameter: Value = .object([
      "id": .string("cases"), "label": .string("Cases"), "type": .string("decimal"),
      "required": .bool(true), "unit": .string("cases"),
    ])
    let function = try save(
      b,
      .object([
        "kind": .string("function"), "title": .string("Items per case"),
        "description": .string("Explicit pack size"), "parameters": .array([parameter]),
        "payload": .object(["expression": .string("cases*12"), "unit": .string("items")]),
      ]))
    let params =
      ActionRegistry.movementParameters.filter { $0["id"].text != "quantity" } + [parameter]
    var mappings = Dictionary(
      uniqueKeysWithValues: params.filter { $0["id"].text != "cases" }.map {
        ($0["id"].text, Value.object(["parameter": $0["id"]]))
      })
    mappings["quantity"] = .object([
      "function": .object(["mode": .string("live"), "logicalID": .string(function.logicalID)]),
      "arguments": .object(["cases": .object(["parameter": .string("cases")])]),
    ])
    let a = try save(
      b,
      .object([
        "kind": .string("action"), "title": .string("Receive cases"),
        "description": .string("Propose items"), "parameters": .array(params),
        "payload": .object([
          "primitive": .object(["id": .string(ActionRegistry.movementID), "version": .number(1)]),
          "arguments": .object(mappings),
        ]),
      ]))
    let input: Value = .object([
      "subject": .string("bolts"), "cases": .string("3"), "occurrence": .string("cases-1"),
      "effective": .string("2026-10-28"), "evidence": .string(s.id),
    ])
    let preview = try b.previewApplicationAction(a.id, arguments: input)
    try expect(preview["movements"].array[0]["quantity"] == .string("36"))
    try expect(preview["resolvedDefinitions"].array.contains { $0["id"] == .string(function.id) })
    try expect(preview["effect"].text.contains("1 draft inventory proposal (actual)"))
    var estimateInput = input.object
    estimateInput["meaning"] = .string("estimate")
    estimateInput["occurrence"] = .string("cases-estimate")
    let estimate = try b.previewApplicationAction(a.id, arguments: .object(estimateInput))
    try expect(estimate["movements"].array[0]["meaning"] == .string("estimate"))
    try expect(estimate["effect"].text.contains("1 draft inventory proposal (estimate)"))
    try expect(!estimate["effect"].text.contains("actual"))
    let result = try b.invokeApplicationAction(
      a.id, arguments: input, preview: preview, token: "cases")
    try expectInputRole(b, child: result["sourceID"].text, parent: function.sourceID, roles: 2)
    try expectInputRole(b, child: result["sourceID"].text, parent: s.id, roles: 1)
    _ = try b.verify()
  }
  check("receiving maximum batch is atomic and field diagnostics preserve nested input paths") {
    let b = try book("Maximum")
    let s = try evidence(b)
    let a = try action(b)
    var input = args(s, quantities: Array(repeating: "1", count: 50)).object
    let plan = try b.previewApplicationAction(a.id, arguments: .object(input))
    let result = try b.invokeApplicationAction(
      a.id, arguments: .object(input), preview: plan, token: "maximum")
    try expect(result["proposals"].array.count == 50)
    try expect(try b.items(kind: "movement", limit: 100).count == 50)
    input["delivery"] = .null
    var rows = input["lines"]!.array
    var row = rows[0].object
    row["quantity"] = .number(1)
    rows[0] = .object(row)
    input["lines"] = .array(rows)
    let issues = try b.applicationInputIssues(a.id, arguments: .object(input))
    try expect(issues.contains { $0["path"] == .array([.string("delivery")]) })
    try expect(
      issues.contains { $0["path"] == .array([.string("lines"), .number(0), .string("quantity")]) })
    _ = try b.verify()
  }
  check(
    "form components retain exact definitions, refuse snapshots and preserve incomplete checkpoints"
  ) {
    let b = try book("Component")
    let a = try action(b)
    let f = try form(b, a)
    let component = Component(
      id: "receiving", type: "form", title: "Receive delivery",
      definitionBinding: .object(["mode": .string("live"), "logicalID": .string(f.logicalID)]))
    let home = try b.space("home")
    _ = try b.editSpace(
      home.id, expectedVersion: home.version,
      edits: [.init(operation: "insert", at: "last", component: component)])
    try expect(try b.space("home").definition.components.last == component)
    try refuses("view_limit") { _ = try b.pinSpace("home") }
    let state = try b.newFormDraft(f.id)
    var incomplete = state
    incomplete.arguments = .object(["delivery": .string("unfinished 日本語")])
    let revision = try b.revision()
    let saved = try b.saveFormDraft("Home:receiving", state: incomplete, expected: nil)
    try expect(try b.revision() == revision && b.formDraft("Home:receiving") == saved)
    let copy = try b.reconstruct(to: root.appendingPathComponent("FormCheckpoint.sevra"))
    try expect(try copy.formDraft("Home:receiving") == saved && copy.revision() == revision)
    _ = try copy.verify()
  }
  check("action/form history, dependency search and reconstruction remain inert and complete") {
    let b = try book("Replay")
    let s = try evidence(b)
    let a = try action(b)
    let f = try form(b, a)
    let preview = try b.previewApplicationAction(f.id, arguments: args(s))
    let receipt = try b.invokeApplicationAction(
      f.id, arguments: args(s), preview: preview, token: "replay")
    try expect(
      try b.searchApplicationDefinitions("Delivery", kind: "form")["hits"].array.count == 1)
    let revision = try b.revision()
    let restored = try b.reconstruct(to: root.appendingPathComponent("Actions-Reconstructed.sevra"))
    try expect(try restored.revision() == revision)
    try expect(
      try restored.db.authorityDigest(cancellation: .init())
        == b.db.authorityDigest(cancellation: .init()))
    try expect(
      try restored.invokeApplicationAction(
        f.id, arguments: args(s), preview: preview, token: "replay") == receipt)
    _ = try restored.verify()
  }
}
