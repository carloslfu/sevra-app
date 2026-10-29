import Foundation

@testable import SevraCore

func checkBusinessInputs(at root: URL) {
  func book(_ name: String) throws -> Workbook {
    try Workbook.create(
      at: root.appendingPathComponent("BusinessInput-" + name + ".sevra"), title: name)
  }
  func declarations(_ book: Workbook, _ ids: [String]) throws -> [Value] {
    try book.readBusinessFeed(cancellation: .init()) {
      try book.inspectBusinessInputDeclarations(ids, cancellation: .init())
    }
  }
  check("explicit original observations retain creating identity and retry without new roots") {
    let book = try book("Retry")
    for token in ["", String(repeating: "x", count: 513)] {
      try refuses("business_input") {
        _ = try book.recordBusinessObservation(title: "Invalid", token: token)
      }
    }
    let input = try book.recordBusinessObservation(
      title: "Independent stock count", token: "observation")
    let first = try declarations(book, [input.id])
    try expect(first.count == 1 && first[0]["kind"].text == "observation")
    try expect(first[0]["creatingCommitID"].text == "observation")
    try expect(first[0]["qualification"].text == "explicit-host-input-intent")
    let history = try book.committedHistory()
    try expect(
      try book.recordBusinessObservation(title: input.title, token: "observation").id == input.id)
    try expect(try book.committedHistory() == history && declarations(book, [input.id]) == first)
    try refuses("idempotency") {
      _ = try book.recordBusinessObservation(title: "Different", token: "observation")
    }
    _ = try book.verify()
  }
  check("several original inputs in one atomic capture share the same root") {
    let book = try book("Atomic")
    var inputs: [String] = []
    _ = try book.mutation("synthetic.business-input", token: "one-atomic-input") {
      for title in ["Delivery A", "Delivery B"] {
        let id = try book.insertItem(
          category: "source", kind: "observation", title: title, text: "", data: .null,
          meaning: "actual", status: "accepted", scenario: "actual", inputs: [],
          transformation: "synthetic")
        try book.declareNewBusinessInput(id, kind: "observation")
        inputs.append(id)
      }
      return .null
    }
    let values = try declarations(book, inputs)
    try expect(values.count == 2 && Set(values.map { $0["rootID"].text }).count == 1)
    let separate = try book.recordBusinessObservation(title: "New independent event")
    try expect(try declarations(book, [separate.id])[0]["rootID"] != values[0]["rootID"])
    _ = try book.verify()
  }
  check("generic human labels and copied origin fields cannot declare independent business inputs")
  {
    let book = try book("Generic")
    let input = try ChangeAttribution.$actor.withValue(.human("synthetic")) {
      try book.addItem(
        category: "source", kind: "observation", title: "Unqualified",
        data: .object(["policy": .string(BusinessInput.policy), "independent": .bool(true)]))
    }
    try expect(try declarations(book, [input.id]).isEmpty)
    try refuses("business_input") {
      try book.declareNewBusinessInput(input.id, kind: "observation")
    }
    try refuses("business_input") {
      _ = try book.mutation("synthetic.late-declaration") {
        try book.declareNewBusinessInput(input.id, kind: "observation")
        return .null
      }
    }
    try expect(try declarations(book, [input.id]).isEmpty)
  }
  check("AI attribution, technical Sources and derived Sources cannot mint fresh business roots") {
    let book = try book("Refuse")
    try refuses("business_input") {
      _ = try ChangeAttribution.$actor.withValue(
        .ai("synthetic", model: "synthetic", policy: "synthetic")
      ) {
        try book.recordBusinessObservation(title: "AI cannot assert independence")
      }
    }
    let original = try book.recordBusinessObservation(title: "Original")
    for kind in ["request", "observation"] {
      try refuses("business_input") {
        _ = try book.mutation("synthetic.bad-declaration") {
          let id = try book.insertItem(
            category: "source", kind: kind, title: "Derived", text: "", data: .null,
            meaning: "actual", status: "accepted", scenario: "actual",
            inputs: kind == "request" ? [] : [original.id], transformation: "synthetic")
          try book.declareNewBusinessInput(id, kind: "observation")
          return .null
        }
      }
    }
    try expect(try book.db.scalar("SELECT count(*) FROM business_inputs").int == 1)
    _ = try book.verify()
  }
  check("failed publication rolls back both input and declaration and retry starts clean") {
    let book = try book("Rollback")
    let before = try book.db.authorityDigest()
    try refuses("synthetic_failure") {
      _ = try book.mutation("synthetic.rollback", token: "retry") {
        let id = try book.insertItem(
          category: "source", kind: "observation", title: "Rollback", text: "", data: .null,
          meaning: "actual", status: "accepted", scenario: "actual", inputs: [],
          transformation: "synthetic")
        try book.declareNewBusinessInput(id, kind: "observation")
        throw SevraError("synthetic_failure", "Synthetic rollback")
      }
    }
    try expect(
      try book.db.authorityDigest() == before && book.db.changes?.businessInputs.isEmpty == true)
    let saved = try book.recordBusinessObservation(title: "Retry", token: "retry")
    try expect(try declarations(book, [saved.id]).count == 1)
  }
  check("failure after declaration publication rolls back the complete captured input") {
    let book = try book("PublicationRollback")
    let before = try book.db.authorityDigest()
    try refuses("synthetic_failure") {
      _ = try book.mutation(
        "synthetic.publication-rollback", token: "publication",
        commitGuard: {
          try expect(try book.db.scalar("SELECT count(*) FROM business_inputs").int == 1)
          throw SevraError("synthetic_failure", "Fail immediately before COMMIT")
        }
      ) {
        let id = try book.insertItem(
          category: "source", kind: "observation", title: "Independent input",
          text: "", data: .null, meaning: "actual", status: "accepted", scenario: "actual",
          inputs: [],
          transformation: "synthetic")
        try book.declareNewBusinessInput(id, kind: "observation")
        return .string(id)
      }
    }
    try expect(
      try book.db.authorityDigest() == before && book.db.changes?.businessInputs.isEmpty == true)
    let saved = try book.recordBusinessObservation(title: "Explicit retry", token: "publication")
    try expect(try declarations(book, [saved.id]).count == 1)
    _ = try book.verify()
  }
  check("top-level file intake declares one root and derived archive members retain it") {
    let book = try book("Intake")
    let file = root.appendingPathComponent("Independent-file.txt")
    try Data("Independent supplier document".utf8).write(to: file)
    let job = try book.captureIntake(file, token: "file")
    let source = try book.item(job.sourceID)
    let declared = try declarations(book, [source.id])
    try expect(declared.count == 1 && declared[0]["kind"].text == "external-file")
    let derived = try book.importFile(file, token: "derived", inputs: [source.id])
    try expect(try declarations(book, [derived.id]).isEmpty)
    try expect(
      try book.businessOrigins(inputs: [derived.id])["originalInputCandidates"].array == [
        .string(source.id)
      ])
    try refuses("business_input") {
      _ = try book.importFile(file, token: "forbidden", inputs: [source.id], independentInput: true)
    }
    _ = try book.verify()
  }
  check("independent declarations survive inert reconstruction without live grants") {
    let book = try book("Reconstruct")
    let input = try book.recordBusinessObservation(title: "Original")
    let first = try declarations(book, [input.id])
    let before = try book.db.authorityDigest()
    let copy = try book.reconstruct(to: root.appendingPathComponent("BusinessInputCopy.sevra"))
    try expect(try declarations(copy, [input.id]) == first && book.db.authorityDigest() == before)
    try expect(try copy.db.scalar("SELECT count(*) FROM automatic_admissions").int == 0)
    _ = try copy.verify()
  }
  check("creating-change inspection enforces its cumulative16MiB budget before decoding") {
    let book = try book("EnvelopeBudget")
    var sources: [String] = []
    for index in 0..<4 {
      sources.append(
        try book.recordBusinessObservation(
          title: "Input \(index)",
          text: String(repeating: "x", count: 1_300_000)
        ).id)
    }
    let size = try book.db.scalar(
      "SELECT sum(length(CAST(c.payload AS BLOB))) FROM committed_changes c WHERE c.id IN (SELECT commit_id FROM business_inputs)"
    ).int!
    try expect(size > 16_777_216)
    try expect(try declarations(book, [sources[0]]).count == 1)
    try refuses("business_input_limit") { _ = try declarations(book, sources) }
  }
  check("altered missing foreign and oversized declaration histories cannot establish independence")
  {
    for damage in 0..<6 {
      let book = try book("Damage\(damage)")
      _ = try book.addItem(
        category: "source", kind: "observation", title: "Earlier unrelated input")
      let input = try book.recordBusinessObservation(title: "Original")
      let raw = try Database(book.url.appendingPathComponent("workbook.sqlite"))
      _ = try raw.transaction {
        switch damage {
        case 0: try raw.execute("UPDATE business_inputs SET item_index=1")
        case 1:
          try raw.execute(
            "UPDATE business_inputs SET commit_id=(SELECT id FROM committed_changes ORDER BY rowid LIMIT 1)"
          )
        case 2: try raw.execute("DELETE FROM business_inputs")
        case 3:
          try raw.execute(
            "UPDATE committed_changes SET hash='altered' WHERE id=(SELECT commit_id FROM business_inputs)"
          )
        case 4:
          try raw.execute("UPDATE items SET category='record' WHERE id=?", [.string(input.id)])
        default:
          try raw.execute(
            "UPDATE committed_changes SET payload=? WHERE id=(SELECT commit_id FROM business_inputs)",
            [.string(String(repeating: "x", count: 16_777_217))])
        }
      }
      if damage == 2 {
        try expect(try declarations(book, [input.id]).isEmpty)
      } else if damage != 4 {
        do {
          try refuses(damage == 5 ? "business_input_limit" : "business_input_integrity") {
            _ = try declarations(book, [input.id])
          }
        } catch { throw SevraError("test", "Declaration read damage \(damage): \(error)") }
      }
      do { try refuses { _ = try book.verify() } } catch {
        throw SevraError("test", "Damaged declaration case \(damage): \(error)")
      }
    }
  }
}

func businessInputDeathWorker(at url: URL, stage: String) throws {
  try require(
    ["prepared", "committed"].contains(stage), "fixture", "Use an exact fixture boundary.")
  let book = try Workbook.create(at: url, title: "Synthetic independent input publication")
  var source = ""
  func barrier() throws {
    print(try Value.object(["stage": .string(stage), "sourceID": .string(source)]).json())
    _ = readLine()
  }
  _ = try book.mutation(
    "synthetic.input-death", token: "synthetic-input-death",
    commitGuard: {
      if stage == "prepared" { try barrier() }
    },
    {
      source = try book.insertItem(
        category: "source", kind: "observation", title: "Independent input",
        text: "Synthetic evidence", data: .null, meaning: "actual", status: "accepted",
        scenario: "actual", inputs: [],
        transformation: "synthetic")
      try book.declareNewBusinessInput(source, kind: "observation")
      return .string(source)
    })
  if stage == "committed" { try barrier() }
}
