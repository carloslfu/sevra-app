import Foundation

@testable import SevraCore

func checkFoldersAndTemplates(at root: URL) {
  check("a folder pass adds each file once, keeps earlier originals and deletes nothing") {
    let folder = root.appendingPathComponent("Quotes")
    let files = FileManager.default
    try files.createDirectory(
      at: folder.appendingPathComponent("2026"), withIntermediateDirectories: true)
    func write(_ name: String, _ text: String) throws {
      try Data(text.utf8).write(to: folder.appendingPathComponent(name))
    }
    try write("a.txt", "Atlas quote")
    try write("2026/b.txt", "Brio quote")
    try write(".DS_Store", "hidden")
    let book = try Workbook.create(
      at: root.appendingPathComponent("Folder.sevra"), title: "Folder")
    func add(_ plan: FolderPlan) throws {
      for file in plan.files {
        let job = try book.captureIntake(
          folder.appendingPathComponent(file.relative), role: .reference, token: plan.token(file))
        _ = try book.runIntake(job.id)
      }
    }
    func sources() throws -> [String] {
      try book.items().filter { $0.category == "source" && $0.title.hasSuffix(".txt") }
        .map(\.title).sorted()
    }
    let first = try book.folderPlan(folder)
    try expect(first.added.map(\.relative) == ["2026/b.txt", "a.txt"] && first.changed.isEmpty)
    try add(first)
    // Doing it again, or replaying a stopped pass, saves nothing new.
    try add(first)
    try expect(try sources() == ["a.txt", "b.txt"])
    let same = try book.folderPlan(folder)
    try expect(same.files.isEmpty && same.unchanged == 2 && same.missing.isEmpty)
    // A file changes, one leaves, one arrives and one repeats content already saved.
    try write("a.txt", "Atlas quote, corrected")
    try files.removeItem(at: folder.appendingPathComponent("2026/b.txt"))
    try write("c.txt", "Cedar quote")
    try write("copy.txt", "Atlas quote")
    let next = try book.folderPlan(folder)
    try expect(next.changed.map(\.relative) == ["a.txt"])
    try expect(next.added.map(\.relative) == ["c.txt"] && next.unchanged == 1)
    try expect(next.missing == ["2026/b.txt"])
    try expect(next.summary.contains("1 no longer in the folder"))
    try add(next)
    try expect(try sources() == ["a.txt", "a.txt", "b.txt", "c.txt"])
    try expect(try book.verify()["ok"] == .bool(true))
    // Past the bound nothing is planned at all.
    let large = root.appendingPathComponent("Large")
    try files.createDirectory(at: large, withIntermediateDirectories: true)
    for index in 0...Workbook.folderFileLimit {
      try Data("\(index)".utf8).write(to: large.appendingPathComponent("\(index).txt"))
    }
    try refuses("folder_limit") { _ = try book.folderPlan(large) }
  }
  check("longer recordings divide into overlapping parts and keep real timestamps") {
    try expect(FileTranscriber.partStarts(duration: 60) == [0])
    try expect(FileTranscriber.partStarts(duration: 61) == [0, 56])
    try expect(FileTranscriber.partStarts(duration: 170) == [0, 56, 112])
    let starts = FileTranscriber.partStarts(duration: 7200)
    try expect(zip(starts, starts.dropFirst()).allSatisfy { $1 - $0 == 56 })
    try expect(starts.last! + FileTranscriber.partSeconds >= 7200)
    func word(_ text: String, _ start: Double) -> SpokenWord {
      SpokenWord(text: text, start: start, end: start + 0.4)
    }
    // The second part starts 56 seconds in and repeats the word heard at 57.
    let first = [word("alpha", 1), word("beta", 57)]
    let joined = FileTranscriber.joined(first, [word("beta", 1), word("gamma", 3)], offset: 56)
    try expect(joined.map(\.text) == ["alpha", "beta", "gamma"] && joined[2].start == 59)
    // A silent part adds nothing and loses nothing.
    try expect(FileTranscriber.joined(first, [], offset: 56) == first)
    func spoken(_ text: String, _ start: Double, _ end: Double) -> SpokenWord {
      SpokenWord(text: text, start: start, end: end)
    }
    // A real recording lost "order two": the part ended mid-phrase, the recognizer dropped those
    // words and stretched "gasket" across the gap.
    let cut = [
      spoken("delivered", 56.1, 56.45), spoken("the", 56.5, 56.9), spoken("gasket", 56.96, 57.8),
    ]
    let whole = [
      spoken("the", 0.55, 0.85), spoken("gasket", 0.96, 1.3), spoken("order", 1.36, 1.6),
      spoken("two", 1.66, 1.85), spoken("days", 1.9, 2.2), spoken("late", 2.25, 2.6),
    ]
    try expect(
      FileTranscriber.joined(cut, whole, offset: 56).map(\.text)
        == ["delivered", "the", "gasket", "order", "two", "days", "late"])
    // A word across the handover joins once, and later timing that drifts a little changes nothing.
    let earlier = [
      spoken("one", 56.2, 56.7), spoken("word", 56.8, 57.2), spoken("after", 57.3, 57.7),
    ]
    for drift in [-0.1, 0, 0.1] {
      let later = [
        spoken("one", 0.2 + drift, 0.7 + drift), spoken("word", 0.8 + drift, 1.2 + drift),
        spoken("after", 1.3 + drift, 1.7 + drift), spoken("more", 2 + drift, 2.4 + drift),
      ]
      try expect(
        FileTranscriber.joined(earlier, later, offset: 56).map(\.text)
          == ["one", "word", "after", "more"])
    }
    let chunks = FileTranscriber.chunks((0..<25).map { word("w\($0)", Double($0)) })
    try expect(chunks.count == 2 && chunks[1].text == "w24")
    try expect(chunks[1].locator == "time=24.0; end=24.4")
  }
  check("naming a category as a search kind still finds the evidence") {
    let book = try Workbook.create(
      at: root.appendingPathComponent("Kinds.sevra"), title: "Kinds")
    _ = try book.addItem(
      category: "source", kind: "note", title: "Supplier quotes", text: "Atlas sells bolts.")
    func hits(_ kind: String) throws -> Int {
      try WorkbookTools(book).execute(
        "search", .object(["query": .string("Atlas"), "kind": .string(kind)])
      )["hits"].array.count
    }
    try expect(try hits("source") == 1 && hits("Record") == 1 && hits("note") == 1)
    try expect(try hits("movement") == 0)
  }
  check("a job template carries an inert copy to another workbook, once") {
    let original = try Workbook.create(
      at: root.appendingPathComponent("Template.sevra"), title: "Original")
    let function = try original.saveApplicationDefinition(
      logicalID: identifier(),
      content: .object([
        "kind": .string("function"), "title": .string("Count"),
        "description": .string("Synthetic"), "parameters": .array([]),
        "payload": .object(["expression": .string("2*2"), "unit": .string("items")]),
      ]))
    let workflow = try original.saveApplicationDefinition(
      logicalID: identifier(), content: original.workflowTemplate(function.id))
    let automation = try original.saveApplicationDefinition(
      logicalID: identifier(),
      content: .object([
        "kind": .string("automation"), "title": .string("Monday count"),
        "description": .string("Synthetic"), "parameters": .array([]),
        "payload": .object([
          "policy": .string("calendar-drafts-v1"),
          "workflow": .object(["mode": .string("exact"), "versionID": .string(workflow.id)]),
          "arguments": .object([:]),
          "schedule": .object([
            "policy": .string("native-calendar-v1"), "timeZone": .string("America/Bogota"),
            "hour": .number(9), "minute": .number(0),
            "recurrence": .object(["kind": .string("weekly"), "weekdays": .array([.number(1)])]),
          ]),
        ]),
      ]))
    let file = root.appendingPathComponent("Monday template.json")
    try original.exportTemplate(automation.id, to: file)
    let copy = try Workbook.create(
      at: root.appendingPathComponent("Copy.sevra"), title: "Copy")
    let saved = try copy.importTemplate(file)
    try expect(saved.kind == "automation" && saved.title == "Monday count")
    try expect(saved.id != automation.id)
    // Its parts arrive too, and it points at those, not at the original workbook.
    let linked = saved.payload["workflow"]["versionID"].text
    try expect(linked != workflow.id && (try copy.applicationDefinition(linked).kind) == "workflow")
    try expect(try copy.importTemplate(file).id == saved.id)
    try expect(try copy.verify()["ok"] == .bool(true))
    let other = root.appendingPathComponent("Other.json")
    try Data("{\"format\":\"something\"}".utf8).write(to: other)
    try refuses("template_file") { _ = try copy.importTemplate(other) }
  }
}
