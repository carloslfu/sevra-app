import Foundation

public struct ImageReference: Codable, Equatable, Sendable {
  public let sourceID: String
  public let assetID: String
}

public struct ImagePresentation: Codable, Equatable, Sendable {
  public let reference: ImageReference
  public var caption: String
  public var accessibilityDescription: String
}

/// Native visuals use workbook-owned references and bounded presentation values.
public struct VisualDefinition: Codable, Equatable, Sendable {
  public enum Kind: String, Codable, Sendable { case image, chart, work, diagram, overview, text }
  public let version: Int
  public let kind: Kind
  public var image: ImagePresentation?
  public var chart: VisualChart?
  public var work: WorkVisual?
  public var diagram: VisualDiagram?
  public var overview: VisualOverview?
  public var text: VisualText?

  public var title: String? {
    chart?.title ?? work?.title ?? diagram?.title ?? overview?.title ?? text?.title
  }

  var queries: [Value] {
    [chart?.query, work?.query, diagram?.nodes, diagram?.edges].compactMap { $0 }
      + (overview?.panels.map(\.query) ?? [])
  }

  func sourceChart(panel: Int?) throws -> VisualChart {
    if let panel, let panels = overview?.panels, panels.indices.contains(panel) {
      return panels[panel]
    }
    if panel == nil, let chart { return chart }
    throw SevraError("visual_source", "Choose an exact chart or overview panel.")
  }

  public init(image: ImagePresentation) {
    self.version = 1
    self.kind = .image
    self.image = image
  }

  public init(chart: VisualChart) {
    self.version = 1
    self.kind = .chart
    self.chart = chart
  }

  public init(work: WorkVisual) {
    self.version = 1
    self.kind = .work
    self.work = work
  }

  public init(diagram: VisualDiagram) {
    self.version = 1
    self.kind = .diagram
    self.diagram = diagram
  }

  public init(overview: VisualOverview) {
    self.version = 1
    self.kind = .overview
    self.overview = overview
  }

  public init(text: VisualText) {
    self.version = 1
    self.kind = .text
    self.text = text
  }

  func validate(appAliases: Set<String>? = nil) throws {
    try require(version == 1, "visual", "This visual uses an unsupported version.")
    if kind == .text {
      guard let text, overview == nil, chart == nil, image == nil, work == nil, diagram == nil
      else {
        throw SevraError("visual", "Choose a text definition.")
      }
      try text.validate(appOwned: appAliases != nil)
      return
    }
    try require(text == nil, "visual", "Choose one visual definition.")
    if kind == .overview {
      guard let overview, chart == nil, image == nil, work == nil, diagram == nil else {
        throw SevraError("visual", "Choose an overview definition.")
      }
      try overview.validate(appAliases: appAliases)
      return
    }
    try require(overview == nil, "visual", "Choose one visual definition.")
    if kind == .chart {
      guard let chart, image == nil, work == nil, diagram == nil else {
        throw SevraError("visual", "Choose a chart definition.")
      }
      try chart.validate(appAliases: appAliases)
      return
    }
    if kind == .work {
      guard let work, image == nil, chart == nil, diagram == nil else {
        throw SevraError("visual", "Choose a work view definition.")
      }
      try work.validate(appAliases: appAliases)
      return
    }
    if kind == .diagram {
      guard let diagram, image == nil, chart == nil, work == nil else {
        throw SevraError("visual", "Choose a diagram definition.")
      }
      try diagram.validate(appAliases: appAliases)
      return
    }
    guard let image, chart == nil, work == nil, diagram == nil, appAliases == nil,
      !image.reference.sourceID.isEmpty, image.reference.sourceID.utf8.count <= 128,
      !image.reference.assetID.isEmpty, image.reference.assetID.utf8.count <= 128,
      image.caption.utf8.count <= 400,
      !image.accessibilityDescription.isEmpty, image.accessibilityDescription.utf8.count <= 240
    else {
      throw SevraError("visual", "Use an exact included image and a short caption and description.")
    }
  }
}

/// Only resolved by the workbook. The decoder verifies the bytes it reads.
public struct ImageAssetRead: Sendable {
  public let file: URL
  public let hash: String
  public let bytes: Int64
}

