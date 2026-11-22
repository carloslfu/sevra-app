import AppKit
import PDFKit
import SevraAI
import SevraAppUI
import SevraCore
import SevraPreviewUI
import SevraProduct
import SevraVoice
import SwiftUI

@MainActor final class CatalogSession: ObservableObject {
  static let live = NSHashTable<CatalogSession>.weakObjects()
  @Published var state: WorkspaceState?
  @Published var failure: String?
  @Published var validationFailure: String?
  @Published var events: [String] = []
  @Published var ready = false
  @Published var rendered = false
  @Published var replaying = false
  @Published var component: Component?
  @Published var app: Space?
  @Published var step = 0
  @Published var interactionChecked = false
  @Published var visualReviewed = false
  @Published var visualReviewNote = ""
  var reviewedConfiguration: String?
  var reviewedRevision: Int?
  func reviewIsCurrent(_ configuration: CatalogConfiguration) -> Bool {
    visualReviewed && reviewedConfiguration == (try? configuration.json())
      && reviewedRevision == (try? book?.revision())
  }
  @Published var input: ConversationSurface?
  let root: URL
  let defaults: UserDefaults
  let suite: String
  var book: Workbook?
  var table: Dataset?
  var tasks: Dataset?
  var source: Item?
  var image: Item?
  var visual: VisualDefinition?
  var fileItems: [String: String] = [:]
  var workflowDefinition: ApplicationDefinition?
  var automationDefinition: ApplicationDefinition?
  var workflowRunID: String?
  var excelID: String?
  let transport = CatalogTransportGate()
  var generation = UUID()
  var mountedTask: Task<Void, Never>?
  let story: CatalogStory
  let variant: String
  let label: String
  let count: Int
  var minimumCanvasWidth: Double {
    if story.id == "main.settings" { return 420 }
    if story.id.hasPrefix("home.component.")
      || [
        "main.welcome", "main.opening", "main.column-editor", "main.navigation", "home.layout",
        "main.intake",
        "main.voice",
      ].contains(story.id)
    {
      return 420
    }
    return state?.focus == true ? 450 : 740
  }
  let spacing: Int
  let columns: Int
  let vertical: Bool
  init(
    story: CatalogStory, variant: String = "Default", label: String = "", count: Int = 6,
    spacing: Int = 16, columns: Int = 2, vertical: Bool = false
  ) {
    self.story = story
    self.variant = variant
    self.label = label
    self.count = count
    self.spacing = spacing
    self.columns = columns
    self.vertical = vertical
    suite = "com.sevra.ui-catalog.story." + UUID().uuidString
    defaults = UserDefaults(suiteName: suite)!
    root = AppHost.root.appendingPathComponent(UUID().uuidString)
    Self.live.add(self)
  }
  func prepare() async {
    let epoch = generation
    do {
      try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
      // Tool grants of catalog workbooks stay in the catalog's own folder.
      setenv("SEVRA_TOOL_GRANTS", AppHost.root.appendingPathComponent("tool-grants").path, 1)
      let b = try Workbook.create(
        at: root.appendingPathComponent("Example.sevra"), title: "Willow Workshop · Synthetic")
      book = b
      if story.id == "home.start" || story.id == "composition.first-workbook" {
        let ai = ProductAI(qualifying: CatalogInference())
        let workspace = WorkspaceState(
          ai: ai, defaults: defaults,
          automation: NativeAutomationHost(
            directory: root.appendingPathComponent("Schedules"), ai: ai, defaults: defaults))
        state = workspace
        try await workspace.open(b.url)
        book = workspace.workbook
        let deadline = Date().addingTimeInterval(8)
        while workspace.spaces.isEmpty && Date() < deadline {
          try await Task.sleep(for: .milliseconds(20))
        }
        try Task.checkCancellation()
        ready = !workspace.spaces.isEmpty
        events.append("Fresh empty workbook · no evidence, tables or conversation")
        return
      }
      let s = try b.addItem(
        category: "source", kind: "note", title: "Workshop observations",
        text: "Synthetic supplier quotes and tasks. All amounts exclude unknown tax.",
        status: "accepted")
      source = s
      let columns: [Column] = [
        .init(id: "name", title: "Supplier"),
        .init(id: "amount", title: "Cost", type: "decimal", unit: "USD"),
        .init(id: "series", title: "Region"), .init(id: "number", title: "Index", type: "decimal"),
      ]
      let n = variant == "Empty" ? 0 : variant == "Dense" ? 60 : count
      let rows: [[String: Value]] = (0..<n).map { i in
        [
          "name": .string(
            label.isEmpty
              ? (variant == "Long labels"
                ? "Supplier \(i + 1) with a deliberately long descriptive name"
                : ["Oak Supply", "Cedar Tools", "Birch Parts"][i % 3] + " \(i/3+1)")
              : label + " \(i+1)"),
          "amount": variant == "Missing and zero"
            ? (i == 0 ? .null : i == 1 ? .string("0") : .string(String((i + 1) * 24)))
            : .string(String((i + 1) * 24 * (variant == "Negative" && i % 2 == 0 ? -1 : 1))),
          "series": .string(i % 2 == 0 ? "North" : "South"), "number": .string(String(i)),
        ]
      }
      table = try b.createDataset(
        title: "Supplier comparison", columns: columns, rows: rows, sourceID: s.id)
      let tcols: [Column] = [
        .init(id: "name", title: "Task"), .init(id: "status", title: "Status"),
        .init(id: "due", title: "Due", type: "date"), .init(id: "end", title: "End", type: "date"),
      ]
      tasks = try b.createDataset(
        title: "Project plan", columns: tcols,
        rows: (0..<n).map { i in
          [
            "name": .string("Prepare order \(i+1)"),
            "status": .string(["Planned", "Doing", "Done"][i % 3]),
            "due": .string(String(format: "2026-11-%02d", min(28, i % 24 + 1))),
            "end": .string(String(format: "2026-11-%02d", min(28, i % 24 + 3))),
          ]
        }, sourceID: s.id)
      try seedFiles(b)
      let ai = ProductAI(qualifying: CatalogInference())
      let automation = NativeAutomationHost(
        directory: root.appendingPathComponent("Schedules"), ai: ai, defaults: defaults)
      let speechMode = variant
      let speech = SpeechInput(driverFactory: { CatalogDictation(mode: speechMode) })
      let exchange: (@Sendable (Data) async throws -> Data)?
      if story.id == "mini.state.starting" {
        let gate = transport
        exchange = { _ in try await gate.wait() }
      } else if story.id == "mini.state.invalid-frame" {
        exchange = { _ in Data("{invalid frame}".utf8) }
      } else {
        exchange = nil
      }
      let workspace = WorkspaceState(
        ai: ai, defaults: defaults, automation: automation, appExchange: exchange, speech: speech)
      state = workspace
      try await configure(b, workspace)
      guard generation == epoch, !Task.isCancelled else { return }
      try await workspace.open(b.url)
      book = workspace.workbook
      // open() deliberately resets presentation; apply the route only after snapshot hydration.
      let deadline = Date().addingTimeInterval(8)
      while workspace.spaces.isEmpty && Date() < deadline {
        try await Task.sleep(for: .milliseconds(20))
      }
      try require(
        !workspace.spaces.isEmpty, "catalog_ready", "Workspace snapshot did not become ready.")
      applyPresentation(workspace)
      ready = true
      events.append("Ready · real workbook, scripted inference, isolated preferences")
    } catch {
      guard generation == epoch, !Task.isCancelled else { return }
      failure = error.localizedDescription
    }
  }
  func stop() {
    Self.live.remove(self)
    generation = UUID()
    Task { await transport.finish() }
    mountedTask?.cancel()
    mountedTask = nil
    state?.stop()
    state?.close()
    state = nil
    book = nil
    defaults.removePersistentDomain(forName: suite)
    try? FileManager.default.removeItem(at: root)
    ready = false
  }
  func tearDown() async {
    await transport.finish()
    let pending = mountedTask
    pending?.cancel()
    state?.stop()
    await pending?.value
    if let state {
      _ = await state.saveBeforeClosing()
      await state.automation.stop()
    }
    stop()
  }
  func runUI(_ operation: @escaping @MainActor () async -> Void) {
    guard mountedTask == nil else { return }
    mountedTask = Task {
      await operation()
      mountedTask = nil
    }
  }
  func validateFixture() async throws {
    if let app, let state, let book {
      let host = state.nativeAppSession(app, book: book)
      let expected =
        story.id == "mini.state.access" || variant == "Disabled"
        ? "disabled"
        : story.id == "mini.state.starting"
          ? "starting"
          : ["mini.state.failed", "mini.state.invalid-frame", "mini.state.limits"].contains(
            story.id) ? "failed" : "running"
      try require(
        host.status == expected, "catalog_worker", story.id + ": " + (host.error ?? host.status))
    }
    if variant == "Failure" { return }
    if let chart = visual?.chart { _ = try book!.chartData(chart) }
    if let work = visual?.work { _ = try book!.workVisualData(work) }
    if let diagram = visual?.diagram { _ = try book!.diagramData(diagram) }
    if let overview = visual?.overview { _ = try book!.overviewData(overview) }
  }
  func query(_ dataset: Dataset, fields: [String], alias: String? = nil) -> Value {
    .object([
      "sources": .array([
        alias.map { .object(["table": .string($0)]) }
          ?? .object([
            "datasetID": .string(dataset.id), "definitionID": .string(dataset.definitionID),
          ])
      ]),
      "select": .array(
        fields.map {
          .object([
            "id": .string($0), "column": .object(["source": .number(0), "column": .string($0)]),
          ])
        }), "limit": .number(100),
    ])
  }
  func decode<T: Decodable>(_ value: Value, as: T.Type) throws -> T {
    try JSONDecoder().decode(T.self, from: Data(value.json().utf8))
  }
  func chart(_ style: String = "bar", alias: String? = nil) throws -> VisualChart {
    let t = table!
    if style == "metric" {
      let q: Value = .object([
        "sources": query(t, fields: [])["sources"],
        "select": .array([
          .object([
            "id": .string("series"),
            "column": .object(["source": .number(0), "column": .string("series")]),
          ]),
          .object([
            "id": .string("amount"),
            "column": .object(["source": .number(0), "column": .string("amount")]),
            "aggregate": .string("sum"),
          ]),
        ]), "groupBy": .array([.object(["source": .number(0), "column": .string("series")])]),
        "limit": .number(100),
      ])
      return try decode(
        .object([
          "title": .string("Quoted cost by reporting period"), "style": .string("metric"),
          "query": q, "x": .string("series"), "y": .string("amount"),
          "periods": .object([
            "current": .object([
              "key": .string("North"), "start": .string("2026-11-01"), "end": .string("2026-12-01"),
            ]),
            "baseline": .object([
              "key": .string("South"), "start": .string("2026-10-01"), "end": .string("2026-11-01"),
            ]),
          ]),
        ]), as: VisualChart.self)
    }
    let numeric = ["scatter", "histogram"].contains(style)
    let series = ["stackedBar", "heatmap"].contains(style) || variant == "Grouped"
    let fields = [numeric ? "number" : "name", "amount"] + (series ? ["series"] : [])
    var q = query(t, fields: fields, alias: alias)
    if style == "histogram" {
      q = .object([
        "sources": q["sources"],
        "select": .array([
          .object([
            "id": .string("number"),
            "column": .object(["source": .number(0), "column": .string("number")]),
          ]), .object(["id": .string("amount"), "aggregate": .string("countRows")]),
        ]), "groupBy": .array([.object(["source": .number(0), "column": .string("number")])]),
        "projections": .array([
          .object([
            "column": .object(["source": .number(0), "column": .string("number")]),
            "format": .string("decimal"), "binWidth": .string("2"),
          ])
        ]), "limit": .number(100),
      ])
    }
    return VisualChart(
      title: label.isEmpty ? "Quoted supplier costs" : label,
      style: VisualChart.Style(rawValue: style) ?? .bar, query: q, x: numeric ? "number" : "name",
      y: "amount", series: series ? "series" : nil,
      annotations: variant == "Annotated"
        ? try decode(
          .array([.object(["text": .string("Quoted cost, tax unknown"), "point": .number(0)])]),
          as: [VisualChart.Annotation].self) : nil)
  }
  func makeVisual(_ id: String) throws -> VisualDefinition {
    if id.contains(".chart.") {
      return .init(chart: try chart(id.components(separatedBy: ".").last!))
    }
    if id.contains(".work.") || id.hasSuffix(".work") || id.contains("projects") {
      let style = id.contains(".work.") ? id.components(separatedBy: ".").last! : "board"
      let board = style == "board"
      return .init(
        work: try decode(
          .object([
            "title": .string("Project plan"), "style": .string(style),
            "query": query(tasks!, fields: board ? ["name", "status"] : ["name", "due", "end"]),
            "label": .string("name"), "field": .string(board ? "status" : "due"),
            "lanes": board ? .array(["Planned", "Doing", "Done"].map(Value.string)) : .null,
            "end": board ? .null : .string("end"),
            "month": style == "calendar" ? .string("2026-11-01") : .null,
          ]), as: WorkVisual.self))
    }
    if id.hasSuffix("image") {
      return try book!.imageDefinition(
        sourceID: image!.id, caption: "Synthetic workshop image",
        accessibilityDescription: "Three colored shapes on a warm surface")
    }
    if id.hasSuffix("text") {
      return .init(
        text: try VisualText.parse(
          .object([
            "title": .string("Decision notes"),
            "blocks": .array(
              ["paragraph", "bullet", "callout"].map {
                .object([
                  "kind": .string($0),
                  "runs": .array([
                    .object([
                      "text": .string("Costs are exact. Tax remains unknown. "),
                      "strong": .bool($0 == "callout"), "sourceID": .string(source!.id),
                    ])
                  ]),
                ])
              }),
          ])))
    }
    if id.hasSuffix("diagram") {
      let b = book!
      let s = source!
      let nodeCount = variant == "Empty" ? 0 : variant == "Dense" ? 60 : 3
      let nodeRows: [[String: Value]] = (0..<nodeCount).map { i in
        [
          "key": .string("n\(i)"),
          "name": .string(
            variant == "Long labels"
              ? "Step \(i+1): inspect evidence and reconcile the exact supplier quotation"
              : "Order step \(i+1)"),
        ]
      }
      var pairs: [(Int, Int)] = (0..<max(0, nodeCount - 1)).map { ($0, $0 + 1) }
      if variant == "Branch" { pairs = [(0, 1), (0, 2)] }
      if variant == "Cycle" { pairs.append((2, 0)) }
      if variant == "Disconnected" { pairs = [(0, 1)] }
      let nodes = try b.createDataset(
        title: "Dependencies",
        columns: [.init(id: "key", title: "Key"), .init(id: "name", title: "Name")],
        rows: nodeRows, sourceID: s.id)
      let edges = try b.createDataset(
        title: "Relationships",
        columns: [.init(id: "from", title: "From"), .init(id: "to", title: "To")],
        rows: pairs.map { ["from": .string("n\($0.0)"), "to": .string("n\($0.1)")] }, sourceID: s.id
      )
      return .init(
        diagram: try decode(
          .object([
            "title": .string("Order dependencies"), "nodes": query(nodes, fields: ["key", "name"]),
            "edges": query(edges, fields: ["from", "to"]), "key": .string("key"),
            "label": .string("name"), "from": .string("from"), "to": .string("to"),
          ]), as: VisualDiagram.self))
    }
    if id.hasSuffix("overview") {
      return .init(
        overview: try VisualOverview.parse(
          .object([
            "title": .string("Supplier overview"),
            "panels": .array(
              try
                (variant == "Eight panels"
                ? ["bar", "metric", "table", "line", "donut", "area", "horizontalBar", "records"]
                : ["bar", "metric", "table"]).map { try encoded(chart($0)) }),
            "columns": .number(variant == "Eight panels" ? 3 : 2),
          ])))
    }
    return .init(chart: try chart())
  }
  func seedFiles(_ b: Workbook) throws {
    let text = root.appendingPathComponent("Observations.txt")
    try "Synthetic workshop observations\nSupplier costs exclude unknown tax.\n".write(
      to: text, atomically: true, encoding: .utf8)
    fileItems["text"] = try b.importFile(text).id
    let csv = root.appendingPathComponent("Quotes.csv")
    try "Supplier,Quantity,Cost\nOak,10,24\nCedar,10,27.50\n".write(
      to: csv, atomically: true, encoding: .utf8)
    fileItems["csv"] = try b.importFile(csv).id
    let picture =
      variant == "Portrait"
      ? "Portrait.png" : variant == "Transparency" ? "Transparent.png" : "Workshop.png"
    let png = root.appendingPathComponent("Workshop.png")
    try FileManager.default.copyItem(
      at: Bundle.main.resourceURL!.appendingPathComponent("CatalogAssets/" + picture), to: png)
    image = try b.importFile(png)
    fileItems["image"] = image!.id
    let pdfURL = root.appendingPathComponent("Quote.pdf")
    try FileManager.default.copyItem(
      at: Bundle.main.resourceURL!.appendingPathComponent("CatalogAssets/Quote.pdf"), to: pdfURL)
    fileItems["pdf"] = try b.importFile(pdfURL).id
    for (kind, name) in [
      ("audio", "Workshop.wav"), ("video", "Workshop.mp4"), ("archive", "Evidence.zip"),
    ] {
      let asset = Bundle.main.resourceURL!.appendingPathComponent("CatalogAssets/" + name)
      let copy = root.appendingPathComponent(name)
      try FileManager.default.copyItem(at: asset, to: copy)
      fileItems[kind] = try b.importFile(copy).id
      if kind == "audio" {
        try b.index(
          fileItems[kind]!,
          chunks: [
            .init(
              "Synthetic transcript sample; this text was scripted, not recognized from the tone.",
              locator: "time=0; end=0.5")
          ], detail: "Synthetic catalog transcript", parser: "apple-speech-catalog-script")
      }
    }
    try b.extract(fileItems["text"]!)
    fileItems["extracted"] = fileItems["text"]
    fileItems["references"] = try b.addItem(
      category: "record", kind: "note", title: "Evidence-backed recommendation",
      text: "Oak quotes 24 USD. Tax is unknown.",
      inputs: [source!.id, fileItems["pdf"]!, image!.id]
    ).id
  }
  func configure(_ b: Workbook, _ ws: WorkspaceState) async throws {
    let id = story.id
    if id == "chat.queue" {
      let texts = [
        "Chart the delivery days by supplier",
        "Then write a short summary I can send to the team, with the cheapest option first and anything still unknown at the end",
        "Add the Northwind quote from the PDF",
      ]
      var queue = ConversationQueue()
      for n in 0..<(variant == "Many" ? 14 : 3) {
        try queue.add(
          texts[n % texts.count] + (n < texts.count ? "" : " (\(n + 1))"),
          context: n == 2 ? "Supplier quotes, rows 1 to 4" : "", id: "queued-\(n)",
          queued: timestamp())
      }
      _ = try b.saveConversationViewState(
        try b.chats()[0].id, draft: "", reading: .init(), expectedDraft: "", queue: queue)
    }
    visual = try makeVisual(id)
    component = Component(
      type: visual?.kind == .image ? "image" : "visual", title: story.title, visual: visual)
    if id.hasPrefix("mini.") || id.contains("inventory") || id == "home.embedded"
      || id == "home.component.app" || id == "composition.surfaces"
    {
      let type =
        id == "mini.view.image"
        ? "image"
        : id.hasPrefix("mini.node.")
          ? String(id.dropFirst("mini.node.".count))
          : id.hasPrefix("mini.helper.")
            ? String(id.dropFirst("mini.helper.".count))
            : id.hasPrefix("mini.action-input.")
              ? "ActionInput." + id.components(separatedBy: ".").last! : "Workspace"
      var source = CatalogMiniApps.source(
        type: type, variant: variant, label: label, spacing: spacing, columns: columns,
        vertical: vertical)
      if id.hasPrefix("mini.example."),
        let url = Bundle.main.resourceURL?.appendingPathComponent(
          "CatalogExamples/" + id.components(separatedBy: ".").last! + "/app.sevraapp")
      {
        let template = try JSONDecoder().decode(NativeAppPackage.self, from: Data(contentsOf: url))
        // Full standalone examples supply their own schema, preserving app behavior.
        app = try b.installNativeApp(template)
      } else {
        if id == "mini.state.limits" {
          source =
            "Sevra.mount(Sevra.h(Sevra.Column,{},...Array.from({length:10001},(_,i)=>Sevra.h(Sevra.Text,{text:String(i)}))));"
        }
        if id == "mini.state.draft" {
          source = CatalogMiniApps.source(type: "draftSignal", variant: variant, label: label)
        }
        if id == "mini.state.failed" {
          source = "throw Error('Synthetic worker failure. Restart or reset this story.');"
        }
        let stock = try b.createDataset(
          title: "Stock",
          columns: [
            .init(id: "name", title: "Item"),
            .init(id: "quantity", title: "Quantity", type: "decimal"),
          ],
          rows: variant == "Empty"
            ? []
            : (0..<(id == "mini.state.paging" ? 240 : variant == "Dense" ? 60 : count)).map {
              ["name": .string("Brass bolts \($0+1)"), "quantity": .string(String($0 + 20))]
            }, sourceID: self.source!.id)
        if id == "composition.surfaces" {
          table = stock
          visual = .init(
            chart: VisualChart(
              title: "Stock quantities", style: .bar,
              query: query(stock, fields: ["name", "quantity"]), x: "name", y: "quantity"))
          component = .init(type: "visual", title: "Live stock", visual: visual)
        }
        let binding = NativeAppDataset(
          title: "Stock", columns: stock.columns, writable: true, datasetID: stock.id)
        app = try b.installNativeApp(
          NativeAppPackage(
            name: "Workshop app", source: source, datasets: ["stock": binding],
            images: ["photo": image!.assetID!],
            views: [
              "stockView": .init(
                chart: VisualChart(
                  title: "Stock", style: .bar,
                  query: query(stock, fields: ["name", "quantity"], alias: "stock"), x: "name",
                  y: "quantity"))
            ]))
      }
    }
    if id.hasPrefix("mini.view.") { try declaredView(id.components(separatedBy: ".").last!, b) }
    if id.hasPrefix("home.component.") {
      component = try spaceComponent(String(id.dropFirst("home.component.".count)))
    }
    if id == "home.comparison" {
      component = Component(
        type: "comparison", title: "Compare suppliers",
        children: [
          Component(type: "visual", title: "Costs", visual: .init(chart: try chart())),
          Component(type: "text", title: "Decision", text: "Inspect the source before choosing."),
        ])
    }
    if let component,
      id.hasPrefix("visual.") || id.hasPrefix("home.component.") || id == "home.comparison"
        || id.contains("overview") || id.contains("projects")
    {
      _ = try b.saveSpace(
        id: "example", title: story.title, definition: .init(components: [component]))
    }
    try await seedBusiness(b, ws)
    try await seedChat(b)
    if (id == "main.review" && variant != "Empty") || id == "home.attention"
      || id == "home.customized"
    {
      _ = try b.addItem(
        category: "record", kind: "note", title: "Proposed purchasing decision",
        text: "Review the supplier comparison before accepting.", status: "draft",
        inputs: [source!.id])
    }
    if id == "home.empty" {
      _ = try b.saveSpace(
        id: "home", title: "Home", definition: .init(components: []), expectedVersion: 1)
    }
    if id == "home.customized" {
      _ = try b.saveSpace(
        id: "home", title: "Home",
        definition: .init(components: [
          .init(
            type: "text", title: "My workspace",
            text: "The attention fallback keeps pending work reachable.")
        ]), expectedVersion: 1)
    }
    if id == "home.embedded", let app {
      _ = try b.saveSpace(
        id: "home", title: "Home",
        definition: .init(components: [.init(type: "app", title: app.title, spaceID: app.id)]),
        expectedVersion: 1)
    }
    try await seedBoundaries(b, ws)
  }
  func spaceComponent(_ type: String) throws -> Component {
    let t = table!
    switch type {
    case "table", "chart", "metric":
      return .init(
        type: type, title: story.title, datasetID: t.id, x: "name", y: "amount", chartStyle: "bar",
        aggregation: "SUM", unit: "USD")
    case "document", "asset":
      return .init(
        type: type, title: story.title, itemID: fileItems[type == "asset" ? "image" : "text"])
    case "search": return .init(type: type, title: story.title, query: "supplier")
    case "text":
      return .init(
        type: type, title: story.title,
        text: label.isEmpty ? "Bring the evidence together, then decide." : label)
    case "comparison":
      return .init(
        type: type, title: story.title,
        children: [
          .init(type: "text", title: "Evidence", text: "Quoted costs"),
          .init(type: "text", title: "Decision", text: "Tax remains unknown"),
        ])
    case "image":
      return .init(
        type: type, title: story.title, visual: try book!.imageDefinition(sourceID: image!.id))
    case "query":
      let q = try book!.saveApplicationDefinition(
        logicalID: identifier(),
        content: .object([
          "kind": .string("query"), "title": .string("Supplier costs"),
          "description": .string("Current exact table"), "parameters": .array([]),
          "payload": .object([
            "dataMode": .string("exact"), "query": query(t, fields: ["name", "amount"]),
          ]),
        ]))
      return .init(
        type: type, title: "Supplier costs",
        definitionBinding: .object(["mode": .string("live"), "logicalID": .string(q.logicalID)]),
        arguments: .object([:]))
    case "form":
      let action = try book!.saveApplicationDefinition(
        logicalID: identifier(), content: ActionRegistry.receivingDefinition())
      let form = try book!.saveApplicationDefinition(
        logicalID: identifier(), content: ActionRegistry.formDefinition(target: action))
      return .init(
        type: type, title: "Receive delivery",
        definitionBinding: .object(["mode": .string("live"), "logicalID": .string(form.logicalID)]))
    case "calculation":
      let f = try book!.saveApplicationDefinition(
        logicalID: UUID().uuidString,
        content: try Value.parse(
          #"{"kind":"function","title":"Case count","description":"Synthetic","parameters":[{"id":"x","label":"Cases","type":"decimal","required":true}],"payload":{"expression":"x*12","calls":[],"unit":"items"}}"#
        ))
      return .init(
        type: type, title: "Count cases",
        definitionBinding: .object(["mode": .string("live"), "logicalID": .string(f.logicalID)]),
        arguments: .object(["x": .string("3")]))
    case "app":
      return .init(
        type: type, title: app?.title ?? "Unavailable app", spaceID: app?.id ?? "missing")
    case "visual": return .init(type: type, title: story.title, visual: visual)
    default: return .init(type: type, title: story.title)
    }
  }
  func applyPresentation(_ ws: WorkspaceState) {
    let id = story.id
    if id.hasPrefix("visual.") || id.hasPrefix("home.component.") || id == "home.comparison"
      || id.contains("overview") || id.contains("projects")
    {
      ws.route = .space("example")
    } else if let app, id.hasPrefix("mini.") || id.contains("inventory") {
      ws.route = .space(app.id)
    } else if id == "main.definitions" {
      ws.route = .space("example")
    } else if let excelID {
      ws.route = .excelImport(excelID)
    } else if id == "main.table" {
      ws.route = .table(table!.id)
    } else if id == "main.search" {
      ws.route = .search
      ws.searchQuery = variant == "Empty" ? "no matching evidence" : "supplier"
    } else if id == "main.review" {
      ws.route = .reviews
    } else if id == "main.workflows" || id.contains("workflow") {
      ws.route =
        (id == "main.workflow-detail" && workflowRunID != nil)
        ? .workflow(workflowRunID!) : .activity
    } else if id == "main.tools" {
      ws.route = .tools
    } else if id == "main.automations" {
      ws.route =
        variant == "Detail" || variant == "Armed"
        ? .automation(automationDefinition!.id) : .automations
    } else if id.hasPrefix("main.viewer.") {
      ws.route = .item(fileItems[id.components(separatedBy: ".").last!] ?? source!.id)
    } else if id == "main.table-update" {
      ws.route = .tableUpdate(fileItems["csv"]!, nil)
    } else if id == "main.automation-detail", let definition = automationDefinition {
      ws.route = .automation(definition.id)
    } else if id == "main.references" {
      ws.route = .item(fileItems["references"]!)
      ws.referencePanel = .incoming
    } else if id == "main.document" || id.contains("evidence") {
      ws.route = .item(fileItems["historical"] ?? source!.id)
    }
    if id == "chat.composer" || id == "chat.context" {
      ws.prompt =
        variant == "Empty"
        ? "" : "Compare the quotes, include delivery, and explain what remains unknown."
    }
    if id == "main.history-search" { ws.showingHistorySearch = true }
    if id == "chat.chat-list" { ws.showingChats = true }
    if id == "main.voice" && ["Recording", "Denied"].contains(variant) { ws.voice() }
    ws.focus =
      variant == "Focused" || id.hasPrefix("mini.") || id.hasPrefix("visual.")
      || id == "home.comparison"
    if id == "chat.queue", variant != "Paused" {
      var queue = ws.queue
      queue.paused = false
      ws.conversationSession.updateQueue(queue)
    }
    if variant == "Busy" || variant == "Analyzing" || variant == "Building"
      || variant == "Streaming" || (id == "chat.queue" && variant != "Paused")
    {
      ws.busy = true
      ws.status = "Reading synthetic evidence…"
      var live = LiveRequestActivity(conversation: ws.conversation, started: Date(timeIntervalSinceNow: -12))
      live.update(ws.status)
      if variant == "Streaming" {
        live.preview(
          "I can help compare supplier quotes with source citations, organize inventory…",
          sequence: 1)
      }
      ws.liveActivity = live
    }
    if variant == "Failure" { ws.error = "Synthetic service failure. Reset or retry this example." }
    if let app, variant != "Disabled", story.id != "mini.state.access" {
      ws.nativeAppSession(app, book: book!).enable()
    }
  }
  func replay() async {
    guard ready, !replaying, step < flowSteps.count else { return }
    replaying = true
    defer { replaying = false }
    do {
      try await runFlowStep()
      book = state?.workbook ?? book
      events.append("✓ " + flowSteps[step])
      step += 1
    } catch {
      events.append("Failed: " + error.localizedDescription)
      failure = error.localizedDescription
    }
  }
}
