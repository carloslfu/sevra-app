import Foundation
import SevraAppUI
import SevraAutomationUI
import SevraCore
import SevraMedia
import SevraVisualUI

extension WorkspaceState {
  func performChatAction(
    _ name: String, arguments a: Value, book: Workbook, readOnly: Bool,
    cancellation: Cancellation, confirmed: Bool = false
  ) async throws -> Value {
    _ = try ChatOperations.validate(name, arguments: a, readOnly: readOnly)
    try cancellation.check()
    func approve(_ title: String, arguments: Value? = nil) throws -> Value {
      try book.prepareChatApproval(
        action: name, arguments: arguments ?? a, title: title, conversation: conversation)
      return .object([
        "status": .string("confirmation_required"), "preview": .string(title),
        "instruction": .string("Show the review in chat and wait for the person to confirm."),
      ])
    }
    if name.hasPrefix("app.") {
      let target = try book.spaceTarget(a["id"].text)
      let space = try book.space(target.id)
      try require(space.definition.app != nil, "app_package", "Choose a programmable app.")
      if !["app.inspect", "app.browse"].contains(name) {
        try require(
          a["expectedVersion"].int == space.version, "stale_app",
          "Inspect the current app version before changing it.")
      }
      if name == "app.enable" && !confirmed {
        let package = space.definition.app!
        let titles = try book.nativeAppTableTitles(package)
        let images = try book.nativeAppImageTitles(package)
        let tables = package.datasets.keys.sorted().map {
          (titles[$0] ?? $0)
            + (package.datasets[$0]!.writable
              ? ": read and change records" : ": read records")
        }
        let access = tables + images.values.sorted().map { $0 + ": display image" }
        return try approve(
          "Enable “" + space.title + "” on this Mac?\n"
            + (access.isEmpty ? "No workbook data access." : access.joined(separator: "\n")))
      }
      return try await nativeAppSession(space, book: book).converse(
        String(name.dropFirst(4)), arguments: a, readOnly: readOnly, cancellation: cancellation)
    }
    switch name {
    case "visual.app_filter":
      let space = try book.space(a["id"].text)
      try require(
        space.version == a["expectedVersion"].int && space.definition.app != nil,
        "stale_app", "Use the current exact app version and declared view ID.")
      let filters = a.object["filters"]?.array
      try await nativeAppSession(space, book: book).setVisualFilters(
        a["viewID"].text, presetID: a["presentationID"].string, filters: filters,
        cancellation: cancellation)
      return .object(["status": .string(filters == nil ? "reset" : "filtered")])
    case "visual.app_select":
      let space = try book.space(a["id"].text)
      try require(
        space.version == a["expectedVersion"].int && space.definition.app != nil,
        "stale_app", "Use the current exact app version and declared view ID.")
      let view = a["viewID"].text
      let preset = a["presentationID"].string
      let session = nativeAppSession(space, book: book)
      var point: VisualChartData.Point?
      if let id = a["point"].int {
        let result = try await session.loadVisual(
          view, presetID: preset, cancellation: cancellation)
        guard let chart = result.chartData,
          a["snapshot"] == .string(chart.snapshot),
          a["queryHash"] == .string(chart.queryHash),
          let exact = chart.points.first(where: { $0.id == id })
        else { throw SevraError("visual_links", "Refresh the chart before selecting a group.") }
        point = exact
      }
      try cancellation.check()
      try session.selectVisualPoint(view, presetID: preset, point: point)
      return .object([
        "status": .string(point == nil ? "cleared" : "selected"),
        "label": point.map { .string($0.label) } ?? .null,
      ])
    case "visual.app_capture", "visual.app_pin", "visual.app_preset", "visual.app_restore_preset",
      "visual.app_archive_preset", "visual.app_preset_info", "visual.app_sources",
      "visual.app_diagram_positions":
      let space = try book.space(a["id"].text)
      try require(
        space.version == a["expectedVersion"].int && space.definition.app != nil,
        "stale_app", "Use the current exact app version and declared view ID.")
      let view = a["viewID"].text
      let preset = a["presentationID"].string
      let session = nativeAppSession(space, book: book)
      let filters = session.visualFilters(view, presetID: preset)
      let presetMutation = [
        "visual.app_preset", "visual.app_restore_preset", "visual.app_archive_preset",
      ].contains(name)
      let result = try await session.withVisualAccess(
        committing: name == "visual.app_pin" || presetMutation
      ) { book, access -> Value in
        try cancellation.check()
        if name == "visual.app_preset_info" {
          return try book.nativeAppPresetHistory(access, view: view, presetID: preset!)
        }
        if name == "visual.app_diagram_positions" {
          let result = try book.nativeAppVisual(
            access, view: view, presetID: preset, cancellation: cancellation)
          guard let diagram = result.diagram, let data = result.diagramData else {
            throw SevraError("visual_diagram", "Choose an enabled diagram view.")
          }
          return try data.positionPage(
            diagram.positions, offset: a["offset"].int ?? 0, cancellation: cancellation)
        }
        if name == "visual.app_sources" {
          return try book.nativeAppChartSources(
            access, view: view, presetID: preset, filters: filters,
            snapshot: a["snapshot"].text, queryHash: a["queryHash"].text, point: a["point"].int!,
            offset: a["offset"].int ?? 0, panel: a["panel"].int, cancellation: cancellation)
        }
        if name == "visual.app_pin" {
          return try encoded(
            book.pinNativeAppView(
              access, view: view, presetID: preset,
              expectedHomeVersion: a["homeVersion"].int!))
        }
        if presetMutation {
          let archiving = name == "visual.app_archive_preset"
          let style = a["style"].string.flatMap(VisualChart.Style.init(rawValue:))
          try require(
            a["style"] == .null || style != nil, "visual_preset", "Choose a known chart style.")
          let positions = try a.object["positions"].map {
            try JSONDecoder().decode(
              [String: DiagramGeometry.Position].self, from: Data($0.json().utf8))
          }
          let saved = try book.saveNativeAppPreset(
            access, view: view, title: a["title"].string,
            style: style, filters: a["filters"] == .null ? nil : a["filters"].array,
            expectedPresetVersion: a["presetVersionID"].string,
            restoring: a["restoreVersionID"].string,
            archiving: archiving, positions: positions,
            cancellation: cancellation)
          return .object([
            "status": .string(archiving ? "archived" : "saved"),
            "presentationID": .string(saved.logicalID),
            "versionID": .string(saved.id), "version": .number(Double(saved.version)),
          ])
        }
        let visual = try book.nativeAppVisual(
          access, view: view, presetID: preset,
          capture: true, filters: filters, cancellation: cancellation)
        let captured = try encoded(visual)
        try require(
          captured.json().utf8.count <= 24 * 1024, "visual_limit",
          "This view is too large to capture. Narrow its scope and try again.")
        let title = visual.definition.title ?? view
        return .object([
          "status": .string("captured"), "capture": captured,
          "visualSummary": try visual.captureSummary(title: title, capture: captured),
          "notice": .string("Attach the capture receipt using finish.visuals."),
        ])
      }
      if presetMutation { session.invalidateVisualPresentation() }
      return result
    case "visual.expand", "visual.open_current":
      return try await openChatVisual(
        a["messageID"].text, index: a["index"].int!,
        current: name == "visual.open_current", book: book, cancellation: cancellation)
    case "visual.image_view":
      let chat = conversation
      let messageID = a["messageID"].text
      let mode = a["mode"].text
      try require(
        ["open", "fit", "zoom", "retry"].contains(mode), "visual_image",
        "Choose open, fit, zoom or retry.")
      let zoom = a["zoom"].string.flatMap(Double.init) ?? 1
      try require(
        zoom.isFinite && (0.25...6).contains(zoom)
          && (mode == "zoom" ? a["zoom"].string.flatMap(Double.init) != nil : a["zoom"] == .null),
        "visual_image", "Choose a zoom between 0.25 and 6 for zoom mode.")
      let image = try await Task.detached {
        let result = try book.conversationVisual(
          messageID, index: a["index"].int!, conversation: chat)
        guard let image = result.image else {
          throw SevraError("visual_image", "Choose an exact captured image.")
        }
        return image
      }.value
      let asset = try await Task.detached { try book.imageAssetRead(image.reference) }.value
      let preview = try await WorkbookImageDecoder.shared.load(asset, enlarged: true)
      try cancellation.check()
      try require(
        workbook === book && conversation == chat && !changingConversation,
        "visual_image", "Return to the conversation for this image.")
      imageInspection = ConversationImageInspection(
        title: image.accessibilityDescription,
        preview: preview, zoom: zoom)
      return .object([
        "status": .string("opened"), "sourceID": .string(image.reference.sourceID),
        "zoom": .number(zoom),
      ])
    case "visual.open_source":
      let chat = conversation
      let messageID = a["messageID"].text
      let source = try await Task.detached {
        if let point = a["point"].int, let sourceID = a["sourceID"].string {
          let sources = try book.chartGroupSources(
            messageID: messageID, index: a["index"].int!,
            conversation: chat, point: point, offset: a["offset"].int ?? 0, panel: a["panel"].int)
          try require(
            sources["rows"].array.contains { $0.array.contains(.string(sourceID)) },
            "visual_source", "Choose a source version from the exact captured page.")
          return sourceID
        }
        let result = try book.conversationVisual(
          messageID, index: a["index"].int!, conversation: chat)
        return try result.sourceForInspection(a["sourceID"].string)
      }.value
      try cancellation.check()
      try require(
        workbook === book && conversation == chat && !changingConversation,
        "visual", "Return to the conversation for this visual.")
      try require(
        navigate(.item(source), returningTo: .message(messageID)),
        "visual", "Resolve the open draft before opening the captured source.")
      return .object(["status": .string("opened"), "sourceID": .string(source)])
    case "visual.export":
      let destination = URL(fileURLWithPath: (a["path"].text as NSString).expandingTildeInPath)
      try require(
        (a["path"].text.hasPrefix("/") || a["path"].text.hasPrefix("~/"))
          && !a["path"].text.contains("\0"), "export_path", "Supply the full destination filename.")
      let chat = conversation
      let capture = try await Task.detached {
        try book.conversationVisual(a["messageID"].text, index: a["index"].int!, conversation: chat)
      }.value
      guard let chart = capture.chart, let saved = capture.chartData else {
        throw SevraError("visual_export", "Choose a captured chart to export.")
      }
      try cancellation.check()
      let data = try VisualChartExport.data(
        chart: chart, captured: saved, format: destination.pathExtension.lowercased())
      let file = try await Task.detached {
        try book.publishSmallExport(data, to: destination, cancellation: cancellation)
      }.value
      return .object(["status": .string("saved"), "path": .string(file.path)])
    case "file.export_workbook", "file.export_table", "file.export_app", "file.export_original":
      let path = (a["path"].text as NSString).expandingTildeInPath
      try require(
        path.hasPrefix("/") && !path.contains("\0"), "export_path",
        "Supply a full destination path.")
      let destination = try book.assetCopyDestination(URL(fileURLWithPath: path))
      try await Task.detached {
        if name == "file.export_workbook" {
          try book.export(to: destination, cancellation: cancellation)
        } else if name == "file.export_table" {
          try book.exportCSV(a["id"].text, to: destination, cancellation: cancellation)
        } else if name == "file.export_original" {
          try book.copyAsset(a["id"].text, to: destination, cancellation: cancellation)
        } else {
          try book.exportNativeAppTemplate(
            book.spaceTarget(a["id"].text).id, to: destination, cancellation: cancellation)
        }
      }.value
      return .object(["status": .string("saved"), "path": .string(destination.path)])
    case "form.submit":
      var draft = try book.newFormDraft(a["id"].text, cancellation: cancellation)
      draft.arguments = a["inputs"]
      let preview = try book.previewFormDraft(draft, cancellation: cancellation)
      if !confirmed {
        let definition = try book.applicationDefinition(a["id"].text)
        return try approve(
          "Submit “" + definition.title + "”?\n"
            + chatInputSummary(
              preview["arguments"] == .null ? a["inputs"] : preview["arguments"],
              fields: definition.content["parameters"].array) + "\n" + preview["effect"].text,
          arguments: .object(a.object.merging(["preview": preview]) { _, new in new }))
      }
      return try book.submitFormDraft(
        draft, preview: a["preview"], actor: .human("Sevra.chat-confirmation"),
        cancellation: cancellation)
    case "workflow.answer":
      let target = try book.workflowClarification(a["id"].text)
      var draft = WorkflowClarificationDraft(target: target)
      draft.entry.values = a["values"]
      draft.entry.reason = a["reason"].text
      _ = try book.previewWorkflowClarificationDraft(draft)
      if !confirmed {
        return try approve(
          "Save these workflow inputs?\n"
            + chatInputSummary(a["values"], fields: target["fields"].array) + "\n"
            + a["reason"].text,
          arguments: .object(a.object.merging(["target": target]) { _, new in new }))
      }
      try require(
        a["target"] == target, "stale_workflow_clarification",
        "The workflow question changed. Prepare the answer again.")
      let session = try book.authorizeWorkflowExecution(a["id"].text)
      return try book.clarifyWorkflow(
        session, target: target, values: a["values"], reason: a["reason"].text, token: identifier(),
        actor: .human("Sevra.chat-confirmation"), cancellation: cancellation)
    case "record.review":
      let item = try book.item(a["id"].text)
      try require(
        item.id == a["id"].text && book.item(item.logicalID).id == item.id, "stale_revision",
        "Read the current item before deciding.")
      let decision = a["decision"].text
      try require(
        ["accept", "undo", "withdraw"].contains(decision), "review",
        "Choose accept, undo or withdraw.")
      if !confirmed {
        return try approve(
          decision.capitalized + " “" + item.title + "”?\n" + String(item.text.prefix(6000)))
      }
      let actor = ChangeActor.human("Sevra.chat-confirmation")
      let result: Item
      switch decision {
      case "accept": result = try book.accept(item.id, cancellation: cancellation, actor: actor)
      case "undo": result = try book.undoItem(item.id, cancellation: cancellation, actor: actor)
      default: result = try book.withdrawDraft(item.id, actor: actor)
      }
      return .object(["status": .string("completed"), "item": try encoded(result)])
    case "file.transcribe":
      try await AppHost.transcribe(book, id: a["id"].text, cancellation: cancellation)
      return .object(["status": .string("completed"), "sourceID": a["id"]])
    case "automation.inspect", "automation.enable", "automation.pause":
      let definition = try book.applicationDefinition(a["id"].text)
      try require(
        definition.kind == "automation" && definition.id == a["id"].text, "automation",
        "Use an exact automation version.")
      let controller = automation.controller
      let grants = try controller.registry.grants().filter {
        $0.sourceID == definition.id
          && (try? controller.registry.matches($0, workbook: book)) == true
      }
      if name == "automation.inspect" {
        return .object([
          "definition": try encoded(definition), "grants": try encoded(grants),
          "activation": try book.automationState(definition.id),
        ])
      }
      if name == "automation.pause" {
        for grant in grants {
          try await controller.pause(grant, actor: .programmatic("Sevra.chat-action"))
        }
        return .object(["status": .string("paused"), "id": .string(definition.id)])
      }
      guard case .bool(let allowAI) = a["allowAI"], let generation = a["generation"].int else {
        throw SevraError(
          "automation", "Supply the inspected generation and whether to allow local AI.")
      }
      if !confirmed {
        return try approve(
          "Enable “" + definition.title + "” on this Mac?\nLocal AI: "
            + (allowAI ? "allowed" : "not allowed") + "\n" + definition.content["description"].text)
      }
      try await controller.enable(
        book, exactID: definition.id, expectedGeneration: generation, allowAI: allowAI,
        fromNow: a["fromNow"] == .bool(true), actor: .human("Sevra.chat-confirmation"))
      return .object(["status": .string("enabled"), "id": .string(definition.id)])
    default: throw SevraError("chat_action", "This conversational operation is not connected yet.")
    }
  }

