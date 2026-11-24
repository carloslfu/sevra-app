import Foundation
import SevraAI
import SevraCore
import SevraNativeAI

private actor SurfaceModel: WorkbookInference {
  let identity = "scripted interaction"
  let lastMetrics = Value.null
  private let input: Value?
  private let attachVisual: Bool
  private let operation: (String, Value)?
  private var step = 0
  private(set) var request: InferenceMessage?
  private(set) var offeredScope: InferenceToolScope?
  private(set) var policy: InferenceMessage?

  init(input: Value? = nil, operation: (String, Value)? = nil, attachVisual: Bool = false) {
    self.input = input
    self.operation = operation
    self.attachVisual = attachVisual
  }

  func beginRun() {}
  func endRun() {}

  func respond(
    messages: [InferenceMessage], directory: URL, cancellation: Cancellation,
    progress: @escaping @Sendable (String) -> Void, toolScope: InferenceToolScope,
    citationIDs: [String]
  ) async throws -> NativeReply {
    step += 1
    if step == 1 {
      request = messages.last
      policy = messages.first
      offeredScope = toolScope
    }
    let tool: String
    let arguments: Value
    if step == 1, let input {
      tool = "request_input"
      arguments = input
    } else if step == 1, let operation {
      tool = "workspace_action"
      arguments = .object(["action": .string(operation.0), "arguments": operation.1])
    } else {
      tool = "finish"
      var fields: [String: Value] = [
        "answer": .string("Ready."), "basis": .string("general"), "citations": .array([]),
      ]
      if attachVisual {
        fields["visuals"] = .array([.string(messages.first?.visualCaptureIDs.first ?? "forged-id")])
      }
      arguments = .object(fields)
    }
    return NativeReply(
      text: "", calls: [try .init(id: "surface-\(step)", operation: tool, arguments, scope: toolScope)])
  }
}