extension Workbook {
  public func imageDefinition(
    sourceID: String, caption: String = "", accessibilityDescription: String? = nil
  ) throws -> VisualDefinition {
    let item = try item(sourceID)
    guard item.id == sourceID, item.category == "source", let assetID = item.assetID else {
      throw SevraError("visual_image", "Choose an exact source version with an included image.")
    }
    let asset = try includedImage(assetID)
    let definition = VisualDefinition(
      image: ImagePresentation(
        reference: ImageReference(sourceID: item.id, assetID: asset.id), caption: caption,
        accessibilityDescription: accessibilityDescription ?? String(asset.name.prefix(60))))
    try definition.validate()
    return definition
  }

  package func includedImageSources(matching search: String) throws -> [(id: String, title: String)]
  {
    let query = String(search.trimmingCharacters(in: .whitespacesAndNewlines).prefix(200))
    return try synchronized {
      try db.execute(
        """
        SELECT i.id,i.title FROM items i JOIN heads h ON h.item_id=i.id
        JOIN assets a ON a.id=i.asset_id
        WHERE i.category='source' AND i.status!='rejected'
          AND a.mode='included' AND a.media_type LIKE 'image/%' AND a.path LIKE 'assets/%'
          AND instr(lower(i.title), lower(?))>0
        ORDER BY i.created DESC,i.id LIMIT 50
        """, [.string(query)]
      ).map { ($0["id"]!.text, $0["title"]!.text) }
    }
  }

  func includedImage(_ id: String) throws -> Asset {
    let asset = try asset(id)
    try require(
      asset.mode == "included" && asset.path.hasPrefix("assets/")
        && asset.mediaType.hasPrefix("image/"),
      "visual_image", "Choose an image included in this workbook.")
    return asset
  }

  func validateImageReference(_ reference: ImageReference) throws -> Asset {
    let source = try item(reference.sourceID)
    try require(
      source.id == reference.sourceID && source.category == "source"
        && source.assetID == reference.assetID,
      "visual_image", "The image does not belong to this source version.")
    return try includedImage(reference.assetID)
  }

  public func imageAssetRead(_ reference: ImageReference) throws -> ImageAssetRead {
    let asset = try validateImageReference(reference)
    return try imageAssetRead(asset)
  }

  func imageAssetRead(_ asset: Asset) throws -> ImageAssetRead {
    ImageAssetRead(file: try safePath(asset.path), hash: asset.hash, bytes: asset.bytes)
  }
}

extension Workbook {
  /// The saved import is independent of extraction or image decoding. Reusing
  /// the same intake token cannot duplicate or relocate its event.
  @discardableResult package func publishConversationAttachment(
    _ intakeID: String, conversation: String
  ) throws -> String {
    let id = identifier()
    return try mutation(
      "conversation_attachment", token: intakeID + "-conversation-event",
      request: .object(["intake": .string(intakeID), "conversation": .string(conversation)])
    ) {
      let job = try intakeJob(intakeID)
      try require(intakeID.hasSuffix("-use"), "history_scope", "Choose an exact chat attachment.")
      let token = String(intakeID.dropLast("-use".count))
      let intendedConversation = try db.scalar(
        "SELECT json_extract(request,'$.conversation') FROM operations WHERE kind='conversation_attachment_intent' AND id=?",
        [.string(token + "-conversation-intent")])
      let capturedSource = try db.scalar(
        "SELECT json_extract(result,'$') FROM operations WHERE kind='import' AND id=?",
        [.string(token + "-file")])
      try require(
        intendedConversation == .string(conversation) && capturedSource == .string(job.sourceID),
        "history_scope", "This attachment belongs to another capture or conversation.")
      let source = try item(job.sourceID)
      let asset = try source.assetID.map(asset)
      let image = try? imageDefinition(sourceID: source.id)
      let body = (asset?.mode == "linked" ? "Linked " : "Included ") + source.referenceMarkdown
      var fields: [String: Value] = [
        "kind": .string("conversation_attachment"), "sourceID": .string(source.id),
      ]
      if let image { fields["visuals"] = .array([try encoded(VisualResult(definition: image))]) }
      try insertSurfaceMessage(
        id, conversation: conversation, role: "event", body: body, state: "complete",
        payload: .object(fields))
      return .string(id)
    }.text
  }

