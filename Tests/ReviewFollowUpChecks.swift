import Foundation
import SevraCore

func checkReviewFollowUps(at root: URL) {
  check("a term inside a run of text written without spaces is found, by prefix or not") {
    let book = try Workbook.create(at: root.appendingPathComponent("Runs.sevra"), title: "Runs")
    let note = try book.addItem(
      category: "source", kind: "note", title: "Warehouse", text: "東京都の倉庫 holds 12 bolts.")
    try expect(try book.search("京都").hits.map(\.itemID) == [note.id])
    try expect(try book.search("東京").hits.map(\.itemID) == [note.id])
    try expect(try book.search("京都 bolts").hits.map(\.itemID) == [note.id])
    try expect(try book.search("大阪").hits.isEmpty)
    try expect(try book.search("olts").hits.isEmpty)
    let said = try book.addMessage("東京都の倉庫 is full.", role: "user")
    try expect(try book.searchHistory("京都")["hits"].array.map { $0["id"].text } == [said])
    let table = try book.createDataset(
      title: "Sites", columns: [.init(id: "site", title: "Site")],
      rows: [["site": .string("東京都の倉庫")], ["site": .string("大阪の倉庫")]], sourceID: note.id)
    try expect(try book.tablePage(table.id, query: "京都").rows.count == 1)
  }
  check("a far indented line and a spaced ruler are not deep, and real nesting still is") {
    let rulers = [
      Array(repeating: "-", count: 120).joined(separator: " "),
      Array(repeating: "*", count: 120).joined(separator: " "),
      "> " + Array(repeating: "-", count: 120).joined(separator: " "),
      String(repeating: " ", count: 120) + "- item",
      String(repeating: " ", count: 120) + "> quote",
      String(repeating: " ", count: 120) + "12. item",
    ]
    for text in rulers {
      try expect(MarkdownNesting.isReadable(text + "\n\n" + text + "\n"), text)
    }
    let lines = (0..<160).map { String(repeating: " ", count: $0 * 2) + "- item" }
    let wide = (0..<160).map { String(repeating: " ", count: $0 * 3) + "1. item" }
    let lazy = (0..<160).flatMap { [String(repeating: " ", count: $0 * 2) + "- item", "lazy"] }
    let inline = Array(repeating: "- ", count: 160).joined() + "x"
    let numbers = Array(repeating: "1234. ", count: 160).joined() + "x"
    let quotes = String(repeating: "> ", count: 160) + "x"
    for text in [
      lines.joined(separator: "\n"), wide.joined(separator: "\n"), lazy.joined(separator: "\n"),
      inline, numbers, quotes,
    ] {
      try expect(!MarkdownNesting.isReadable(text), String(text.prefix(40)))
    }
  }
}
