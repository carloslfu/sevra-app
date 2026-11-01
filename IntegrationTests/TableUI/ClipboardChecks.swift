import AppKit
import SevraCore

@testable import SevraTableUI

@MainActor func checkTableClipboard() throws {
  let board = NSPasteboard(name: .init("sevra-table-check-" + identifier()))
  defer { board.releaseGlobally() }
  let cells: [[Value]] = [
    [.string("0014"), .string("1,200.10"), .string("a\tb"), .string("line 1\nline 2")],
    [.null, .string(""), .bool(false), .number(0)],
    [.string("<script>alert(1)</script>&\""), .string("a\rb"), .string("=A1"), .string("")],
    [.string(""), .string(""), .string(""), .string("")],
  ]
  let copied = try TableClipboard(cells: cells)
  try copied.write(to: board)
  try expect(try TableClipboard.read(from: board) == cells, "Typed clipboard lost values or types")
  try expect(
    board.string(forType: .string) == copied.text
      && board.string(forType: .tabularText) == copied.text
      && board.string(forType: .html) == copied.html,
    "Native clipboard did not contain all three interoperable presentations")
  try expect(
    copied.html.contains("&lt;script&gt;") && copied.html.contains("&amp;&quot;")
      && !copied.html.contains("<script>") && copied.html.contains("line 1<br>line 2"),
    "HTML table did not escape literal content and preserve line breaks")
  try expect(
    try CSV.parse(copied.text, delimiter: "\t") == cells.map { $0.map(\.text) },
    "TSV round trip changed tabs, quotes, carriage returns or a final empty row")
  board.clearContents()
  board.setString(copied.text, forType: .string)
  let external = try TableClipboard.read(from: board)
  try expect(
    external.map { $0.map(\.text) } == cells.map { $0.map(\.text) }
      && external[0][0] == .string("0014"),
    "Plain-text paste lost cell boundaries or guessed a numeric code")
  board.clearContents()
  board.setString("a,b\r\nc,d", forType: .string)
  try expect(
    try TableClipboard.read(from: board) == [[.string("a,b")], [.string("c,d")]],
    "A comma in ordinary text was guessed to be a CSV column")
  let windowsLine = try TableClipboard(cells: [[.string("one\r\ntwo"), .string("x")]])
  try expect(windowsLine.text == "\"one\r\ntwo\"\tx", "A CR LF inside a cell was copied unquoted")
  board.clearContents()
  board.setString("5\" pipe\tx\r\n\"say \"\"hi\"\"\"\t\"6\" tall\r\n\"a\nb\"\t\"open\r\n", forType: .string)
  try expect(
    try TableClipboard.read(from: board).map { $0.map(\.text) } == [
      ["5\" pipe", "x"], ["say \"hi\"", "\"6\" tall"], ["a\nb", "\"open"],
    ], "A quote in ordinary text refused or merged cells")
  try expect(
    TableClipboard.holdsTable("a\tb\r\n1\t2\r\n") && TableClipboard.holdsTable("a\tb\r1\t2")
      && TableClipboard.holdsTable("a\tb\n") && !TableClipboard.holdsTable("a\r\nb")
      && !TableClipboard.holdsTable("a\tb"), "Table text was judged by one line ending")
  print(
    "PASS clipboard typed, TSV and escaped HTML round trips; codes, commas, multiline and empty cells"
  )

  board.clearContents()
  board.setString("keep this clipboard", forType: .string)
  do {
    let tooLarge = try TableClipboard(cells: [[.string(String(repeating: "x", count: 4_000_001))]])
    try tooLarge.write(to: board)
    throw SevraError("check", "Oversize copy was accepted")
  } catch let error as SevraError where error.code == "paste_limit" || error.code == "copy_limit" {}
  try expect(
    board.string(forType: .string) == "keep this clipboard", "Failed copy cleared the clipboard")
  let hostile = NSPasteboardItem()
  hostile.setString("visible", forType: .string)
  hostile.setData(
    try JSONSerialization.data(withJSONObject: [
      "version": 1, "text": "visible", "cells": [["different"]],
    ]),
    forType: TableClipboard.valuesType)
  board.clearContents()
  board.writeObjects([hostile])
  do {
    _ = try TableClipboard.read(from: board)
    throw SevraError("check", "Mismatched typed data was trusted")
  } catch let error as SevraError where error.code == "paste_format" {}
  print("PASS oversized copy preserves clipboard; mismatched typed data refuses")

  let url = FileManager.default.temporaryDirectory.appendingPathComponent(
    "sevra-clipboard-" + identifier() + ".sevra")
  defer { try? FileManager.default.removeItem(at: url) }
  let demo = try Demo.create(at: url)
  let book = try Workbook(url)
  let id = demo["datasetID"].text
  let page = try book.tablePage(id, sort: "supplier")
  let selection = Set(page.rows.map(\.logicalID))
  let revision = try book.revision()
  let range = try TableClipboard(page: page, selection: selection)
  try expect(
    range.cells
      == page.values.map { values in page.dataset.columns.map { values[$0.id] ?? .null } },
    "Copy used raw data instead of displayed order and calculated values")
  let headings = try TableClipboard(page: page, selection: selection, headings: true)
  try expect(
    headings.cells.first == page.dataset.columns.map { .string($0.title) }
      && Array(headings.cells.dropFirst()) == range.cells,
    "Copy with headings did not add exactly one heading row")
  let presentation = TableSelectionPresentation(
    page: page, selected: Array(page.rows.reversed()), column: 3)
  try expect(
    presentation.label.contains("2 selected rows on this page")
      && page.rows.allSatisfy { presentation.context.contains($0.id) },
    "Multi-selection context did not include every exact selected version")
  let single = TableSelectionPresentation(page: page, selected: [page.rows[0]], column: 3)
  try expect(
    single.label.contains(page.values[0]["total"]!.text),
    "Single-row context lost its computed cell")
  let empty = TableSelectionPresentation(page: page, selected: [], column: 0)
  try expect(empty.label.isEmpty && empty.context.isEmpty, "Cleared selection left context")
  try expect(try book.revision() == revision, "Copy or selection mutated the workbook")
  print(
    "PASS copy uses displayed order and computed values; headings optional; context includes the entire selection"
  )

  let edits = try TableClipboard.edits(
    cells: [[.string("31")], [.string("42")]], page: page, selection: selection, column: 1)
  try expect(
    edits.map(\.id) == page.rows.map(\.id)
      && edits[0].values["supplier"] == page.rows[0].data["supplier"],
    "Paste retargeted a row or overwrote an untouched column")
  let change = try book.editRows(id, edits: edits, expectedRevision: page.revision)
  let edited = try book.tablePage(id, sort: "supplier")
  try expect(
    edited.values.map { $0["quantity"]?.text } == ["31", "42"], "Multi-row paste did not apply")
  let inverse = try book.undoTableChange(change.id)
  let restored = try book.tablePage(id, sort: "supplier")
  try expect(restored.values == page.values, "One Undo did not restore the entire paste")
  _ = try book.undoTableChange(inverse.id)
  try expect(
    try book.tablePage(id, sort: "supplier").values == edited.values, "Redo lost a pasted row")
  let beforeRefusal = try book.revision()
  func refuse(_ operation: () throws -> Void) throws {
    do { try operation() } catch let error as SevraError where error.code != "check" { return }
    throw SevraError("check", "Invalid paste was accepted")
  }
  try refuse {
    _ = try TableClipboard.edits(
      cells: [[.string("x"), .string("y")]], page: page, selection: selection, column: 2)
  }
  try refuse {
    _ = try TableClipboard.edits(
      cells: [[.string("x")], [.string("y")], [.string("z")]], page: page, selection: selection,
      column: 0)
  }
  try refuse {
    _ = try TableClipboard.edits(cells: [[.string("x")]], page: page, selection: [], column: 0)
  }
  let csv = url.deletingLastPathComponent().appendingPathComponent(identifier() + ".csv")
  defer { try? FileManager.default.removeItem(at: csv) }
  try "code,value\nA,1\nB,2\nC,3\n".write(to: csv, atomically: true, encoding: .utf8)
  let source = try book.importFile(csv)
  let extra = try book.importCSV(source.id)
  let three = try book.tablePage(extra.id)
  let gap = Set([three.rows[0].logicalID, three.rows[2].logicalID])
  let afterImport = try book.revision()
  try refuse {
    _ = try TableClipboard.edits(
      cells: [[.string("changed")], [.string("changed")]], page: three, selection: gap, column: 0)
  }
  try expect(
    try book.revision() == afterImport && afterImport > beforeRefusal,
    "Refused paste mutated evidence")
  try expect(try book.verify()["ok"] == .bool(true), "Clipboard fixture integrity failed")
  print(
    "PASS range paste validates before mutation, targets immutable rows, undoes/redoes atomically, and refuses formulas, overflow and discontiguous selection"
  )
}