  private func chatInputSummary(_ values: Value, fields: [Value]) -> String {
    values.object.keys.sorted().map { key in
      let field = fields.first { $0["id"].text == key }
      let label = field?["label"].string ?? field?["title"].string ?? key
      if case .array(let entries) = values[key] {
        return label + ":\n"
          + entries.enumerated().map { index, entry in
            "\(index + 1). " + chatInputSummary(entry, fields: field?["fields"].array ?? [])
          }.joined(separator: "\n")
      }
      return label + ": " + values[key].text
    }.joined(separator: "\n")
  }

  func handleChatConfirmation(_ input: String, book: Workbook) -> Bool {
    let command = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
      .trimmingCharacters(in: CharacterSet(charactersIn: ".!"))
    guard ["confirm", "confirm change", "cancel approval"].contains(command) else { return false }
    guard let approval = chatApproval else {
      error = "No change in this conversation is waiting for your confirmation."
      return true
    }
    applyChatApproval(approval, book: book, cancel: command == "cancel approval", humanText: input)
    return true
  }

  func respondToApproval(_ approval: ChatApproval, cancel: Bool) {
    guard let book = workbook else { return }
    applyChatApproval(
      approval, book: book, cancel: cancel, humanText: cancel ? "Cancel approval" : "Confirm change"
    )
  }

