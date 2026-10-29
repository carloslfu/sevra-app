import Foundation

@testable import SevraCore

func derivationRow(_ book: Workbook, _ id: String) throws -> [String: Value] {
  try book.db.execute("SELECT id,supersedes,derivation FROM items WHERE id=?", [.string(id)]).first!
}

func expectInputRole(
  _ book: Workbook, child: String, parent: String, roles: Int, relation: String = "derives-from"
) throws {
  _ = try book.verifiedItemDerivation(derivationRow(book, child))
  let retained = try book.db.scalar(
    "SELECT roles FROM lineage WHERE child=? AND parent=? AND relation=?",
    [.string(child), .string(parent), .string(relation)])
  try expect(
    retained == .number(Double(roles)),
    "Expected exact input roles \(roles) for \(child) from \(parent); retained \(retained).")
}

func expectTechnicalReference(_ book: Workbook, origin: String, annotation: String) throws {
  let edges = try book.lineage(origin)
  try expect(
    edges.count == 1 && edges[0]["child"] == .string(annotation)
      && edges[0]["parent"] == .string(origin)
      && edges[0]["roles"] == .array([.string("control")]))
  try expectInputRole(book, child: annotation, parent: origin, roles: 2)
  try expect(try book.verifiedItemDerivation(derivationRow(book, origin))["edgeCount"].int == 0)
}

