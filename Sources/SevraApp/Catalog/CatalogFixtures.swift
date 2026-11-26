import AppKit
import SevraAI
import SevraCore
import SevraProduct
import SevraVoice

@MainActor extension CatalogSession {
  func seedBusiness(_ b: Workbook, _ ws: WorkspaceState) async throws {
    let id = story.id
    if id == "main.welcome" {
      defaults.set(
        variant == "Empty"
          ? []
          : (0..<(variant == "Dense" ? 9 : 3)).map {
            root.appendingPathComponent("Workshop \($0+1).sevra").path
          }, forKey: "recentWorkbooks")
    }
    if id == "main.tools" && variant == "Default" {
      // One tool saved here, so enabled here.
      _ = try b.chatSaveTool(
        name: "table_names", description: "The names of this workbook's tables.", inputs: [],
        statements: ["SELECT name FROM tables ORDER BY name"], source: nil,
        token: "catalog-tool", requestSourceID: nil)
      // One as a copied workbook brings it: saved, with no grant on this Mac.
      _ = try b.saveApplicationDefinition(
        logicalID: identifier(),
        content: .object([
          "kind": .string("tool"), "title": .string("reorder_check"),
          "description": .string("Counts the parts below a reorder level."),
          "parameters": .array([
            .object([
              "id": .string("level"), "label": .string("level"), "type": .string("decimal"),
              "required": .bool(true),
            ])
          ]),
          "payload": .object([
            "name": .string("reorder_check"), "language": .string("javascript"),
            "source": .string(
              "const rows = await sql('SELECT count(*) AS n FROM stock WHERE quantity < :level', {level: inputs.level}); return rows[0].n;"
            ),
          ]),
        ]))
    }
    if id == "main.definitions" {
      _ = try b.saveSpace(
        id: "example", title: "Calculations and forms",
        definition: .init(components: [
          try spaceComponent("calculation"), try spaceComponent("query"),
          try spaceComponent("form"),
        ]))
    }
    if id.contains("workflow") || id == "main.automations" || id == "main.automation-detail"
      || id == "home.attention"
    {
      let action = try b.saveApplicationDefinition(
        logicalID: identifier(),
        content: ActionRegistry.documentDefinition(
          title: "Draft a supplier note", description: "Synthetic note; review before accepting"))
      let workflow = try b.saveApplicationDefinition(
        logicalID: identifier(),
        content: .object([
          "kind": .string("workflow"), "title": .string("Draft and review"),
          "description": .string("Synthetic supplier note; each draft needs review"),
          "parameters": action.parameters,
          "payload": .object([
            "readPolicy": .string("latest-at-step"),
            "steps": .array([
              .object([
                "id": .string("draft"), "kind": .string("action"),
                "binding": .object(["mode": .string("exact"), "versionID": .string(action.id)]),
                "arguments": .object(
                  Dictionary(
                    uniqueKeysWithValues: action.parameters.array.map {
                      ($0["id"].text, Value.object(["parameter": $0["id"]]))
                    })),
              ]),
              .object([
                "id": .string("review"), "kind": .string("review"), "review": .string("draft"),
              ]),
            ]),
          ]),
        ]))
      let args: Value = .object([
        "title": .string("Supplier summary"),
        "body": .string("Oak Supply quoted 24.00 and Cedar Tools quoted 27.50. Tax is still unknown."),
        "evidence": .string(source!.id), "meaning": .string("estimate"),
        "scenario": .string("actual"),
      ])
      workflowDefinition = workflow
      if variant != "Empty" {
        let run = try b.startWorkflow(workflow.id, arguments: args, token: identifier())
        workflowRunID = run["id"].text
        let execution = try b.authorizeWorkflowExecution(workflowRunID!)
        if variant == "Running" {
          _ = try b.claimWorkflowStep(execution, owner: "catalog", leaseSeconds: 60)
        } else if variant == "Failure" {
          let claim = try b.claimWorkflowStep(execution, owner: "catalog")
          _ = try b.failWorkflowStep(
            execution, claim: claim,
            detail: "Synthetic source preparation failed. Inspect and retry this exact run.")
        } else if variant == "Cancelled" {
          _ = try b.cancelWorkflow(execution, token: identifier())
        } else if variant != "Queued" {
          _ = try b.advanceWorkflow(execution, owner: "catalog")
          _ = try b.advanceWorkflow(execution, owner: "catalog")
          if variant == "Completed" {
            for proposal in try b.workflowRun(workflowRunID!)["steps"].array.first!["output"][
              "value"]["proposals"].array
            { _ = try b.accept(proposal.text) }
            _ = try b.advanceWorkflow(execution, owner: "catalog")
          }

        }
      }
      automationDefinition = try b.saveApplicationDefinition(
        logicalID: identifier(),
        content: .object([
          "kind": .string("automation"), "title": .string("Morning supplier summary"),
          "description": .string("Synthetic, inert until explicitly stepped in this catalog"),
          "parameters": .array([]),
          "payload": .object([
            "policy": .string("calendar-drafts-v1"),
            "workflow": .object(["mode": .string("exact"), "versionID": .string(workflow.id)]),
            "arguments": args,
            "schedule": .object([
              "policy": .string("native-calendar-v1"), "timeZone": .string("UTC"),
              "hour": .number(9), "minute": .number(0),
              "recurrence": .object(["kind": .string("daily")]),
            ]),
          ]),
        ]))
    }
    if id == "main.excel" || id == "composition.excel" {
      let url = Bundle.main.resourceURL!.appendingPathComponent("CatalogAssets/Quotes.xlsx")
      let original = try b.importFile(url)
      var conversion = try b.beginExcelConversion(sourceID: original.id)
      if !["Default", "Empty", "Inspected"].contains(variant) {
        let plan: Value = .object([
          "name": .string("Supplier comparison"),
          "purpose": .string("Compare supplier quantities and costs"),
          "workflows": .array([.string("Inspect quotes, correct quantities, compare costs")]),
          "questions": .array(
            variant == "Attention" ? [.string("Do quoted costs include delivery?")] : []),
        ])
        conversion = try b.saveExcelConversionPlan(
          conversion.id, expectedVersion: conversion.version, plan: plan, model: "catalog-script")
        if variant == "Tables" { conversion = try b.importExcelConversionTables(conversion.id) }
        if ["Analyzing", "Building", "Attention", "Failure"].contains(variant) {
          conversion = try b.updateExcelConversion(
            conversion.id, expectedVersion: conversion.version,
            state: variant == "Failure" || variant == "Attention"
              ? "needs_attention" : variant.lowercased(),
            failure: variant == "Failure"
              ? "Synthetic build was interrupted. Retry preserves the original." : nil)
        }
      }
      excelID = conversion.id
      if variant == "Ready" {
        step = 1
        try await advanceExcel(b, ws)
        step = 2
        try await advanceExcel(b, ws)
        step = 0
      }
    }
    if id.hasPrefix("main.viewer.") {
      let kind = id.components(separatedBy: ".").last!
      if variant == "Failure", let itemID = fileItems[kind], let asset = try b.item(itemID).assetID
      {
        try? FileManager.default.removeItem(at: b.assetURL(asset))
      }
    }
    if id == "composition.evidence" {
      _ = try b.addItem(
        category: "record", kind: "note", title: "Review purchasing recommendation",
        text: "Check the original quote and unknown tax", status: "draft",
        inputs: [fileItems["pdf"]!])
    }
    if id == "main.lifecycle" || id == "composition.interrupted" {
      _ = try b.saveConversationViewState(
        b.chats()[0].id, draft: "Include delivery before choosing a supplier", reading: .init(),
        expectedDraft: "")
    }
  }

