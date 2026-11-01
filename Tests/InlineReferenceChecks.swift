import Foundation
import SevraCore

private func parsedLabels(_ text: String) throws -> [String] {
  let scalars = Array(text.unicodeScalars)
  return try InlineReferenceParser.parse(text).selections.map {
    String(String.UnicodeScalarView(scalars[$0.startScalar..<($0.startScalar + $0.scalarCount)]))
  }
}

/// Worker threads get 512 KiB, where a few hundred nested levels used to end the process.
private func onWorkerStack(_ body: @escaping () throws -> Void) throws {
  var failure: Error?
  let finished = DispatchSemaphore(value: 0)
  let thread = Thread {
    do { try body() } catch { failure = error }
    finished.signal()
  }
  thread.stackSize = 512 * 1024
  thread.start()
  finished.wait()
  if let failure { throw failure }
}

func checkInlineReferences(at root: URL) {
  check("shared parser preserves exact Unicode spans and resolves only explicit stable routes") {
    let body =
      "👩🏽‍💻 Cafe\u{301}\r\n[[ Supplier quote | Cafe\u{301} ]] and [**exact**](sevra://item/version-1)\r\n[Live][ref]\r\n\r\n[ref]: sevra://logical/logical-1\r\n\r\n<sevra://workbook/foreign/item/exact-2>"
    let parsed = try InlineReferenceParser.parse(body)
    try expect(
      parsed.state == "ready" && parsed.selections.count == 4,
      "state=\(parsed.state), labels=\(try parsedLabels(body))")
    try expect(
      try parsedLabels(body) == [
        "Cafe\u{301}", "**exact**", "Live", "sevra://workbook/foreign/item/exact-2",
      ])
    try expect(
      parsed.selections[0].target == nil && parsed.selections[0].lookup == "Supplier quote")
    try expect(parsed.selections[1].target == .init(mode: .pinned, identity: "version-1"))
    try expect(parsed.selections[2].target == .init(mode: .live, identity: "logical-1"))
    try expect(
      parsed.selections[3].target
        == .init(mode: .pinned, identity: "exact-2", workbookID: "foreign"))
    // A NUL is retained in the original body. Its replacement in the Markdown
    // parse must not shift byte/scalar coordinates for the next real link.
    try expect(
      try parsedLabels("prefix\0 [[real|label]] [pin](sevra://item/pin)") == ["label", "pin"],
      "NUL labels=\(try parsedLabels("prefix\0 [[real|label]] [pin](sevra://item/pin)"))")
  }
  check("hostile nesting is refused on a worker stack and ordinary Markdown keeps its links") {
    let steps = (0..<400).map { String(repeating: " ", count: $0 * 2) + "- a" }
    let hostile = [
      "[[x]] " + String(repeating: "*a ", count: 1000) + "b"
        + String(repeating: " c*", count: 1000),
      "[[x]] " + String(repeating: "![", count: 1000) + "a"
        + String(repeating: "](b)", count: 1000),
      // Closers inside code spans must not cancel the openers they follow.
      "[[x]] " + String(repeating: "*a `b*` ", count: 400) + "c"
        + String(repeating: " d*", count: 400),
      "a\r" + String(repeating: ">", count: 2000) + " [[x]]",
      "\u{FEFF}" + String(repeating: ">", count: 2000) + " [[x]]",
      steps.joined(separator: "\n") + "\n[[x]]",
    ]
    let deepest =
      (0..<49).map { String(repeating: " ", count: $0 * 2) + "- a" }.joined(separator: "\n")
      + "\n" + String(repeating: " ", count: 98) + "- [[x]] "
      + String(repeating: "*a ", count: 100) + "b" + String(repeating: " c*", count: 100)
    try onWorkerStack {
      for text in hostile {
        let parsed = try InlineReferenceParser.parse(text)
        try expect(parsed.state == "partial" && parsed.selections.isEmpty, String(text.prefix(40)))
      }
      try expect(try InlineReferenceParser.parse(deepest).selections.count == 1)
    }
    let bold = (0..<300).map { "- **Item \($0)** text" }.joined(separator: "\n")
    let ruled = [String(repeating: "-", count: 120), String(repeating: "*", count: 120)]
    for text in ruled + [bold, "a\r\n\r\n> [[real]]"] {
      try expect(try InlineReferenceParser.parse(text + "\n\n[[last]]").state == "ready", text)
    }
    try expect(try parsedLabels(ruled[0] + "\n\n[[Quote]]") == ["Quote"])
  }
  check("Markdown positions name the right bytes or the parse says it is partial") {
    let link = "[b](sevra://item/pin)"
    // cmark numbers these lines from the first line's column.
    for body in [
      "Intro\n    [a] \(link)", "  First\n\(link)", "- item\n      \(link)",
      "> quote\n\(link)", "Title\n  \(link)\n=====",
    ] {
      try expect(try parsedLabels(body) == ["b"], body)
    }
    try expect(try parsedLabels("   First\n`[[code]]` [[real]]") == ["real"])
    // A backslash break leaves cmark on the wrong line. Nothing is bound to other bytes.
    let broken = try InlineReferenceParser.parse("a\\\n  \(link) [[real]]")
    try expect(broken.state == "partial" && broken.selections.isEmpty)
    // Only a whole definition is ambiguous. Bracketed text before a colon is a paragraph.
    try expect(
      try parsedLabels("[[Acme Quote]]: 30 days net\n\n[[Other]] \(link)")
        == ["Acme Quote", "Other", "b"])
    try expect(try parsedLabels("[Note] see [Other]: thing and [[Real]]") == ["Real"])
    // A bracket in a label's code span is not the end of the label.
    try expect(try parsedLabels("[a `]` b](sevra://item/pin)") == ["a `]` b"])
    try expect(try parsedLabels("[a [b] c](sevra://item/pin)") == ["a [b] c"])
    // Tags are matched by whole name, a self-closed tag hides nothing, and a closer may be spaced.
    for body in ["a <premium> [[real]]", "<code>x</code > [[real]]", "<code/> [[real]]"] {
      try expect(try parsedLabels(body) == ["real"], body)
    }
    try expect(try parsedLabels("a <pre lang=\"x\">[[code]]</pre> [[real]]") == ["real"])
  }
  check("links in escaped syntax, code, images and HTML code remain plain examples") {
    let body = #"""
      \[[escaped]] `[[inline]]` ![[image]](photo.png)
      ```markdown
      [[fenced]] [pin](sevra://item/example)
      ```
      ~~~
      [[tilde]]
      ~~~

          [[indented]]

      > - `[[quoted code]]`
      text <code>[[html code]] [pin](sevra://item/hidden)</code> after

      <div>
      [[html block]]
      </div>

      [[real]] and [web [[not a wiki]]](https://example.com) and [label](sevra://item/exact)
      """#
    try expect(try parsedLabels(body) == ["real", "label"])
    try expect(try parsedLabels(#"\\[[even]] \[[odd]] [[real]]"#) == ["even", "real"])
    try expect(try parsedLabels("`[[open]]\n[[plain]]") == ["open", "plain"])
  }
  check("unsafe routes and malformed tokens cannot become local or external bindings") {
    try expect(try parsedLabels("[[outer [[inner]] [[real]]") == ["real"])
    for next in ["<sevra://item/pin>", "`[[code]]`", "[[a]] [pin](sevra://item/pin)"] {
      let parsed = try InlineReferenceParser.parse("[ref]: sevra://item/ref\n" + next)
      try expect(
        parsed.state == "partial" && parsed.selections.isEmpty,
        "Ambiguous cmark locations must fail closed.")
    }
    for route in [
      "sevra://item/x?y=z", "sevra://item/x#part", "sevra://item/%2e", "sevra://item/../x",
      "sevra://item/x/", "sevra://item:80/x", "sevra://user@item/x", "file:///tmp/x",
      "sevra://workbook//item/x",
    ] {
      try expect(InlineReferenceParser.target(route) == nil, route)
    }
    let body =
      "[[unclosed\n[[a|b|c]] [[sevra://item/x?bad|unsafe]] [bad](sevra://item/x#bad) [[good|yes]]"
    let parsed = try InlineReferenceParser.parse(body)
    try expect(parsed.state == "partial" && parsed.unsupportedTokens >= 3)
    try expect(try parsedLabels(body) == ["yes"])
    try expect(
      InlineReferenceParser.target("SEVRA://ITEM/Mixed-Case")
        == .init(mode: .pinned, identity: "Mixed-Case"))
  }
  check("parser bounds, cancellation and unsupported bodies report incomplete coverage") {
    let structural = try InlineReferenceParser.parse(
      String(repeating: "[x](https://example.com) ", count: 26_000))
    try expect(structural.state == "partial" && structural.selections.isEmpty)
    let parsed = try InlineReferenceParser.parse(
      (0..<130).map { "[[name-\($0)]]" }.joined(separator: " "))
    try expect(parsed.state == "partial" && parsed.selections.count == 128)
    try expect(
      try InlineReferenceParser.parse("[[" + String(repeating: "é", count: 600) + "]]").state
        == "partial")
    try expect(
      try InlineReferenceParser.parse(String(repeating: "x", count: 1_000_001)).state
        == "unsupported")
    let cancelled = Cancellation()
    cancelled.cancel()
    try refuses("cancelled") {
      _ = try InlineReferenceParser.parse("[[link]]", cancellation: cancelled)
    }
  }
  check(
    "automatic links are atomic, unresolved names never rebind, and rebuild preserves snapshots"
  ) {
    let book = try Workbook.create(
      at: root.appendingPathComponent("ParsedReferences.sevra"), title: "Parsed")
    let target = try book.addItem(category: "source", kind: "observation", title: "Quote")
    let origin = try book.addItem(
      category: "source", kind: "observation", title: "Notes",
      text: "[[Later]] [quote](sevra://item/\(target.id)) [[sevra://item/missing|absent]]")
    let saved = try book.referenceSnapshot(origin.id)
    try expect(saved.coverage == "ready" && saved.references.count == 3)
    try expect(
      saved.references[0].resolution == .unresolved && saved.references[1].resolution == .bound
        && saved.references[2].resolution == .unresolved)
    _ = try book.addItem(category: "source", kind: "observation", title: "Later")
    try book.rebuildReferenceIndex()
    try expect(try book.referenceSnapshot(origin.id) == saved)
    try expect(try book.indexReferences(origin.id) == saved)
    let before = try book.counts()
    try expect(try book.referenceLinks(origin.id)["hits"].array.count == 3)
    try expectTechnicalReference(book, origin: origin.id, annotation: saved.sourceID!)
    try expect(try book.counts() == before)
    try expect(try book.verify()["ok"] == .bool(true))
  }
  check("indexed backlinks deduplicate exact origins and preserve live versus pinned history") {
    let book = try Workbook.create(
      at: root.appendingPathComponent("Backlinks.sevra"), title: "Links")
    let old = try book.addItem(category: "source", kind: "observation", title: "Old")
    let text =
      "[live](sevra://logical/\(old.logicalID)) [pin](sevra://item/\(old.id)) [again](sevra://item/\(old.id))"
    let note = try book.addItem(category: "source", kind: "observation", title: "Note", text: text)
    let outgoing = try book.referenceLinks(note.id)
    try expect(
      outgoing["hits"].array.count == 1 && outgoing["hits"].array[0]["mentionCount"].int == 3)
    let new = try book.addItem(
      category: "source", kind: "observation", title: "New", text: "Revised", supersedes: old.id)
    try expect(try book.referenceLinks(note.id)["hits"].array.count == 2)
    try expect(
      try book.referenceLinks(old.id, direction: .incoming, targetScope: .exact)["hits"].array[0][
        "mentionCount"
      ].int == 2)
    try expect(
      try book.referenceLinks(new.id, direction: .incoming, targetScope: .exact)["hits"].array[0][
        "mentionCount"
      ].int == 1)
    try expect(
      try book.referenceLinks(new.id, direction: .incoming)["hits"].array[0]["mentionCount"].int
        == 3)
    let revisedNote = try book.addItem(
      category: "source", kind: "observation", title: "No links", text: "None", supersedes: note.id)
    try expect(try book.referenceLinks(new.id, direction: .incoming)["hits"].array.isEmpty)
    try expect(
      try book.referenceLinks(new.id, direction: .incoming, historicalOrigins: true)["hits"].array
        .count == 1)
    try expect(try book.referenceSnapshot(revisedNote.id).coverage == "ready")
    try expect(try book.verify()["ok"] == .bool(true))
  }
  check("backlink keyset pages are bounded, filtered, cancellable and revision bound") {
    let book = try Workbook.create(
      at: root.appendingPathComponent("FanoutReferences.sevra"), title: "Fanout")
    let target = try book.addItem(category: "source", kind: "observation", title: "Target")
    let text = "[one](sevra://item/\(target.id)) [two](sevra://item/\(target.id))"
    var expected: Set<String> = []
    for index in 0..<260 {
      let origin = try book.addItem(
        category: "source", kind: "observation", title: "Origin \(index)", text: text,
        meaning: index % 2 == 0 ? "actual" : "estimate",
        status: index % 2 == 0 ? "accepted" : "draft", scenario: index % 2 == 0 ? "actual" : "plan")
      if index % 2 == 0 { expected.insert(origin.id) }
    }
    var seen: Set<String> = []
    var cursor: String?
    repeat {
      let page = try book.referenceLinks(
        target.id, direction: .incoming, kind: "observation", meaning: "actual", status: "accepted",
        scenario: "actual", limit: 17, cursor: cursor)
      try expect(page["hits"].array.count <= 17)
      for hit in page["hits"].array {
        try expect(seen.insert(hit["evidence"]["id"].text).inserted && hit["mentionCount"].int == 2)
        try expect(hit["evidence"]["body"] == .null)
      }
      cursor = page["nextCursor"].string
      _ = try book.addMessage("A receipt-safe intervening message", role: "user")
    } while cursor != nil
    try expect(seen == expected)
    let first = try book.referenceLinks(target.id, direction: .incoming, limit: 1)
    _ = try book.addItem(category: "source", kind: "observation", title: "Changed")
    try refuses("stale_cursor") {
      _ = try book.referenceLinks(
        target.id, direction: .incoming, limit: 1, cursor: first["nextCursor"].string)
    }
    let cancelled = Cancellation()
    cancelled.cancel()
    try refuses("cancelled") {
      _ = try book.referenceLinks(target.id, direction: .incoming, cancellation: cancelled)
    }
    try refuses("deadline") {
      _ = try book.referenceLinks(target.id, direction: .incoming, deadlineSeconds: 0)
    }
    try refuses("reference_limit") { _ = try book.referenceLinks(target.id, limit: 51) }
    try expect(try book.verify()["ok"] == .bool(true))
  }
  check("outgoing pages deduplicate targets, retain external hints and invalidate changed filters")
  {
    let book = try Workbook.create(
      at: root.appendingPathComponent("OutgoingReferences.sevra"), title: "Outgoing")
    var targets: [Item] = []
    for index in 0..<7 {
      targets.append(
        try book.addItem(category: "source", kind: "observation", title: "Target \(index)"))
    }
    let text =
      targets.map { "[one](sevra://item/\($0.id)) [two](sevra://logical/\($0.logicalID))" }.joined(
        separator: " ")
      + " [[Missing]] [[Missing|Alias]] [external](sevra://workbook/elsewhere/item/foreign)"
    let origin = try book.addItem(
      category: "source", kind: "observation", title: "Origin", text: text)
    var cursor: String?
    var seen: Set<String> = []
    var all: [Value] = []
    repeat {
      let page = try book.referenceLinks(origin.id, limit: 2, cursor: cursor)
      all += page["hits"].array
      for hit in page["hits"].array where hit["evidence"] != .null {
        try expect(seen.insert(hit["evidence"]["id"].text).inserted && hit["mentionCount"].int == 2)
      }
      cursor = page["nextCursor"].string
    } while cursor != nil
    try expect(seen == Set(targets.map(\.id)) && all.count == 9)
    try expect(all.filter { $0["resolution"].text == "unresolved" }.first?["mentionCount"].int == 2)
    try expect(try book.referenceLinks(origin.id, kind: "observation")["hits"].array.count == 7)
    let first = try book.referenceLinks(origin.id, limit: 1)
    try refuses("stale_cursor") {
      _ = try book.referenceLinks(
        origin.id, kind: "observation", limit: 1, cursor: first["nextCursor"].string)
    }
    let archive = root.appendingPathComponent("Outgoing.sevraz")
    try book.export(to: archive)
    let opened = try Workbook.openArchive(
      archive, at: root.appendingPathComponent("OutgoingOpened.sevra"))
    try opened.rebuildReferenceIndex()
    try expect(try opened.referenceSnapshot(origin.id) == book.referenceSnapshot(origin.id))
    try expect(
      try opened.referenceLinks(origin.id)["hits"] == book.referenceLinks(origin.id)["hits"])
    try expect(try opened.verify()["ok"] == .bool(true))
  }
}
