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
  try await checkTableUpdateDrafts()
}

/// Only the newest choices are written, in order, and a proposal cannot be
/// followed by an older save that would bring its finished draft back.
@MainActor private func checkTableUpdateDrafts() async throws {
  func settle(_ session: TableUpdateSession) async {
    // A save is debounced and then runs detached; wait out both.
    try? await Task.sleep(nanoseconds: 500_000_000)
  }
  let log = SaveLog()
  let session = TableUpdateSession()
  for value in 1...3 { session.keep { log.add(value) } }
  await settle(session)
  try expect(log.values == [3], "Superseded draft choices were saved")
  session.keep(immediately: true) {
    Thread.sleep(forTimeInterval: 0.1)
    log.add(4)
  }
  // The first write is now running, so the next must wait for it.
  try? await Task.sleep(nanoseconds: 30_000_000)
  session.keep(immediately: true) { log.add(5) }
  await settle(session)
  try expect(log.values == [3, 4, 5], "An older draft save finished after a newer one")
  session.keep(immediately: true) { throw SevraError("synthetic", "Disk is full") }
  await settle(session)
  try expect(
    session.draftFailure?.contains("Disk is full") == true && session.failure == nil,
    "A failed draft save was hidden or interrupted the review")
  session.keep(immediately: true) { log.add(6) }
  await settle(session)
  try expect(session.draftFailure == nil, "A later successful save kept the failure")

  session.keep { log.add(7) }
  let preview = try makeDraftPreview()
  await session.inspectChanges { _ in preview.0 }
  let published = await session.publish { _, _ in
    log.add(8)
    return preview.1
  }
  await settle(session)
  try expect(published != nil && log.values == [3, 4, 5, 6, 8], "A save landed around publication")
  print("PASS update drafts save the newest choices in order, report failure and end at proposal")
  try checkTableUpdateForm()
}

