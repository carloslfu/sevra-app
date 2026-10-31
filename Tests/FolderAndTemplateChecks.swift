import CoreMedia
import Foundation
import Speech

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
  check("a transcript keeps each word, its punctuation and its real time") {
    guard #available(macOS 26.0, *) else { return }
    func run(_ text: String, _ start: Double?) -> AttributedString {
      var piece = AttributedString(text)
      if let start {
        piece.audioTimeRange = CMTimeRange(
          start: CMTime(seconds: start, preferredTimescale: 600),
          duration: CMTime(seconds: 0.5, preferredTimescale: 600))
      }
      return piece
    }
    // The transcriber puts the space before a word in the word's run, and a pause changes nothing.
    var text = run("We", 0) + run(" agreed", 0.5) + run(" ", nil) + run(" Monday.", 31.2)
    text += run(" Late", nil)
    let words = FileTranscriber.words(text, after: 0)
    try expect(words.map(\.text) == ["We", "agreed", "Monday.", "Late"])
    try expect(words.map(\.start) == [0, 0.5, 31.2, 31.7] && words[2].end == 31.7)
    // A later result carries on from the time already heard, and a time with no value never lands.
    try expect(FileTranscriber.words(run("more", nil), after: 40).first?.start == 40)
    var broken = AttributedString("still")
    broken.audioTimeRange = CMTimeRange(start: .indefinite, duration: .indefinite)
    try expect(FileTranscriber.words(broken, after: 12).first == SpokenWord(text: "still", start: 12, end: 12))
    let chunks = FileTranscriber.chunks(
      (0..<25).map { SpokenWord(text: "w\($0)", start: Double($0), end: Double($0) + 0.4) })
    try expect(chunks.count == 2 && chunks[1].text == "w24")
    try expect(chunks[1].locator == "time=24.0; end=24.4")
    // A sentence ends a chunk once it has a dozen words, and a short one runs on.
    let sentences = FileTranscriber.chunks(
      (0..<30).map {
        SpokenWord(text: [2, 13, 29].contains($0) ? "w\($0)." : "w\($0)", start: 0, end: 0)
      })
    try expect(sentences.map { $0.text.split(separator: " ").count } == [14, 16])
  }
  check("Stop returns from system work that ignores it") {
    let stop = Cancellation()
    let stopped = DispatchSemaphore(value: 0)
    Task {
      do {
        try await FileTranscriber.waiting(within: stop) { Thread.sleep(forTimeInterval: 4) }
      } catch { if (error as? SevraError)?.code == "cancelled" { stopped.signal() } }
    }
    DispatchQueue.global().asyncAfter(deadline: .now() + 0.2) { stop.cancel() }
    try expect(stopped.wait(timeout: .now() + 2) == .success)
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
    // Beside its original a copy says so, and importing it again changes nothing.
    let beside = try original.importTemplate(file)
    try expect(beside.id != automation.id && beside.title == "Monday count (imported)")
    try expect(try original.importTemplate(file).id == beside.id)
    let other = root.appendingPathComponent("Other.json")
    try Data("{\"format\":\"something\"}".utf8).write(to: other)
    try refuses("template_file") { _ = try copy.importTemplate(other) }
  }
}
