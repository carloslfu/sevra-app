import Foundation
import SevraCore

@MainActor extension CatalogSession {
  func declaredView(_ kind: String, _ b: Workbook) throws {
    // Images use an explicitly granted image alias; the product intentionally
    // disallows an ImageReference as a declared app view.
    if kind == "image" {
      events.append(
        "Not applicable: declared image views are unsupported. This story shows the supported native Image alias under the same grant."
      )
      return
    }
    let actual =
      kind == "work"
      ? "visual.work." + (CatalogRegistry.work.contains(variant) ? variant : "board")
      : kind == "chart"
        ? "visual.chart." + (CatalogRegistry.charts.contains(variant) ? variant : "bar")
        : "visual." + kind
    let definition = try makeVisual(actual)
    let datasets = try b.datasets()
    let aliases = Dictionary(
      uniqueKeysWithValues: datasets.enumerated().map { ($0.element.id, "table\($0.offset+1)") })
    func aliasQueries(_ value: Value) -> Value {
      if case .array(let a) = value { return .array(a.map(aliasQueries)) }
      if case .object(let o) = value {
        if let id = o["datasetID"]?.string, let alias = aliases[id] {
          var fields = o
          fields.removeValue(forKey: "datasetID")
          fields.removeValue(forKey: "definitionID")
          fields["table"] = .string(alias)
          return .object(fields.mapValues(aliasQueries))
        }
        var fields = o
        // App-owned rich text cannot cite arbitrary workbook sources.
        fields.removeValue(forKey: "sourceID")
        return .object(fields.mapValues(aliasQueries))
      }
      return value
    }
    let aliased = try decode(aliasQueries(try encoded(definition)), as: VisualDefinition.self)
    let bindings = Dictionary(
      uniqueKeysWithValues: datasets.map {
        (
          aliases[$0.id]!,
          NativeAppDataset(title: $0.title, columns: $0.columns, writable: true, datasetID: $0.id)
        )
      })
    app = try b.installNativeApp(
      .init(
        name: "Declared " + kind,
        source:
          "Sevra.mount(Sevra.h(Sevra.Column,{padding:16},Sevra.h(Sevra.View,{viewID:'exampleView'})));",
        datasets: bindings, views: ["exampleView": aliased]))
  }
}
