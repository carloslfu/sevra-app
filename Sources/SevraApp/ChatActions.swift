import Foundation
import SevraAppUI
import SevraAutomationUI
import SevraCore

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
        "instruction": .string("Ask the user to type Confirm. No action has been applied."),
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
          let space = try book.space(book.spaceTarget(a["id"].text).id)
          guard var package = space.definition.app else {
            throw SevraError("app_package", "Choose a mini app.")
          }
          for key in package.datasets.keys { package.datasets[key]?.datasetID = nil }
          try Data(encoded(package).json().utf8).write(
            to: destination, options: .withoutOverwriting)
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
      try await book.transcribe(a["id"].text, cancellation: cancellation)
      return .object(["status": .string("completed"), "sourceID": a["id"]])
    case "automation.inspect", "automation.enable", "automation.pause":
      let definition = try book.applicationDefinition(a["id"].text)
      try require(
        definition.kind == "automation" && definition.id == a["id"].text, "automation",
        "Use an exact automation version.")
      let controller = NativeAutomationHost.shared.controller
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
    guard let (_, ticket) = beginOperation("Applying your confirmed change") else { return true }
    let chat = conversation
    Task {
      defer { finishOperation(ticket, in: book) }
      var approval: ChatApproval?
      do {
        let messageID = try book.addMessage(input, role: "user", conversation: chat)
        let claimed = try book.claimChatApproval(
          conversation: chat, messageID: messageID, cancel: command == "cancel approval")
        if command == "cancel approval" {
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
    return true
  }
}
