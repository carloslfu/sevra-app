import Foundation
import SevraCore
import SevraTableUI

private actor UpdateGate<Result: Sendable> {
  private var continuation: CheckedContinuation<Result, Error>?
  private var waiting: [CheckedContinuation<Void, Never>] = []
  private var started = false
  func read() async throws -> Result {
    try await withCheckedThrowingContinuation {
      continuation = $0
      started = true
      for waiter in waiting { waiter.resume() }
      waiting = []
    }
  }
  func wait() async {
    if started { return }
    await withCheckedContinuation { waiting.append($0) }
  }
  func finish(_ value: Result) {
    continuation?.resume(returning: value)
    continuation = nil
  }
  func fail() {
    continuation?.resume(throwing: SevraError("old", "Old update failed"))
    continuation = nil
  }
}

@MainActor func checkTableUpdateSession() async throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(
    "sevra-update-ui-" + identifier())
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: root) }
  let book = try Workbook.create(at: root.appendingPathComponent("Review.sevra"), title: "Review")
  let file = root.appendingPathComponent("Rows.csv")
  try Data("sku,qty\n0012,7\n".utf8).write(to: file)
  let source = try book.importFile(file)
  let table = try book.createDataset(
    title: "Parts", columns: [.init(id: "sku", title: "SKU"), .init(id: "qty", title: "Quantity")],
    rows: [], sourceID: source.id)
  let inspection = try book.inspectTableUpdateSource(source.id)
  let preview = try book.previewTableUpdate(
    sourceID: source.id, datasetID: table.id, mode: .append,
    mapping: [.init(position: 0, target: "sku"), .init(position: 1, target: "qty")])
  let session = TableUpdateSession()
  let oldGate = UpdateGate<TableUpdateSource>()
  let old = Task { await session.inspect { _ in try await oldGate.read() } }
  await oldGate.wait()
  await session.inspect { _ in inspection }
  await oldGate.fail()
  await old.value
  try expect(
    session.source?.sourceID == source.id && session.failure == nil && !session.busy,
    "An obsolete source inspection failure replaced the current result")
  let previewGate = UpdateGate<TableUpdatePreview>()
  let pendingPreview = Task { await session.inspectChanges { _ in try await previewGate.read() } }
  await previewGate.wait()
  session.invalidate()
  await previewGate.finish(preview)
  await pendingPreview.value
  try expect(session.preview == nil && !session.busy, "A changed mapping restored a late preview")
  await session.inspectChanges { _ in preview }
  let cancelledGate = UpdateGate<Item>()
  let pending = Task { await session.publish { _, _ in try await cancelledGate.read() } }
  await cancelledGate.wait()
  session.stop()
  let unrelated = try book.addItem(
    category: "source", kind: "observation", title: "Synthetic callback")
  await cancelledGate.finish(unrelated)
  let lateResult = await pending.value
  try expect(lateResult == nil, "A closed review published a late navigation result")
  try expect(session.preview != nil && !session.busy, "Stop discarded a completed preview")
  print(
    "PASS table update inspection, changed-mapping previews and closed-review callbacks are fenced")

  // A lost reply after a committed draft must retry the same publication token.
  let fresh = try book.previewTableUpdate(
    sourceID: source.id, datasetID: table.id, mode: .append,
    mapping: preview.mapping)
  await session.inspectChanges { _ in fresh }
  let tokens = TokenRegister()
  @Sendable func write(_ token: String, _ cancel: Cancellation) async throws -> Item {
    try book.proposeTableUpdate(
      sourceID: fresh.sourceID, datasetID: fresh.datasetID, mode: fresh.mode,
      mapping: fresh.mapping, newRowMeaning: "estimate", newRowScenario: "forecast",
      expectedRevision: fresh.revision, expectedFingerprint: fresh.fingerprint,
      token: token, cancellation: cancel)
  }
  let lost = await session.publish { token, cancel in
    await tokens.add(token)
    _ = try await write(token, cancel)
    throw SevraError("synthetic_reply_loss", "Draft committed; reply lost")
  }
  try expect(
    lost == nil && session.failure?.contains("reply lost") == true,
    "Publication failure was hidden")
  let retry = await session.publish { token, cancel in
    await tokens.add(token)
    return try await write(token, cancel)
  }
  let seen = await tokens.values
  try expect(
    retry?.status == "draft" && seen.count == 2 && Set(seen).count == 1,
    "An exact publication retry changed tokens or duplicated its draft")
  try expect(
    try book.dataset(table.id).rowCount == 0 && book.verify()["ok"] == .bool(true),
    "Creating an update draft changed working data")
  print("PASS lost publication reply retries its exact receipt and leaves working rows untouched")
}

private actor TokenRegister {
  var values: [String] = []
  func add(_ value: String) { values.append(value) }
}
