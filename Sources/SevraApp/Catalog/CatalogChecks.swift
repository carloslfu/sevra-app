import Foundation
import SevraAppProtocol
import SevraCore

@MainActor enum CatalogChecks {
  static let stories = [
    "main.table", "home.component.table", "mini.helper.ActionForm", "chat.field.boolean",
    "chat.approval", "visual.chart.bar", "visual.work.board", "visual.diagram",
    "visual.overview", "visual.image", "composition.surfaces", "main.lifecycle",
  ]
  static func refuses(_ operation: () async throws -> Void) async throws {
    do { try await operation() } catch let e as SevraError where e.code != "catalog_check" {
      return
    }
    throw SevraError("catalog_check", "Expected adjacent refusal was accepted")
  }
  static func verify(_ session: CatalogSession) async throws {
    try require(
      stories.contains(session.story.id), "catalog_check",
      "No automated interaction check is declared for this example. Use the production controls and record a manual review."
    )
    guard let b = session.book, let state = session.state else {
      throw SevraError("catalog_check", "Missing workbook")
    }
    try require(
      b.url.path.hasPrefix(AppHost.root.path + "/"), "catalog_isolation",
      "Workbook escaped session root")
    try require(
      state.defaults !== UserDefaults.standard, "catalog_isolation", "Product defaults were used")
    if session.story.id == "main.table", let t = session.table {
      let row = try b.tablePage(t.id).rows[0]
      let before = row.data
      let edit = try b.editRows(
        t.id,
        edits: [
          .init(
            id: row.id, values: row.data.object.merging(["amount": .string("51.25")]) { _, n in n })
        ])
      try require(
        try b.item(row.logicalID).data["amount"] == .string("51.25"), "catalog_check",
        "Table edit was not saved")
      _ = try b.undoTableChange(edit.id)
      try require(
        try b.item(row.logicalID).data == before, "catalog_check",
        "Undo did not restore exact values")
      try await refuses {
        _ = try b.editRow(row.id, values: ["amount": .string("2")], expectedRevision: 0)
      }
    }
    if session.story.id == "home.component.table" {
      let home = try b.space("home")
      _ = try b.editSpace(
        home.id, expectedVersion: home.version,
        edits: [.init(operation: "rename", title: "Workshop Home")])
      try await refuses {
        _ = try b.editSpace(
          home.id, expectedVersion: home.version,
          edits: [.init(operation: "rename", title: "Stale title")])
      }
      try require(
        try b.space("home").title == "Workshop Home", "catalog_check",
        "A stale update replaced the current Home")
    }
    if session.story.id == "mini.helper.ActionForm", let app = session.app {
      let host = state.nativeAppSession(app, book: b)
      _ = try await host.converse("inspect")
      let table = app.definition.app!.datasets["stock"]!.datasetID!
      let before = try b.dataset(table).rowCount
      let result = try await host.converse(
        "run",
        arguments: .object([
          "action": .string("saveItem"),
          "inputs": .object(["name": .string("Native path"), "quantity": .string("3")]),
        ]))
      try require(
        result["outcome"] != .string("failed") && (try b.dataset(table).rowCount) == before + 1,
        "catalog_check", "App action did not persist one row")
      let invalid = try await host.converse(
        "run",
        arguments: .object([
          "action": .string("saveItem"),
          "inputs": .object(["name": .string("Invalid"), "quantity": .string("-1")]),
        ]))
      try require(
        invalid["outcome"] == .string("failed") && (try b.dataset(table).rowCount) == before + 1,
        "catalog_check", "Invalid action wrote a row")
      host.revoke()
      try require(
        !host.isGranted && host.tree.root == nil, "catalog_grant",
        "Revocation retained an active app")
      try await refuses {
        _ = try await host.converse(
          "run",
          arguments: .object([
            "action": .string("saveItem"),
            "inputs": .object(["name": .string("Revoked"), "quantity": .string("1")]),
          ]))
      }
    }
    if let input = try b.pendingConversationInput(conversation: b.chats()[0].id) {
      let field = input.input!.fields[0]
      let value: Value =
        field.type == .boolean
        ? .bool(false)
        : field.type == .decimal
          ? .string("12.50")
          : field.type == .date
            ? .string("2026-11-17")
            : field.type == .record
              ? .string(field.records!.rowIDs[0]) : .string("Include delivery")
      let revision = try b.conversationInputDraft(input)?.revision ?? 0
      let draft = try b.saveConversationInputDraft(
        input, values: ["answer": value], expectedRevision: revision)
      _ = try b.submitConversationInput(
        input, response: .fields(["answer": value]), draftRevision: draft.revision)
      try await refuses { _ = try b.submitConversationInput(input, response: .cancel) }
    }
    if let approval = try b.pendingChatApproval(conversation: b.chats()[0].id) {
      let claimed = try b.claimChatApproval(
        approval, conversation: b.chats()[0].id, cancel: false, humanText: "Confirm change")
      let result = try await state.performChatAction(
        claimed.action, arguments: claimed.arguments, book: b, readOnly: false,
        cancellation: .init(), confirmed: true)
      try b.finishChatApproval(claimed, conversation: b.chats()[0].id, result: result)
      try await refuses {
        _ = try b.claimChatApproval(
          approval, conversation: b.chats()[0].id, cancel: false, humanText: "Confirm change")
      }
    }
    if session.story.id == "composition.surfaces" {
      for _ in 0..<session.flowSteps.count { await session.replay() }
      try require(session.failure == nil, "catalog_check", session.failure ?? "")
    }
    if session.story.id == "main.lifecycle" {
      let draft = try b.conversationViewState(b.chats()[0].id).draft
      try await state.open(b.url)
      session.book = state.workbook
      try require(
        try b.conversationViewState(b.chats()[0].id).draft == draft && !draft.isEmpty, "catalog_check",
        "Reopen lost draft")
      let other = CatalogSession(story: session.story)
      await other.prepare()
      try require(
        other.ready && other.root != session.root && other.defaults !== session.defaults,
        "catalog_isolation", "Story fixtures were shared")
      _ = try other.book!.saveConversationViewState(
        other.book!.chats()[0].id, draft: "Other window", reading: .init(), expectedDraft: draft)
      try require(
        try b.conversationViewState(b.chats()[0].id).draft == draft, "catalog_isolation",
        "Another fixture changed this draft")
      await other.tearDown()
      try require(
        !FileManager.default.fileExists(atPath: other.root.path), "catalog_isolation",
        "Teardown left owned files")
      let pending = CatalogSession(
        story: CatalogRegistry.stories.first { $0.id == "mini.state.starting" }!)
      await pending.prepare()
      try require(pending.ready, "catalog_isolation", "Pending worker fixture did not prepare")
      let host = pending.state!.nativeAppSession(pending.app!, book: pending.book!)
      try require(host.status == "starting", "catalog_isolation", "Transport was not pending")
      await pending.tearDown()
      try require(
        host.status == "disabled" && host.tree.root == nil
          && !FileManager.default.fileExists(atPath: pending.root.path), "catalog_isolation",
        "Pending work survived teardown")
    }
    // Revocation is the terminal state of the authority checks, so it must not be
    // compared with the fixture's initial running state after the action succeeds.
    if let app = session.app {
      if state.nativeAppSession(app, book: session.book!).isGranted {
        try await session.validateFixture()
      }
    } else {
      try await session.validateFixture()
    }
    state.refresh()
    session.interactionChecked = true
    session.events.append(
      "Interaction checked · actual mutation plus adjacent refusal where applicable")
  }
}
