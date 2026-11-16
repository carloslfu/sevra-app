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
  public enum Kind: String, Codable, Sendable { case image, chart, work }
  public let version: Int
  public let kind: Kind
  public var image: ImagePresentation?
  public var chart: VisualChart?
  public var work: WorkVisual?

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

  func validate(appAliases: Set<String>? = nil) throws {
    try require(version == 1, "visual", "This visual uses an unsupported version.")
    if kind == .chart {
      guard let chart, image == nil, work == nil else {
        throw SevraError("visual", "Choose a chart definition.")
      }
      try chart.validate(appAliases: appAliases)
      return
    }
    if kind == .work {
      guard let work, image == nil, chart == nil else {
        throw SevraError("visual", "Choose a work view definition.")
      }
      try work.validate(appAliases: appAliases)
      return
    }
    guard let image, chart == nil, work == nil, appAliases == nil,
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
    guard item.id == sourceID, let assetID = item.assetID else {
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
    guard !messages.isEmpty else { return [:] }
    let ids = messages.map(\.id)
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
      ORDER BY (m.id=?) DESC, m.rowid DESC LIMIT 2
      """, [.string(conversation)] + ids.map(Value.string) + [anchor.map(Value.string) ?? .null])
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
      return .object([
        "version": .number(1),
        "chart": .string(
          "For visual.evaluate or visual.pin, pass chart {title,style:bar|horizontalBar|stackedBar|line|area|scatter|donut,x,y,series?,threshold?,query}. Supply either chart or sourceID, never both. x, y and optional series are output IDs. Series are supported on bars and lines; stackedBar requires series. query {sources:[{datasetID,definitionID,scope:{meaning,status,scenario}}],select:[{id,column:{source:0,column},aggregate?}],groupBy?:[{source,column}],sort?:[{field,descending}],filters?:[{column:{source,column},op,value}],limit:100}. Omit groupBy/aggregate for exact rows. Use sum/average/min/max/count/countRows, with no column for countRows. No partial results. For app views use [{table:alias,scope}] as sources."
        ),
        "work": .string(
          "Pass work {title,style:board|timeline|agenda|calendar,query,label,field,end?,lanes?,month?} to visual.evaluate or visual.pin. query selects exact rows from one dataset with limit <=100. label is a selected title field. field selects text status for a board, date start for time views. Board lanes are declared status values; calendar month is YYYY-MM-01. Optional end is another selected date field."
        ),
        "image": .string(
          "Pass sourceID (exact included image source), optional caption and accessibilityDescription to visual.evaluate. For a durable image use visual.pin; configure captions with visual.configure. Replace its source with edit_space replace."
        ),
      ])
    case "visual.evaluate":
      let visual = try visualDefinition(a)
      let data = try visual.chart.map { try workbook.chartData($0, cancellation: cancellation) }
      let records = try visual.work.map {
        try workbook.workVisualData($0, cancellation: cancellation)
      }
      let capture = try encoded(
        VisualResult(definition: visual, chartData: data, workData: records))
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
            ?? records.map { .number(Double($0.records.count)) } ?? .null,
          "unknown": data.map { .number(Double($0.unknown)) } ?? .null,
          "scope": data?.scope ?? records?.scope ?? .null,
        ]),
        "notice": .string(
          "Attach this receipt ID with finish.visuals. Exact values are saved in the receipt. Image decoding is checked at display."
        ),
      ])
    case "visual.pin":
      let visual = try visualDefinition(a)
      return try encoded(
        workbook.addVisualToHome(
          visual, title: a["title"].string, expectedVersion: a["expectedVersion"].int!, token: token
        ))
    case "visual.promote":
      return try encoded(
        workbook.promoteConversationVisual(
          a["messageID"].text, index: a["index"].int!, conversation: conversation,
          expectedVersion: a["expectedVersion"].int!, token: token))
    case "visual.inspect":
      let owner = try workbook.space(a["id"].text)
      guard let component = owner.definition.component(a["componentID"].text),
        let visual = component.visual
      else {
        throw SevraError("visual", "Choose an exact saved visual component.")
      }
      let records = try visual.work.map {
        try workbook.workVisualData($0, cancellation: cancellation)
      }
      return .object([
        "id": .string(owner.id), "version": .number(Double(owner.version)),
        "componentID": .string(component.id), "definition": try encoded(visual),
        "records": try records.map(encoded) ?? .null,
      ])
    case "visual.change_record":
      let changed = try workbook.changeWorkRecord(
        spaceID: a["id"].text, componentID: a["componentID"].text,
        expectedVersion: a["expectedVersion"].int!, recordID: a["recordID"].text,
        value: a["value"].text, end: a["end"].string, token: token, cancellation: cancellation)
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
      let edits = a.object.filter { !["id", "componentID", "expectedVersion"].contains($0.key) }
      if var image = visual.image {
        allowed = ["title", "caption", "accessibilityDescription"]
        if let caption = a["caption"].string { image.caption = caption }
        if let description = a["accessibilityDescription"].string {
          image.accessibilityDescription = description
        }
        changed = VisualDefinition(image: image)
      } else if let chart = visual.chart {
        allowed = ["title", "style", "threshold", "filters"]
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
    if let raw = a.object["chart"] {
      try require(
        a["sourceID"] == .null && a["work"] == .null && a["caption"] == .null
          && a["accessibilityDescription"] == .null,
        "visual", "Choose either an image or a chart.")
      return try VisualDefinition(chart: VisualChart.parse(raw))
    }
    if let raw = a.object["work"] {
      try require(
        a["sourceID"] == .null && a["caption"] == .null && a["accessibilityDescription"] == .null,
        "visual", "Choose only one image, chart or work view.")
      return try VisualDefinition(work: WorkVisual.parse(raw))
    }
    return try workbook.imageDefinition(
      sourceID: a["sourceID"].text, caption: a["caption"].string ?? "",
      accessibilityDescription: a["accessibilityDescription"].string)
  }

  private func visualTitle(_ visual: VisualDefinition, arguments: Value) throws -> String {
    if let title = arguments["title"].string ?? visual.chart?.title ?? visual.work?.title {
      return title
    }
    return try workbook.item(visual.image!.reference.sourceID).title
  }

}