/// The review rules behind the native form, without a window.
private func checkTableUpdateForm() throws {
  func source(_ headings: [String], header: Int = 1, sheets: [String] = [], sheet: String? = nil)
    throws -> TableUpdateSource
  {
    var fields: [String: Value] = [
      "sourceID": .string("original"), "headerRow": .number(Double(header)),
      "headings": .array(headings.map(Value.string)), "incoming": .number(1),
      "examples": .array([]), "sheets": .array(sheets.map(Value.string)), "notes": .array([]),
    ]
    if let sheet { fields["sheet"] = .string(sheet) }
    return try JSONDecoder().decode(
      TableUpdateSource.self, from: Data(Value.object(fields).json().utf8))
  }
  let columns = [
    Column(id: "sku", title: "SKU", unique: true), Column(id: "unit_price", title: "Unit price"),
    Column(id: "total", title: "Total", formula: "unit_price * 2"),
  ]
  let incoming = try source(["sku", "Unit-Price", "Total", "Supplier"])
  var form = TableUpdateForm()
  try expect(form.blocker(nil, columns: nil) == nil, "A review blocked before it had a file")
  let choosing = try source([], sheets: ["Notes", "Quotes"])
  try expect(
    choosing.needsSheet && form.blocker(choosing, columns: columns) == "Choose a worksheet.",
    "A multi-sheet original did not ask for a worksheet first")
  try expect(
    form.blocker(incoming, columns: nil) == "Choose a target table.",
    "A review without a table named the wrong next step")
  form.choose(target: "parts", source: incoming, columns: columns)
  try expect(
    form.mapping == [0: .column("sku"), 1: .column("unit_price")] && form.isSuggested(1),
    "Exact headings were not suggested, or a calculated column was offered")
  try expect(
    form.blocker(incoming, columns: columns) == "Choose an update method.",
    "A missing method was not named")
  form.choose(mode: .merge, source: incoming, columns: columns)
  try expect(form.keys == ["sku"], "A declared unique key was not suggested")
  try expect(
    form.blocker(incoming, columns: columns) == "Map or ignore every incoming column.",
    "Undecided inputs were not named")
  try expect(form.canIgnoreRest(incoming, columns: columns), "Ignoring the rest was not offered")
  form.ignoreRest(incoming)
  try expect(
    form.mapping[2] == .ignore && form.mapping[3] == .ignore
      && form.blocker(incoming, columns: columns) == nil,
    "Ignoring the rest did not finish the mapping")
  form.keys = []
  try expect(
    form.blocker(incoming, columns: columns) == "Choose at least one key column.",
    "A merge without keys could preview")
  form.keys = ["sku"]
  form.header = "4"
  try expect(
    form.blocker(incoming, columns: columns) == "Read the headings for this header row.",
    "Headings from another header row could preview")
  form.header = "1"

  // A person's choices outrank suggestions, and a saved draft restores them exactly.
  var person = TableUpdateForm()
  person.choose(target: "parts", source: nil, columns: nil)
  person.mapping = [0: .ignore, 3: .column("sku")]
  person.mode = .append
  person.meaning = "estimate"
  person.scenario = "forecast"
  person.suggest(incoming, columns: columns)
  try expect(
    person.mapping == [0: .ignore, 1: .column("unit_price"), 3: .column("sku")]
      && !person.isSuggested(0),
    "A suggestion replaced a person's mapping or mapped a column twice")
  let saved = person.draft(sourceID: "original")
  var reopened = TableUpdateForm()
  reopened.restore(saved)
  try expect(
    reopened.mapping == person.mapping && reopened.mode == .append && reopened.target == "parts"
      && reopened.meaning == "estimate" && reopened.scenario == "forecast"
      && reopened.draft(sourceID: "original") == saved,
    "A draft did not restore the same review")
  reopened.suggest(incoming, columns: columns)
  try expect(reopened.mapping == person.mapping, "Reopening changed a saved mapping")
  reopened.mapping[1] = .column("sku")
  try expect(
    reopened.blocker(incoming, columns: columns) == "SKU is mapped twice.",
    "A repeated column was not named")
  reopened.mapping[1] = .ignore
  try expect(
    reopened.blocker(incoming, columns: columns) == "Still to map: Unit price.",
    "A missing column was not named")

  // A table that changed since the draft keeps only the choices it still supports.
  let current = saved.reconciled(
    headings: ["sku", "Unit-Price"], columns: columns.filter { $0.id != "unit_price" })
  try expect(
    current.decisions == [.init(position: 0, target: nil)] && current.datasetID == "parts",
    "A draft kept a removed column or a missing input")
  try expect(
    saved.reconciled(headings: incoming.headings, columns: nil).datasetID == nil,
    "A draft kept a missing table")
  var other = form
  other.choose(target: "other", source: incoming, columns: [Column(id: "supplier", title: "Supplier")])
  try expect(
    other.mapping == [3: .column("supplier")] && other.keys.isEmpty,
    "Changing the table kept the earlier mapping")
  try expect(
    try source(["SKU", "sku"]).suggestion(for: columns).mapping.isEmpty,
    "Two headings for one column were guessed")
  print("PASS update form suggests only undecided inputs, names blockers and restores saved choices")
}

@MainActor private func makeDraftPreview() throws -> (TableUpdatePreview, Item) {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(
    "sevra-update-drafts-" + identifier())
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: root) }
  let book = try Workbook.create(at: root.appendingPathComponent("Draft.sevra"), title: "Draft")
  let file = root.appendingPathComponent("Rows.csv")
  try Data("sku\n0012\n".utf8).write(to: file)
  let source = try book.importFile(file)
  let table = try book.createDataset(
    title: "Parts", columns: [.init(id: "sku", title: "SKU")], rows: [], sourceID: source.id)
  return (
    try book.previewTableUpdate(
      sourceID: source.id, datasetID: table.id, mode: .append,
      mapping: [.init(position: 0, target: "sku")]), source
  )
}

private final class SaveLog: @unchecked Sendable {
  private let lock = NSLock()
  private var saved: [Int] = []
  var values: [Int] { lock.withLock { saved } }
  func add(_ value: Int) { lock.withLock { saved.append(value) } }
}

private actor TokenRegister {
  var values: [String] = []
  func add(_ value: String) { values.append(value) }
}
