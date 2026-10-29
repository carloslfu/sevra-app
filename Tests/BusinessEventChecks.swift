import Foundation

@testable import SevraCore

func businessFixture(_ root: URL, _ name: String) throws -> (Workbook, Item) {
  let book = try Workbook.create(at: root.appendingPathComponent(name + ".sevra"), title: name)
  return (book, try book.addItem(category: "source", kind: "observation", title: "Exact input"))
}

func businessEntries(_ book: Workbook) throws -> [Value] {
  try book.businessBatches(limit: 50)["batches"].array.flatMap {
    try book.businessBatch($0["id"].text, limit: 100)["events"].array
  }
}

func insertBusinessFixtureRecord(
  _ book: Workbook, source: String, status: String = "accepted", supersedes: String? = nil
) throws -> String {
  try book.insertItem(
    category: "record", kind: "forecast", title: "Forecast", text: "", data: .object([:]),
    meaning: "estimate", status: status, scenario: "forecast", inputs: [source],
    transformation: "synthetic.business-event-check", supersedes: supersedes)
}

func checkBusinessEvents(at root: URL) {
  check("global business pages and tail preserve integer order beyond nine batches") {
    let (book, source) = try businessFixture(root, "BusinessIntegerOrder")
    for n in 1...23 {
      _ = try book.addItem(
        category: "record", kind: "metric", title: "Metric \(n)", status: "accepted",
        inputs: [source.id])
    }
    var cursor: String?
    var positions: [String] = []
    for _ in 0..<6 {
      let page = try book.businessBatches(after: cursor, limit: 4)
      positions += page["batches"].array.map { $0["position"].text }
      try expect(page["tail"]["position"].text == "23")
      cursor = page["nextCursor"].string
      if page["hasMore"] == .bool(false) { break }
    }
    try expect(positions == (1...23).map(String.init))
    try expect(try book.businessBatches(after: cursor)["batches"].array.isEmpty)
  }
  check("business feed excludes Sources, drafts, rejected proposals and operational kinds") {
    let (book, source) = try businessFixture(root, "BusinessFiltering")
    for status in ["draft", "rejected"] {
      _ = try book.addItem(
        category: "record", kind: "forecast", title: status, status: status, inputs: [source.id])
    }
    for kind in Item.technicalKinds {
      _ = try book.addItem(
        category: "record", kind: kind, title: kind, status: "accepted", inputs: [source.id])
    }
    _ = try book.addMessage("Operational conversation", role: "user")
    try expect(try book.businessBatches()["batches"].array.isEmpty)
    try expect(try book.verify()["ok"] == .bool(true))
  }
  check("accepted forecast keeps meaning, exact predecessor and committed attribution") {
    let (book, source) = try businessFixture(root, "BusinessMeaning")
    let draft = try book.addItem(
      category: "record", kind: "forecast", title: "Forecast", meaning: "estimate",
      scenario: "forecast", inputs: [source.id])
    let accepted = try book.accept(draft.id, actor: .human("business.fixture"))
    let batch = try book.businessBatches()["batches"].array[0]
    let event = try book.businessBatch(batch["id"].text)["events"].array[0]
    try expect(event["beforeID"] == .null && event["afterID"].text == accepted.id)
    try expect(event["payload"]["after"]["meaning"].text == "estimate")
    try expect(event["payload"]["after"]["scenario"].text == "forecast")
    try expect(batch["actor"]["kind"].text == "human")
    let saved = try book.db.execute("SELECT * FROM committed_changes WHERE id=?", [batch["id"]])[0]
    try expect(batch["recorded"] == saved["recorded"])
    try expect(batch["actor"] == Value.parse(saved["actor"]!.text))
    _ = try book.addItem(
      category: "record", kind: "forecast", title: "Unsettled change", meaning: "estimate",
      scenario: "forecast", inputs: [source.id], supersedes: accepted.id)
    try expect(try businessEntries(book).count == 1)
  }
  check("settled correction and withdrawal retain last settled version through drafts") {
    let (book, source) = try businessFixture(root, "BusinessCorrection")
    let first = try book.addItem(
      category: "record", kind: "forecast", title: "First", status: "accepted", inputs: [source.id])
    let draft = try book.addItem(
      category: "record", kind: "forecast", title: "Edit", inputs: [source.id], supersedes: first.id
    )
    let corrected = try book.accept(draft.id)
    let withdrawn = try book.undoItem(corrected.id)
    let entries = try businessEntries(book)
    try expect(entries.count == 3)
    try expect(
      entries[1]["beforeID"].text == first.id && entries[1]["afterID"].text == corrected.id)
    try expect(
      entries[2]["beforeID"].text == corrected.id && entries[2]["afterID"].text == withdrawn.id)
    try expect(entries[2]["payload"]["after"]["status"].text == "rejected")
    try expect(try book.verify()["ok"] == .bool(true))
  }
  check("atomic business commit coalesces logical edits and preserves independent occurrences") {
    let (book, source) = try businessFixture(root, "BusinessAtomic")
    var final = ""
    _ = try book.mutation("synthetic.atomic", token: "atomic-business", actor: .human("fixture")) {
      let first = try insertBusinessFixtureRecord(book, source: source.id)
      final = try insertBusinessFixtureRecord(book, source: source.id, supersedes: first)
      _ = try insertBusinessFixtureRecord(book, source: source.id)
      let transient = try insertBusinessFixtureRecord(book, source: source.id)
      _ = try insertBusinessFixtureRecord(
        book, source: source.id, status: "rejected", supersedes: transient)
      return .string(final)
    }
    let batches = try book.businessBatches()["batches"].array
    try expect(batches.count == 1 && batches[0]["id"].text == "atomic-business")
    let entries = try book.businessBatch("atomic-business")["events"].array
    try expect(entries.count == 2 && entries.contains { $0["afterID"].text == final })
    try expect(entries.allSatisfy { $0["beforeID"] == .null })
    try expect(try book.verify()["ok"] == .bool(true))
  }
  check("inventory scope retains exact item IDs and future basis without inventing effects") {
    let (book, source) = try businessFixture(root, "BusinessInventory")
    try book.setOpeningBalance(
      subject: "parts", quantity: "20", effective: "2030-01-01", sourceID: source.id)
    let movement = try book.movement(
      subject: "parts", quantity: "-2", occurrence: "sale", effective: "2030-01-02",
      input: source.id,
      status: "accepted")
    let batches = try book.businessBatches(scopeKind: "inventory", scopeKey: "parts")["batches"]
      .array
    try expect(batches.count == 2)
    let basis = try book.businessBatch(batches[0]["id"].text)["events"].array[0]
    try expect(basis["payload"]["after"]["quantity"].text == "20")
    try expect(basis["payload"]["after"]["effective"].text.hasPrefix("2030-01-01"))
    let event = try book.businessBatch(batches[1]["id"].text)["events"].array[0]
    try expect(event["afterID"].text == movement.id && event["scopeKey"].text == "parts")
    try expect(
      try book.db.scalar("SELECT count(*) FROM effects WHERE item_id=?", [.string(movement.id)]).int
        == 1)
    let impostor = try book.addItem(
      category: "record", kind: "movement", title: "Just a claim",
      data: .object(["subject": .string("parts")]),
      status: "accepted", inputs: [source.id])
    try expect(
      try book.db.scalar("SELECT count(*) FROM effects WHERE item_id=?", [.string(impostor.id)]).int
        == 0)
    try expect(try book.balance(subject: "parts")["quantity"].text == "18")
    try expect(try book.verify()["ok"] == .bool(true))
  }
  check("dataset schema and membership feed uses captured maps after later removal") {
    let (book, source) = try businessFixture(root, "BusinessDataset")
    let dataset = try book.createDataset(
      title: "Rows", columns: [.init(id: "name", title: "Name")],
      rows: [["name": .string("A")], ["name": .string("B")]], sourceID: source.id)
    let initial = try book.businessBatches(scopeKind: "dataset", scopeKey: dataset.id)["batches"]
      .array[0]
    let entries = try book.businessBatch(initial["id"].text)["events"].array
    let membership = entries.filter { $0["family"].text == "dataset-membership" }
    try expect(
      membership.count == 2 && entries.filter { $0["family"].text == "dataset-schema" }.count == 1)
    try expect(membership.allSatisfy { $0["payload"]["after"]["ordinal"].string != nil })
    let definition = try book.datasetDefinition(dataset.id)
    _ = try book.updateDatasetDefinition(
      dataset.id, expectedVersion: definition.version, expectedDefinitionID: definition.id,
      columns: [.init(id: "name", title: "Renamed")])
    _ = try book.mutation("synthetic.remove-membership") {
      try book.clearDatasetMembers(dataset.id)
      return .null
    }
    try expect(try book.businessBatch(initial["id"].text)["events"].array == entries)
    try expect(try book.verify()["ok"] == .bool(true))
    let schemaEvents = try businessEntries(book).filter { $0["family"].text == "dataset-schema" }
    try expect(schemaEvents.count == 2)
    try expect(schemaEvents[1]["payload"]["before"]["versionID"].text == definition.id)
  }
  check("temporary membership replacement with same map emits no business event") {
    let (book, source) = try businessFixture(root, "BusinessMembershipNoop")
    let table = try book.createDataset(
      title: "Rows", columns: [.init(id: "x", title: "X")], rows: [["x": .string("a")]],
      sourceID: source.id)
    let before = try book.businessBatches()
    _ = try book.mutation("synthetic.membership.noop") {
      let rows = try book.db.execute(
        "SELECT * FROM dataset_rows WHERE dataset_id=?", [.string(table.id)])
      try book.db.execute("DELETE FROM dataset_rows WHERE dataset_id=?", [.string(table.id)])
      for row in rows {
        try book.db.execute(
          "INSERT INTO dataset_rows VALUES(?,?,?,?)",
          [
            row["dataset_id"]!, row["row_id"]!, row["ordinal"]!, row["logical_id"]!,
          ])
      }
      return .null
    }
    try expect(try book.businessBatches() == before)
    try expect(try book.verify()["ok"] == .bool(true))
  }
  check("business pages preserve atomic completion and reject foreign or malformed cursors") {
    let (book, source) = try businessFixture(root, "BusinessPaging")
    _ = try book.mutation("synthetic.three", token: "three") {
      for _ in 0..<3 { _ = try insertBusinessFixtureRecord(book, source: source.id) }
      return .null
    }
    _ = try book.addItem(
      category: "record", kind: "metric", title: "Next", status: "accepted", inputs: [source.id])
    let first = try book.businessBatches(limit: 1)
    try expect(first["hasMore"] == .bool(true) && first["nextCursor"].text == "three")
    let next = try book.businessBatches(after: "three", limit: 1)
    try expect(next["batches"].array.count == 1 && next["hasMore"] == .bool(false))
    let page = try book.businessBatch("three", limit: 2)
    try expect(page["events"].array.count == 2 && page["batchComplete"] == .bool(false))
    let last = try book.businessBatch("three", afterOrdinal: page["nextOrdinal"].int, limit: 2)
    try expect(last["events"].array.count == 1 && last["batchComplete"] == .bool(true))
    try refuses("business_cursor") { _ = try book.businessBatches(after: source.id) }
    try refuses("business_cursor") { _ = try book.businessBatch("three", afterOrdinal: 3) }
    try refuses("business_batch") { _ = try book.businessBatch(source.id) }
    try refuses("business_scope") { _ = try book.businessBatches(scopeKind: "inventory") }
    try refuses("business_limit") { _ = try book.businessBatch("three", limit: 101) }
    try refuses("business_limit") { _ = try book.businessBatches(limit: 0) }
  }
  check("sparse scope paging uses its scope index and reports exact global coverage") {
    let (book, source) = try businessFixture(root, "BusinessSparse")
    for index in 0..<20 {
      _ = try book.movement(
        subject: index == 4 || index == 16 ? "rare" : "other", quantity: "1",
        occurrence: String(index), effective: "2026-01-01", input: source.id, status: "accepted")
    }
    let first = try book.businessBatches(limit: 1, scopeKind: "inventory", scopeKey: "rare")
    let second = try book.businessBatches(
      after: first["nextCursor"].text, limit: 1, scopeKind: "inventory", scopeKey: "rare")
    try expect(first["hasMore"] == .bool(true) && second["hasMore"] == .bool(false))
    try expect(second["nextCursor"] == second["tail"]["id"])
    try expect(second["batches"].array[0]["position"].text == "17")
    let plan = try book.db.execute(
      "EXPLAIN QUERY PLAN SELECT batch_position,batch_id FROM business_events WHERE scope_kind=? AND scope_key=? AND batch_position>CAST(? AS INTEGER) GROUP BY batch_position ORDER BY batch_position LIMIT 2",
      [.string("inventory"), .string("rare"), .string("0")])
    try expect(plan.contains { $0["detail"]!.text.contains("business_events_scope") })
  }
  check("business mutation rollback after publication leaves no receipt, versions or feed") {
    let (book, source) = try businessFixture(root, "BusinessRollback")
    let digest = try book.db.authorityDigest()
    try refuses("synthetic_rollback") {
      _ = try book.mutation(
        "synthetic.rollback", token: "rollback",
        commitGuard: {
          try expect(try book.db.scalar("SELECT count(*) FROM business_batches").int == 1)
          throw SevraError("synthetic_rollback", "Rollback after semantic publication")
        }
      ) {
        _ = try insertBusinessFixtureRecord(book, source: source.id)
        return .null
      }
    }
    try expect(try book.db.authorityDigest() == digest)
    let cancel = Cancellation()
    cancel.cancel()
    try refuses("cancelled") { _ = try book.businessBatches(cancellation: cancel) }
    try expect(try book.verify()["ok"] == .bool(true))
  }
  check("feed cancellation under a real exclusive writer avoids SQLite's default long busy wait") {
    let (book, _) = try businessFixture(root, "BusinessBusy")
    let other = try Database(book.url.appendingPathComponent("workbook.sqlite"))
    try other.execute("BEGIN EXCLUSIVE")
    defer { _ = try? other.execute("ROLLBACK") }
    let cancellation = Cancellation()
    DispatchQueue.global().asyncAfter(deadline: .now() + 0.03) { cancellation.cancel() }
    let started = ProcessInfo.processInfo.systemUptime
    try refuses("cancelled") { _ = try book.businessBatches(cancellation: cancellation) }
    try expect(ProcessInfo.processInfo.systemUptime - started < 1)
    try other.execute("ROLLBACK")
    try expect(try book.businessBatches()["batches"].array.isEmpty)
  }
  check("business receipts retry identical IDs and reconstruct the feed inertly") {
    let (book, source) = try businessFixture(root, "BusinessReconstruct")
    let draft = try book.movement(
      subject: "parts", quantity: "2", occurrence: "delivery", effective: "2026-01-01",
      input: source.id)
    _ = try book.accept(draft.id, token: "same-accept")
    let before = try book.businessBatches()
    _ = try book.accept(draft.id, token: "same-accept")
    try expect(try book.businessBatches() == before)
    let restored = try book.reconstruct(to: root.appendingPathComponent("BusinessRestored.sevra"))
    try expect(try restored.businessBatches() == before)
    try expect(try businessEntries(restored) == businessEntries(book))
    try expect(try restored.verify()["ok"] == .bool(true))
    try expect(try restored.db.scalar("SELECT count(*) FROM automation_activations").int == 0)
  }
  check("semantic verifier refuses missing, modified and spurious outbox content") {
    let (book, source) = try businessFixture(root, "BusinessCorruption")
    _ = try book.addItem(
      category: "record", kind: "metric", title: "Metric", status: "accepted", inputs: [source.id])
    let statements = [
      "DELETE FROM business_events",
      "UPDATE business_events SET payload='{}'",
      "UPDATE business_events SET scope_key='fabricated'",
      "UPDATE business_batches SET recorded='fabricated'",
      "UPDATE business_events SET id='fabricated'",
    ]
    for (index, statement) in statements.enumerated() {
      let path = root.appendingPathComponent("BusinessBad\(index).sevra")
      try FileManager.default.copyItem(at: book.url, to: path)
      let raw = try Database(path.appendingPathComponent("workbook.sqlite"))
      try raw.execute(statement)
      let changed = try Workbook(path)
      try refuses("business_integrity") { _ = try changed.verify() }
    }
  }
  check("independent concurrent workbook writers get contiguous unique business positions") {
    let (book, source) = try businessFixture(root, "BusinessConcurrent")
    let failures = BusinessFailureBox()
    DispatchQueue.concurrentPerform(iterations: 6) { index in
      do {
        let writer = try Workbook(book.url)
        _ = try writer.movement(
          subject: "parts", quantity: "1", occurrence: "worker\(index)", effective: "2026-01-01",
          input: source.id, status: "accepted")
      } catch { failures.append(String(describing: error)) }
    }
    try expect(failures.values.isEmpty, failures.values.joined(separator: "; "))
    let batches = try book.businessBatches()["batches"].array
    try expect(batches.map { $0["position"].text } == (1...6).map(String.init))
    try expect(Set(batches.map { $0["id"].text }).count == 6)
    try expect(try book.verify()["ok"] == .bool(true))
  }
}

private final class BusinessFailureBox: @unchecked Sendable {
  let lock = NSLock()
  private var failures: [String] = []
  func append(_ value: String) {
    lock.lock()
    defer { lock.unlock() }
    failures.append(value)
  }
  var values: [String] {
    lock.lock()
    defer { lock.unlock() }
    return failures
  }
}

func businessEventDeathWorker(_ path: String, stage: String) throws {
  let book = try Workbook(URL(fileURLWithPath: path))
  let source = try book.items(kind: "observation")[0]
  func barrier() -> Never {
    print("BUSINESS_PUBLICATION_" + stage)
    fflush(stdout)
    while true { Thread.sleep(forTimeInterval: 1) }
  }
  let beforeCommit = {
    if stage == "before-commit" { barrier() }
  }
  let mutation = {
    _ = try insertBusinessFixtureRecord(book, source: source.id)
    return Value.null
  }
  _ = try book.mutation(
    "synthetic.process-death", token: "business-process-death",
    commitGuard: beforeCommit, mutation)
  barrier()
}
