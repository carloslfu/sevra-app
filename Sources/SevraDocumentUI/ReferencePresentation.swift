import CryptoKit
import Foundation
import SevraCore

public struct ReferenceOccurrence: Identifiable, Equatable, Sendable {
  public enum Kind: String, Sendable { case body, extracted }
  public let kind: Kind
  public let origin: String
  public let snapshot: String
  public let reference: WorkbookReference
  public let region: Int?
  public let locator: String
  public var id: String { kind.rawValue + ":" + snapshot + ":" + reference.id }
  public var url: URL {
    URL(
      string: "sevra-ref://" + kind.rawValue + "/" + origin + "/" + snapshot + "/" + reference.id)!
  }
  public var selection: ReferenceSelection {
    .init(
      startScalar: reference.startScalar, scalarCount: reference.scalarCount,
      target: reference.targetMode.map {
        .init(
          mode: $0,
          identity: ($0 == .live ? reference.targetLogicalID : reference.targetVersionID)!,
          workbookID: reference.targetWorkbookID)
      }, lookup: reference.lookup, id: reference.id)
  }
}

/// Rendering never resolves names, opens raw URLs or changes the original body.
public struct ReferencePresentation: Sendable {
  public struct Part: Sendable {
    public let text: String
    public let occurrence: ReferenceOccurrence?
  }
  public let parts: [Part]
  public let occurrences: [ReferenceOccurrence]
  public var plainText: String { parts.map(\.text).joined() }

  public static func make(
    text: String, snapshot: ReferenceSnapshot, cancellation: Cancellation = .init()
  ) throws -> Self {
    try cancellation.check()
    guard let snapshotID = snapshot.id else {
      return .init(parts: [.init(text: text, occurrence: nil)], occurrences: [])
    }
    let hash = SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    try require(
      hash == snapshot.bodyHash, "reference_body", "The saved links belong to different text.")
    let scalars = Array(text.unicodeScalars)
    let syntax = try InlineReferenceParser.parse(text, cancellation: cancellation).syntax
    var parts: [Part] = []
    var occurrences: [ReferenceOccurrence] = []
    var end = 0
    for (index, reference) in snapshot.references.enumerated() {
      try cancellation.check()
      let start = reference.startScalar
      let labelEnd = start + reference.scalarCount
      try require(
        start >= end && labelEnd <= scalars.count, "reference_range", "Invalid saved link span.")
      let label = String(String.UnicodeScalarView(scalars[start..<labelEnd]))
      try require(
        label.utf8.elementsEqual(reference.label.utf8), "reference_body", "The saved label changed."
      )
      // Hide delimiters only for a complete recognized token whose label is the
      // saved span and which does not swallow another explicit selection.
      let next =
        index + 1 < snapshot.references.count
        ? snapshot.references[index + 1].startScalar : scalars.count
      let token = syntax.first {
        $0.labelStartScalar == start && $0.labelScalarCount == reference.scalarCount
          && $0.startScalar >= end && $0.startScalar + $0.scalarCount <= next
      }
      let visibleStart = token?.startScalar ?? start
      if visibleStart > end {
        parts.append(
          .init(
            text: String(String.UnicodeScalarView(scalars[end..<visibleStart])), occurrence: nil))
      }
      let occurrence = ReferenceOccurrence(
        kind: .body, origin: snapshot.originVersionID,
        snapshot: snapshotID, reference: reference, region: nil, locator: reference.locator)
      occurrences.append(occurrence)
      parts.append(.init(text: label, occurrence: occurrence))
      end = token.map { $0.startScalar + $0.scalarCount } ?? labelEnd
    }
    if end < scalars.count {
      parts.append(.init(text: String(String.UnicodeScalarView(scalars[end...])), occurrence: nil))
    }
    return .init(parts: parts, occurrences: occurrences)
  }
}
