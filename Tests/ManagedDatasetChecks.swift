import CSQLite
import Foundation

@testable import SevraCore

func checkManagedDatasets(at root: URL) {
  check("managed native tables preserve scalar semantics and immutable row identities") {
    let book = try Workbook.create(
      at: root.appendingPathComponent("NativeValues.sevra"), title: "Native")
    let source = try book.addItem(category: "source", kind: "note", title: "Original")
    let columns: [Column] = [
      .init(id: "sku", title: "SKU"),
      .init(id: "amount", title: "Amount", type: "decimal", unit: "USD"),
      .init(id: "flag", title: "Flag", type: "boolean"),
      .init(id: "date", title: "Date", type: "date"),
      .init(id: "optional", title: "Optional"),
      .init(id: "cached", title: "Calculated", type: "decimal", formula: "amount*2"),
    ]
    let values: [[String: Value]] = [
      [
        "sku": .string("0012"), "amount": .string("9007199254740993.0100"), "flag": .string("TRUE"),
        "date": .string("2026-01-02"), "optional": .null, "cached": .string("stale"),
      ],
      [
        "sku": .string("Cafe\u{301} 👩🏽‍💻\0"), "amount": .number(2), "flag": .bool(false),
        "date": .string(""), "optional": .string(""),
      ],
      ["sku": .string("missing"), "amount": .null, "flag": .null],
    ]
    let table = try book.createDataset(
      title: "Orders", columns: columns, rows: values, sourceID: source.id)
    let second = try book.createDataset(
      title: "Other", columns: [.init(id: "n", title: "N")], rows: [], sourceID: source.id)
    let schema = try book.db.managedSchema(table.id)
    try expect(schema.table != book.db.managedSchema(second.id).table)
    try expect(try book.rows(table.id).map(\.data) == values.map(Value.object))
    let physical = try book.db.execute(
      "SELECT * FROM " + ChangeFormat.quote(schema.table) + " ORDER BY _sevra_ordinal")
    try expect(physical[0][schema.field("amount")]?.string == "9007199254740993.0100")
    try expect(physical[0][schema.field("flag")]?.int == 1)
    try expect(physical[0][schema.field("date")]?.text == "2026-01-02T00:00:00.000Z")
    let row = try book.rows(table.id)[0]
    var edited = values[1]
    edited["cached"] = values[0]["cached"]
    let edit = try book.editRow(row.id, values: edited, token: "edit-once")
    try expect(edit.logicalID == row.logicalID && edit.id != row.id)
    try expect(try book.editRow(row.id, values: edited, token: "edit-once").id == edit.id)
    try expect(
      try book.rows(table.id)[0].data == edit.data && book.item(row.id).data == .object(values[0]))
    _ = try book.undoItem(edit.id)
    try expect(try book.rows(table.id)[0].data == .object(values[0]))
    try expect(try book.verify()["ok"] == .bool(true))
  }
  check("managed schema changes and independent projection rebuild reconstruct exactly") {
    let book = try Workbook.create(
      at: root.appendingPathComponent("NativeSchema.sevra"), title: "Schema")
    let source = try book.addItem(category: "source", kind: "note", title: "Original")
    let table = try book.createDataset(
      title: "Values", columns: [.init(id: "n", title: "N")],
      rows: [["n": .string("0012")], ["n": .string("14")]], sourceID: source.id)
    let original = try book.rows(table.id)
    let firstSchema = try book.db.managedSchema(table.id)
    try book.setColumns(
      table.id,
      columns: [
        .init(id: "n", title: "Renamed", type: "decimal"), .init(id: "memo", title: "Memo"),
      ])
    try expect(try book.rows(table.id).map(\.data) == original.map(\.data))
    try book.setColumns(
      table.id,
      columns: [
        .init(id: "n", title: "Renamed", type: "decimal"),
        .init(id: "memo", title: "Memo", type: "decimal", formula: "n*2"),
      ])
    try expect(
      try book.calculatedValues(book.rows(table.id)[0], columns: book.dataset(table.id).columns)[
        "memo"]?.text == "24")
    try book.restoreColumns(table.id, version: 1)
    try expect(try book.db.managedSchema(table.id).table == firstSchema.table)
    try expect(try book.verify()["ok"] == .bool(true))
  }
  check("managed projection corruption is detected and repair reads only canonical versions") {
    let book = try Workbook.create(
      at: root.appendingPathComponent("NativeRebuild.sevra"), title: "Repair")
    let source = try book.addItem(category: "source", kind: "note", title: "Original")
    let table = try book.createDataset(
      title: "Values", columns: [.init(id: "n", title: "N")],
      rows: [["n": .string("0012")], ["n": .string("14")]], sourceID: source.id)
    let original = try book.rows(table.id)
    let schema = try book.db.managedSchema(table.id)
    let raw = try Database(book.url.appendingPathComponent("workbook.sqlite"))
    try raw.execute(
      "UPDATE " + ChangeFormat.quote(schema.table) + " SET " + ChangeFormat.quote(schema.field("n"))
        + "='corrupt'")
    try refuses("managed_projection") { _ = try book.verify() }
    let revision = try book.revision()
    try book.rebuildDataset(table.id, expectedRevision: revision, token: "rebuild")
    try refuses("idempotency") {
      try book.rebuildDataset(table.id, expectedRevision: revision + 1, token: "rebuild")
    }
    try expect(try book.rows(table.id) == original)
    try book.rebuildDataset(table.id, expectedRevision: revision, token: "rebuild")
    try refuses("idempotency") {
      try book.rebuildDataset("another", expectedRevision: revision, token: "rebuild")
    }
    try expect(try book.verify()["ok"] == .bool(true))
    // A typed projection reset discards damaged projection bytes, not history.
    let replay = try book.reconstruct(to: root.appendingPathComponent("CorruptionReplay.sevra"))
    try expect(try replay.rows(table.id) == original)
  }
  check("managed schema and rebuild history replay into fresh storage without adapters") {
    let book = try Workbook.create(
      at: root.appendingPathComponent("NativeReplay.sevra"), title: "Replay")
    let source = try book.addItem(category: "source", kind: "note", title: "Original")
    let table = try book.createDataset(
      title: "Values", columns: [.init(id: "n", title: "N")],
      rows: [["n": .string("0012")], ["n": .string("14")]], sourceID: source.id)
    try book.setColumns(
      table.id,
      columns: [.init(id: "n", title: "Amount", type: "decimal"), .init(id: "note", title: "Note")])
    try book.setColumns(
      table.id,
      columns: [
        .init(id: "n", title: "Amount", type: "decimal"),
        .init(id: "note", title: "Double", type: "decimal", formula: "n*2"),
      ])
    try book.restoreColumns(table.id, version: 1)
    let original = try book.rows(table.id)
    try book.rebuildDataset(table.id, expectedRevision: book.revision())
    let rebuilt = try book.reconstruct(to: root.appendingPathComponent("NativeReplayed.sevra"))
    try expect(
      try rebuilt.rows(table.id) == original
        && rebuilt.columnHistory(table.id) == book.columnHistory(table.id))
    try expect(try rebuilt.db.authorityDigest() == book.db.authorityDigest())
    try expect(try rebuilt.verify()["ok"] == .bool(true))
  }
  check("managed width uses fragmented capture and rejects over-wide definitions atomically") {
    let book = try Workbook.create(
      at: root.appendingPathComponent("NativeWide.sevra"), title: "Wide")
    let source = try book.addItem(category: "source", kind: "note", title: "Original")
    let columns = (0..<500).map { Column(id: "c\($0)", title: "Column \($0)") }
    let values = Dictionary(
      uniqueKeysWithValues: columns.map { ($0.id, Value.string($0.id + "\0value")) })
    let table = try book.createDataset(
      title: "Wide", columns: columns, rows: [values], sourceID: source.id)
    try expect(try book.rows(table.id)[0].data == .object(values))
    let rebuilt = try book.reconstruct(to: root.appendingPathComponent("WideReplayed.sevra"))
    try expect(try rebuilt.rows(table.id)[0].data == .object(values))
    let count = try book.committedHistory().count
    try refuses("columns") {
      _ = try book.createDataset(
        title: "Too wide", columns: columns + [.init(id: "extra", title: "Extra")], rows: [],
        sourceID: source.id)
    }
    try expect(try book.committedHistory().count == count && book.datasets().count == 1)
  }
  check("managed registry rejects unregistered schema and malicious field definitions") {
    let book = try Workbook.create(
      at: root.appendingPathComponent("NativeGuard.sevra"), title: "Guard")
    let source = try book.addItem(category: "source", kind: "note", title: "Original")
    let raw = try Database(book.url.appendingPathComponent("workbook.sqlite"))
    try raw.script("CREATE TABLE sevra_data_unregistered(value TEXT)")
    try refuses("schema") { _ = try Workbook(book.url) }
    try refuses("schema") {
      _ = try book.addItem(category: "source", kind: "note", title: "Cannot bypass")
    }
    try raw.script("DROP TABLE sevra_data_unregistered")
    for id in ["_sevra_row", "a\";DROP TABLE items;--", "nul\0id"] {
      try refuses("columns") {
        _ = try book.createDataset(
          title: "Unsafe", columns: [.init(id: id, title: "Unsafe")], rows: [], sourceID: source.id)
      }
    }
    try expect(try book.datasets().isEmpty)
    let table = try book.createDataset(
      title: "Safe", columns: [.init(id: "n", title: "N")], rows: [], sourceID: source.id)
    let schema = try book.db.managedSchema(table.id)
    try raw.script(
      "CREATE INDEX unexpected ON " + ChangeFormat.quote(schema.table) + "(_sevra_ordinal)")
    try refuses("schema") { _ = try Workbook(book.url) }
  }
  check(
    "managed table creation, projection write and publication faults roll back with their schemas"
  ) {
    let book = try Workbook.create(
      at: root.appendingPathComponent("NativeFault.sevra"), title: "Fault")
    let source = try book.addItem(category: "source", kind: "note", title: "Original")
    let count = try book.committedHistory().count
    _ = try faultSQL(
      book,
      "CREATE TRIGGER fail_dataset BEFORE INSERT ON committed_changes BEGIN SELECT RAISE(ABORT,'publication'); END;"
    )
    try refuses("database") {
      _ = try book.createDataset(
        title: "Values", columns: [.init(id: "n", title: "N")], rows: [["n": .string("1")]],
        sourceID: source.id, token: "create")
    }
    try expect(try book.datasets().isEmpty && book.committedHistory().count == count)
    try expect(
      try book.db.execute(
        "SELECT name FROM sqlite_master WHERE type='table' AND name LIKE 'sevra_data_%'"
      ).isEmpty)
    _ = try faultSQL(book, "DROP TRIGGER fail_dataset;")
    let table = try book.createDataset(
      title: "Values", columns: [.init(id: "n", title: "N")], rows: [["n": .string("1")]],
      sourceID: source.id, token: "create")
    try expect(
      try book.createDataset(
        title: "Values", columns: table.columns, rows: [["n": .string("1")]], sourceID: source.id,
        token: "create"
      ).id == table.id)
    let schema = try book.db.managedSchema(table.id)
    _ = try faultSQL(
      book,
      "CREATE TRIGGER fail_projection BEFORE UPDATE ON " + ChangeFormat.quote(schema.table)
        + " BEGIN SELECT RAISE(ABORT,'projection'); END;")
    let before = try book.rows(table.id)[0]
    try refuses("database") {
      _ = try book.editRow(before.id, values: ["n": .string("2")], token: "edit")
    }
    try expect(try book.rows(table.id)[0] == before && book.item(before.logicalID).id == before.id)
    _ = try faultSQL(book, "DROP TRIGGER fail_projection;")
    _ = try book.editRow(before.id, values: ["n": .string("2")], token: "edit")
    try expect(try book.rows(table.id)[0].data["n"].text == "2")
    try expect(try book.verify()["ok"] == .bool(true))
  }
  check("managed physical shape failure restores the previous schema and capture path") {
    let book = try Workbook.create(
      at: root.appendingPathComponent("NativeShapeFault.sevra"), title: "Shape")
    let source = try book.addItem(category: "source", kind: "note", title: "Original")
    let table = try book.createDataset(
      title: "Values", columns: [.init(id: "n", title: "N")], rows: [["n": .string("1")]],
      sourceID: source.id)
    let before = try book.db.authorityDigest()
    _ = try faultSQL(
      book,
      "CREATE TRIGGER shape_fault BEFORE INSERT ON committed_changes BEGIN SELECT RAISE(ABORT,'shape rollback'); END;"
    )
    try refuses("database") {
      try book.setColumns(
        table.id,
        columns: [.init(id: "n", title: "N", type: "decimal"), .init(id: "more", title: "More")])
    }
    try expect(
      try book.db.authorityDigest() == before && book.dataset(table.id).columns == table.columns)
    _ = try faultSQL(book, "DROP TRIGGER shape_fault;")
    try book.setColumns(
      table.id,
      columns: [.init(id: "n", title: "N", type: "decimal"), .init(id: "more", title: "More")])
    let row = try book.rows(table.id)[0]
    _ = try book.editRow(row.id, values: ["n": .string("2"), "more": .string("valid")])
    let reconstructed = try book.reconstruct(to: root.appendingPathComponent("ShapeReplayed.sevra"))
    try expect(try reconstructed.rows(table.id) == book.rows(table.id))
  }
  check("native table actors stay human and model-attributed edits require accepted rules") {
    let book = try Workbook.create(
      at: root.appendingPathComponent("NativeTableActors.sevra"), title: "Actors")
    let source = try book.addItem(category: "source", kind: "note", title: "Original")
    let table = try book.createDataset(
      title: "Values", columns: [.init(id: "n", title: "N")], rows: [["n": .string("1")]],
      sourceID: source.id)
    let row = try book.rows(table.id)[0]
    let actor = ChangeActor.human("Sevra native table editor")
    let change = try book.editRows(
      table.id, edits: [.init(id: row.id, values: ["n": .string("2")])], token: "native-edit",
      actor: actor)
    try expect(try book.committedHistory()[0]["actor"]["kind"].text == "human")
    try refuses("idempotency") {
      _ = try book.editRows(
        table.id, edits: [.init(id: row.id, values: ["n": .string("2")])], token: "native-edit")
    }
    _ = try book.undoTableChange(change.id, actor: .human("Sevra native table history"))
    try expect(try book.committedHistory()[0]["actor"]["kind"].text == "human")
    let current = try book.rows(table.id)[0]
    try refuses {
      _ = try ChangeAttribution.$actor.withValue(
        .ai("fixture", model: "local-model", policy: source.id)
      ) {
        try book.editRow(current.id, values: ["n": .string("3")])
      }
    }
    try expect(try book.rows(table.id)[0].id == current.id)
    let replay = try book.reconstruct(to: root.appendingPathComponent("TableActorsReplayed.sevra"))
    try expect(try replay.committedHistory() == book.committedHistory())
  }
  check("managed repair refuses missing schema authority before publishing a reset") {
    let book = try Workbook.create(
      at: root.appendingPathComponent("NativeMissingSchema.sevra"), title: "Missing")
    let source = try book.addItem(category: "source", kind: "note", title: "Original")
    let table = try book.createDataset(
      title: "Values", columns: [.init(id: "n", title: "N")], rows: [["n": .string("1")]],
      sourceID: source.id)
    let before = try book.rows(table.id)
    let commits = try book.committedHistory()
    let raw = try Database(book.url.appendingPathComponent("workbook.sqlite"))
    try raw.execute("DELETE FROM column_versions WHERE dataset_id=?", [.string(table.id)])
    try refuses("managed_schema") { _ = try book.verify() }
    try refuses("managed_schema") {
      try book.rebuildDataset(table.id, expectedRevision: book.revision())
    }
    try expect(try book.rows(table.id) == before && book.committedHistory() == commits)
  }
  check("managed capture budget refusal leaves no partial canonical or native values") {
    let book = try Workbook.create(
      at: root.appendingPathComponent("NativeCaptureLimit.sevra"), title: "Limit")
    let source = try book.addItem(category: "source", kind: "note", title: "Original")
    let table = try book.createDataset(
      title: "Values", columns: [.init(id: "n", title: "N")], rows: [["n": .string("1")]],
      sourceID: source.id)
    let before = try book.db.authorityDigest()
    let row = try book.rows(table.id)[0]
    try refuses("change_limit") {
      _ = try book.mutation("forced_capture_limit") {
        book.db.changes?.bytes = 67_108_863
        return try book.applyRows(
          table.id, edits: [.init(id: row.id, values: ["n": .string("2")])], request: .null)
      }
    }
    try expect(try book.db.authorityDigest() == before)
    _ = try book.editRow(row.id, values: ["n": .string("2")])
    try expect(try book.verify()["ok"] == .bool(true))
  }
  check("an already open connection captures another writer's new managed schema") {
    let book = try Workbook.create(
      at: root.appendingPathComponent("NativeWriters.sevra"), title: "Writers")
    let other = try Workbook(book.url)
    let source = try book.addItem(category: "source", kind: "note", title: "Original")
    let table = try book.createDataset(
      title: "Values", columns: [.init(id: "n", title: "N")], rows: [["n": .string("1")]],
      sourceID: source.id)
    let row = try other.rows(table.id)[0]
    _ = try other.editRow(row.id, values: ["n": .string("2")])
    try book.setColumns(
      table.id,
      columns: [.init(id: "n", title: "N", type: "decimal"), .init(id: "more", title: "More")])
    let current = try other.rows(table.id)[0]
    _ = try other.editRow(current.id, values: ["n": .string("3"), "more": .string("new column")])
    let rebuilt = try other.reconstruct(to: root.appendingPathComponent("WritersReplayed.sevra"))
    try expect(try rebuilt.rows(table.id) == other.rows(table.id))
  }
}