func checkDerivationRoles(at root: URL) {
  check("generic data inputs and original Sources retain complete conservative seals") {
    let (book, source) = try businessFixture(root, "RoleOriginal")
    let original = try book.verifiedItemDerivation(derivationRow(book, source.id))
    try expect(
      original["classification"].text == "unclassified-original" && original["edgeCount"].int == 0)
    let record = try book.addItem(
      category: "record", kind: "document", title: "Derived", inputs: [source.id])
    let seal = try book.verifiedItemDerivation(derivationRow(book, record.id))
    try expect(seal["classification"].text == "retained-derivation" && seal["edgeCount"].int == 1)
    try expect(
      try book.db.scalar("SELECT roles FROM lineage WHERE child=?", [.string(record.id)]).int == 1)
    _ = try book.verify()
  }
  check("one exact parent retains simultaneous data, control and producer roles") {
    let (book, source) = try businessFixture(root, "RoleDual")
    let id = try book.mutation("synthetic.dual-role") {
      .string(
        try book.insertItem(
          category: "record", kind: "document", title: "Dual role", text: "",
          data: .object([:]), meaning: "estimate", status: "draft", scenario: "planning",
          inputs: [source.id, source.id], transformation: "synthetic-role-v1",
          controlInputs: [source.id], producerInputs: [source.id]))
    }.text
    try expect(
      try book.db.scalar("SELECT count(*) FROM lineage WHERE child=?", [.string(id)]).int == 1)
    try expect(
      try book.db.scalar("SELECT roles FROM lineage WHERE child=?", [.string(id)]).int == 7)
    try expect(
      DerivationRole.names(7) == .array([.string("data"), .string("control"), .string("producer")]))
    try expect(
      try book.lineage(id)[0]["roles"]
        == .array([.string("data"), .string("control"), .string("producer")]))
    _ = try book.verify()
  }
  check("corrections preserve exact revision role separately from business evidence") {
    let (book, source) = try businessFixture(root, "RoleRevision")
    let old = try book.addItem(
      category: "record", kind: "document", title: "Original", inputs: [source.id])
    let revised = try book.addItem(
      category: "record", kind: "document", title: "Revised", inputs: [source.id, old.id],
      supersedes: old.id)
    let rows = try book.db.execute(
      "SELECT relation,roles FROM lineage WHERE child=? AND parent=? ORDER BY relation",
      [.string(revised.id), .string(old.id)])
    try expect(rows.count == 2 && rows[0]["roles"]?.int == 1 && rows[1]["roles"]?.int == 8)
    _ = try book.verify()
  }
  check("missing, extra, changed roles and erased or unsupported seals refuse") {
    for damage in 0..<5 {
      let (book, source) = try businessFixture(root, "RoleDamage\(damage)")
      let spare = try book.addItem(category: "source", kind: "observation", title: "Spare")
      let item = try book.addItem(
        category: "record", kind: "document", title: "Derived", inputs: [source.id])
      _ = try book.db.transaction {
        switch damage {
        case 0: try book.db.execute("DELETE FROM lineage WHERE child=?", [.string(item.id)])
        case 1: try book.db.execute("UPDATE lineage SET roles=2 WHERE child=?", [.string(item.id)])
        case 2:
          try book.db.execute(
            "INSERT INTO lineage VALUES(?,?,'derives-from','synthetic',1)",
            [.string(item.id), .string(spare.id)])
        case 3:
          try book.db.execute("UPDATE items SET derivation='{}' WHERE id=?", [.string(item.id)])
        default:
          try book.db.execute(
            "UPDATE items SET derivation=json_set(derivation,'$.policy','unknown') WHERE id=?",
            [.string(item.id)])
        }
      }
      try refuses("derivation_integrity") {
        _ = try book.verifiedItemDerivation(derivationRow(book, item.id))
      }
      try refuses("derivation_integrity") { _ = try book.verify() }
    }
  }
  check("relation and role contradictions refuse even with a freshly forged seal") {
    let (book, source) = try businessFixture(root, "RoleContradiction")
    let item = try book.addItem(
      category: "record", kind: "document", title: "Derived", inputs: [source.id])
    _ = try book.db.transaction {
      try book.db.execute("UPDATE lineage SET roles=8 WHERE child=?", [.string(item.id)])
    }
    try refuses("derivation_integrity") {
      _ = try book.verifiedItemDerivation(derivationRow(book, item.id))
    }
  }
  check("definition dependency additions are sealed in the creating transaction only") {
    let (book, source) = try businessFixture(root, "RoleDependency")
    let id = try book.mutation("synthetic.dependency-role") {
      let id = try book.insertItem(
        category: "source", kind: "application_definition", title: "Definition", text: "",
        data: .object([:]), meaning: "actual", status: "accepted", scenario: "actual", inputs: [],
        transformation: "synthetic-definition")
      try book.insertDefinitionDerivation(
        id, parent: source.id, transformation: "synthetic-definition")
      try book.sealNewDefinitionDerivation(id)
      return .string(id)
    }.text
    try expect(
      try book.db.scalar("SELECT roles FROM lineage WHERE child=?", [.string(id)]).int == 2)
    try expect(try book.verifiedItemDerivation(derivationRow(book, id))["edgeCount"].int == 1)
    let digest = try book.db.authorityDigest()
    try refuses("derivation_transaction") {
      _ = try book.mutation("synthetic.illegal-reseal") {
        try book.sealNewDefinitionDerivation(id)
        return .null
      }
    }
    try expect(try book.db.authorityDigest() == digest)
    try refuses("derivation_transaction") {
      try book.insertDefinitionDerivation(id, parent: source.id, transformation: "synthetic")
    }
    _ = try book.verify()
  }
  check("normal item insertion seals before writing and captures a large body only once") {
    let (book, source) = try businessFixture(root, "RoleCapture")
    let text = String(repeating: "q", count: 750_000)
    var id = ""
    _ = try book.mutation("synthetic.single-item-write") {
      id = try book.insertItem(
        category: "record", kind: "document", title: "Large", text: text,
        data: .object([:]), meaning: "actual", status: "draft", scenario: "actual",
        inputs: [source.id], transformation: "synthetic-single-write")
      let writes = book.db.changes!.pending!.filter { $0.table == "items" }
      try expect(
        writes.count == 1 && writes[0].before == nil && writes[0].after?.values.first?.string == id)
      return .string(id)
    }
    _ = try book.verify()
    try expect(try book.item(id).text == text)
  }
  check("canonical derivation hashing stays exact through several edge pages and escaped text") {
    let (book, source) = try businessFixture(root, "RolePages")
    var inputs = [source.id]
    let id = try book.mutation("synthetic.role-pages") {
      for n in 0..<205 {
        inputs.append(
          try book.insertItem(
            category: "source", kind: "observation", title: "Input \(n)", text: "",
            data: .object([:]), meaning: "actual", status: "accepted", scenario: "actual",
            inputs: [], transformation: "synthetic"))
      }
      return .string(
        try book.insertItem(
          category: "record", kind: "document", title: "Many", text: "",
          data: .object([:]), meaning: "actual", status: "draft", scenario: "actual",
          inputs: inputs.reversed(),
          transformation: "text/with/á and \"quotes\"\n"))
    }.text
    try expect(try book.verifiedItemDerivation(derivationRow(book, id))["edgeCount"].int == 206)
    _ = try book.verify()
  }
  check("derivation metadata and named roles reconstruct inertly without changing data meaning") {
    let (book, source) = try businessFixture(root, "RoleRebuild")
    let movement = try book.movement(
      subject: "parts", quantity: "-2", occurrence: "delivery", effective: "2026-01-02",
      input: source.id, status: "accepted")
    let copy = try book.reconstruct(to: root.appendingPathComponent("RoleReconstructed.sevra"))
    try expect(try derivationRow(copy, movement.id) == derivationRow(book, movement.id))
    try expect(try copy.lineage(movement.id) == book.lineage(movement.id))
    _ = try copy.verify()
  }
  check("a rejected publication rolls back item, input roles and seal before retry") {
    let (book, source) = try businessFixture(root, "RoleRollback")
    let before = try book.db.authorityDigest()
    try refuses("synthetic_abort") {
      _ = try book.mutation(
        "synthetic.role-rollback", token: "same-role-token",
        commitGuard: {
          throw SevraError("synthetic_abort", "Abort this synthetic publication.")
        }
      ) {
        .string(
          try book.insertItem(
            category: "record", kind: "document", title: "Draft", text: "", data: .object([:]),
            meaning: "actual", status: "draft", scenario: "actual", inputs: [source.id],
            transformation: "synthetic"))
      }
    }
    try expect(try book.db.authorityDigest() == before)
    let item = try book.addItem(
      category: "record", kind: "document", title: "Retry", inputs: [source.id],
      token: "same-role-token")
    _ = try book.verifiedItemDerivation(derivationRow(book, item.id))
    _ = try book.verify()
  }
  check("table edits retain business versions while the schema remains an exact control input") {
    let (book, source) = try businessFixture(root, "RoleTable")
    let table = try book.createDataset(
      title: "Counts", columns: [.init(id: "count", title: "Count", type: "decimal")],
      rows: [["count": .string("2")]], sourceID: source.id)
    let schema = try book.datasetDefinition(table.id)
    let row = try book.rows(table.id)[0]
    try expectInputRole(book, child: row.id, parent: source.id, roles: 1)
    try expectInputRole(book, child: row.id, parent: schema.sourceID, roles: 2)
    let revised = try book.editRow(row.id, values: ["count": .string("3")])
    try expectInputRole(book, child: revised.id, parent: row.id, roles: 1)
    try expectInputRole(book, child: revised.id, parent: row.id, roles: 8, relation: "supersedes")
    try expectInputRole(book, child: revised.id, parent: schema.sourceID, roles: 2)
    _ = try book.verify()
  }
  check("nested item arguments retain automatic evidence alongside independent manual input") {
    let url = root.appendingPathComponent("RoleNested.sevra")
    let data = try createAutomaticAncestryFixture(at: url)
    let book = try Workbook(url)
    var content = try book.applicationDefinition(data["workflowID"].text).content.object
    var parameters = content["parameters"]!.array
    parameters.append(
      .object([
        "id": .string("attachments"), "label": .string("Attachments"), "type": .string("entries"),
        "required": .bool(true), "maxEntries": .number(4),
        "fields": .array([ActionRegistry.field("evidence", "Evidence", "item")]),
      ]))
    content["parameters"] = .array(parameters)
    let definition = try book.saveApplicationDefinition(
      logicalID: identifier(), content: .object(content), inputs: [data["acceptedID"].text])
    var arguments = data["arguments"].object
    arguments["attachments"] = .array([.object(["evidence": data["acceptedID"]])])
    let run = try book.startWorkflow(definition.id, arguments: .object(arguments), token: "nested")
    try expect(run["policy"] == .string("manual-drafts-v1"))
    try expectInputRole(book, child: run["source_id"].text, parent: data["sourceID"].text, roles: 1)
    try expectInputRole(
      book, child: run["source_id"].text, parent: data["acceptedID"].text, roles: 1)
    try expectInputRole(book, child: run["source_id"].text, parent: definition.sourceID, roles: 2)
    try expectInputRole(book, child: definition.sourceID, parent: data["acceptedID"].text, roles: 1)
    _ = try book.verify()
  }
  check("saved automatic authority and planning are control history, never business observations") {
    let url = root.appendingPathComponent("RoleTechnical.sevra")
    let data = try createAutomaticAncestryFixture(at: url)
    let book = try Workbook(url)
    let rows = try book.db.execute(
      "SELECT id,supersedes,derivation FROM items WHERE kind IN ('automation_authorization','automation_planning','automation_dispatch','workflow_authorization')"
    )
    try expect(rows.count >= 3)
    for row in rows {
      let seal = try book.verifiedItemDerivation(row)
      try expect(seal["classification"] == .string("unclassified-original"))
      try expect(
        try book.db.scalar("SELECT count(*) FROM lineage WHERE child=? AND roles<>2", [row["id"]!])
          .int == 0)
    }
    let movement = try book.item(data["acceptedID"].text)
    let correction = try book.movement(
      subject: "parts", quantity: "6", occurrence: movement.data["occurrence"].text,
      effective: movement.data["effective"].text, input: data["sourceID"].text,
      supersedes: movement.id)
    try expectInputRole(
      book, child: correction.id, parent: movement.id, roles: 8, relation: "supersedes")
    _ = try book.verify()
  }
}
