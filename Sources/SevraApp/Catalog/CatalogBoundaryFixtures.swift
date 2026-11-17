import Foundation
import SevraCore

@MainActor extension CatalogSession {
  func seedBoundaries(_ b: Workbook, _ ws: WorkspaceState) async throws {
    let id = story.id
    if id == "home.limits" {
      _ = try b.saveSpace(
        id: "home", title: "Sixteen components",
        definition: .init(
          components: (0..<16).map {
            .init(
              id: "part-\($0)", type: "text", title: "Section \($0+1)",
              text: "Bounded native composition")
          }), expectedVersion: 1)
      do {
        _ = try b.editSpace(
          "home", expectedVersion: 2,
          edits: [
            .init(
              operation: "insert", at: "last", component: .init(type: "text", title: "Seventeenth"))
          ])
        throw SevraError("catalog_check", "Over-limit layout was accepted")
      } catch let error as SevraError where error.code != "catalog_check" {
        events.append("17th component refused by production validator: " + error.message)
      }
    }
    if id == "home.customized" {
      _ = try b.editSpace(
        "home", expectedVersion: b.space("home").version,
        edits: [
          .init(
            operation: "insert", at: "last",
            component: .init(
              id: "home-attention", type: "text", title: "Occupied fallback ID",
              text: "The attention fallback chooses a distinct identity."))
        ])
    }
    if id == "home.component.app", let app {
      if variant == "Missing" {
        component = .init(type: "app", title: "Missing app", spaceID: identifier())
      }
      if variant == "Missing view" {
        component = .init(
          type: "app", title: "Unavailable declared view", spaceID: app.id, viewID: "removedView",
          viewVersion: app.version)
      }
      if variant == "Changed version" {
        component = .init(
          type: "app", title: "Saved app view", spaceID: app.id, viewID: "stockView",
          viewVersion: app.version)
        var package = app.definition.app!
        package.name += " revised"
        self.app = try b.installNativeApp(package, spaceID: app.id, expectedVersion: app.version)
      }
    }
    if id == "main.table", let t = table {
      if variant == "Archived" {
        _ = try b.updateDatasetDefinition(
          t.id, expectedVersion: t.version, expectedDefinitionID: t.definitionID, archived: true)
      }
      if variant == "Formula" {
        var columns = t.columns
        columns.append(
          .init(id: "double", title: "Double cost", type: "decimal", formula: "amount*2"))
        _ = try b.updateDatasetDefinition(
          t.id, expectedVersion: t.version, expectedDefinitionID: t.definitionID, columns: columns)
      }
    }
    if id == "main.document", variant == "Historical" {
      let old = source!
      source = try b.addItem(
        category: "source", kind: old.kind, title: old.title,
        text: "Updated observations. Inspect the previous version in history.", supersedes: old.id)
      fileItems["historical"] = old.id
    }
    if id == "main.automations" || id == "main.automation-detail",
      let definition = automationDefinition, ["Armed", "Paused", "Stale"].contains(variant)
    {
      let session = try b.authorizeAutomationExecution(
        definition.id, expectedGeneration: 0, after: Date(timeIntervalSince1970: 1_794_900_000),
        token: identifier(), actor: .human("Catalog.synthetic"))
      let grant = try ws.automation.controller.registry.register(b, session: session)
      if variant == "Paused" {
        try await ws.automation.controller.pause(grant, actor: .human("Catalog.synthetic"))
      }
      if variant == "Stale" {
        var content = definition.content.object
        content["title"] = .string("Revised morning check")
        _ = try b.saveApplicationDefinition(
          logicalID: definition.logicalID, content: .object(content),
          expectedDefinitionID: definition.id)
      }
      await ws.automation.controller.reload()
      events.append("Synthetic device registry only. No scheduler timer is running.")
    }
    if ["visual.image", "home.component.image"].contains(id),
      ["Failure", "Missing", "Corrupt"].contains(variant)
    {
      let asset = try b.assetURL(image!.assetID!)
      if variant == "Missing" {
        try FileManager.default.removeItem(at: asset)
      } else {
        try Data("Synthetic corrupt image".utf8).write(to: asset)
      }
    }
    if id == "visual.text", variant == "Invalid" {
      do {
        _ = try VisualText.parse(
          .object(["title": .string("Empty proposal"), "blocks": .array([])]))
        throw SevraError("catalog_check", "Empty rich text was accepted")
      } catch let error as SevraError where error.code != "catalog_check" {
        validationFailure = error.message
        events.append(
          "Invalid empty text refused; the last valid view is retained: " + error.message)
      }
    }
    if id.hasPrefix("visual."), id != "visual.image", variant == "Failure",
      let t = id.hasPrefix("visual.work.") ? tasks : table
    {
      _ = try b.updateDatasetDefinition(
        t.id, expectedVersion: t.version, expectedDefinitionID: t.definitionID, archived: true)
      events.append(
        "Original query binding archived after layout save; production renderer reports its unavailable source."
      )
    }
  }
}