  private func applyChatApproval(
    _ expected: ChatApproval, book: Workbook, cancel: Bool, humanText: String
  ) {
    guard !changingConversation,
      let (_, ticket) = beginOperation(cancel ? "Cancelling approval" : "Applying confirmed change")
    else { return }
    let chat = conversation
    Task {
      defer { finishOperation(ticket, in: book) }
      var approval: ChatApproval?
      do {
        let claimed = try book.claimChatApproval(
          expected, conversation: chat, cancel: cancel, humanText: humanText)
        if cancel {
          refresh()
          return
        }
        approval = claimed
        let result = try await performChatAction(
          claimed.action, arguments: claimed.arguments, book: book, readOnly: false,
          cancellation: ticket.cancellation, confirmed: true)
        try book.finishChatApproval(claimed, conversation: chat, result: result)
        refresh()
      } catch {
        if let approval {
          try? book.finishChatApproval(
            approval, conversation: chat, result: .null, error: error.localizedDescription)
        }
        report(error, for: ticket, in: book)
      }
    }
  }
}

extension WorkspaceState {
  func openChatVisual(
    _ messageID: String, index: Int, current: Bool, book: Workbook,
    cancellation: Cancellation = .init()
  ) async throws -> Value {
    let chat = conversation
    let result = try await Task.detached {
      try book.conversationVisual(messageID, index: index, conversation: chat)
    }.value
    try cancellation.check()
    try require(
      workbook === book && conversation == chat && !changingConversation,
      "visual", "Return to the conversation for this visual.")
    if current {
      if let reference = result.appReference {
        let space = try book.space(reference.spaceID)
        try require(
          space.version == reference.version && space.definition.app?.digest == reference.digest,
          "stale_app", "The app view has changed. Open the current app to inspect it.")
        let session = nativeAppSession(space, book: book)
        _ = try await session.withVisualAccess { book, access in
          try book.nativeAppPresentation(
            access, view: reference.viewID, presetID: reference.presetID)
        }
        try cancellation.check()
        try require(
          workbook === book && conversation == chat && !changingConversation,
          "visual", "Return to the conversation for this visual.")
        visualInspection = .init(
          messageID: messageID, index: index, conversation: chat,
          content: .current(session, reference))
      } else {
        let home = try book.space("home")
        let origin = VisualOrigin(messageID: messageID, index: index, conversation: chat)
        let matching = home.definition.components.filter {
          $0.visualOrigin == origin || ($0.visualOrigin == nil && $0.visual == result.definition)
        }
        guard matching.count == 1, let component = matching.first else {
          throw SevraError("visual", "Choose the corresponding saved view in Home.")
        }
        try require(
          navigate(.space(home.id), returningTo: .message(messageID)),
          "visual", "Resolve the open draft before opening Home.")
        spaceScroll[home.id] = component.id
      }
    } else {
      try require(
        result.chart != nil || result.overview != nil || result.diagram != nil,
        "visual", "Choose a captured chart, overview or diagram to expand.")
      visualInspection = .init(
        messageID: messageID, index: index, conversation: chat,
        content: .captured(result))
    }
    return .object(["status": .string("opened"), "mode": .string(current ? "live" : "captured")])
  }

  func showChatVisual(_ messageID: String, index: Int, current: Bool) {
    guard let workbook else { return }
    Task {
      do {
        _ = try await openChatVisual(messageID, index: index, current: current, book: workbook)
      } catch { self.error = error.localizedDescription }
    }
  }
}
