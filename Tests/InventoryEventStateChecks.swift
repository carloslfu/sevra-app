import CSQLite
import Foundation

@testable import SevraCore

func checkInventoryEventState(at root: URL) {
  func fixture(_ name: String, quantity: String = "20", effective: String = "2026-01-01") throws
    -> (Workbook, Item, String)
  {
    let (book, source) = try businessFixture(root, "InventoryEvent" + name)
    try book.setOpeningBalance(
      subject: "parts", quantity: quantity, effective: effective, sourceID: source.id)
    return (book, source, try book.businessBatches()["tail"]["id"].text)
  }
  func tail(_ book: Workbook) throws -> String { try book.businessBatches()["tail"]["id"].text }
  func state(_ book: Workbook, _ batch: String, through: String = "2026-12-31") throws -> Value {
    try book.inventoryAtBusinessBatch(batch, subject: "parts", effectiveThrough: through)
  }
  check(
    "historical inventory keeps an earlier accepted version after later correction and withdrawal"
  ) {
    let (book, source, basisBatch) = try fixture("Corrections")
    let proposal = try book.movement(
      subject: "parts", quantity: "-2", occurrence: "sale", effective: "2026-01-02",
      input: source.id)
    let accepted = try book.accept(proposal.id)
    let originalBatch = try tail(book)
    let revision = try book.movement(
      subject: "parts", quantity: "-5", occurrence: "sale", effective: "2026-01-02",
      input: source.id,
      supersedes: accepted.id)
    try expect(try state(book, originalBatch)["quantity"].text == "18")
    let corrected = try book.accept(revision.id)
    let correctionBatch = try tail(book)
    _ = try book.undoItem(corrected.id)
    let withdrawalBatch = try tail(book)
    try expect(try state(book, basisBatch)["quantity"].text == "20")
    let original = try state(book, originalBatch)
    try expect(
      original["quantity"].text == "18"
        && original["effects"].array[0]["itemID"].text == accepted.id)
    try expect(try state(book, correctionBatch)["quantity"].text == "15")
    // Undo restores the earlier settled movement, rather than withdrawing its occurrence.
    try expect(try state(book, withdrawalBatch)["quantity"].text == "18")
    try expect(try book.verify()["ok"] == .bool(true))
  }
  check("historical inventory rejects an accepted proposal when its later withdrawal was known") {
    let (book, source, _) = try fixture("Withdrawal")
    let proposal = try book.movement(
      subject: "parts", quantity: "-2", occurrence: "sale", effective: "2026-01-02",
      input: source.id)
    let accepted = try book.accept(proposal.id)
    let before = try tail(book)
    _ = try book.undoItem(accepted.id)
    try expect(try state(book, before)["quantity"].text == "18")
    let after = try state(book, tail(book))
    try expect(after["quantity"].text == "20" && after["effects"].array.isEmpty)
  }
  check(
    "historical actual inventory ignores drafts, estimates, other scenarios and fake movement labels"
  ) {
    let (book, source, _) = try fixture("Meaning")
    _ = try book.movement(
      subject: "parts", quantity: "5", occurrence: "draft", effective: "2026-01-02",
      input: source.id)
    _ = try book.movement(
      subject: "parts", quantity: "8", occurrence: "estimate", effective: "2026-01-02",
      input: source.id, meaning: "estimate", status: "accepted")
    _ = try book.movement(
      subject: "other", quantity: "99", occurrence: "other", effective: "2026-01-02",
      input: source.id, status: "accepted")
    _ = try book.addHostOwnedItem(
      category: "record", kind: "movement", title: "No effect",
      data: .object(["subject": .string("parts"), "quantity": .string("99")]), status: "accepted",
      inputs: [source.id])
    let actual = try book.movement(
      subject: "parts", quantity: "1.25", occurrence: "actual", effective: "2026-01-02",
      input: source.id, status: "accepted")
    _ = try book.addHostOwnedItem(
      category: "record", kind: "movement", title: "Other scenario", data: actual.data,
      status: "accepted", scenario: "forecast", inputs: [source.id], supersedes: actual.id)
    let value = try state(book, tail(book))
    try expect(value["quantity"].text == "20" && value["effects"].array.isEmpty)
  }
  check("historical inventory separates committed knowledge from explicit effective dates") {
    let (book, source, _) = try fixture("Time")
    _ = try book.movement(
      subject: "parts", quantity: "-2", occurrence: "at-basis", effective: "2026-01-01",
      input: source.id, status: "accepted")
    _ = try book.movement(
      subject: "parts", quantity: "-3", occurrence: "future", effective: "2030-01-01",
      input: source.id, status: "accepted")
    let batch = try tail(book)
    try expect(try state(book, batch)["quantity"].text == "20")
    let future = try state(book, batch, through: "2030-01-01")
    try expect(future["quantity"].text == "17" && future["effectiveThrough"].text.hasPrefix("2030"))
    try expect(future["knowledgeBatch"]["id"].text == batch)
    try expect(future["effects"].array.count == 1 && future["execution"].text == "inert")
    try expect(
      try book.balance(subject: "parts", asOf: "2030-01-01")["quantity"] == future["quantity"])
  }
  check("later cross-scope settled revisions cannot leave an older logical effect active") {
    let (book, source, _) = try fixture("CrossScope")
    let first = try book.movement(
      subject: "parts", quantity: "2", occurrence: "one", effective: "2026-01-02",
      input: source.id, status: "accepted")
    let before = try tail(book)
    _ = try book.addHostOwnedItem(
      category: "record", kind: "movement", title: "Replacement claim has no effect",
      data: .object(["subject": .string("other")]), status: "accepted", inputs: [source.id],
      supersedes: first.id)
    try expect(try state(book, before)["quantity"].text == "22")
    try expect(try state(book, tail(book))["quantity"].text == "20")
  }
  check("an exact effect in a non-actual scenario cannot contribute to actual inventory") {
    let (book, source, _) = try fixture("Scenario")
    let first = try book.movement(
      subject: "parts", quantity: "2", occurrence: "one", effective: "2026-01-02",
      input: source.id, status: "accepted")
    _ = try book.mutation("synthetic.scenario") {
      let version = try book.insertItem(
        category: "record", kind: "movement", title: "Scenario alternative", text: "",
        data: first.data,
        meaning: "actual", status: "accepted", scenario: "forecast", inputs: [source.id],
        transformation: "synthetic.scenario", supersedes: first.id)
      try book.db.execute(
        "INSERT INTO effects SELECT occurrence,subject,kind,?,quantity,effective FROM effects WHERE item_id=?",
        [.string(version), .string(first.id)])
      return .null
    }
    try expect(try state(book, tail(book))["quantity"].text == "20")
  }
  check("unknown and future opening bases never become an invented zero balance") {
    let (book, source) = try businessFixture(root, "InventoryEventUnknown")
    _ = try book.addItem(
      category: "record", kind: "metric", title: "Cutoff", status: "accepted", inputs: [source.id])
    let unknown = try state(book, tail(book))
    try expect(unknown["known"] == .bool(false) && unknown["quantity"] == .null)
    try expect(unknown["reason"].text == "unknown_basis")
    try book.setOpeningBalance(
      subject: "parts", quantity: "20", effective: "2030-01-01", sourceID: source.id)
    let future = try state(book, tail(book))
    try expect(future["reason"].text == "basis_not_effective" && future["quantity"] == .null)
    try expect(try state(book, tail(book), through: "2030-01-02")["quantity"].text == "20")
  }
  check("retained opening basis survives later captured basis correction and removal") {
    let (book, source, initial) = try fixture("BasisHistory")
    _ = try book.mutation("synthetic.basis-correction") {
      try book.db.execute("UPDATE bases SET quantity='30' WHERE subject='parts'")
      return .null
    }
    let corrected = try tail(book)
    _ = try book.mutation("synthetic.basis-removal") {
      try book.db.execute("DELETE FROM bases WHERE subject='parts'")
      return .null
    }
    try expect(try state(book, initial)["quantity"].text == "20")
    let retained = try state(book, corrected)
    try expect(retained["quantity"].text == "30" && retained["basis"]["inputID"].text == source.id)
    let removed = try state(book, tail(book))
    try expect(removed["quantity"] == .null && removed["basis"]["removed"] == .bool(true))
    try expect(try book.verify()["ok"] == .bool(true))
  }
  check("historical inventory observes final atomic state and distinct independent occurrences") {
    let (book, source, _) = try fixture("Atomic")
    _ = try book.mutation("synthetic.inventory-atomic", token: "inventory-atomic") {
      let request = try book.movementRequest(
        subject: "parts", quantity: "-10", occurrence: "first", effective: "2026-01-02",
        input: source.id, status: "accepted")
      let first = try book.insertMovement(request)
      let revision = try book.movementRequest(
        subject: "parts", quantity: "-2", occurrence: "first", effective: "2026-01-02",
        input: source.id, status: "accepted", supersedes: first)
      _ = try book.insertMovement(revision)
      let second = try book.movementRequest(
        subject: "parts", quantity: "3", occurrence: "second", effective: "2026-01-02",
        input: source.id, status: "accepted")
      _ = try book.insertMovement(second)
      return .null
    }
    let value = try state(book, "inventory-atomic")
    try expect(value["quantity"].text == "21" && value["effects"].array.count == 2)
    try expect(Set(value["effects"].array.map { $0["occurrence"].text }) == ["first", "second"])
  }
  check("historical inventory uses exact decimals and refuses lossy addition") {
    let (book, source, _) = try fixture("Decimals", quantity: "9007199254740993.1")
    _ = try book.movement(
      subject: "parts", quantity: "0.2", occurrence: "fraction", effective: "2026-01-02",
      input: source.id, status: "accepted")
    try expect(try state(book, tail(book))["quantity"].text == "9007199254740993.3")
    let (large, input, _) = try fixture(
      "Precision", quantity: "99999999999999999999999999999999999999")
    _ = try large.movement(
      subject: "parts", quantity: "0.1", occurrence: "fraction", effective: "2026-01-02",
      input: input.id, status: "accepted")
    try refuses { _ = try state(large, tail(large)) }
  }
  check("historical inventory reads mutate nothing and reconstruct with exact contribution IDs") {
    let (book, source, _) = try fixture("Reconstruction")
    _ = try book.movement(
      subject: "parts", quantity: "2", occurrence: "delivery", effective: "2026-01-02",
      input: source.id, status: "accepted")
    let batch = try tail(book)
    let before = try book.db.authorityDigest()
    let result = try state(book, batch)
    try expect(try book.db.authorityDigest() == before)
    let restored = try book.reconstruct(
      to: root.appendingPathComponent("InventoryEventRestored.sevra"))
    try expect(try state(restored, batch) == result)
    try refuses("business_batch") { _ = try state(book, source.id) }
    try refuses("date") { _ = try state(book, batch, through: "next week") }
    let cancel = Cancellation()
    cancel.cancel()
    try refuses("cancelled") {
      _ = try book.inventoryAtBusinessBatch(
        batch, subject: "parts", effectiveThrough: "2026-12-31", cancellation: cancel)
    }
  }
}