  func conversationVisuals(_ messages: [Message], conversation: String, anchor: String?) throws
    -> [String: [VisualResult]]
  {
    try readConversationVisuals(
      messages.map(\.id), conversation: conversation,
      anchor: anchor, limit: 2)
  }

  public func hydrateConversationVisuals(
    _ ids: [String], conversation: String, cancellation: Cancellation = .init()
  ) throws -> [String: [VisualResult]] {
    try require(
      ids.count <= 4 && ids.allSatisfy { $0.utf8.count <= 128 },
      "visual_window", "Hydrate up to four visible messages.")
    return try synchronized(cancellation: cancellation) {
      try readConversationVisuals(ids, conversation: conversation, anchor: ids.first, limit: 4)
    }
  }

  private func readConversationVisuals(
    _ ids: [String], conversation: String, anchor: String?, limit: Int
  ) throws -> [String: [VisualResult]] {
    guard !ids.isEmpty else { return [:] }
    let markers = ids.map { _ in "?" }.joined(separator: ",")
    // Inspect JSON in SQLite. Transfer at most two bounded visual payloads,
    // keeping a historical message selected by an exact jump as the first choice.
    let rows = try db.execute(
      """
      SELECT m.id, json_extract(p.payload,'$.visuals') AS visuals
      FROM messages m JOIN message_payloads p ON p.message_id=m.id
      WHERE m.conversation_id=? AND m.id IN (\(markers)) AND m.role IN ('assistant','event')
        AND json_type(p.payload,'$.visuals')='array'
        AND length(CAST(json_extract(p.payload,'$.visuals') AS BLOB))<=49152
      ORDER BY (m.id=?) DESC, m.rowid DESC LIMIT ?
      """,
      [.string(conversation)] + ids.map(Value.string)
        + [anchor.map(Value.string) ?? .null, .number(Double(limit))],
      maxRows: limit, maxBytes: limit * 50_000)
    var result: [String: [VisualResult]] = [:]
    for row in rows {
      guard let data = row["visuals"]?.string,
        let definitions = try? JSONDecoder().decode([VisualResult].self, from: Data(data.utf8)),
        (1...2).contains(definitions.count),
        definitions.allSatisfy({ (try? $0.validate()) != nil })
      else { continue }
      result[row["id"]!.text] = definitions
    }
    return result
  }
}

