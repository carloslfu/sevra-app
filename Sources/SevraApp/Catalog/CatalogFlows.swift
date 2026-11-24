import Foundation
import SevraAI
import SevraAppProtocol
import SevraCore

/// Small executable journeys. Business effects go through production APIs and the
/// same named chat actions as the app; the driver supplies only synthetic intent.
enum CatalogFlows {
  static func steps(_ id: String) -> [String] {
    switch id {
    case "composition.first-workbook":
      return [
        "Include synthetic quotes", "Open Home", "Ask for an exact captured chart",
        "Inspect source",
      ]
    case "composition.supplier":
      return [
        "Answer the saved question", "Capture exact comparison", "Add live view to Home",
        "Change data and compare with captured answer",
      ]
    case "composition.inventory":
      return [
        "Save through the shared app action", "Run the chat equivalent", "Undo the chat change",
        "Redo and reopen",
      ]
    case "composition.projects":
      return [
        "Open board", "Open calendar and timeline", "Inspect dependency diagram",
        "Open exact task record",
      ]
    case "composition.overview":
      return [
        "Show overview in chat", "Add current overview to Home", "Inspect original source",
        "Reopen saved arrangement",
      ]
    case "composition.evidence":
      return ["Read PDF", "Read image", "Inspect referenced recommendation", "Open pending review"]
    case "composition.excel":
      return [
        "Save inferred purpose and questions", "Use imported tables",
        "Build a checked native table workspace", "Compare original and reopen import",
      ]
    case "composition.interrupted":
      return [
        "Save independent question drafts", "Reopen with questions retained", "Answer exactly once",
        "Refuse the stale answer",
      ]
    case "composition.workflow":
      return [
        "Open waiting workflow", "Inspect pending proposals", "Accept the synthetic proposal",
        "Continue to completed receipt",
      ]
    case "composition.surfaces":
      return [
        "Place captured and live views together", "Change one shared record",
        "Save an app display preset", "Change app version and require a new grant", "Revoke access",
      ]
    default: return ["Exercise the surface", "Reopen saved fixture"]
    }
  }
}
@MainActor extension CatalogSession {
  var flowSteps: [String] { CatalogFlows.steps(story.id) }
  func runFlowStep() async throws {
    guard let b = book, let ws = state else {
      throw SevraError("catalog_flow", "Fixture is closed")
    }
    let id = story.id
    switch id {
    case "composition.first-workbook":
      if step == 0 {
        source = try b.addItem(
          category: "source", kind: "note", title: "Synthetic quote observations",
          text: "Costs exclude unknown tax", status: "accepted")
        try seedFiles(b)
        table = try b.createDataset(
          title: "Supplier quotes",
          columns: [
            .init(id: "name", title: "Supplier"),
            .init(id: "amount", title: "Cost", type: "decimal", unit: "USD"),
          ],
          rows: [
            ["name": .string("Oak"), "amount": .string("24")],
            ["name": .string("Cedar"), "amount": .string("27.50")],
          ], sourceID: fileItems["csv"]!)
        visual = .init(chart: try chart())
        ws.refresh()
        ws.route = .table(table!.id)
        events.append("Included synthetic CSV and opened its exact table")
      } else if step == 1 {
        ws.route = .space("home")
      } else if step == 2 {
        _ = try await captureVisual(b)
        ws.refresh()
      } else {
        ws.route = .item(fileItems["csv"]!)
      }
    case "composition.supplier":
      if step == 0, let input {
        _ = try b.submitConversationInput(
          input, response: .fields(["answer": .string("Goods and delivery")]))
      } else if step == 1 {
        _ = try await captureVisual(b)
      } else if step == 2 {
        try promoteLatestCapture(b)
        ws.route = .space("home")
      } else {
        try changeFirstRow(b)
        try compareCapturedAndCurrent(b)
      }
    case "composition.inventory":
      let app = app!
      let host = ws.nativeAppSession(app, book: b)
      if step == 0 {
        let result = try await host.converse(
          "run",
          arguments: .object([
            "action": .string("saveItem"),
            "inputs": .object(["name": .string("Pencils from controls"), "quantity": .string("3")]),
          ]))
        events.append("Native action receipt: " + result["outcome"].text)
      } else if step == 1 {
        _ = try await runChatAction(
          "app.run",
          arguments: .object([
            "id": .string(app.id), "expectedVersion": .number(Double(app.version)),
            "action": .string("saveItem"),
            "inputs": .object(["name": .string("Pencils from chat"), "quantity": .string("3")]),
          ]))
      } else if step == 2 {
        _ = try await host.converse("undo")
      } else {
        _ = try await host.converse("redo")
        try await ws.open(b.url)
        ws.route = .space(app.id)
      }
    case "composition.projects":
      if step == 0 {
        ws.route = .space("example")
      } else if step == 1 {
        try presentSpace(
          b,
          components: [
            .init(
              type: "visual", title: "Calendar", visual: try makeVisual("visual.work.calendar")),
            .init(
              type: "visual", title: "Timeline", visual: try makeVisual("visual.work.timeline")),
          ])
      } else if step == 2 {
        try presentSpace(
          b,
          components: [
            .init(type: "visual", title: "Dependencies", visual: try makeVisual("visual.diagram"))
          ])
      } else {
        ws.route = .item(try b.tablePage(tasks!.id).rows[0].id)
      }
    case "composition.overview":
      if step == 0 {
        _ = try await captureVisual(b)
      } else if step == 1 {
        try promoteLatestCapture(b)
        ws.route = .space("home")
      } else if step == 2 {
        ws.route = .item(source!.id)
      } else {
        try await ws.open(b.url)
        ws.route = .space("home")
      }
    case "composition.evidence":
      ws.route =
        step == 3
        ? .reviews : .item(fileItems[step == 0 ? "pdf" : step == 1 ? "image" : "references"]!)
    case "composition.excel": try await advanceExcel(b, ws)
    case "composition.interrupted":
      let pending = try b.pendingConversationInputs(conversation: b.chats()[0].id)
      if step == 0 {
        for (i, q) in pending.enumerated() {
          _ = try b.saveConversationInputDraft(
            q, values: ["answer": .string("Independent draft \(i+1)")], expectedRevision: 0)
        }
      } else if step == 1 {
        try await ws.open(b.url)
      } else if step == 2, let input {
        let previous = try b.conversationInputDraft(input)?.revision ?? 0
        let draft = try b.saveConversationInputDraft(
          input, values: ["answer": .string("Include delivery")], expectedRevision: previous)
        _ = try b.submitConversationInput(
          input, response: .fields(["answer": .string("Include delivery")]),
          draftRevision: draft.revision)
      } else if let input {
        do {
          _ = try b.submitConversationInput(input, response: .cancel)
          throw SevraError("catalog_check", "A closed question accepted a second answer")
        } catch let e as SevraError where e.code != "catalog_check" {
          events.append("Stale submission refused: " + e.message)
        }
      }
    case "composition.workflow":
      let run = workflowRunID!
      if step == 0 {
        ws.route = .workflow(run)
      } else if step == 1 {
        ws.route = .reviews
      } else if step == 2 {
        let r = try b.workflowRun(run)
        for p in r["steps"].array[0]["output"]["value"]["proposals"].array {
          _ = try b.accept(p.text)
        }
      } else {
        let authority = try b.authorizeWorkflowExecution(run)
        _ = try b.advanceWorkflow(authority, owner: "catalog")
        ws.route = .workflow(run)
      }
    case "composition.surfaces": try await advanceSurfaces(b, ws)
    default:
      if step == 0, let app {
        let host = ws.nativeAppSession(app, book: b)
        if id == "mini.state.revoke" {
          host.revoke()
        } else if id == "mini.state.stale-version" {
          var package = app.definition.app!
          package.name += " revised"
          _ = try b.installNativeApp(package, spaceID: app.id, expectedVersion: app.version)
          do {
            _ = try await host.converse(
              "run",
              arguments: .object([
                "action": .string("saveItem"),
                "inputs": .object(["name": .string("Stale"), "quantity": .string("1")]),
              ]))
          } catch { events.append("Old app refused: " + error.localizedDescription) }
        } else if id == "mini.state.draft" || id == "mini.helper.draftSignal" {
          _ = try await host.converse(
            "set",
            arguments: .object([
              "target": .string("Saved draft"), "value": .string("Restored after restart"),
            ]))
          host.stop()
          host.start()
        } else {
          _ = try await host.converse("inspect")
          events.append("App semantic inspection succeeded")
        }
      } else if step == 0, let q = try b.pendingConversationInput(conversation: b.chats()[0].id) {
        let value: Value =
          q.input!.fields[0].type == .boolean
          ? .bool(false)
          : q.input!.fields[0].type == .decimal
            ? .string("12.50")
            : q.input!.fields[0].type == .date
              ? .string("2026-11-17")
              : q.input!.fields[0].type == .record
                ? .string(q.input!.fields[0].records!.rowIDs[0]) : .string("Include delivery")
        _ = try b.submitConversationInput(q, response: .fields(["answer": value]))
      } else if step == 0, let approval = try b.pendingChatApproval(conversation: b.chats()[0].id) {
        let claimed = try b.claimChatApproval(
          approval, conversation: b.chats()[0].id, cancel: false, humanText: "Confirm change")
        let result = try await ws.performChatAction(
          claimed.action, arguments: claimed.arguments, book: b, readOnly: false,
          cancellation: .init(), confirmed: true)
        try b.finishChatApproval(claimed, conversation: b.chats()[0].id, result: result)
      } else if step == 0, story.id == "home.counter" {
        // One press through the production path. The count above the button goes up by one.
        _ = try b.pressButton(
          spaceID: "home", componentID: "add", actor: .human("Sevra view button"))
      } else if step == 0, story.id == "home.layout" || story.id == "home.limits" {
        _ = try b.editSpace(
          "home", expectedVersion: b.space("home").version,
          edits: [.init(operation: "rename", title: "Workshop home")])
      } else {
        try await ws.open(b.url)
        events.append("Reopened fixture with production draft restoration")
      }
    }
    ws.refresh()
  }
  func presentSpace(_ b: Workbook, components: [Component]) throws {
    let current = try b.space("example")
    _ = try b.saveSpace(
      id: current.id, title: current.title, definition: .init(components: components),
      expectedVersion: current.version)
    state?.route = .space(current.id)
  }
  func promoteLatestCapture(_ b: Workbook) throws {
    let captures = try b.workspaceSnapshot(conversation: b.chats()[0].id)!.visuals
    guard
      let message = try b.conversationWindow(conversation: b.chats()[0].id).messages.reversed().first(
        where: { captures[$0.id]?.isEmpty == false })
    else { throw SevraError("catalog_flow", "Capture the view first") }
    _ = try b.promoteConversationVisual(
      message.id, index: 0, conversation: b.chats()[0].id, expectedVersion: b.space("home").version)
  }
  func changeFirstRow(_ b: Workbook) throws {
    let t = table!
    let row = try b.tablePage(t.id).rows[0]
    _ = try b.editRow(
      row.id,
      values: [t.columns.contains { $0.id == "quantity" } ? "quantity" : "amount": .string("99")])
  }
  func compareCapturedAndCurrent(_ b: Workbook) throws {
    let chart = visual!.chart!
    let live = try b.chartData(chart)
    let captures = try b.workspaceSnapshot(conversation: b.chats()[0].id)!.visuals.values.flatMap { $0 }
      .compactMap(\.chartData)
    try require(
      captures.contains { $0 != live }, "catalog_semantics",
      "Captured and current values did not diverge")
    events.append("Verified: historical chat retained its exact values; the live view now reads 99")
  }
  func runChatAction(_ name: String, arguments: Value) async throws -> AgentResult {
    let b = book!
    let ws = state!
    return try await WorkbookAgent.run(
      "Perform the synthetic " + name, workbook: b, conversation: b.chats()[0].id,
      // Chat offers the seven general tools; a named action is run with its arguments.
      model: CatalogInference([
        ("run", .object(["action": .object(["name": .string(name), "arguments": arguments])]))
      ]),
      workspaceAction: { name, args, readOnly, cancel in
        try await ws.performChatAction(
          name, arguments: args, book: b, readOnly: readOnly, cancellation: cancel)
      }, conversationInput: true)
  }
  func advanceSurfaces(_ b: Workbook, _ ws: WorkspaceState) async throws {
    let app = app!
    if step == 0 {
      try promoteLatestCapture(b)
      _ = try await ws.performChatAction(
        "visual.app_pin",
        arguments: .object([
          "id": .string(app.id), "expectedVersion": .number(Double(app.version)),
          "viewID": .string("stockView"),
          "homeVersion": .number(Double(try b.space("home").version)),
        ]), book: b, readOnly: false, cancellation: .init())
      ws.route = .space("home")
    } else if step == 1 {
      try changeFirstRow(b)
      try compareCapturedAndCurrent(b)
    } else if step == 2 {
      _ = try await ws.performChatAction(
        "visual.app_preset",
        arguments: .object([
          "id": .string(app.id), "expectedVersion": .number(Double(app.version)),
          "viewID": .string("stockView"), "title": .string("Horizontal stock"),
          "style": .string("horizontalBar"),
        ]), book: b, readOnly: false, cancellation: .init())
    } else if step == 3 {
      var package = app.definition.app!
      package.name = "Workshop app revised"
      self.app = try b.installNativeApp(package, spaceID: app.id, expectedVersion: app.version)
      events.append(
        "New version has no grant; the existing Home embed retains its exact version boundary")
    } else {
      ws.nativeAppSession(self.app!, book: b).revoke()
      events.append("Access revoked; captured chat remains readable")
    }
  }
  func advanceExcel(_ b: Workbook, _ ws: WorkspaceState) async throws {
    var draft = try b.excelConversion(excelID!)
    if step == 0 {
      draft = try b.saveExcelConversionPlan(
        draft.id, expectedVersion: draft.version,
        plan: .object([
          "name": .string("Supplier comparison"),
          "purpose": .string("Compare quoted supplier costs"),
          "workflows": .array([.string("Inspect and correct quotes")]),
          "questions": .array([.string("Does delivery cost extra?")]),
        ]), model: "catalog-script")
    } else if step == 1 {
      draft = try b.importExcelConversionTables(draft.id)
    } else if step == 2 {
      let build = try b.prepareExcelConversionBuild(draft.id)
      let t = build.tables[0]
      let package = NativeAppPackage(
        name: "Supplier comparison",
        source:
          "Sevra.mount(Sevra.h(Sevra.Column,{padding:16},Sevra.h(Sevra.Text,{text:'Review original quotes'}),Sevra.h(Sevra.Table,{table:'sheet1',label:'Quotes',height:300})));",
        datasets: [
          "sheet1": .init(title: t.title, columns: t.columns, writable: true, datasetID: t.id)
        ])
      let check = try await NativeAppCheck.run(
        package: package,
        steps: [.object(["kind": .string("expect_control"), "target": .string("Quotes")])])
      app = try b.installExcelConversionApp(
        package, build: build, check: check, token: identifier(), cancellation: .init())
      events.append("Actual sandbox control check and original-result comparison passed")
    } else {
      events.append(
        "Original comparison: " + (try b.excelConversion(draft.id).record.data["comparison"].json())
      )
      try await ws.open(b.url)
    }
    ws.route = .excelImport(draft.id)
  }
}