@MainActor func checkConversationSurfaces() async throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(identifier())
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
  defer { try? FileManager.default.removeItem(at: root) }
  let book = try Workbook.create(
    at: root.appendingPathComponent("Proof.sevra"), title: "Interaction proof")
  let arguments = try Value.parse(
    #"""
    {"kind":"question","purpose":"Comparison basis","question":"Include delivery?",
    "fields":[{"id":"delivery","type":"boolean","required":true,"label":"Delivery"}],
    "choices":[{"id":"include","label":"Include delivery","values":{"delivery":true}}],
    "allowTextReply":true}
    """#)
  for scope in InferenceToolScope.allCases {
    for capability in [false, true] {
      let tools = try NativeTools.referenceDefinitions(
        toolScope: scope, conversationInput: capability)
      try expectEqual(
        tools.contains { $0.name == (scope.specialized ? "request_input" : "ask") },
        scope.allows("request_input", conversationInput: capability))
      _ = try NativeCitationPolicy.make([], toolScope: scope, conversationInput: capability)
    }
  }
  let question = try await WorkbookAgent.run(
    "Read only. Do not change anything. Compare the amounts.", workbook: book,
    model: SurfaceModel(input: arguments), conversationInput: true)
  try expectEqual(question.state, "needs_input")
  let pending = try book.pendingConversationInput(conversation: book.startChat)!
  try expectEqual(pending.readOnly, true)
  try expectEqual(try book.requestRunStatus(pending.requestID), "needs_input")
  try expectEqual(try book.workspaceSnapshot(conversation: book.startChat)?.pendingInput, pending)
  try expectThrows(
    try book.submitConversationInput(pending, response: .fields(["delivery": .string("yes")])))
  let draft = try book.saveConversationInputDraft(
    pending, values: ["delivery": .bool(true)], expectedRevision: 0)
  try expectThrows(
    try book.saveConversationInputDraft(
      pending, values: ["delivery": .bool(false)], expectedRevision: 0))
  try expectThrows(try book.submitConversationInput(pending, response: .text("No delivery.")))
  let id = try book.submitConversationInput(
    pending, response: .choice("include"), draftRevision: draft.revision)!
  try expectEqual(try book.resumableConversationAnswer(conversation: book.startChat), id)
  try expectEqual(try book.historyMessage(id).role, "user")
  try expectThrows(try book.submitConversationInput(pending, response: .choice("include")))
  let model = SurfaceModel()
  _ = try await WorkbookAgent.run(
    "", workbook: book, model: model, conversationInput: true, inputAnswerID: id)
  try expectEqual(await model.offeredScope, .conversationAnswer)
  try expectEqual(await model.request?.content, "Include delivery\nDelivery: true")
  try expectEqual(await model.policy?.content.contains("Compare the amounts."), true)
  try expectEqual(try book.resumableConversationAnswer(conversation: book.startChat), nil)
  try expectEqual(try book.requestRunStatus(id), "complete")
  let defaultRunner = SurfaceModel(input: arguments)
  do {
    _ = try await WorkbookAgent.run("Read the table", workbook: book, model: defaultRunner)
    throw SevraError(
      "check", "A runner without publication authority asked an actionable question.")
  } catch let error as SevraError where error.code == "tool_scope" {
    try expectEqual(try book.pendingConversationInput(conversation: book.startChat), nil)
  }

  _ = try await WorkbookAgent.run(
    "Compare delivery independently.", workbook: book,
    model: SurfaceModel(input: arguments), conversationInput: true)
  let typedQuestion = try book.pendingConversationInput(conversation: book.startChat)!
  _ = try await WorkbookAgent.run(
    "A separate comparison", workbook: book, model: SurfaceModel(input: arguments),
    conversationInput: true)
  let otherQuestion = try book.pendingConversationInput(conversation: book.startChat)!
  _ = try book.addMessage("An unrelated note", role: "user", conversation: book.startChat)
  try expectEqual(
    try book.pendingConversationInputs(conversation: book.startChat), [otherQuestion, typedQuestion])
  let selectedInput = try book.workspaceSnapshot(
    conversation: book.startChat, activeInputID: typedQuestion.id)
  try expectEqual(selectedInput?.pendingInputs.map(\.id), [otherQuestion.id, typedQuestion.id])
  try expectEqual(selectedInput?.pendingInput, typedQuestion)
  let firstDraft = try book.saveConversationInputDraft(
    typedQuestion, values: ["delivery": .bool(true)], expectedRevision: 0)
  try expectEqual(try Workbook(book.url).conversationInputDraft(typedQuestion), firstDraft)
  let typedID = try book.submitConversationInput(
    typedQuestion, response: .text("Include delivery"), draftRevision: firstDraft.revision)!
  _ = try book.addMessage("A note before resuming", role: "user", conversation: book.startChat)
  try expectEqual(try book.resumableConversationAnswer(conversation: book.startChat), typedID)
  let typedModel = SurfaceModel()
  _ = try await WorkbookAgent.run(
    "", workbook: book, model: typedModel, conversationInput: true, inputAnswerID: typedID)
  try expectEqual(await typedModel.request?.content, "Include delivery")
  try expectEqual(
    await typedModel.policy?.content.contains("\"validatedAnswerValues\":{\"delivery\":true}"), true
  )
  try expectEqual(try book.pendingConversationInput(conversation: book.startChat), otherQuestion)
  let declined = try book.submitConversationInput(otherQuestion, response: .decline)!
  let declinedModel = SurfaceModel()
  _ = try await WorkbookAgent.run(
    "", workbook: book, model: declinedModel, conversationInput: true, inputAnswerID: declined)
  // The skipped request may still do its work. It may not ask again.
  try expectEqual(await declinedModel.offeredScope, .all)
  try expectEqual(await declinedModel.policy?.conversationInput, false)
  try expectEqual(
    await declinedModel.policy?.content.contains("The person skipped this question"), true)
  // Skipping hands the choice over. It does not turn the task into a read-only one.
  try expectEqual(try book.historyMessage(declined).body, "Skip this question. Go on without it.")
  try expectEqual(try book.pendingConversationInput(conversation: book.startChat), nil)

  var dateForm = arguments.object
  dateForm["choices"] = .array([])
  dateForm["fields"] = .array([
    .object([
      "id": .string("payment_date"), "type": .string("date"), "required": .bool(true),
      "label": .string("Payment date"),
    ])
  ])
  dateForm["question"] = .string("What was the payment date?")
  _ = try await WorkbookAgent.run(
    "Find Acme's payment by date.", workbook: book,
    model: SurfaceModel(input: .object(dateForm)), conversationInput: true)
  var local = Calendar(identifier: .gregorian)
  local.timeZone = TimeZone(identifier: "America/Los_Angeles")!
  let dateReference = ConversationDateContext(
    now: try Date.ISO8601FormatStyle().parse("2026-03-09T06:00:00Z"), calendar: local)
  let dateID = try book.submitConversationInput(
    book.pendingConversationInput(conversation: book.startChat)!, response: .text("Yesterday"),
    dateContext: dateReference)!
  let dateModel = SurfaceModel()
  _ = try await WorkbookAgent.run(
    "", workbook: book, model: dateModel, conversationInput: true, inputAnswerID: dateID)
  try expectEqual(await dateModel.request?.content, "Yesterday")
  try expectEqual(
    await dateModel.policy?.content.contains(
      "\"validatedAnswerValues\":{\"payment_date\":\"2026-03-07\"}"),
    true)

  let command = "app.enable"
  let target: Value = .object(["id": .string("test-app"), "expectedVersion": .number(1)])
  try book.prepareChatApproval(
    action: command, arguments: target, title: "First review", conversation: book.startChat)
  let older = try book.pendingChatApproval(conversation: book.startChat)!
  try book.prepareChatApproval(
    action: command, arguments: target, title: "Second review", conversation: book.startChat)
  let latest = try book.pendingChatApproval(conversation: book.startChat)!
  try expectThrows(try book.claimChatApproval(older, conversation: book.startChat, humanText: "Confirm"))
  let claimed = try book.claimChatApproval(latest, conversation: book.startChat, humanText: "Confirm")
  try expectEqual(claimed, latest)
  try expectThrows(try book.claimChatApproval(latest, conversation: book.startChat, humanText: "Confirm"))
  print(
    "PASS saved native question, exact answer and continuation, stale review refusal and scope parity"
  )

  let file = root.appendingPathComponent("Photo.png")
  try Data(
    base64Encoded:
      "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9Wl40r8AAAAASUVORK5CYII="
  )!.write(to: file)
  let job = try book.captureConversationAttachment(file, conversation: book.startChat, token: "chat-photo")
  let event = try book.messages().last!.id
  try expectEqual(try book.publishConversationAttachment(job.id, conversation: book.startChat), event)
  try expectThrows(try book.publishConversationAttachment(job.id, conversation: "foreign"))
  try expectEqual(
    try book.workspaceSnapshot(conversation: book.startChat)?.visuals[event]?.first?.image?.reference
      .sourceID,
    job.sourceID)
  let capture = SurfaceModel(
    operation: ("visual.evaluate", .object(["sourceID": .string(job.sourceID)])), attachVisual: true
  )
  let imageAnswer = try await WorkbookAgent.run(
    "Read only. Do not change anything. Show the original photo.", workbook: book,
    model: capture, conversationInput: true)
  try expectEqual(imageAnswer.state, "complete")
  let last = try book.messages().last!
  try expectEqual(
    try book.workspaceSnapshot(conversation: book.startChat)?.visuals[last.id]?.first?.image?.reference
      .sourceID,
    job.sourceID)
  do {
    _ = try await WorkbookAgent.run(
      "Show the photo", workbook: book, model: SurfaceModel(attachVisual: true))
    throw SevraError("check", "An invented visual receipt was accepted.")
  } catch let error as SevraError where error.code == "visual_capture" {}
  let pin = SurfaceModel(
    operation: (
      "visual.pin",
      .object([
        "sourceID": .string(job.sourceID),
        "expectedVersion": .number(Double(try book.space("home").version)),
      ])
    ))
  _ = try await WorkbookAgent.run("Add the photo to Home.", workbook: book, model: pin)
  try expectEqual(
    try book.space("home").definition.components.last?.visual?.image?.reference.sourceID,
    job.sourceID)
  print(
    "PASS included image attachment replay, read-only chat capture, forged receipt refusal and Home binding"
  )
  let table = try book.createDataset(
    title: "Accepted collections",
    columns: [
      Column(id: "customer", title: "Customer", type: "text"),
      Column(id: "amount", title: "Amount", type: "decimal", unit: "USD"),
    ],
    rows: [
      ["customer": .string("A"), "amount": .string("10.25")],
      ["customer": .string("A"), "amount": .string("1.01")],
      ["customer": .string("B"), "amount": .string("8.19")],
    ], sourceID: job.sourceID)
  let query = try Value.parse(
    """
    {"sources":[{"datasetID":"\(table.id)","definitionID":"\(table.definitionID)","scope":{"meaning":"actual","status":"accepted"}}],
    "select":[{"id":"customer","column":{"source":0,"column":"customer"}},
    {"id":"total","column":{"source":0,"column":"amount"},"aggregate":"sum"}],
    "groupBy":[{"source":0,"column":"customer"}],"sort":[{"field":"customer"}],"limit":10}
    """)
  let chart = VisualChart(
    title: "Collections by customer", style: .bar, query: query, x: "customer", y: "total")
  let exact = try book.chartData(chart)
  try expectEqual(exact.points.map(\.amount), ["11.26", "8.19"])
  try expectEqual(exact.unit, "USD")
  var firstOnly = query.object
  firstOnly["limit"] = .number(1)
  try expectThrows(
    try book.chartData(
      .init(
        title: chart.title, style: .bar, query: .object(firstOnly), x: chart.x, y: chart.y)))

  let chartModel = SurfaceModel(
    operation: ("visual.evaluate", .object(["chart": try encoded(chart)])), attachVisual: true)
  _ = try await WorkbookAgent.run(
    "Read only. Do not change anything. Show the collected amounts.", workbook: book,
    model: chartModel, conversationInput: true)
  let chartMessage = try book.messages().last!
  let captureSnapshot = try book.conversationVisual(chartMessage.id, index: 0, conversation: book.startChat)
  try expectEqual(captureSnapshot.chartData?.points, exact.points)
  let reopen = try Workbook(book.url)
  try expectEqual(
    try reopen.conversationVisual(chartMessage.id, index: 0, conversation: reopen.startChat), captureSnapshot)
  let homeChart = SurfaceModel(
    operation: (
      "visual.promote",
      .object([
        "messageID": .string(chartMessage.id), "index": .number(0),
        "expectedVersion": .number(Double(try book.space("home").version)),
      ])
    ))
  _ = try await WorkbookAgent.run(
    "Add this collections chart to Home.", workbook: book, model: homeChart)
  try expectEqual(try book.space("home").definition.components.last?.visual?.chart, chart)

  let promotedHome = try book.space("home")
  let promotedID = promotedHome.definition.components.last!.id
  _ = try await WorkbookAgent.run(
    "Filter the sales chart on Home to customer A.", workbook: book,
    model: SurfaceModel(
      operation: (
        "visual.filter",
        .object([
          "id": .string("home"), "componentID": .string(promotedID),
          "expectedVersion": .number(Double(promotedHome.version)),
          "filters": .array([
            .object([
              "column": .object(["source": .number(0), "column": .string("customer")]),
              "op": .string("eq"), "value": .string("A"),
            ])
          ]),
        ])
      )))
  let filtered = try book.space("home").definition.components.last!.visual!.chart!
  try expectEqual(try book.chartData(filtered).points.map(\.amount), ["11.26"])
  try expectEqual(
    try book.conversationVisual(chartMessage.id, index: 0, conversation: book.startChat), captureSnapshot)

  var aliasedQuery = query.object
  aliasedQuery["sources"] = .array([
    .object([
      "table": .string("sales"), "scope": query["sources"].array[0]["scope"],
    ])
  ])
  let appChart = VisualChart(
    title: chart.title, style: chart.style, query: .object(aliasedQuery), x: chart.x, y: chart.y)
  let package = NativeAppPackage(
    name: "Collections", source: "Sevra.mount(Sevra.h(Sevra.View,{viewID:'collections'}));",
    datasets: [
      "sales": NativeAppDataset(title: table.title, columns: table.columns, datasetID: table.id)
    ],
    views: ["collections": VisualDefinition(chart: appChart)])
  let app = try book.installNativeApp(package)
  let currentHome = try book.space("home")
  let appLink = Component(
    id: "app-collections", type: "app", title: "Collections in app", spaceID: app.id,
    viewID: "collections", viewVersion: app.version)
  var invalidLink = appLink
  invalidLink.viewVersion = app.version + 1
  try expectThrows(
    try book.editSpace(
      "home", expectedVersion: currentHome.version,
      edits: [
        .init(operation: "insert", at: "last", component: invalidLink)
      ]))
  _ = try book.editSpace(
    "home", expectedVersion: currentHome.version,
    edits: [
      .init(operation: "insert", at: "last", component: appLink)
    ])
  let access = try NativeAppAccess(workbook: book, space: app)
  try expectEqual(try book.nativeAppChart(access, view: "collections").points, exact.points)
  let preset = try book.saveNativeAppPreset(
    access, view: "collections", title: "Monthly collections", style: nil, filters: nil)
  let beforeArchive = try book.space("home")
  let pinnedPreset = try book.pinNativeAppView(
    access, view: "collections", presetID: preset.logicalID,
    expectedHomeVersion: beforeArchive.version)
  let archived = try book.saveNativeAppPreset(
    access, view: "collections", title: nil, style: nil, filters: nil,
    expectedPresetVersion: preset.id, archiving: true)
  try expectEqual(try book.space("home").version, pinnedPreset.version)
  try expectEqual(try book.space("home").definition, pinnedPreset.definition)
  try expectThrows(
    try book.nativeAppPresentation(access, view: "collections", presetID: preset.logicalID))
  try expectThrows(
    try book.nativeAppPresentation(access, view: "collections", presetID: preset.id))
  try expectThrows(
    try book.saveNativeAppPreset(
      access, view: "collections", title: "Stale", style: nil, filters: nil,
      expectedPresetVersion: preset.id))
  let history = try book.nativeAppPresetHistory(
    access, view: "collections", presetID: preset.logicalID)
  try expectEqual(
    history["recentVersions"].array.map { $0["archived"] }, [.bool(true), .bool(false)])
  let restored = try book.saveNativeAppPreset(
    access, view: "collections", title: nil, style: nil, filters: nil,
    expectedPresetVersion: archived.id, restoring: preset.id)
  try expectEqual(restored.logicalID, preset.logicalID)
  try expectEqual(
    try book.nativeAppPresentation(access, view: "collections", presetID: preset.logicalID).title,
    "Monthly collections")
  access.revoke()
  try expectThrows(try book.nativeAppChart(access, view: "collections"))
  let csv = root.appendingPathComponent("chart.csv")
  try book.publishSmallExport(exact.csv(chart), to: csv)
  try expectThrows(try book.publishSmallExport(Data(), to: csv))
  try expectEqual(try Data(contentsOf: csv), exact.csv(chart))
  let imageApp = try book.installNativeApp(
    NativeAppPackage(
      name: "Image alias",
      source: "Sevra.mount(Sevra.h(Sevra.Image,{asset:'photo',label:'Photo'}));",
      images: ["photo": try book.item(job.sourceID).assetID!]))
  let invalidTemplate = root.appendingPathComponent("Photo.sevraapp")
  try expectThrows(try book.exportNativeAppTemplate(imageApp.id, to: invalidTemplate))
  try expectEqual(FileManager.default.fileExists(atPath: invalidTemplate.path), false)
  print(
    "PASS exact chart grouping, captured reopen, Home and app parity, preset archive and restore"
  )

  let jobs = try book.createDataset(
    title: "Jobs",
    columns: [
      Column(id: "task", title: "Job"), Column(id: "status", title: "Status"),
      Column(id: "date", title: "Date", type: "date"),
    ],
    rows: [
      ["task": .string("Fit lock"), "status": .string("To do"), "date": .string("2026-11-16")],
      ["task": .string("Paint door"), "status": .string("Done"), "date": .string("2026-11-20")],
    ], sourceID: job.sourceID)
  let jobQuery = try Value.parse(
    """
    {"sources":[{"datasetID":"\(jobs.id)","definitionID":"\(jobs.definitionID)"}],
    "select":[{"id":"task","column":{"source":0,"column":"task"}},
    {"id":"lane","column":{"source":0,"column":"status"}}],"sort":[{"field":"task"}],"limit":20}
    """)
  let board: Value = .object([
    "title": .string("Jobs"), "style": .string("board"), "query": jobQuery,
    "label": .string("task"), "field": .string("lane"),
    "lanes": .array([.string("To do"), .string("Done")]),
  ])
  _ = try await WorkbookAgent.run(
    "Add a jobs board to Home.", workbook: book,
    model: SurfaceModel(
      operation: (
        "visual.pin",
        .object([
          "work": board, "expectedVersion": .number(Double(try book.space("home").version)),
        ])
      )))
  let home = try book.space("home")
  let component = home.definition.components.last!
  let work = component.visual!.work!
  let original = try book.workVisualData(work).records.first!
  try expectEqual(original.title, "Fit lock")
  try expectThrows(
    try book.changeWorkRecord(
      spaceID: home.id, componentID: component.id, expectedVersion: home.version,
      recordID: original.id, value: "Unknown"))
  let changed = try book.changeWorkRecord(
    spaceID: home.id, componentID: component.id, expectedVersion: home.version,
    recordID: original.id, value: "Done", token: "move-job")
  let retryMove = try book.changeWorkRecord(
    spaceID: home.id, componentID: component.id, expectedVersion: home.version,
    recordID: original.id, value: "Done", token: "move-job")
  try expectEqual(retryMove.id, changed.id)
  try expectThrows(
    try book.changeWorkRecord(
      spaceID: home.id, componentID: component.id, expectedVersion: home.version,
      recordID: original.id, value: "To do"))
  try expectEqual(try book.workVisualData(work).records.first?.value, "Done")
  try book.undoTableChange(changed.id)
  try expectEqual(try book.workVisualData(work).records.first?.value, "To do")
  var dateQuery = jobQuery.object
  dateQuery["select"] = .array([
    jobQuery["select"].array[0],
    .object([
      "id": .string("start"), "column": .object(["source": .number(0), "column": .string("date")]),
    ]),
  ])
  let workCalendar: Value = .object([
    "title": .string("November jobs"), "style": .string("calendar"), "query": .object(dateQuery),
    "label": .string("task"), "field": .string("start"), "month": .string("2026-11-01"),
  ])
  let calendarDefinition = try JSONDecoder().decode(
    WorkVisual.self, from: Data(workCalendar.json().utf8))
  try expectEqual(
    try book.workVisualData(calendarDefinition).records.map(\.value), ["2026-11-16", "2026-11-20"])
  _ = try await WorkbookAgent.run(
    "Show the November calendar.", workbook: book,
    model: SurfaceModel(
      operation: ("visual.evaluate", .object(["work": workCalendar])), attachVisual: true))
  let calendar = try book.conversationVisual(
    try book.messages().last!.id, index: 0, conversation: book.startChat)
  try expectEqual(calendar.workData?.records.map(\.value), ["2026-11-16", "2026-11-20"])
  try expectEqual(calendar.work?.style, .calendar)
  var trendQuery = dateQuery
  let dateColumn: Value = .object(["source": .number(0), "column": .string("date")])
  trendQuery["select"] = .array([
    dateQuery["select"]!.array[1],
    .object([
      "id": .string("jobs"), "aggregate": .string("countRows"),
    ]),
  ])
  trendQuery["groupBy"] = .array([dateColumn])
  trendQuery["sort"] = .array([.object(["field": .string("start"), "descending": .bool(true)])])
  let trend = try book.chartData(
    VisualChart(
      title: "Jobs by date", style: .line, query: .object(trendQuery), x: "start", y: "jobs",
      threshold: "2"))
  try expectEqual(trend.temporal, true)
  try expectEqual(
    trend.points.map(\.label), ["2026-11-16T00:00:00.000Z", "2026-11-20T00:00:00.000Z"])
  try expectEqual(
    try calendar.sourceForInspection(calendar.workData?.records[0].id),
    calendar.workData!.records[0].id)
  try expectThrows(try calendar.sourceForInspection(job.sourceID))
  print(
    "PASS versioned work board, lane and stale-row refusal, replay, Undo and civil-date calendar capture"
  )

}