extension WorkbookTools {
  func executeVisualOperation(_ name: String, _ a: Value, token: String) throws -> Value {
    switch name {
    case "visual.schema":
      let schema: [String: Value] = [
        "version": .number(1),
        "aggregate": .string(
          "For totals or counts by one category, call visual.evaluate with aggregate:{title,datasetID,definitionID,category,measure,reducer,style?}. category and measure are column IDs. Use reducer=sum for totals, countRows for record counts (omit measure), or average, min, max or count. Default style is bar. Default scope is accepted actual in scenario actual. To use a different scope supply scope:{meaning,status,scenario}."
        ),
        "chart": .string(
          "For visual.evaluate or visual.pin, pass chart {title,style:bar|horizontalBar|stackedBar|line|area|scatter|donut|histogram|heatmap|metric|table|records,x,y,series?,threshold?,periods?,annotations?,dataBars?,query}. For metrics, periods declares current and optional baseline as {key,start,end,observedThrough?} with ISO dates and end exclusive. Supply either chart or sourceID, never both. x, y and optional series are output IDs. Series are supported on bars and lines; stackedBar requires series. query {sources:[{datasetID,definitionID,scope:{meaning,status,scenario}}],select:[{id,column:{source:0,column},aggregate?}],groupBy?:[{source,column}],sort?:[{field,descending}],filters?:[{column:{source,column},op,value}],limit:100}. Omit groupBy/aggregate for exact rows. Use sum/average/min/max/count/countRows, with no column for countRows. No partial results. For app views use [{table:alias,scope}] as sources."
        ),
        "queryExtensions": .string(
          "An Excel source may declare excelRows:{firstRow,lastRow,excludeRows:[row numbers]}. projections:[{column:{source,column},format:decimal|en-US|de-DE|isoDate|isoInstant|mdy|dmy|excel1900|excel1904,bucket?:day|week|month|year,timeZone?,binWidth?,binOrigin?}]. Supply bin settings as decimal strings. Histograms group by a numeric bin and countRows. Heatmaps use x and series as category dimensions. Grouped joins require joins:[{kind,left:{source,column},right,cardinality:manyToOne}]."
        ),
        "work": .string(
          "Pass work {title,style:board|timeline|agenda|calendar,query,label,field,end?,lanes?,month?,thumbnailKey?,thumbnailAssets?,thumbnailAliases?} to visual.evaluate or visual.pin. query selects exact rows from one dataset with limit <=100. label is a selected title field. field selects text status for a board, date start for time views. Board lanes are declared status values; calendar month is YYYY-MM-01. Optional end is another selected date field. An optional thumbnailKey selects exact lookup values in thumbnailAssets (included image references) or thumbnailAliases (declared app aliases). Use up to eight explicit mappings."
        ),
        "diagram": .string(
          "Pass diagram {title,nodes,edges,key,label,from,to}. nodes and edges are typed queries read in the same snapshot. Select two fields per query. key identifies unique nodes; from and to use these exact keys. Limit nodes to 100 and edges to 200. Inspect a saved diagram with visual.inspect for current coordinates. Configure optional positions {nodeKey:{x,y}} through visual.configure or a diagram app preset. Coordinates are top-left points, positive and nonoverlapping. Empty positions restores automatic layout."
        ),
        "overview": .string(
          "Pass overview {title,columns?,panels:[chart descriptors]}. Compose two to eight charts, metrics, tables or record lists over one snapshot. Use one to three responsive columns."
        ),
        "text": .string(
          "Pass text {title,blocks:[{kind:paragraph|bullet|callout,runs:[{text,strong?,sourceID?}]}]}. Text is displayed directly. Link only to an exact workbook source already inspected."
        ),
        "recipes": .string(
          "Sales: sum dated revenue by week, compare aligned periods, show product mix. Collections: filter accepted open invoices, separate currencies, sort overdue balances. Inventory: group available stock by location, flag below target, show exact items. Jobs: use a board for status and agenda for due dates. Suppliers: compare exact lead-time bins, separate missing dates. Dependencies: query declared nodes and relationships from one snapshot."
        ),
        "image": .string(
          "Pass sourceID (exact included image source), optional caption and accessibilityDescription to visual.evaluate. Save with visual.pin, change captions with visual.configure, or replace the included original with visual.replace_image."
        ),
      ]
      if let family = a["family"].string {
        guard let details = schema[family], family != "version" else {
          throw SevraError(
            "visual",
            "Choose aggregate, chart, queryExtensions, work, diagram, overview, text, image or recipes."
          )
        }
        return .object([family: details])
      }
      return .object(schema)
    case "visual.evaluate":
      let visual = try visualDefinition(a)
      let data = try visual.chart.map { try workbook.captureChart($0, cancellation: cancellation) }
      let records = try visual.work.map {
        try workbook.workVisualData($0, cancellation: cancellation)
      }
      try require(
        records?.nextCursor == nil, "work_view_coverage",
        "Filter this live work view before capturing a complete chat answer.")
      let graph = try visual.diagram.map {
        try workbook.diagramData($0, cancellation: cancellation)
      }
      if let graph, let positions = visual.diagram?.positions, !positions.isEmpty {
        _ = try graph.layout(positions: positions, cancellation: cancellation)
      }
      let panels = try visual.overview.map {
        try workbook.overviewData($0, capture: true, cancellation: cancellation)
      }
      let capture = try encoded(
        VisualResult(
          definition: visual, chartData: data, workData: records, diagramData: graph,
          overviewData: panels))
      try require(
        capture.json().utf8.count <= 24 * 1024, "visual_limit",
        "Narrow the chart to save a compact answer.")
      let title = try visualTitle(visual, arguments: a)
      return .object([
        "status": .string("captured"), "capture": capture,
        "visualSummary": .object([
          "title": .string(title), "kind": .string(visual.kind.rawValue),
          "hash": .string(ChangeFormat.hash(try capture.json())),
          "sourceID": visual.image.map { .string($0.reference.sourceID) } ?? .null,
          "marks": data.map { .number(Double($0.points.count)) }
            ?? records.map { .number(Double($0.records.count)) }
            ?? graph.map { .number(Double($0.nodes.count)) } ?? .null,
          "unknown": data.map { .number(Double($0.unknown)) } ?? .null,
          "scope": data?.scope ?? records?.scope ?? .null,
        ]),
        "notice": .string(
          "Attach this receipt ID with finish.visuals. Exact values are saved in the receipt. Image decoding is checked at display."
        ),
      ])
    case "visual.sources":
      return try workbook.chartGroupSources(
        messageID: a["messageID"].text,
        index: a["index"].int!, conversation: conversation, point: a["point"].int!,
        offset: a["offset"].int ?? 0, panel: a["panel"].int)
    case "visual.relationships":
      let result = try workbook.conversationVisual(
        a["messageID"].text, index: a["index"].int!,
        conversation: conversation)
      guard let graph = result.diagramData else {
        throw SevraError("visual_diagram", "Choose an exact captured diagram.")
      }
      return try graph.inspection(node: a["node"].string, offset: a["offset"].int ?? 0)
    case "visual.pin":
      let visual = try visualDefinition(a)
      if let diagram = visual.diagram, let positions = diagram.positions, !positions.isEmpty {
        let graph = try workbook.diagramData(diagram, cancellation: cancellation)
        _ = try graph.layout(positions: positions, cancellation: cancellation)
      }
      return try encoded(
        workbook.addVisualToHome(
          visual, title: a["title"].string, expectedVersion: a["expectedVersion"].int!, token: token
        ))
    case "visual.promote":
      return try encoded(
        workbook.promoteConversationVisual(
          a["messageID"].text, index: a["index"].int!, conversation: conversation,
          expectedVersion: a["expectedVersion"].int!, token: token))
    case "visual.replace_image":
      let owner = try workbook.space(a["id"].text)
      guard var component = owner.definition.component(a["componentID"].text),
        let image = component.visual?.image
      else { throw SevraError("visual_image", "Choose an exact saved image component.") }
      component.visual = try workbook.imageDefinition(
        sourceID: a["sourceID"].text, caption: a["caption"].string ?? image.caption,
        accessibilityDescription: a["accessibilityDescription"].string)
      try cancellation.check()
      return try encoded(
        workbook.editSpace(
          owner.id, expectedVersion: a["expectedVersion"].int!,
          edits: [.init(operation: "replace", componentID: component.id, component: component)],
          token: token))
    case "visual.inspect":
      let owner = try workbook.space(a["id"].text)
      guard let component = owner.definition.component(a["componentID"].text),
        let visual = component.visual
      else {
        throw SevraError("visual", "Choose an exact saved visual component.")
      }
      let records = try visual.work.map {
        try workbook.workVisualData($0, cursor: a["cursor"].string, cancellation: cancellation)
      }
      let chart = try visual.chart.map { try workbook.chartData($0, cancellation: cancellation) }
      let diagram = try visual.diagram.map { definition in
        let data = try workbook.diagramData(definition, cancellation: cancellation)
        return try data.positionPage(
          definition.positions, offset: a["offset"].int ?? 0, cancellation: cancellation)
      }
      return .object([
        "id": .string(owner.id), "version": .number(Double(owner.version)),
        "componentID": .string(component.id), "definition": try encoded(visual),
        "records": try records.map(encoded) ?? .null,
        "chart": try chart.map { try $0.inspection() } ?? .null,
        "diagram": diagram ?? .null,
      ])
    case "visual.live_sources":
      let owner = try workbook.space(a["id"].text)
      guard let visual = owner.definition.component(a["componentID"].text)?.visual else {
        throw SevraError("visual_source", "Choose an exact saved chart.")
      }
      let chart = try visual.sourceChart(panel: a["panel"].int)
      return try workbook.liveChartSources(
        chart, snapshot: a["snapshot"].text,
        queryHash: a["queryHash"].text, point: a["point"].int!, offset: a["offset"].int ?? 0,
        cancellation: cancellation)
    case "visual.change_record":
      let changed = try workbook.changeWorkRecord(
        spaceID: a["id"].text, componentID: a["componentID"].text,
        expectedVersion: a["expectedVersion"].int!, recordID: a["recordID"].text,
        value: a["value"].text, end: a["end"].string, cursor: a["cursor"].string,
        token: token, cancellation: cancellation)
      return .object([
        "status": .string("saved"), "id": .string(changed.items[0].id),
        "changeID": .string(changed.id),
        "operation": .string(token),
      ])
    case "visual.configure", "visual.filter":
      let space = try workbook.space(a["id"].text)
      let id = a["componentID"].text
      guard var component = space.definition.component(id), let visual = component.visual else {
        throw SevraError("visual", "Choose an exact saved workbook visual.")
      }
      let allowed: Set<String>
      let changed: VisualDefinition
      if a["filters"] != .null, let oldQuery = visual.chart?.query ?? visual.work?.query {
        let existing = try DatasetQuery(oldQuery)
        let allowed = Set(
          existing.selections.compactMap(\.column)
            + existing.groups + existing.filters.map(\.column))
        let filters = try a["filters"].array.map { try QueryColumn($0["column"]) }
        try require(
          filters.allSatisfy { allowed.contains($0) }, "visual_filter",
          "Filter the view using its declared fields.")
      }
      let edits = a.object.filter { !["id", "componentID", "expectedVersion"].contains($0.key) }
      if var image = visual.image {
        allowed = ["title", "caption", "accessibilityDescription"]
        if let caption = a["caption"].string { image.caption = caption }
        if let description = a["accessibilityDescription"].string {
          image.accessibilityDescription = description
        }
        changed = VisualDefinition(image: image)
      } else if let chart = visual.chart {
        allowed = ["title", "style", "threshold", "filters", "annotations", "dataBars"]
        let descriptor = revisedQueryDescriptor(try encoded(chart), edits: edits)
        let definition = try VisualChart.parse(descriptor)
        if a["style"] != .null || a["filters"] != .null {
          _ = try workbook.chartData(definition, cancellation: cancellation)
        }
        changed = VisualDefinition(chart: definition)
      } else if let work = visual.work {
        allowed = work.style == .calendar ? ["title", "month", "filters"] : ["title", "filters"]
        let descriptor = revisedQueryDescriptor(try encoded(work), edits: edits)
        let definition = try WorkVisual.parse(descriptor)
        if a["filters"] != .null {
          _ = try workbook.workVisualData(definition, cancellation: cancellation)
        }
        changed = VisualDefinition(work: definition)
      } else if let text = visual.text {
        allowed = ["title", "blocks"]
        var descriptor = try encoded(text).object
        for (key, value) in edits { descriptor[key] = value }
        changed = VisualDefinition(text: try VisualText.parse(.object(descriptor)))
      } else if let overview = visual.overview {
        allowed = ["title", "columns"]
        var descriptor = try encoded(overview).object
        for (key, value) in edits { descriptor[key] = value }
        let definition = try VisualOverview.parse(.object(descriptor))
        _ = try workbook.overviewData(definition, cancellation: cancellation)
        changed = VisualDefinition(overview: definition)
      } else if let diagram = visual.diagram {
        allowed = ["title", "positions"]
        var descriptor = try encoded(diagram).object
        for (key, value) in edits { descriptor[key] = value }
        let definition = try VisualDiagram.parse(.object(descriptor))
        if let positions = definition.positions, !positions.isEmpty {
          let data = try workbook.diagramData(definition, cancellation: cancellation)
          _ = try data.layout(positions: positions, cancellation: cancellation)
        }
        changed = VisualDefinition(diagram: definition)
      } else {
        throw SevraError("visual", "Choose a supported visual.")
      }
      try require(
        !edits.isEmpty && Set(edits.keys).isSubset(of: allowed), "visual",
        "This visual supports changing " + allowed.sorted().joined(separator: ", ") + ".")
      try cancellation.check()
      component.visual = changed
      if let title = a["title"].string { component.title = title }
      return try encoded(
        workbook.editSpace(
          space.id, expectedVersion: a["expectedVersion"].int!,
          edits: [.init(operation: "replace", componentID: id, component: component)], token: token)
      )
    default: throw SevraError("visual", "Discover the available visual operations.")
    }
  }
  private func revisedQueryDescriptor(_ descriptor: Value, edits: [String: Value]) -> Value {
    var fields = descriptor.object
    for (key, value) in edits where key != "filters" { fields[key] = value }
    if let filters = edits["filters"] {
      var query = descriptor["query"].object
      query["filters"] = filters
      fields["query"] = .object(query)
    }
    return .object(fields)
  }