func checkInventoryEventLimit(at root: URL) {
  check(
    "historical inventory returns all 10000 effects and refuses a partial 10001-effect quantity"
  ) {
    let (book, source) = try businessFixture(root, "InventoryEventLimit")
    try book.setOpeningBalance(
      subject: "parts", quantity: "1", effective: "2026-01-01", sourceID: source.id)
    for batch in 0..<10 {
      _ = try book.mutation("synthetic.inventory-scale", token: "inventory-scale-\(batch)") {
        for offset in 0..<1000 {
          let request = try book.movementRequest(
            subject: "parts", quantity: "1", occurrence: "effect-\(batch * 1000 + offset)",
            effective: "2026-01-02", input: source.id, status: "accepted")
          _ = try book.insertMovement(request)
        }
        return .null
      }
    }
    sqlite3_trace_v2(
      book.db.handle, UInt32(SQLITE_TRACE_PROFILE),
      { _, _, statement, elapsed in
        if let statement, let elapsed {
          let sql = sqlite3_sql(OpaquePointer(statement)).map { String(cString: $0) } ?? ""
          let seconds = Double(elapsed.load(as: UInt64.self)) / 1_000_000_000
          print("PROFILE inventory fixture query seconds=\(seconds) sql=\(sql)")
        }
        return 0
      }, nil)
    defer { sqlite3_trace_v2(book.db.handle, 0, nil, nil) }
    let before = try book.inventoryAtBusinessBatch(
      "inventory-scale-9", subject: "parts", effectiveThrough: "2026-01-03")
    try expect(before["quantity"].text == "10001" && before["effects"].array.count == 10_000)
    _ = try book.movement(
      subject: "parts", quantity: "1", occurrence: "effect-10000", effective: "2026-01-02",
      input: source.id, status: "accepted", token: "inventory-over-limit")
    try refuses("inventory_history_limit") {
      _ = try book.inventoryAtBusinessBatch(
        "inventory-over-limit", subject: "parts", effectiveThrough: "2026-01-03")
    }
  }
}
