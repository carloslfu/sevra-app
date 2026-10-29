import CryptoKit
import Foundation
import SevraCore

public struct CopiedDocumentPassage: Identifiable, Equatable, Sendable {
  public let id: Int
  public let sourceVersionID: String
  public let locator: String
  public let text: String
}

/// A bounded presentation of saved copy spans. Full receipt integrity remains
/// Workbook.verify's responsibility; this never retargets an original version.
public struct DocumentProvenance: Equatable, Sendable {
  public let passages: [CopiedDocumentPassage]
  public let unavailable: Bool

  public static func make(_ item: Item) -> Self {
    guard item.category == "record", item.kind == "document",
      item.data["documentComposition"] != .null
    else { return .init(passages: [], unavailable: false) }
    let metadata = item.data["documentComposition"]
    guard metadata["version"].int == 1,
      case .array(let snapshots) = metadata["copies"], snapshots.count <= 64,
      item.text.utf8.count <= 64000
    else { return .init(passages: [], unavailable: true) }
    let scalars = Array(item.text.unicodeScalars)
    var passages: [CopiedDocumentPassage] = []
    var previousEnd = 0
    for (index, snapshot) in snapshots.enumerated() {
      guard let source = snapshot["sourceVersionID"].string, !source.isEmpty,
        source.utf8.count <= 256, let text = snapshot["text"].string,
        text.utf8.count <= 16000, let locator = snapshot["locator"].string,
        let start = snapshot["outputStartScalar"].int,
        let count = snapshot["reference"]["scalarCount"].int,
        start >= previousEnd, start <= scalars.count, count > 0,
        count <= scalars.count - start, count == text.unicodeScalars.count
      else { return .init(passages: [], unavailable: true) }
      let actual = String(String.UnicodeScalarView(scalars[start..<(start + count)]))
      let hash = SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
      guard Data(actual.utf8) == Data(text.utf8),
        hash == snapshot["reference"]["sha256"].text
      else { return .init(passages: [], unavailable: true) }
      passages.append(.init(id: index, sourceVersionID: source, locator: locator, text: text))
      previousEnd = start + count
    }
    return .init(passages: passages, unavailable: false)
  }
}