  private func visualDefinition(_ a: Value) throws -> VisualDefinition {
    let selected = ["sourceID", "chart", "work", "diagram", "overview", "text", "aggregate"].filter
    {
      a[$0] != .null
    }
    try require(
      selected.count == 1, "visual",
      "Choose one image, chart, work view, diagram, overview or text.")
    if selected[0] != "sourceID" {
      try require(
        a["caption"] == .null && a["accessibilityDescription"] == .null,
        "visual", "Image captions and descriptions apply only to images.")
    }
    if let raw = a.object["aggregate"] { return try VisualDefinition(chart: aggregateChart(raw)) }
    if let raw = a.object["chart"] { return try VisualDefinition(chart: VisualChart.parse(raw)) }
    if let raw = a.object["work"] { return try VisualDefinition(work: WorkVisual.parse(raw)) }
    if let raw = a.object["diagram"] {
      return try VisualDefinition(diagram: VisualDiagram.parse(raw))
    }
    if let raw = a.object["overview"] {
      return try VisualDefinition(overview: VisualOverview.parse(raw))
    }
    if let raw = a.object["text"] {
      let text = try VisualText.parse(raw)
      try workbook.validateVisualTextSources(text)
      return VisualDefinition(text: text)
    }
    return try workbook.imageDefinition(
      sourceID: a["sourceID"].text, caption: a["caption"].string ?? "",
      accessibilityDescription: a["accessibilityDescription"].string)
  }

