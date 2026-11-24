import Foundation

/// Bounded, direct text formatting. Links are exact workbook versions.
public struct VisualText: Codable, Equatable, Sendable {
  public struct Block: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable { case paragraph, bullet, callout }
    public struct Run: Codable, Equatable, Sendable {
      public let text: String
      public let strong: Bool?
      public let sourceID: String?
    }
    public let kind: Kind
    public let runs: [Run]
  }
  public let title: String
  public let blocks: [Block]

  public static func parse(_ value: Value) throws -> Self {
    _ = try queryObject(value, keys: ["title", "blocks"])
    for block in value["blocks"].array {
      _ = try queryObject(block, keys: ["kind", "runs"])
      for run in block["runs"].array {
        _ = try queryObject(run, keys: ["text", "strong", "sourceID"])
      }
    }
    let text = try decodeDescriptor(Self.self, from: value, named: "text")
    try text.validate()
    return text
  }

  var sourceIDs: [String] { blocks.flatMap { $0.runs.compactMap(\.sourceID) } }

  func validate(appOwned: Bool = false) throws {
    try require(
      !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && title.utf8.count <= 120 && (1...12).contains(blocks.count)
        && blocks.allSatisfy { block in
          (1...8).contains(block.runs.count)
            && block.runs.allSatisfy {
              !$0.text.isEmpty && $0.text.utf8.count <= 400 && ($0.sourceID?.utf8.count ?? 0) <= 128
            }
        } && sourceIDs.count <= 12 && (!appOwned || sourceIDs.isEmpty)
        && encoded(self).json().utf8.count <= 8_192,
      "visual_text", "Use up to twelve short text blocks. Links must name exact workbook sources.")
  }
}
