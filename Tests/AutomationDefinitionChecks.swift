import Foundation

@testable import SevraCore

func checkAutomationDefinitions(at root: URL) {
  func fixture(_ name: String) throws -> (Workbook, ApplicationDefinition, Value, [String]) {
    let book = try Workbook.create(
      at: root.appendingPathComponent("Automation-" + name + ".sevra"), title: name)
    let primary = try book.addItem(category: "source", kind: "observation", title: "Observed count")
    let attachment = try book.addItem(category: "source", kind: "note", title: "Supporting detail")
    let parameters: [Value] = [
      ActionRegistry.field("quantity", "Count", "decimal", unit: "items"),
      ActionRegistry.field("evidence", "Evidence", "item"),
      .object([
        "id": .string("entries"), "label": .string("Entries"), "type": .string("entries"),
        "required": .bool(true), "maxEntries": .number(3),
        "fields": .array([ActionRegistry.field("attachment", "Attachment", "item")]),
      ]),
    ]
    let function = try book.saveApplicationDefinition(
      logicalID: identifier(),
      content: .object([
        "kind": .string("function"), "title": .string("Double count"),
        "description": .string("Synthetic metadata-only automation fixture"),
        "parameters": .array(parameters),
        "payload": .object(["expression": .string("quantity*2"), "unit": .string("items")]),
      ]))
    let workflow = try book.saveApplicationDefinition(
      logicalID: identifier(), content: book.workflowTemplate(function.id))
    let arguments: Value = .object([
      "quantity": .string("5.00"), "evidence": .string(primary.id),
      "entries": .array([.object(["attachment": .string(attachment.id)])]),
    ])
    return (book, workflow, arguments, [primary.id, attachment.id])
  }
  func content(_ workflow: ApplicationDefinition, _ arguments: Value) -> Value {
    .object([
      "kind": .string("automation"), "title": .string("Weekday inventory summary"),
      "description": .string("An inert intention, not permission to execute."),
      "parameters": .array([]),
      "payload": .object([
        "policy": .string("calendar-drafts-v1"),
        "workflow": .object(["mode": .string("exact"), "versionID": .string(workflow.id)]),
        "arguments": arguments,
        "schedule": .object([
          "policy": .string("native-calendar-v1"), "timeZone": .string("America/Bogota"),
          "hour": .number(9), "minute": .number(0),
          "recurrence": .object([
            "kind": .string("weekly"),
            "weekdays": .array([.number(1), .number(2), .number(3), .number(4), .number(5)]),
          ]),
        ]),
      ]),
    ])
  }
  func date() -> Date { ISO8601DateFormatter().date(from: "2026-10-29T12:00:00Z")! }
  func save(_ book: Workbook, _ content: Value) throws -> ApplicationDefinition {
    try book.saveApplicationDefinition(logicalID: identifier(), content: content)
  }

  check("inert automation definitions retain exact workflow and nested item evidence") {
    let (book, workflow, args, inputs) = try fixture("Evidence")
    let saved = try save(book, content(workflow, args))
    let dependencies = try book.applicationDefinitionDependencies(saved.id)
    try expect(dependencies.count == 1 && dependencies[0]["target_version"].text == workflow.id)
    for id in inputs + [workflow.sourceID] {
      try expect(
        try book.db.scalar(
          "SELECT EXISTS(SELECT 1 FROM lineage WHERE child=? AND parent=?)",
          [.string(saved.sourceID), .string(id)]
        ).int == 1)
    }
    let source = try book.item(saved.sourceID)
    try expect(source.data["submitted"]["content"] == saved.content)
    try expect(source.data["actor"]["kind"].text == "programmatic")
    let revision = try book.revision()
    let history = try book.committedHistory()
    let counts = try book.counts()
    let preview = try book.previewAutomation(saved.id, after: date(), count: 2)
    try expect(preview["execution"].text == "inert" && preview["enabled"] == .bool(false))
    try expect(preview["arguments"]["quantity"].text == "5")
    try expect(saved.payload["arguments"]["quantity"].text == "5.00")
    try expect(
      preview["workflowID"].text == workflow.id && preview["sourceID"].text == saved.sourceID)
    try expect(
      preview["calendar"]["occurrences"].array[0]["due"].text == "2026-10-29T14:00:00.000Z")
    try expect(try book.revision() == revision && book.committedHistory() == history)
    try expect(try book.counts() == counts && book.workflowRuns().isEmpty)
    try expect(
      try book.searchApplicationDefinitions("weekday", kind: "automation")["hits"].array.count == 1)
    _ = try book.verify()
  }
  check(
    "automation validation rejects authority fields, live bindings and invalid typed inputs atomically"
  ) {
    let (book, workflow, args, _) = try fixture("Invalid")
    let valid = content(workflow, args)
    let revision = try book.revision()
    var invalid: [Value] = []
    for (field, value) in [
      ("enabled", Value.bool(true)), ("policy", .string("always-execute")),
      ("workflow", .object(["mode": .string("live"), "logicalID": .string(workflow.logicalID)])),
      ("arguments", .object([:])),
      ("schedule", .object(["cron": .string("* * * * *")])),
    ] {
      var changed = valid.object
      var payload = valid["payload"].object
      payload[field] = value
      changed["payload"] = .object(payload)
      invalid.append(.object(changed))
    }
    var badParameters = valid.object
    badParameters["parameters"] = workflow.parameters
    invalid.append(.object(badParameters))
    var badArgs = args.object
    badArgs["quantity"] = .number(5)
    var bad = valid.object
    var payload = valid["payload"].object
    payload["arguments"] = .object(badArgs)
    bad["payload"] = .object(payload)
    invalid.append(.object(bad))
    badArgs = args.object
    badArgs["evidence"] = .string(identifier())
    payload["arguments"] = .object(badArgs)
    bad["payload"] = .object(payload)
    invalid.append(.object(bad))
    let counts = try book.counts()
    for rejected in invalid {
      try refuses { _ = try save(book, rejected) }
      try expect(try book.revision() == revision && book.counts() == counts)
    }
    try expect(try book.searchApplicationDefinitions("", kind: "automation")["hits"].array.isEmpty)
    _ = try book.verify()
  }
  check("automation edits use exact bases and retry content while old schedules stay pinned") {
    let (book, workflow, args, _) = try fixture("Versions")
    let logical = identifier()
    let firstContent = content(workflow, args)
    let first = try book.saveApplicationDefinition(
      logicalID: logical, content: firstContent, token: "create")
    try expect(
      try book.saveApplicationDefinition(logicalID: logical, content: firstContent, token: "create")
        .id
        == first.id)
    var newWorkflowContent = workflow.content.object
    newWorkflowContent["title"] = .string("A later workflow version")
    let secondWorkflow = try book.saveApplicationDefinition(
      logicalID: workflow.logicalID, content: .object(newWorkflowContent),
      expectedDefinitionID: workflow.id)
    let secondContent = content(secondWorkflow, args)
    let second = try book.saveApplicationDefinition(
      logicalID: logical, content: secondContent, expectedDefinitionID: first.id)
    try expect(second.version == 2 && second.previousID == first.id)
    try expect(
      try book.previewAutomation(first.id, after: date())["workflowID"].text == workflow.id)
    try expect(
      try book.previewAutomation(second.id, after: date())["workflowID"].text == secondWorkflow.id)
    try refuses("stale_definition") {
      _ = try book.saveApplicationDefinition(
        logicalID: logical, content: firstContent, expectedDefinitionID: first.id)
    }
    try refuses("idempotency") {
      _ = try book.saveApplicationDefinition(
        logicalID: logical, content: secondContent, token: "create")
    }
    try refuses("automation_binding") { _ = try book.previewAutomation(logical, after: date()) }
    let restored = try book.restoreApplicationDefinition(
      logical, versionID: first.id, expectedDefinitionID: second.id)
    try expect(restored.version == 3 && restored.payload == first.payload)
    try expect(try book.workflowRuns().isEmpty)
    _ = try book.verify()
  }
  check("automation definitions cannot be executed or used as functions, forms or workflow steps") {
    let (book, workflow, args, _) = try fixture("NoExecution")
    let saved = try save(book, content(workflow, args))
    try refuses("definition_kind") {
      _ = try book.evaluateApplicationDefinition(saved.id, arguments: .object([:]))
    }
    try refuses("workflow_definition") {
      _ = try book.startWorkflow(saved.id, arguments: .object([:]), token: "not-a-workflow")
    }
    var wrongTarget = content(workflow, args).object
    var payload = wrongTarget["payload"]!.object
    payload["workflow"] = .object(["mode": .string("exact"), "versionID": .string(saved.id)])
    wrongTarget["payload"] = .object(payload)
    try refuses("automation_binding") { _ = try save(book, .object(wrongTarget)) }
    var invalidWorkflow = workflow.content.object
    invalidWorkflow["parameters"] = .array([])
    invalidWorkflow["payload"] = .object([
      "readPolicy": .string("latest-at-step"),
      "steps": .array([
        .object([
          "id": .string("run"), "kind": .string("evaluate"),
          "binding": .object(["mode": .string("exact"), "versionID": .string(saved.id)]),
          "arguments": .object([:]),
        ])
      ]),
    ])
    try refuses("workflow_binding") { _ = try save(book, .object(invalidWorkflow)) }
    try refuses {
      _ = try save(
        book,
        .object([
          "kind": .string("form"), "title": .string("Not an activation control"),
          "description": .string("Synthetic"), "parameters": .array([]),
          "payload": .object([
            "workflow": .object(["mode": .string("exact"), "versionID": .string(saved.id)]),
            "fields": .array([]),
          ]),
        ]))
    }
    try expect(try book.workflowRuns().isEmpty)
    _ = try book.verify()
  }
  check("automation capture and catalog roll back on publication faults and cancellation") {
    let (book, workflow, args, _) = try fixture("Rollback")
    let revision = try book.revision()
    let counts = try book.counts()
    try book.db.execute(
      "CREATE TEMP TRIGGER fail_automation_publish BEFORE INSERT ON main.committed_changes BEGIN SELECT RAISE(ABORT,'injected automation publication fault'); END;"
    )
    try refuses { _ = try save(book, content(workflow, args)) }
    try book.db.execute("DROP TRIGGER fail_automation_publish")
    try expect(try book.revision() == revision && book.counts() == counts)
    try expect(try book.searchApplicationDefinitions("", kind: "automation")["hits"].array.isEmpty)
    let control = Cancellation()
    control.cancel()
    try refuses("cancelled") {
      _ = try book.saveApplicationDefinition(
        logicalID: identifier(), content: content(workflow, args), cancellation: control)
    }
    try expect(try book.revision() == revision)
    _ = try book.verify()
  }
  check("agent automation authoring respects read-only requests and never grants execution") {
    let (book, workflow, args, _) = try fixture("AgentBoundary")
    let content = content(workflow, args)
    let saved = try save(book, content)
    let prompt = "Inspect the saved schedule. Do not enable or run it."
    let request = try book.startAgentRequest(prompt, conversation: "main", model: "synthetic")
    let source = try book.addItem(
      category: "source", kind: "request", title: "Current request", text: prompt,
      data: .object([
        "conversationID": .string("main"), "messageID": .string(request.messageID),
      ]))
    let tools = WorkbookTools(
      book, runID: request.runID, requestSourceID: source.id, readOnly: true)
    let revision = try book.revision()
    try expect(
      try tools.execute("read_definition", .object(["id": .string(saved.id)]))["content"] == content
    )
    try refuses("read_only_request") {
      _ = try tools.execute("save_definition", .object(["content": content]))
    }
    try refuses("read_only_request") {
      _ = try tools.execute(
        "start_workflow", .object(["id": .string(saved.id), "arguments": .object([:])]))
    }
    try expect(try book.revision() == revision && book.workflowRuns().isEmpty)
    try book.finishAgentRun(request.runID, status: "complete", steps: 1, metrics: .object([:]))
    let savePrompt = "Save a copy of this schedule. Do not enable or run it."
    let saveRequest = try book.startAgentRequest(
      savePrompt, conversation: "main", model: "synthetic")
    let saveSource = try book.addItem(
      category: "source", kind: "request", title: "Save request", text: savePrompt,
      data: .object([
        "conversationID": .string("main"), "messageID": .string(saveRequest.messageID),
      ]))
    let author = WorkbookTools(book, runID: saveRequest.runID, requestSourceID: saveSource.id)
    let copy = try author.execute("save_definition", .object(["content": content]))
    let copied = try book.applicationDefinition(copy["id"].text)
    try expect(copied.content == content && copied.kind == "automation")
    try expect(try book.automationState(copied.id) == .null && book.workflowRuns().isEmpty)
    try refuses("workflow_definition") {
      _ = try author.execute(
        "start_workflow", .object(["id": .string(copied.id), "arguments": .object([:])]))
    }
    _ = try book.verify()
  }
  check("automation reconstruction retains typed intent and provenance without activation") {
    let (book, workflow, args, _) = try fixture("Reconstruction")
    let saved = try save(book, content(workflow, args))
    let before = try book.previewAutomation(saved.id, after: date())
    let restored = try book.reconstruct(to: root.appendingPathComponent("Automation-inert.sevra"))
    try expect(try restored.previewAutomation(saved.id, after: date()) == before)
    try expect(try restored.applicationDefinition(saved.id).content == saved.content)
    try expect(
      try restored.workflowRuns().isEmpty && restored.workflowEvents()["events"].array.isEmpty)
    try expect(
      try restored.item(saved.sourceID).data["submitted"]["content"] == saved.content)
    _ = try restored.verify()
  }
  check("automation integrity rejects missing pinned dependency or nested argument lineage") {
    let (book, workflow, args, inputs) = try fixture("Integrity")
    let saved = try save(book, content(workflow, args))
    try book.db.transaction {
      try book.db.execute(
        "DELETE FROM lineage WHERE child=? AND parent=?",
        [.string(saved.sourceID), .string(inputs[1])])
    }
    try refuses("definition_integrity") { _ = try book.verify() }
    let (other, otherWorkflow, otherArgs, _) = try fixture("DependencyIntegrity")
    let second = try save(other, content(otherWorkflow, otherArgs))
    try other.db.transaction {
      try other.db.execute(
        "DELETE FROM app_definition_dependencies WHERE definition_id=?", [.string(second.id)])
    }
    try refuses("definition_integrity") { _ = try other.verify() }
  }
}
