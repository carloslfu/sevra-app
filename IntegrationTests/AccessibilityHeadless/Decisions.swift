import Foundation
import SevraCore
import SevraDocumentUI
import SevraTableUI

func decisionChecks(_ suite: inout Suite) {
  suite.check("A1 arrows and Tab skip readonly cells, wrap rows and exit at boundaries") {
    typealias Cell = TableCellNavigation.Cell
    let expected = [
      Cell(row: 0, column: 1), Cell(row: 0, column: 3), Cell(row: 1, column: 1),
      Cell(row: 1, column: 3), Cell(row: 2, column: 1), Cell(row: 2, column: 3),
    ]
    func next(_ from: Cell, _ direction: Int) -> Cell? {
      TableCellNavigation.destination(
        rows: 3, columns: 4, current: from, delta: direction,
        editableOnly: true, isEditable: { [1, 3].contains($0.column) })
    }
    var current = Cell(row: -1, column: 0)
    for target in expected {
      try expect(next(current, 1) == target, "Forward editable order")
      current = target
    }
    try expect(next(current, 1) == nil, "Tab exits the last editable cell")
    current = Cell(row: -1, column: 0)
    for target in expected.reversed() {
      try expect(next(current, -1) == target, "Backward editable order")
      current = target
    }
    try expect(next(current, -1) == nil, "Backtab exits the first cell")
    let arrow = TableCellNavigation.destination(
      rows: 2, columns: 3, current: .init(row: 1, column: 1), delta: -1, editableOnly: false,
      isEditable: { _ in false })
    try expect(arrow == Cell(row: 1, column: 0), "Arrows can inspect readonly cells")
  }
  suite.check("A1 logical focus survives sort/column reorder and drops deleted selection") {
    try expect(
      TableCellNavigation.row(identity: "row-b", rows: ["row-b", "row-a"], selected: [0]) == 0,
      "Row follows identity")
    try expect(
      TableCellNavigation.column(identity: "cost", columns: ["cost", "name"]) == 0,
      "Column follows identity")
    try expect(
      TableCellNavigation.row(identity: "gone", rows: ["a", "b"], selected: [1]) == 1,
      "Fallback current selected row")
    try expect(
      TableCellNavigation.row(identity: "a", rows: ["a"], selected: [9]) == -1,
      "Stale selection is not a destination")
    try expect(
      TableCellNavigation.column(identity: "gone", columns: []) == 0, "Empty schema stays bounded")
  }
  suite.check("A1 empty, fully readonly and invalid movements refuse edits") {
    for delta in [-1, 1] {
      try expect(
        TableCellNavigation.destination(
          rows: 3, columns: 4, current: .init(row: -1, column: 0), delta: delta, editableOnly: true,
          isEditable: { _ in false }) == nil, "No editable cell")
      try expect(
        TableCellNavigation.destination(
          rows: 0, columns: 0, current: .init(row: -1, column: 0), delta: delta,
          editableOnly: false, isEditable: { _ in true }) == nil, "Empty grid")
    }
    try expect(
      TableCellNavigation.destination(
        rows: 1, columns: 2, current: .init(row: 0, column: 0), delta: 0, editableOnly: true,
        isEditable: { _ in true }) == nil, "Zero delta must not loop")
  }
  suite.check(
    "A6 initial/duplicate notices stay silent; terminal changes and repeated explicit operations notify"
  ) {
    var policy = StatusAnnouncementPolicy()
    try expect(policy.update("Already displayed") == nil, "Initial display is silent")
    try expect(policy.update("Already displayed") == nil, "Duplicate display is silent")
    try expect(policy.update(nil) == nil, "Clear is silent")
    let first = policy.update("Copied 2 rows")!
    try expect(
      policy.canDeliver(first, ownWindowIsKey: true, appIsActive: true), "Eligible terminal notice")
    try expect(policy.update("Copied 2 rows") == nil, "No repeated refresh announcement")
    try expect(
      policy.canDeliver(first, ownWindowIsKey: true, appIsActive: true),
      "Unchanged redraw does not cancel queued event")
    _ = policy.update(nil)
    let next = policy.update("Copied 2 rows")!
    try expect(
      !policy.canDeliver(first, ownWindowIsKey: true, appIsActive: true),
      "Earlier generation is obsolete")
    try expect(
      policy.canDeliver(next, ownWindowIsKey: true, appIsActive: true),
      "Repeated explicit event has new generation")
  }
  suite.check("A6 background, inactive and superseded announcements are refused") {
    var policy = StatusAnnouncementPolicy()
    _ = policy.update(nil)
    let first = policy.update("Finished")!
    for (key, active) in [(false, false), (false, true), (true, false)] {
      try expect(
        !policy.canDeliver(first, ownWindowIsKey: key, appIsActive: active),
        "Only own active window may speak")
    }
    _ = policy.update("Failure")
    try expect(
      !policy.canDeliver(first, ownWindowIsKey: true, appIsActive: true),
      "Obsolete completion must not speak after failure")
    try expect(policy.update("") == nil, "Empty status does not speak")
  }
  suite.check("A7 own-sheet focus waits for parent, rejects other windows and obsolete requests") {
    let id = UUID()
    try expect(
      ReadingFocusPolicy.canRequest(appIsActive: true, ownWindowIsKey: false, ownSheetIsKey: true),
      "Sheet can retain return request")
    try expect(
      !ReadingFocusPolicy.canRequest(
        appIsActive: true, ownWindowIsKey: false, ownSheetIsKey: false),
      "Other window does not authorize focus")
    try expect(
      !ReadingFocusPolicy.canRequest(
        appIsActive: false, ownWindowIsKey: true, ownSheetIsKey: false),
      "Inactive app does not queue focus")
    func apply(_ request: UUID, _ pending: Bool, _ active: Bool, _ key: Bool) -> Bool {
      ReadingFocusPolicy.canApply(
        request: request, currentRequest: id, pending: pending, interactionActive: active,
        ownWindowIsKey: key, appIsActive: true)
    }
    try expect(!apply(id, true, true, false), "Parent must become key first")
    try expect(apply(id, true, true, true), "Correct return destination is eligible")
    try expect(
      !apply(UUID(), true, true, true) && !apply(id, false, true, true)
        && !apply(id, true, false, true), "Obsolete, consumed and retired requests refuse")
  }
  suite.check(
    "A7 return targets preserve messages and safely fall back when a message leaves the page"
  ) {
    try expect(
      ReadingFocusPolicy.destination(.message("saved"), visibleMessages: ["saved"])
        == .message("saved"), "Exact message return")
    try expect(
      ReadingFocusPolicy.destination(.message("gone"), visibleMessages: ["saved"]) == .conversation,
      "Missing message fallback")
    for target in [ReadingTarget.workspace, .conversation, .composer, .status] {
      try expect(
        ReadingFocusPolicy.destination(target, visibleMessages: []) == target,
        "Explicit pane target")
    }
  }
  suite.check("A8 bounded zoom steps, invalid preferences and proportional table metrics") {
    for invalid in [-100.0, 0, .nan, .infinity, -.infinity] {
      try expect(ReadingMetrics.scale(invalid) == 1, "Invalid reading size")
    }
    try expect(ReadingMetrics.scale(20) == 2, "Upper bound")
    var scale = 1.0
    for expected in [1.25, 1.5, 1.75, 2, 2] {
      scale = ReadingMetrics.adjusted(scale, steps: 1)
      try expect(scale == expected, "Larger steps")
    }
    for expected in [1.75, 1.5, 1.25, 1, 1] {
      scale = ReadingMetrics.adjusted(scale, steps: -1)
      try expect(scale == expected, "Smaller steps")
    }
    for scale in [1.0, 1.25, 1.5, 1.75, 2.0] {
      try expect(ReadingStyle.scale(scale) == scale, "Native bridge uses bounded scale")
      try expect(
        ReadingStyle.points(30, scale: scale) == 30 * scale
          && ReadingStyle.points(24, scale: scale) == 24 * scale, "Rows and headers grow")
      try expect(
        ReadingStyle.points(13, scale: scale) < ReadingStyle.points(30, scale: scale),
        "Text fits baseline row metrics")
    }
    try expect(ReadingStyle.preference == ReadingMetrics.preference, "One app-only preference key")
  }
  suite.check("A10 PDF matches wrap pages with UTF-16 ranges and honor Reduce Motion") {
    var search = PDFMatchSearch()
    let pages = ["🟢 Bolt and bolt", "Other", "BOLT"]
    var matches: [PDFMatchSearch.Match] = []
    for reduce in [true, false, true, false] {
      let result = search.next(
        query: "bolt", documentID: "one", pageCount: pages.count, currentPage: 0,
        reduceMotion: reduce, text: { pages[$0] })
      guard case .match(let match) = result else {
        throw SevraError("headless_check", "Missing PDF match")
      }
      matches.append(match)
      try expect(
        (pages[match.page] as NSString).substring(with: match.range).lowercased() == "bolt",
        "Actual Unicode substring must match")
      try expect(match.animate == !reduce, "Motion follows supplied preference")
    }
    try expect(
      matches.map(\.page) == [0, 0, 2, 0] && matches[0].range.location == 3,
      "UTF-16 offsets and wrap order")
  }
  suite.check(
    "A10 PDF query/document changes reset search; empty, oversized and scan-only inputs are safe"
  ) {
    var search = PDFMatchSearch()
    _ = search.next(
      query: "bolt", documentID: "old", pageCount: 1, currentPage: 0, reduceMotion: false,
      text: { _ in "bolt bolt" })
    let changed = search.next(
      query: "bolt", documentID: "new", pageCount: 1, currentPage: 0, reduceMotion: true,
      text: { _ in "bolt bolt" })
    guard case .match(let match) = changed else {
      throw SevraError("headless_check", "Document change skipped new first match")
    }
    try expect(match.range.location == 0 && !match.animate, "New document starts fresh")
    guard
      case .match(let changedQuery) = search.next(
        query: "new", documentID: "new", pageCount: 1, currentPage: 0, reduceMotion: true,
        text: { _ in "new new" })
    else { throw SevraError("headless_check", "Missing changed query") }
    try expect(changedQuery.range.location == 0, "Changed query starts at first match")
    try expect(
      search.next(
        query: "", documentID: "new", pageCount: 1, currentPage: 0, reduceMotion: true,
        text: { _ in "" }) == .invalidQuery, "Empty query")
    try expect(
      search.next(
        query: String(repeating: "🟢", count: 513), documentID: "new", pageCount: 1, currentPage: 0,
        reduceMotion: true, text: { _ in "" }) == .invalidQuery, "Byte query limit")
    try expect(
      search.next(
        query: "bolt", documentID: "scan", pageCount: 2, currentPage: 99, reduceMotion: true,
        text: { _ in nil }) == .noMatch, "Scanned pages have no fabricated PDF text")
  }
}
