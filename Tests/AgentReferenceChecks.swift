import Foundation
import SevraCore

func checkAgentReferences(at root: URL) {
  check("agent reference pages exclude technical targets before pagination and retain exact scope")
  {
    let book = try Workbook.create(
      at: root.appendingPathComponent("AgentLinks.sevra"), title: "Links")
    let secret = try book.addItem(
      category: "source", kind: "request", title: "PRIVATE-REQUEST", text: "SECRET-CONTENT")
    let annotation = try book.addItem(
      category: "source", kind: "annotation", title: "PRIVATE-ANNOTATION", text: "SECRET-CHOICE")
    var targets: [Item] = []
    for index in 0..<17 {
      targets.append(
        try book.addItem(
          category: "source", kind: "note", title: "Target \(index)",
          text: "Original \(index)", meaning: index.isMultiple(of: 2) ? "actual" : "estimate",
          status: "accepted", scenario: index.isMultiple(of: 2) ? "base" : "plan"))
    }
    let foreign = identifier()
    let text =
      ([secret, annotation] + targets).map { "[label](sevra://item/\($0.id))" }.joined(
        separator: " ")
      + " [[Unchosen]] [elsewhere](sevra://workbook/\(foreign)/item/\(targets[0].id))"
    let origin = try book.addItem(category: "source", kind: "note", title: "Overview", text: text)
    let tools = WorkbookTools(book, readOnly: true)
    let owner = try book.referenceLinks(origin.id, limit: 50)
    try expect(owner["hits"].array.count == 21, "Owner navigation lost a saved choice")
    var args: [String: Value] = ["id": .string(origin.id)]
    var ids = Set<String>()
    var unresolved = 0
    var pages = 0
    var firstCursor: String?
    repeat {
      let result = try tools.execute("references", .object(args))
      pages += 1
      try expect(result["hits"].array.count <= 12)
      try expect(result["accessScope"].text == "workbook-business-items")
      let json = try result.json()
      try expect(
        !json.contains("PRIVATE-") && !json.contains(secret.id) && !json.contains(annotation.id))
      try expect(!json.contains(foreign), "A foreign lookup route leaked into local discovery")
      for hit in result["hits"].array {
        try expect(hit["lookup"] == .null)
        if let id = hit["evidence"]["id"].string {
          try expect(ids.insert(id).inserted, "Repeated destination across pages")
        } else {
          unresolved += 1
        }
      }
      if let next = result["nextCursor"].string {
        firstCursor = firstCursor ?? next
        args["cursor"] = .string(next)
      } else {
        break
      }
    } while pages < 5
    try expect(pages == 2 && ids == Set(targets.map(\.id)) && unresolved == 2)
    let filtered = try tools.execute(
      "references",
      .object([
        "id": .string(origin.id), "meaning": .string("actual"), "scenario": .string("base"),
        "status": .string("accepted"), "kind": .string("note"),
      ]))
    try expect(
      Set(filtered["hits"].array.map { $0["evidence"]["id"].text })
        == Set(targets.enumerated().filter { $0.offset.isMultiple(of: 2) }.map { $0.element.id }))
    try refuses("stale_cursor") {
      _ = try book.referenceLinks(origin.id, cursor: firstCursor)
    }
    try refuses("stale_cursor") {
      _ = try tools.execute(
        "references",
        .object([
          "id": .string(origin.id), "cursor": .string(firstCursor!), "status": .string("accepted"),
        ]))
    }
    for hidden in [secret, annotation] {
      try refuses("reference_scope") {
        _ = try tools.execute("references", .object(["id": .string(hidden.id)]))
      }
    }
    try expect(try book.verify()["ok"] == .bool(true))
  }
  check("agent reference options are strict and cancellation leaves evidence unchanged") {
    let book = try Workbook.create(
      at: root.appendingPathComponent("AgentLinkRefusals.sevra"), title: "Bounds")
    let source = try book.addItem(category: "source", kind: "note", title: "Anchor")
    let tools = WorkbookTools(book)
    let before = try book.counts()
    for extra: [String: Value] in [
      ["limit": .number(100)], ["businessOnly": .bool(false)],
      ["historicalOrigins": .string("true")],
      ["direction": .string("both")], ["targetScope": .string("global")],
      ["contentScope": .string("network")],
      ["cursor": .array([])], ["scenario": .object([:])],
    ] {
      var args = extra
      args["id"] = .string(source.id)
      try refuses("arguments") { _ = try tools.execute("references", .object(args)) }
    }
    try refuses {
      _ = try tools.execute(
        "references", .object(["id": .string(source.id), "cursor": .string("bad")]))
    }
    let cancel = Cancellation()
    cancel.cancel()
    try refuses("cancelled") {
      _ = try WorkbookTools(book, cancellation: cancel).execute(
        "references", .object(["id": .string(source.id)]))
    }
    try expect(try book.counts() == before)
  }
  check("agent reads, lexical search and lineage cannot bypass request or annotation scope") {
    let book = try Workbook.create(
      at: root.appendingPathComponent("AgentItemScope.sevra"), title: "Scope")
    let own = try book.addItem(
      category: "source", kind: "request", title: "Current submission", text: "Visible input")
    let other = try book.addItem(
      category: "source", kind: "request", title: "Other request", text: "SIBLING-SECRET")
    let annotation = try book.addItem(
      category: "source", kind: "annotation", title: "Technical annotation", text: "SIBLING-SECRET")
    let shared = try book.addItem(
      category: "source", kind: "observation", title: "Shared", text: "Allowed original")
    let record = try book.addItem(
      category: "record", kind: "analysis", title: "Analysis", text: "Shared result",
      inputs: [other.id, shared.id])
    let tools = WorkbookTools(book, requestSourceID: own.id)
    try expect(
      try tools.execute("read", .object(["id": .string(own.id)]))["item"]["text"].text == own.text)
    for hidden in [other, annotation] {
      for identity in [hidden.id, hidden.logicalID] {
        try refuses("item_scope") {
          _ = try tools.execute("read", .object(["id": .string(identity)]))
        }
        try refuses("item_scope") {
          _ = try tools.execute("lineage", .object(["id": .string(identity)]))
        }
      }
      let search = try tools.execute(
        "search", .object(["query": .string("SIBLING-SECRET"), "kind": .string(hidden.kind)]))
      try expect(search["hits"].array.isEmpty && search["conversation"]["searched"] == .bool(false))
    }
    try expect(
      try book.search("SIBLING-SECRET", kind: "request").hits.contains { $0.itemID == other.id },
      "Owner search changed")
    let lineage = try tools.execute("lineage", .object(["id": .string(record.id)]))
    try expect(lineage.array.count == 1 && lineage.array[0]["parent"].text == shared.id)
    try expect(!lineage.json().contains(other.id))
    let privateHead = try book.addItem(
      category: "source", kind: "request", title: "SECRET-HEAD", text: "PRIVATE-CONTENT",
      supersedes: own.id)
    let historic = try tools.execute("read", .object(["id": .string(own.id)]))
    try expect(historic["item"]["id"].text == own.id && historic["currentVersion"] == .null)
    try expect(
      !historic.json().contains(privateHead.id) && !historic.json().contains("SECRET-HEAD"))
    try refuses("item_scope") {
      _ = try tools.execute("read", .object(["id": .string(own.logicalID)]))
    }
    try expect(try book.verify()["ok"] == .bool(true))
  }
}