  func seedChat(_ b: Workbook) async throws {
    let id = story.id
    let chat = try b.chats()[0].id
    let wantsInput =
      id.hasPrefix("chat.field.")
      || [
        "chat.choices", "chat.multiple-pending", "chat.draft-conflict", "chat.continuation",
        "composition.interrupted", "composition.supplier",
      ].contains(id)
    if wantsInput {
      let type = id.hasPrefix("chat.field.") ? id.components(separatedBy: ".").last! : "text"
      var field: [String: Value] = [
        "id": .string("answer"), "label": .string(label.isEmpty ? "Comparison basis" : label),
        "type": .string(type), "required": .bool(true),
      ]
      var answer: Value =
        type == "boolean"
        ? .bool(false)
        : .string(type == "decimal" ? "12.50" : type == "date" ? "2026-11-17" : "Include delivery")
      if type == "record" {
        let rows = try b.tablePage(table!.id).rows
        let ids = Array(rows.prefix(6)).map { $0.id }
        field["records"] = .object([
          "datasetID": .string(table!.id), "definitionID": .string(table!.definitionID),
          "labelColumn": .string("name"), "rowIDs": .array(ids.map(Value.string)),
        ])
        try require(
          !ids.isEmpty, "catalog_fixture",
          "Record picker requires at least one candidate. Increase Rows.")
        answer = .string(ids[0])
      }
      let args: Value = .object([
        "kind": .string("question"), "purpose": .string("Comparison basis"),
        "question": .string("What should the comparison include?"),
        "fields": .array([.object(field)]),
        "choices": .array(
          id == "chat.choices"
            ? [
              .object([
                "id": .string("goods"), "label": .string("Goods and delivery"),
                "values": .object(["answer": answer]),
              ]),
              .object([
                "id": .string("pickup"), "label": .string("Pickup only"),
                "values": .object(["answer": .string("Pickup only")]),
              ]),
            ] : []), "allowTextReply": .bool(true),
      ])
      let repeats = id.contains("multiple") || id.contains("interrupted") ? 2 : 1
      for _ in 0..<repeats {
        _ = try await WorkbookAgent.run(
          "Compare the supplier quotes", workbook: b, conversation: b.chats()[0].id,
          model: CatalogInference([("ask", args)]), conversationInput: true)
      }
      input = try b.pendingConversationInput(conversation: b.chats()[0].id)
      if let input {
        if ["Draft", "Conflict"].contains(variant) || id.contains("draft-conflict") {
          _ = try b.saveConversationInputDraft(
            input, values: ["answer": answer], expectedRevision: 0)
          if variant == "Conflict" || id.contains("draft-conflict") {
            let other = try Workbook(b.url)
            do {
              _ = try other.saveConversationInputDraft(
                input, values: ["answer": .string("Conflicting draft")], expectedRevision: 0)
            } catch {
              events.append(
                "Competing connection refused stale draft: " + error.localizedDescription)
            }
          }
        }
        if ["Answered", "Skipped", "Cancelled"].contains(variant) || id == "chat.continuation" {
          _ = try b.submitConversationInput(
            input,
            response: variant == "Cancelled"
              ? .cancel : variant == "Skipped" ? .decline : .fields(["answer": answer]))
        }
      }
    } else if variant != "Empty" || !id.hasPrefix("chat.") {
      if id == "chat.chat-list" {
        // Chats last active at different times, so every group of the list shows. Each is
        // named by its first message; the open chat stays the most recent.
        let day: TimeInterval = 86_400
        for (prompt, ago) in [
          ("Which supplier delivers fastest?", 2 * 3_600.0),
          ("Draft a reorder rule for brass bolts", day + 3_600),
          ("Check this week's deliveries against the purchase orders", 3 * day),
          (
            variant == "Long labels"
              ? "Summarize last month's deliveries and flag every supplier that was late more than twice this quarter, with the cost of each delay"
              : "Summarize last month's deliveries", 12 * day
          ),
          ("Set up the supplier price table", 400 * day),
        ] {
          let date = ISO8601DateFormatter().string(from: Date().addingTimeInterval(-ago))
          try FixtureContext.$current.withValue(
            FixtureContext(seed: UInt32(ago.truncatingRemainder(dividingBy: 100_000)), date: date)
          ) {
            _ = try b.addMessage(prompt, role: "user", conversation: try b.createChat())
          }
        }
      }
      if id == "chat.chats" {
        // Earlier chats, each named by its first message. The open chat's messages come last.
        for prompt in [
          "Which supplier delivers fastest?", "Draft a reorder rule for brass bolts",
          "Summarize last month's deliveries and flag every supplier that was late more than twice this quarter",
        ] {
          _ = try b.addMessage(prompt, role: "user", conversation: try b.createChat())
        }
      }
      // An opened activity starts the chat, so all of it is in view.
      if !(id == "chat.activity" && ["Opened", "Long labels"].contains(variant)) {
        _ = try b.addMessage("Compare the supplier quotes.", role: "user", conversation: chat)
        _ = try b.addMessage(
          "**Supplier comparison**\n\n| Supplier | Cost |\n| --- | ---: |\n| Oak Supply | 24.00 |\n| Cedar Tools | 27.50 |\n\nTax remains unknown. [Inspect the observations](sevra://item/\(source!.id)).",
          role: "assistant", conversation: chat)
      }
      if id == "chat.chats" && variant == "Long labels" {
        try b.renameChat(
          chat,
          title:
            "Compare every supplier quote for brass bolts, hex nuts and fittings, including delivery, tax and minimum order terms"
        )
      }
      if id == "chat.messages" {
        // A code block keeps its lines, and its longest line scrolls sideways.
        _ = try b.addMessage("Show the quotes as CSV.", role: "user", conversation: chat)
        _ = try b.addMessage(
          "Here are the quotes as CSV:\n\n```csv\nsupplier,cost,note\nOak Supply,24.00,\nCedar Tools,27.50,delivery and tax are not yet known for this supplier\n```\n\nAsk to export the table when you need a file.",
          role: "assistant", conversation: chat)
      }
      if id == "chat.history" || variant == "Dense" {
        for i in 0..<55 {
          _ = try b.addMessage(
            "Observation \(i+1): quoted cost \(i+24). Tax is still unknown.",
            role: i % 2 == 0 ? "user" : "assistant", conversation: chat)
        }
      }
    }
    if id == "chat.activity" && ["Default", "Opened", "Long labels"].contains(variant) {
      // Thoughts before each step, and an answer Sevra sent back before the one it accepted.
      let long = variant == "Long labels"
      _ = try await WorkbookAgent.run(
        "What do the supplier quotes say?", workbook: b, conversation: chat,
        model: CatalogInference(
          [
            ("search", .object(["query": .string("supplier quotes")])),
            ("read", .object(["kind": .string("item"), "id": .string(source!.id)])),
            (
              "finish",
              .object([
                "answer": .string("Oak Supply quoted $24.00 and Cedar Tools quoted $27.50."),
                "basis": .string("evidence"), "citations": .array([.string(source!.id)]),
              ])
            ),
            (
              "finish",
              .object([
                "answer": .string(
                  "Oak Supply quoted 24.00 and Cedar Tools quoted 27.50. Tax is still unknown."),
                "basis": .string("evidence"), "citations": .array([.string(source!.id)]),
              ])
            ),
          ],
          thoughts: [
            "The person asks what the supplier quotes say. Nothing in this chat has the figures yet, so I should search the workbook for the quotes before answering.",
            "The search found the supplier observations. Reading that original gives the exact quoted costs, so the answer can cite it.",
            long
              ? "The observations list two suppliers. Oak Supply quoted 24.00 for the brass bolts and Cedar Tools quoted 27.50 for the same order. Neither line says whether tax or delivery is included, and the person did not ask me to compare them, only what the quotes say.\n\nI should give both figures as they are written, cite the observations so the person can check them, and say that tax is still unknown rather than guessing it. A short answer is enough here."
              : "Oak Supply quoted 24.00 and Cedar Tools 27.50. I will give both and cite the observations.",
            "The quotes do not name a currency, so I should not add one. Same figures without the symbol, and I will say tax is still unknown.",
          ]), conversationInput: true)
    }
    if id == "chat.undo-redo" && variant != "Empty" {
      // A change made through sql, so the answer carries "Change saved" with its Undo.
      _ = try await WorkbookAgent.run(
        "Add a reorder level of 10 for brass bolts.", workbook: b, conversation: b.chats()[0].id,
        model: CatalogInference([
          (
            "sql",
            .object([
              "statements": .array([
                .string("CREATE TABLE reorder_levels(part TEXT, level REAL)"),
                .string("INSERT INTO reorder_levels VALUES('Brass bolts', 10)"),
              ])
            ])
          ),
          (
            "finish",
            .object([
              "answer": .string("Added a reorder level of 10 for brass bolts."),
              "basis": .string("general"), "citations": .array([]),
            ])
          ),
        ]), conversationInput: true)
    }
    if id == "chat.approval" {
      let draft = try b.addItem(
        category: "record", kind: "note", title: "Purchasing decision",
        text: "Choose Oak after delivery is confirmed.", status: "draft", inputs: [source!.id])
      _ = try b.prepareChatApproval(
        action: "record.review",
        arguments: .object(["id": .string(draft.id), "decision": .string("accept")]),
        title: "Accept purchasing decision?", conversation: b.chats()[0].id)
    }
    if id.hasPrefix("chat.visual.") || id == "chat.visuals" || id == "composition.surfaces"
      || id == "composition.overview"
    {
      _ = try await captureVisual(b)
    }
  }
  @discardableResult func captureVisual(_ b: Workbook) async throws -> AgentResult {
    let v = visual!
    let payload: Value
    switch v.kind {
    case .chart: payload = .object(["chart": try encoded(v.chart!)])
    case .work: payload = .object(["work": try encoded(v.work!)])
    case .diagram: payload = .object(["diagram": try encoded(v.diagram!)])
    case .overview: payload = .object(["overview": try encoded(v.overview!)])
    case .text: payload = .object(["text": try encoded(v.text!)])
    case .image: payload = .object(["sourceID": .string(image!.id)])
    }
    return try await WorkbookAgent.run(
      "Show this synthetic view", workbook: b, conversation: b.chats()[0].id,
      model: CatalogInference(
        [
          (
            "run",
            .object([
              "action": .object(["name": .string("visual.evaluate"), "arguments": payload])
            ])
          )
        ], attachVisual: true), conversationInput: true)
  }
}
