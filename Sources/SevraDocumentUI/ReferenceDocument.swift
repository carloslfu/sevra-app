import Foundation
import SevraCore
import SwiftUI

public struct ReferenceDocument: Sendable {
  public let body: ReferenceSnapshot
  public let file: Value
  public let presentation: ReferencePresentation
  public let occurrences: [ReferenceOccurrence]

  public static func read(
    _ item: Item, workbook: Workbook, cancellation: Cancellation = .init()
  ) throws -> Self {
    let body = try workbook.referenceSnapshot(item.id, cancellation: cancellation)
    let file = try workbook.fileReferenceSnapshot(item.id, cancellation: cancellation)
    let presentation = try ReferencePresentation.make(
      text: item.text, snapshot: body, cancellation: cancellation)
    let extracted = try file["references"].array.map { entry -> ReferenceOccurrence in
      let ref = try JSONDecoder().decode(
        WorkbookReference.self, from: Data(entry["reference"].json().utf8))
      return .init(
        kind: .extracted, origin: item.id, snapshot: file["id"].text,
        reference: ref, region: entry["region"].int, locator: entry["locator"].text)
    }
    return .init(
      body: body, file: file, presentation: presentation,
      occurrences: presentation.occurrences + extracted)
  }

  public func resolve(
    _ occurrence: ReferenceOccurrence, workbook: Workbook, cancellation: Cancellation = .init()
  ) throws -> Value {
    try require(
      occurrences.contains(occurrence), "reference_snapshot", "Refresh the document's links first.")
    if occurrence.kind == .body {
      return try workbook.resolveReference(
        occurrence.reference.id, originVersionID: occurrence.origin,
        snapshotID: occurrence.snapshot, cancellation: cancellation)
    }
    return try workbook.resolveFileReference(
      occurrence.reference.id, originVersionID: occurrence.origin,
      snapshotID: occurrence.snapshot, cancellation: cancellation)
  }

  /// Replace a complete saved set while preserving every other occurrence. The
  /// Source annotation or new Record text version enforces its own stale check.
  public func choose(
    _ occurrence: ReferenceOccurrence, target: ReferenceTarget?, item: Item,
    workbook: Workbook, token: String, cancellation: Cancellation = .init()
  ) throws -> Item {
    try require(
      item.id == occurrence.origin && occurrences.contains(occurrence),
      "reference_snapshot", "Refresh the document's links first.")
    func selection(_ entry: ReferenceOccurrence) -> ReferenceSelection {
      guard entry == occurrence else { return entry.selection }
      return .init(
        startScalar: entry.reference.startScalar, scalarCount: entry.reference.scalarCount,
        target: target, lookup: entry.reference.lookup, id: entry.reference.id)
    }
    if occurrence.kind == .extracted {
      _ = try workbook.annotateFileReferences(
        item.id,
        selections: occurrences.filter { $0.kind == .extracted }.map {
          .init(region: $0.region!, selection: selection($0))
        }, expectedSnapshotID: occurrence.snapshot, token: token, cancellation: cancellation)
      return item
    }
    let selections = occurrences.filter { $0.kind == .body }.map(selection)
    if item.category == "source" {
      _ = try workbook.annotateReferences(
        item.id, selections: selections,
        expectedSnapshotID: occurrence.snapshot, token: token, cancellation: cancellation)
      return item
    }
    return try workbook.editDocument(
      item.id, text: item.text, token: token,
      cancellation: cancellation, references: selections)
  }
}

/// A late or cancelled reader cannot change a different exact document preview.
@MainActor public final class ReferenceDocumentSession: ObservableObject {
  @Published public private(set) var document: ReferenceDocument?
  @Published public private(set) var loading = false
  @Published public private(set) var failure: String?
  private var request = UUID()
  private var cancellation: Cancellation?
  private var origin: String?
  public init() {}

  public func cancel() {
    request = UUID()
    cancellation?.cancel()
    cancellation = nil
    loading = false
  }
  public func load(_ item: Item, workbook: Workbook) async {
    await load(item.id) { cancel in
      try await Task.detached(priority: .userInitiated) {
        try ReferenceDocument.read(item, workbook: workbook, cancellation: cancel)
      }.value
    }
  }
  public func load(
    _ origin: String,
    read: @escaping @Sendable (Cancellation) async throws -> ReferenceDocument
  ) async {
    guard !Task.isCancelled else { return }
    cancel()
    if self.origin != origin { document = nil }
    self.origin = origin
    failure = nil
    let identity = UUID()
    let control = Cancellation(deadlineAfterSeconds: 3)
    request = identity
    cancellation = control
    loading = true
    defer {
      if request == identity {
        loading = false
        cancellation = nil
      }
    }
    do {
      let result = try await withTaskCancellationHandler {
        let result = try await read(control)
        try Task.checkCancellation()
        try control.check()
        return result
      } onCancel: {
        control.cancel()
      }
      guard request == identity else { return }
      try require(
        result.body.originVersionID == origin, "reference_snapshot",
        "The saved links belong to a different document. Refresh the document's links first.")
      document = result
    } catch {
      guard request == identity, !Task.isCancelled, !control.isCancelled else { return }
      failure = error.localizedDescription
    }
  }
}
