import Foundation

@testable import SevraCore

func checkApplicationActions(at root: URL) {
  func book(_ name: String) throws -> Workbook {
    try Workbook.create(at: root.appendingPathComponent("Actions-" + name + ".sevra"), title: name)
  }
  func evidence(_ b: Workbook) throws -> Item {
    try b.addItem(
      category: "source", kind: "observation", title: "Supplier quote",
      text: "Oak Supply quoted 2.40 each for ten bolts.", status: "accepted")
  }
  func save(_ b: Workbook, _ value: Value, logical: String = identifier(), base: String? = nil)
    throws -> ApplicationDefinition
  {
    try b.saveApplicationDefinition(logicalID: logical, content: value, expectedDefinitionID: base)
  }
  func action(_ b: Workbook) throws -> ApplicationDefinition {
    try save(
      b,
      ActionRegistry.documentDefinition(
        title: "Draft a supplier note", description: "Draft a note from a quote"))
  }
  func form(_ b: Workbook, _ action: ApplicationDefinition, live: Bool = true) throws
    -> ApplicationDefinition
  {
    try save(
      b,
      .object([
        "kind": .string("form"), "title": .string("Supplier note form"),
        "description": .string("Native note"),
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
  func args(_ source: Item, title: String = "Oak quote", meaning: String = "actual") -> Value {
    .object([
      "title": .string(title), "body": .string("Oak Supply quotes 2.40 each."),
      "evidence": .string(source.id), "meaning": .string(meaning), "scenario": .string("actual"),
    ])
  }
  check("a preview is read-only, its forecast evidence cannot become actual, and form and core share one draft") {
    let b = try book("Preview")
    let s = try evidence(b)
    let a = try action(b)
    let f = try form(b, a)
    let revision = try b.revision()
    let history = try b.committedHistory()
    let input = args(s)
    let preview = try b.previewApplicationAction(f.logicalID, arguments: input)
    try expect(
      preview["documents"].array.count == 1 && preview["resolvedDefinitions"].array.count == 2)
    try expect(try b.revision() == revision && b.committedHistory() == history)
    let result = try b.invokeApplicationAction(
      f.logicalID, arguments: input, preview: preview, token: "note", actor: .human("test-form"))
    try expect(result["state"] == .string("draft") && result["proposals"].array.count == 1)
    let saved = try b.item(result["proposals"].array[0].text)
    try expect(saved.status == "draft" && saved.kind == "document" && saved.meaning == "actual")
    let invocation = try b.item(result["sourceID"].text)
    try expect(invocation.data["actor"]["kind"] == .string("human"))
    try expect(try b.accept(saved.id).status == "accepted")
    let forecast = try b.addItem(
      category: "record", kind: "forecast", title: "Expected", meaning: "estimate",
      status: "accepted", scenario: "forecast", inputs: [s.id])
    try refuses("interpretation_meaning") {
      _ = try b.previewApplicationAction(a.logicalID, arguments: args(forecast))
    }
    _ = try b.verify()
  }
  check("an exact retry survives a later definition and a new token saves a separate draft") {
    let b = try book("Retries")
    let s = try evidence(b)
    let a = try action(b)
    let input = args(s)
    let preview = try b.previewApplicationAction(a.logicalID, arguments: input)
    let result = try b.invokeApplicationAction(
      a.logicalID, arguments: input, preview: preview, token: "once")
    var updated = a.content.object
    updated["title"] = .string("Draft a quote note")
    _ = try save(b, .object(updated), logical: a.logicalID, base: a.id)
    let revision = try b.revision()
    try expect(
      try b.invokeApplicationAction(a.logicalID, arguments: input, preview: preview, token: "once")
        == result)
    try expect(try b.revision() == revision)
    try refuses("stale_action_preview") {
      _ = try b.invokeApplicationAction(
        a.logicalID, arguments: input, preview: preview, token: "twice")
    }
    try expect(try b.revision() == revision)
    let fresh = try b.previewApplicationAction(a.logicalID, arguments: input)
    let twice = try b.invokeApplicationAction(
      a.logicalID, arguments: input, preview: fresh, token: "twice")
    try expect(twice["proposals"] != result["proposals"] && b.revision() > revision)
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
    for title in ["", " ", String(repeating: "x", count: 2049)] {
      try refuses { _ = try b.previewApplicationAction(f.id, arguments: args(s, title: title)) }
    }
    var bad = args(s).object
    bad["execute"] = .string("accept everything")
    try refuses("definition_input") {
      _ = try b.previewApplicationAction(f.id, arguments: .object(bad))
    }
    bad = args(s).object
    bad["title"] = .number(5)
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
  check("a publication fault and cancellation leave no partial proposals") {
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
  check(
    "form components retain exact definitions, refuse snapshots and preserve incomplete checkpoints"
  ) {
    let b = try book("Component")
    let a = try action(b)
    let f = try form(b, a)
    let component = Component(
      id: "note", type: "form", title: "Supplier note",
      definitionBinding: .object(["mode": .string("live"), "logicalID": .string(f.logicalID)]))
    let home = try b.space("home")
    _ = try b.editSpace(
      home.id, expectedVersion: home.version,
      edits: [.init(operation: "insert", at: "last", component: component)])
    try expect(try b.space("home").definition.components.last == component)
    try refuses("view_limit") { _ = try b.pinSpace("home") }
    let state = try b.newFormDraft(f.id)
    var incomplete = state
    incomplete.arguments = .object(["title": .string("unfinished 日本語")])
    let revision = try b.revision()
    let saved = try b.saveFormDraft("Home:note", state: incomplete, expected: nil)
    try expect(try b.revision() == revision && b.formDraft("Home:note") == saved)
    let copy = try b.reconstruct(to: root.appendingPathComponent("FormCheckpoint.sevra"))
    try expect(try copy.formDraft("Home:note") == saved && copy.revision() == revision)
    _ = try copy.verify()
    // A window whose empty draft gave up its slot in a full workbook just saves again.
    let spare = try b.saveFormDraft("spare", state: state, expected: nil)
    for index in 0..<254 {
      _ = try b.saveFormDraft("filler\(index)", state: incomplete, expected: nil)
    }
    _ = try b.saveFormDraft("newest", state: state, expected: nil)
    try expect(try b.formDraft("spare") == nil)
    var typed = spare
    typed.arguments = .object(["title": .string("typed later")])
    try expect(try b.saveFormDraft("spare", state: typed, expected: spare) == typed)
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
      try b.searchApplicationDefinitions("Supplier", kind: "form")["hits"].array.count == 1)
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