  private func aggregateChart(_ raw: Value) throws -> VisualChart {
    _ = try queryObject(
      raw,
      keys: [
        "title", "datasetID", "definitionID", "category", "measure", "reducer", "style", "scope",
      ])
    let reducer = raw["reducer"].text
    let category = raw["category"].text
    let measure = raw["measure"].string
    let style = raw["style"].string.flatMap(VisualChart.Style.init(rawValue:)) ?? .bar
    try require(
      ["sum", "countRows", "count", "average", "min", "max"].contains(reducer)
        && [.bar, .horizontalBar, .line].contains(style)
        && (raw["style"] == .null || raw["style"] == .string(style.rawValue))
        && !category.isEmpty
        && (reducer == "countRows" ? measure == nil : !(measure?.isEmpty ?? true)),
      "visual_chart", "Use a category, compatible reducer, and measure unless counting rows.")
    func ref(_ column: String) -> Value {
      .object(["source": .number(0), "column": .string(column)])
    }
    var output: [String: Value] = ["id": .string("amount"), "aggregate": .string(reducer)]
    if let measure { output["column"] = ref(measure) }
    let scope =
      raw["scope"] == .null
      ? Value.object([
        "meaning": .string("actual"), "status": .string("accepted"), "scenario": .string("actual"),
      ])
      : raw["scope"]
    let query: Value = .object([
      "sources": .array([
        .object([
          "datasetID": raw["datasetID"], "definitionID": raw["definitionID"],
          "scope": scope,
        ])
      ]),
      "select": .array([
        .object(["id": .string("category"), "column": ref(category)]), .object(output),
      ]),
      "groupBy": .array([ref(category)]), "limit": .number(100),
    ])
    let chart = VisualChart(
      title: raw["title"].text, style: style, query: query, x: "category", y: "amount")
    try chart.validate()
    return chart
  }

  private func visualTitle(_ visual: VisualDefinition, arguments: Value) throws -> String {
    if let title = arguments["title"].string ?? visual.title {
      return title
    }
    return try workbook.item(visual.image!.reference.sourceID).title
  }

}

extension Workbook {
  func validateVisualTextSources(_ text: VisualText) throws {
    for id in text.sourceIDs {
      let source = try item(id)
      try require(
        source.id == id && !Item.technicalKinds.contains(source.kind), "visual_source",
        "Choose an exact workbook record or source version.")
    }
  }
}
