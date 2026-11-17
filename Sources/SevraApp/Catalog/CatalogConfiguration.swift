import Foundation
import SevraCore

struct CatalogConfiguration: Codable {
  var story = "composition.supplier"
  var variant = "Default"
  var label = ""
  var rows = 6
  var width = 900.0
  var height = 640.0
  var dark = false
  var readingScale = 1.0
  var spacing = 16
  var columns = 2
  var vertical = false
  func validate() throws {
    guard let entry = CatalogRegistry.stories.first(where: { $0.id == story }) else {
      throw SevraError("catalog_config", "Unknown story: " + story)
    }
    try require(
      entry.variants.contains(variant), "catalog_config", "This state is not declared for " + story)
    try require(
      label.utf8.count <= 240 && (0...100).contains(rows) && width.isFinite
        && (360...1600).contains(width) && height.isFinite && (320...1200).contains(height)
        && [1, 1.25, 1.5, 1.75, 2].contains(readingScale)
        && (0...48).contains(spacing) && (1...4).contains(columns), "catalog_config",
      "Use bounded labels, 0–100 rows, a 360–1600 × 320–1200 canvas, a declared reading size, 0–48 spacing and 1–4 grid columns."
    )
  }
  func json() throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return String(decoding: try encoder.encode(self), as: UTF8.self)
  }
}
