import Foundation

public struct VisualAppReference: Codable, Equatable, Sendable {
  public let spaceID: String
  public let version: Int
  public let digest: String
  public let viewID: String
  public let presetID: String?
}

public struct VisualPreset: Codable, Equatable, Sendable {
  public let owner: VisualAppReference
  public let title: String?
  public let filters: [Value]?
  public let style: VisualChart.Style?
  public let archived: Bool?
  public let positions: [String: DiagramGeometry.Position]?

  func applied(to visual: VisualDefinition) throws -> VisualDefinition {
    if let diagram = visual.diagram, filters == nil, style == nil {
      var descriptor = try encoded(diagram).object
      if let title { descriptor["title"] = .string(title) }
      if let positions { descriptor["positions"] = try encoded(positions) }
      return try VisualDefinition(diagram: VisualDiagram.parse(.object(descriptor)))
    }
    guard let chart = visual.chart, positions == nil else {
      throw SevraError("visual_preset", "Choose presentation controls for this view's family.")
    }
    var result = try encoded(chart).object
    if let title { result["title"] = .string(title) }
    if let style { result["style"] = .string(style.rawValue) }
    if let filters {
      let current = chart.query["filters"].array
      // Updates can only change values of explicitly declared filter slots.
      try require(
        filters.count == current.count
          && zip(filters, current).allSatisfy {
            $0["column"] == $1["column"] && $0["op"] == $1["op"]
          }, "visual_preset",
        "Change only the declared filter values. Use the same field and comparison.")
      var query = chart.query.object
      query["filters"] = .array(filters)
      result["query"] = .object(query)
    }
    let updated = try JSONDecoder().decode(
      VisualChart.self, from: Data(Value.object(result).json().utf8))
    return VisualDefinition(chart: updated)
  }
}

extension Workbook {
  public func nativeAppPresentation(
    _ access: NativeAppAccess, view: String, presetID: String? = nil, filters: [Value]? = nil
  ) throws -> VisualDefinition {
    try synchronized {
      try access.authorized(self) {
        guard let base = access.package.views?[view] else {
          throw SevraError("visual", "Choose a declared app view.")
        }
        var result = base
        if let presetID {
          let saved = try item(presetID)
          try require(
            presetID == saved.logicalID, "visual_preset", "Use the saved presentation ID.")
          let preset = try readVisualPreset(
            saved, spaceID: access.spaceID,
            version: access.version, digest: access.package.digest, view: view)
          try require(
            preset.archived != true, "visual_preset_archived",
            "This preset is archived. Restore an earlier version or remove this placement.")
          result = try preset.applied(to: base)
        }
        if let filters {
          result = try VisualPreset(
            owner: appVisualReference(access, view: view),
            title: nil, filters: filters, style: nil, archived: nil, positions: nil
          ).applied(to: result)
        }
        try result.validate(appAliases: Set(access.package.datasets.keys))
        return result
      }
    }
  }

  func readVisualPreset(_ item: Item, spaceID: String, version: Int, digest: String, view: String)
    throws -> VisualPreset
  {
    try require(
      item.kind == "visual_presentation", "visual_preset", "Choose a saved visual preset.")
    let preset = try JSONDecoder().decode(VisualPreset.self, from: Data(item.data.json().utf8))
    try require(
      preset.owner.spaceID == spaceID && preset.owner.version == version
        && preset.owner.digest == digest && preset.owner.viewID == view,
      "visual_preset", "This preset belongs to a different app view or version.")
    return preset
  }

  public func nativeAppPresetHistory(_ access: NativeAppAccess, view: String, presetID: String)
    throws -> Value
  {
    try synchronized {
      try access.authorized(self) {
        let current = try item(presetID)
        try require(
          current.logicalID == presetID, "visual_preset", "Use the saved presentation ID.")
        let records = try db.execute(
          "SELECT * FROM items WHERE logical_id=? ORDER BY version DESC LIMIT 8",
          [.string(presetID)]
        ).map { row -> Value in
          let revision = try decodeItem(row)
          let preset = try readVisualPreset(
            revision, spaceID: access.spaceID, version: access.version,
            digest: access.package.digest, view: view)
          return .object([
            "versionID": .string(revision.id), "version": .number(Double(revision.version)),
            "title": .string(revision.title), "archived": .bool(preset.archived == true),
          ])
        }
        return .object([
          "presentationID": .string(presetID), "currentVersionID": .string(current.id),
          "recentVersions": .array(records),
        ])
      }
    }
  }

