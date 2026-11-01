import Foundation
import SevraCore
import SevraPreviewUI

func checkConversationPresentation() throws {
  func expect(_ condition: @autoclosure () -> Bool) throws {
    try require(condition(), "conversation_presentation", "Conversation link projection changed.")
  }
  let markdown = """
    Evidence: [**Supplier** café](sevra://item/source-v2?locator=page%3D2).
    [Open original exchange](sevra://conversation/thread-a?message=message-7)
    [Same source](sevra://item/source-v2?locator=page%3D2)
    `[not a link](https://example.com/in-code)`
    [Website](https://example.com/prices?q=12#section)
    """
  let content = ConversationPresentation(markdown)
  try expect(content.links.count == 3)
  try expect(content.links[0].title == "Supplier café")
  try expect(content.links[0].actionTitle == "Open Supplier café")
  try expect(content.links[1].actionTitle == "Open original exchange")
  try expect(
    ConversationLinkTarget(content.links[0].url) == .evidence(id: "source-v2", locator: "page=2"))
  try expect(ConversationLinkTarget(content.links[1].url) == .message(id: "message-7"))
  try expect(content.links[2].url.absoluteString == "https://example.com/prices?q=12#section")
  try expect(String(content.text.characters).contains("[not a link](https://example.com/in-code)"))
  for raw in [
    "file:///tmp/test", "javascript:alert(1)",
    "x-apple.systempreferences:com.apple.preference.security",
    "sevra://other/id", "sevra://item/a/b", "sevra://item/a%2Fb", "sevra://item/..",
    "sevra://user@item/id", "sevra://item/id?locator=a&locator=b", "sevra://item/id?unexpected=yes",
    "sevra://conversation/thread", "sevra://conversation/thread?message=",
    "sevra://conversation/thread?message=a&message=b",
  ] {
    try expect(ConversationLinkTarget(URL(string: raw)!) == nil)
    let blocked = ConversationPresentation("[Preserved label](\(raw))")
    try expect(blocked.links.isEmpty)
    try expect(!blocked.text.runs.contains { $0.link != nil })
    try expect(String(blocked.text.characters).contains("Preserved label"))
  }
  try expect(ConversationPresentation("Plain **formatted** text").links.isEmpty)
  let table = "Before\n\n| A | B |\n|---|---|\n| 1 | 2 |\n\n   \n"
  let parsed = ConversationMessageContent(table)
  try expect(parsed.blocks.count == 2)
  if case .text(let before) = parsed.blocks[0] {
    try expect(String(before.characters).trimmingCharacters(in: .whitespaces) == "Before")
  } else {
    try expect(false)
  }
  if case .table(let cells) = parsed.blocks[1] { try expect(cells.rows == [["1", "2"]]) } else {
    try expect(false)
  }
  let cache = ConversationContentCache()
  func message(_ id: String, _ body: String) throws -> Message {
    let saved: Value = .object([
      "id": .string(id), "role": .string("assistant"), "body": .string(body),
      "state": .string("complete"), "created": .string("2026-11-01"),
    ])
    return try JSONDecoder().decode(Message.self, from: Data(saved.json().utf8))
  }
  let window = try (0..<100).map { try message("m\($0)", "Answer **\($0)**") }
  try cache.prepare(window, cancellation: .init())
  try cache.prepare(window, cancellation: .init())
  for shown in window { _ = cache.content(id: shown.id, body: shown.body) }
  try expect(cache.parseCount == 100)
  let edited = cache.content(id: "m7", body: "Corrected **answer**")
  try expect(String(edited.presentation.text.characters) == "Corrected answer")
  try expect(cache.parseCount == 101)
  cache.retain([try message("m7", "Corrected **answer**")])
  _ = cache.content(id: "m8", body: "Answer **8**")
  try expect(cache.parseCount == 102)
  let stopped = Cancellation()
  stopped.cancel()
  do {
    try ConversationContentCache().prepare(window, cancellation: stopped)
    try expect(false)
  } catch let error as SevraError { try expect(error.code == "cancelled") }
  let many = ConversationPresentation(
    (0..<2_000).map { "[Source \($0)](sevra://item/source-\($0))" }.joined(separator: "\n"))
  try expect(many.links.count == 2_000)
  try expect(many.links.last?.url.absoluteString == "sevra://item/source-1999")
  print(
    "PASS conversation links preserve formatted labels, exact version/locator/origin and safe native routes"
  )
}
