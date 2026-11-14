import Foundation

@testable import SevraCore

func checkCorruptMetadata(at root: URL) {
  check("corrupt stored layouts reject duplicate identities and excessive nesting before rendering")
  {
    let book = try Workbook.create(
      at: root.appendingPathComponent("Layouts.sevra"), title: "Layouts")
    let raw = try Database(book.url.appendingPathComponent("workbook.sqlite"))
    let original = try raw.scalar("SELECT definition FROM spaces WHERE id='home'").text
    let duplicate = Component(id: "duplicate", type: "text", title: "Duplicate")
    var nested = Component(id: "deep", type: "text", title: "Deep")
    for index in 0..<4 {
      nested = Component(
        id: "group\(index)", type: "comparison", title: "Group", children: [nested])
    }
    for definition in [
      SpaceDefinition(components: [duplicate, duplicate]),
      SpaceDefinition(components: [nested]),
      SpaceDefinition(
        components: (0..<17).map { Component(id: "n\($0)", type: "text", title: "Text") }),
    ] {
      try raw.execute(
        "UPDATE spaces SET definition=? WHERE id='home'", [.string(try encoded(definition).json())])
      try refuses("integrity") { _ = try book.space("home") }
      try refuses("integrity") { _ = try book.spaces() }
    }
    try raw.execute("UPDATE spaces SET definition=? WHERE id='home'", [.string(original)])
    try expect(try book.space("home").definition == .defaultHome)
  }
  check("corrupt export sizes refuse instead of overflowing or publishing an archive") {
    let book = try Workbook.create(at: root.appendingPathComponent("Sizes.sevra"), title: "Sizes")
    let file = root.appendingPathComponent("size-source.txt")
    try Data("Synthetic size probe".utf8).write(to: file)
    _ = try book.importFile(file)
    _ = try book.importFile(file)
    let raw = try Database(book.url.appendingPathComponent("workbook.sqlite"))
    let destination = root.appendingPathComponent("Sizes.sevraz")
    // Sum overflow, same-volume snapshot+archive overflow, and negative metadata.
    for bytes in ["8000000000000000000", "3000000000000000000", "-1"] {
      try raw.execute("UPDATE assets SET bytes=CAST(? AS INTEGER)", [.string(bytes)])
      try refuses("export_size") { try book.export(to: destination) }
      try expect(!FileManager.default.fileExists(atPath: destination.path))
    }
  }
  check("corrupt revision metadata refuses writes without trapping or silently resetting") {
    let book = try Workbook.create(
      at: root.appendingPathComponent("Revision.sevra"), title: "Revision")
    let raw = try Database(book.url.appendingPathComponent("workbook.sqlite"))
    for revision in ["9223372036854775807", "9007199254740992", "-1", "1.5", "invalid", "01"] {
      try raw.execute("UPDATE meta SET value=? WHERE key='revision'", [.string(revision)])
      try refuses("integrity") { _ = try book.revision() }
      try refuses("integrity") {
        _ = try book.addItem(category: "source", kind: "note", title: "Must refuse")
      }
      try expect(try raw.scalar("SELECT count(*) FROM items").int == 0)
    }
    try raw.execute("UPDATE meta SET value='9007199254740990' WHERE key='revision'")
    _ = try book.addItem(category: "source", kind: "note", title: "Last exact revision")
    try expect(try book.revision() == 9_007_199_254_740_991)
    try refuses("integrity") {
      _ = try book.addItem(category: "source", kind: "note", title: "Cannot advance past limit")
    }
    try expect(try raw.scalar("SELECT count(*) FROM items").int == 1)
    try raw.execute("UPDATE meta SET value='0' WHERE key='revision'")
    _ = try book.addItem(category: "source", kind: "note", title: "Valid counterexample")
    try expect(try book.revision() == 1)
  }
}
