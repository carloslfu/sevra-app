import Foundation
import SevraCore
import SevraPreviewUI

@MainActor func checkSpaceNavigation() async throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(
    "sevra-spaces-" + identifier())
  defer { try? FileManager.default.removeItem(at: root) }
  let book = try Workbook.create(
    at: root.appendingPathComponent("Navigation.sevra"), title: "Navigation")
  var ids: [String] = []
  for index in 0..<12 {
    ids.append(
      try book.saveSpace(
        title: index < 2 ? "Café suppliers" : "Space \(index)",
        definition: SpaceDefinition(components: [
          Component(type: "text", title: "Note", text: "Original")
        ])))
  }
  let before = try book.workspaceSnapshot(conversation: "main")!
  let originalSpaces = try encoded(book.spaces())
  let first = try book.updateSpaceNavigation([.pin(ids[0], true), .visit(ids[1])])
  let other = try Workbook(book.url)
  let merged = try other.updateSpaceNavigation([.pin(ids[1], true), .visit(ids[2])])
  try require(
    merged.pinned == [ids[0], ids[1]], "navigation", "A visit or second window erased a pin.")
  try require(merged.recent == [ids[2], ids[1]], "navigation", "Visits lost ordering.")
  let refreshed = try book.workspaceSnapshot(
    conversation: "main", ifChangedFrom: before.revision, ifSpaceNavigationMatches: first)
  try require(
    refreshed?.spaceNavigation == merged, "navigation", "Presentation-only changes were missed.")
  try require(
    try book.workspaceSnapshot(
      conversation: "main", ifChangedFrom: before.revision,
      ifSpaceNavigationMatches: merged) == nil,
    "navigation", "Unchanged presentation did not coalesce.")
  do {
    _ = try book.updateSpaceNavigation([.pin(ids[0], false), .visit("missing")])
    throw SevraError("check", "Missing space was accepted.")
  } catch let failure as SevraError {
    try require(failure.code == "space_navigation", "navigation", "Unexpected failure.")
  }
  try require(
    try book.workspaceSnapshot(conversation: "main")!.spaceNavigation == merged,
    "navigation", "Invalid batch partly changed preferences.")

  let session = SpaceNavigationSession()
  await session.open(book)
  session.receive(merged, generation: session.generation)
  let staleGeneration = session.generation
  for id in ids { session.visit(id) }
  await session.flush()
  session.receive(first, generation: staleGeneration)
  try require(
    session.state.recent == Array(ids.suffix(8).reversed()), "navigation",
    "Rapid visits or an old read regressed recency.")
  session.pin(ids[0], selected: false)
  await SpaceNavigationSession.flushAll()
  try require(
    session.state.pinned == [ids[1]], "navigation", "Unpin failed or erased another shortcut.")
  var failure: String?
  session.failed = { failure = $0 }
  session.pin("missing", selected: true)
  await session.flush()
  try require(
    failure != nil && session.state.pinned == [ids[1]], "navigation",
    "Failed save appeared persisted.")
  let current = session.state
  let sections = SpacePickerSections(
    spaces: try book.spaces(), navigation: current, query: "  cafe  ")
  try require(
    sections.pinned.map(\.id) == [ids[1]] && sections.others.map(\.id) == [ids[0]],
    "navigation", "Search lost duplicate titles or accent-insensitive matching.")
  let all = SpacePickerSections(spaces: try book.spaces(), navigation: current, query: "")
  let shown = (all.home + all.pinned + all.recent + all.others).map(\.id)
  try require(
    shown.count == 13 && Set(shown).count == 13 && all.home.first?.id == "home",
    "navigation", "Picker omitted or duplicated a space.")
  let archive = root.appendingPathComponent("Portable.sevraz")
  try book.export(to: archive)
  let reopened = try Workbook.openArchive(
    archive, at: root.appendingPathComponent("Restored.sevra"))
  try require(
    try reopened.workspaceSnapshot(conversation: "main")!.spaceNavigation == current,
    "navigation", "Navigation preferences did not survive portable reopen.")
  try require(
    try book.revision() == before.revision && encoded(book.spaces()) == originalSpaces,
    "navigation", "Pinning changed business history or captured a snapshot.")
  try require(
    try book.verify()["ok"] == .bool(true), "navigation", "Navigation damaged workbook integrity.")
  print(
    "PASS space pins/recents merge across windows, bound visits, refuse stale/invalid changes, preserve business state and survive portable reopen"
  )
}