  public func saveNativeAppPreset(
    _ access: NativeAppAccess, view: String, title: String?, style: VisualChart.Style?,
    filters: [Value]?, expectedPresetVersion: String? = nil, restoring: String? = nil,
    archiving: Bool = false, positions: [String: DiagramGeometry.Position]? = nil,
    token: String = identifier(),
    cancellation: Cancellation = .init()
  ) throws -> Item {
    try synchronized(cancellation: cancellation) {
      try access.authorized(self) {
        guard let base = access.package.views?[view] else {
          throw SevraError("visual_preset", "Choose a declared app view.")
        }
        let prior = try expectedPresetVersion.map { try item($0) }
        let saved = try prior.map {
          try readVisualPreset(
            $0, spaceID: access.spaceID,
            version: access.version, digest: access.package.digest, view: view)
        }
        let restored = try restoring.map { id -> VisualPreset in
          let earlier = try item(id)
          try require(
            earlier.id == id && prior?.logicalID == earlier.logicalID
              && (prior?.version ?? 0) > earlier.version, "visual_preset",
            "Choose an earlier version of this exact preset.")
          return try readVisualPreset(
            earlier, spaceID: access.spaceID, version: access.version,
            digest: access.package.digest, view: view)
        }
        try require(
          !archiving || (saved?.archived != true && saved != nil && restoring == nil),
          "visual_preset", "Choose an exact active preset version to archive.")
        try require(
          restoring != nil || saved?.archived != true,
          "visual_preset_archived", "Restore an earlier version before editing this preset.")
        try require(
          restored?.archived != true, "visual_preset_archived",
          "Choose an earlier version from before the preset was archived.")
        let next =
          restored
          ?? VisualPreset(
            owner: appVisualReference(access, view: view),
            title: title ?? saved?.title, filters: filters ?? saved?.filters,
            style: style ?? saved?.style, archived: archiving ? true : nil,
            positions: positions ?? saved?.positions)
        if !archiving {
          let candidate = try next.applied(to: base)
          try candidate.validate(appAliases: Set(access.package.datasets.keys))
          if let chart = candidate.chart {
            _ = try VisualChartData(
              nativeAppQuerySet(
                access, requests: [chart.query],
                cancellation: cancellation)[0], chart: chart)
          }
          if let diagram = candidate.diagram, let positions = diagram.positions, !positions.isEmpty
          {
            let rows = try nativeAppQuerySet(
              access, requests: [diagram.nodes, diagram.edges], cancellation: cancellation)
            _ = try VisualDiagramData(rows, diagram: diagram).layout(
              positions: positions, cancellation: cancellation)
          }
        }
        let data = try encoded(next)
        let request: Value = .object([
          "preset": data,
          "expected": expectedPresetVersion.map(Value.string) ?? .null,
          "restore": restoring.map(Value.string) ?? .null,
        ])
        return try mutation(
          "visual_presentation", token: token, request: request,
          cancellation: cancellation, commitGuard: { try access.authorized(self) {} },
          reading: { try item($0.text) }
        ) {
          if let prior {
            try require(
              prior.id == expectedPresetVersion, "stale_revision",
              "Open the latest saved preset before editing it.")
          }
          return .string(
            try insertItem(
              category: "source", kind: "visual_presentation",
              title: next.title ?? base.chart?.title ?? view,
              text: archiving ? "Archived visual presentation." : "Saved visual presentation.",
              data: data, meaning: "actual",
              status: "accepted", scenario: "actual", inputs: [],
              transformation: "visual-presentation-v1",
              supersedes: prior?.id))
        }
      }
    }
  }

  func appVisualReference(_ access: NativeAppAccess, view: String, presetID: String? = nil)
    -> VisualAppReference
  {
    VisualAppReference(
      spaceID: access.spaceID, version: access.version, digest: access.package.digest,
      viewID: view, presetID: presetID)
  }

  public func pinNativeAppView(
    _ access: NativeAppAccess, view: String, presetID: String? = nil, expectedHomeVersion: Int,
    token: String = identifier()
  ) throws -> Space {
    try synchronized {
      try access.authorized(self) {
        let visual = try nativeAppPresentation(access, view: view, presetID: presetID)
        let title = visual.title ?? view
        let component = Component(
          id: "visual-" + token, type: "app", title: title,
          spaceID: access.spaceID, viewID: view, viewVersion: access.version,
          presentationID: presetID)
        return try editSpace(
          "home", expectedVersion: expectedHomeVersion,
          edits: [.init(operation: "insert", at: "last", component: component)], token: token,
          commitGuard: { try access.authorized(self) {} })
      }
    }
  }
}
