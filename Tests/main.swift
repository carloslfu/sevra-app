import CoreText
import Darwin
import Foundation
import ImageIO
import SevraCore
import ZIPFoundation

setbuf(stdout, nil)

if CommandLine.arguments.count == 5 && CommandLine.arguments[1] == "--condition-death-worker" {
  try inventoryConditionDeathWorker(
    CommandLine.arguments[2], consumer: CommandLine.arguments[3], stage: CommandLine.arguments[4])
  exit(0)
}

if CommandLine.arguments.count == 4 && CommandLine.arguments[1] == "--business-death-worker" {
  try businessEventDeathWorker(CommandLine.arguments[2], stage: CommandLine.arguments[3])
  exit(0)
}

if CommandLine.arguments.count == 3 && CommandLine.arguments[1] == "--history-fixture" {
  print(
    try createCLIHistoryFixture(at: URL(fileURLWithPath: CommandLine.arguments[2])).json())
  exit(0)
}

var passed = 0
var failed = 0
func check(_ name: String, _ body: () throws -> Void) {
  do {
    try body()
    passed += 1
    print("PASS \(name)")
  } catch {
    failed += 1
    print("FAIL \(name): \(error)")
  }
}
func expect(_ condition: @autoclosure () throws -> Bool, _ message: String = "Expectation failed")
  throws
{ if try !condition() { throw SevraError("test", message) } }
func refuses(_ code: String? = nil, _ body: () throws -> Void) throws {
  do { try body() } catch {
    if let code {
      try expect((error as? SevraError)?.code == code, "Expected \(code), got \(error)")
    }
    return
  }
  throw SevraError("test", "Expected refusal")
}
let temp = FileManager.default.temporaryDirectory.appendingPathComponent(
  "sevra-checks-" + identifier())
try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: temp) }
if CommandLine.arguments.count == 4 && CommandLine.arguments[1] == "--business-input-death-worker" {
  try businessInputDeathWorker(
    at: URL(fileURLWithPath: CommandLine.arguments[2]), stage: CommandLine.arguments[3])
  exit(0)
}
if CommandLine.arguments.count == 3 && CommandLine.arguments[1] == "--condition-cause-fixture" {
  print(try createConditionCauseFixture(at: URL(fileURLWithPath: CommandLine.arguments[2])).json())
  exit(0)
}
if CommandLine.arguments.count == 5 && CommandLine.arguments[1] == "--condition-dispatch-fixture" {
  print(
    try createConditionDispatchFixture(
      at: URL(fileURLWithPath: CommandLine.arguments[2]),
      targets: Int(CommandLine.arguments[3])!, admitted: Int(CommandLine.arguments[4])!
    ).json())
  exit(0)
}
if (4...5).contains(CommandLine.arguments.count)
  && CommandLine.arguments[1] == "--condition-dispatch-worker"
{
  do {
    print(
      try conditionDispatchWorker(
        at: URL(fileURLWithPath: CommandLine.arguments[2]),
        definition: CommandLine.arguments[3],
        stage: CommandLine.arguments.count == 5 ? CommandLine.arguments[4] : nil
      ).json())
  } catch {
    fputs(
      (try! encoded(error as? SevraError ?? SevraError("fixture", error.localizedDescription))
        .json()) + "\n", stderr)
    exit(1)
  }
  exit(0)
}
if CommandLine.arguments.dropFirst() == ["--condition-dispatch"] {
  checkConditionDispatch(at: temp)
  print("\(passed) passed; \(failed) failed")
  exit(failed == 0 ? 0 : 1)
}
if CommandLine.arguments.dropFirst() == ["--business-inputs"] {
  checkBusinessInputs(at: temp)
  checkConditionCauses(at: temp)
  print("\(passed) passed; \(failed) failed")
  exit(failed == 0 ? 0 : 1)
}
if CommandLine.arguments.count == 3 && CommandLine.arguments[1] == "--condition-origin-fixture" {
  print(try createConditionOriginFixture(at: URL(fileURLWithPath: CommandLine.arguments[2])).json())
  exit(0)
}
if CommandLine.arguments.dropFirst() == ["--condition-origins"] {
  checkConditionOrigins(at: temp)
  checkConditionInputs(at: temp)
  checkBusinessOrigins(at: temp)
  print("\(passed) passed; \(failed) failed")
  exit(failed == 0 ? 0 : 1)
}
if CommandLine.arguments.dropFirst() == ["--business-origins"] {
  checkBusinessOrigins(at: temp)
  checkAutomaticAncestry(at: temp)
  checkDefinitionResults(at: temp)
  checkWorkflowLookups(at: temp)
  checkWorkflowInterpretations(at: temp)
  checkWorkflowIntakes(at: temp)
  checkAutomationCausalityCorruption(at: temp)
  print("\(passed) passed; \(failed) failed")
  exit(failed == 0 ? 0 : 1)
}
if CommandLine.arguments.dropFirst() == ["--derivation-roles"] {
  checkDerivationRoles(at: temp)
  print("\(passed) passed; \(failed) failed")
  exit(failed == 0 ? 0 : 1)
}
if CommandLine.arguments.count == 3 && CommandLine.arguments[1] == "--condition-inputs-fixture" {
  print(try createConditionInputFixture(at: URL(fileURLWithPath: CommandLine.arguments[2])).json())
  exit(0)
}
if CommandLine.arguments.dropFirst() == ["--condition-inputs"] {
  checkConditionInputs(at: temp)
  print("\(passed) passed; \(failed) failed")
  exit(failed == 0 ? 0 : 1)
}
if CommandLine.arguments.dropFirst() == ["--condition-input-limit"] {
  checkConditionInputLimit(at: temp)
  print("\(passed) passed; \(failed) failed")
  exit(failed == 0 ? 0 : 1)
}
if CommandLine.arguments.count == 3 && CommandLine.arguments[1] == "--automation-causality-fixture"
{
  print(
    try createAutomationCausalityFixture(at: URL(fileURLWithPath: CommandLine.arguments[2])).json())
  exit(0)
}
if CommandLine.arguments.count == 5 && CommandLine.arguments[1] == "--automation-causality-worker" {
  do {
    print(
      try automationCausalityWorker(
        path: CommandLine.arguments[2], definition: CommandLine.arguments[3],
        parent: CommandLine.arguments[4]
      ).json())
  } catch {
    fputs(
      (try? encoded(error as? SevraError ?? SevraError("error", error.localizedDescription)).json())
        ?? "{}", stderr)
    exit(1)
  }
  exit(0)
}
if CommandLine.arguments.dropFirst() == ["--automation-causality"] {
  checkAutomationCausality(at: temp)
  checkSharedBusinessAdmissions(at: temp)
  print("\(passed) passed; \(failed) failed")
  exit(failed == 0 ? 0 : 1)
}
if CommandLine.arguments.count == 3 && CommandLine.arguments[1] == "--shared-admission-fixture" {
  print(try createSharedAdmissionFixture(at: URL(fileURLWithPath: CommandLine.arguments[2])).json())
  exit(0)
}
if CommandLine.arguments.count == 5 && CommandLine.arguments[1] == "--shared-admission-worker" {
  do {
    print(
      try sharedAdmissionWorker(
        path: CommandLine.arguments[2], definition: CommandLine.arguments[3],
        input: CommandLine.arguments[4]
      ).json())
  } catch {
    fputs(
      (try? encoded(error as? SevraError ?? SevraError("error", error.localizedDescription)).json())
        ?? "{}", stderr)
    exit(1)
  }
  exit(0)
}
if CommandLine.arguments.count == 4 && CommandLine.arguments[1] == "--shared-admission-death-worker"
{
  try sharedAdmissionDeathWorker(
    at: URL(fileURLWithPath: CommandLine.arguments[2]), stage: CommandLine.arguments[3])
  exit(0)
}
if CommandLine.arguments.count == 3 && CommandLine.arguments[1] == "--automatic-ancestry-fixture" {
  print(
    try createAutomaticAncestryFixture(at: URL(fileURLWithPath: CommandLine.arguments[2])).json())
  exit(0)
}
if CommandLine.arguments.dropFirst() == ["--automatic-ancestry"] {
  checkAutomaticAncestry(at: temp)
  print("\(passed) passed; \(failed) failed")
  exit(failed == 0 ? 0 : 1)
}
if CommandLine.arguments.count == 3
  && ["--automation-execution-fixture", "--automation-ai-fixture"].contains(
    CommandLine.arguments[1])
{
  print(
    try createAutomationExecutionFixture(
      at: URL(fileURLWithPath: CommandLine.arguments[2]),
      ai: CommandLine.arguments[1] == "--automation-ai-fixture"
    ).json())
  exit(0)
}
if CommandLine.arguments.dropFirst() == ["--automation-execution"] {
  checkAutomationExecution(at: temp)
  print("\(passed) passed; \(failed) failed")
  exit(failed == 0 ? 0 : 1)
}
if CommandLine.arguments.count == 3 && CommandLine.arguments[1] == "--automation-planning-fixture" {
  print(
    try createAutomationPlanningFixture(at: URL(fileURLWithPath: CommandLine.arguments[2])).json())
  exit(0)
}
if CommandLine.arguments.dropFirst() == ["--automation-planning"] {
  checkAutomationPlanning(at: temp)
  print("\(passed) passed; \(failed) failed")
  exit(failed == 0 ? 0 : 1)
}
if CommandLine.arguments.dropFirst() == ["--schedules"] {
  checkCalendarSchedules()
  print("\(passed) passed; \(failed) failed")
  exit(failed == 0 ? 0 : 1)
}
if CommandLine.arguments.dropFirst() == ["--conditions"] {
  checkConditionTransitions()
  print("\(passed) passed; \(failed) failed")
  exit(failed == 0 ? 0 : 1)
}
if CommandLine.arguments.dropFirst() == ["--business-events"] {
  checkBusinessEvents(at: temp)
  print("\(passed) passed; \(failed) failed")
  exit(failed == 0 ? 0 : 1)
}
if CommandLine.arguments.dropFirst() == ["--inventory-condition-limit"] {
  checkInventoryConditionLimit(at: temp)
  print("\(passed) passed; \(failed) failed")
  exit(failed == 0 ? 0 : 1)
}
if CommandLine.arguments.dropFirst() == ["--inventory-conditions"] {
  checkInventoryConditions(at: temp)
  print("\(passed) passed; \(failed) failed")
  exit(failed == 0 ? 0 : 1)
}
if CommandLine.arguments.dropFirst() == ["--inventory-event-state"] {
  checkInventoryEventState(at: temp)
  print("\(passed) passed; \(failed) failed")
  exit(failed == 0 ? 0 : 1)
}
if CommandLine.arguments.dropFirst() == ["--inventory-event-limit"] {
  checkInventoryEventLimit(at: temp)
  print("\(passed) passed; \(failed) failed")
  exit(failed == 0 ? 0 : 1)
}
if CommandLine.arguments.dropFirst() == ["--automations"] {
  checkAutomationDefinitions(at: temp)
  print("\(passed) passed; \(failed) failed")
  exit(failed == 0 ? 0 : 1)
}
if CommandLine.arguments.dropFirst() == ["--document-actions"] {
  checkDocumentActions(at: temp)
  print("\(passed) passed; \(failed) failed")
  exit(failed == 0 ? 0 : 1)
}
if CommandLine.arguments.dropFirst() == ["--workflow-intake"] {
  checkTableIntake(at: temp)
  checkWorkflowIntakes(at: temp)
  print("\(passed) passed; \(failed) failed")
  exit(failed == 0 ? 0 : 1)
}
if CommandLine.arguments.dropFirst() == ["--workflows"] {
  checkWorkflows(at: temp)
  checkWorkflowTools(at: temp)
  checkWorkflowInterpretations(at: temp)
  checkWorkflowExtractions(at: temp)
  checkWorkflowIntakes(at: temp)
  print("\(passed) passed; \(failed) failed")
  exit(failed == 0 ? 0 : 1)
}
var book: Workbook!
var source: Item!
var movement: Item!
var table: Dataset!
var fileItem: Item!
check("create/open canonical package") {
  book = try Workbook.create(at: temp.appendingPathComponent("Shop.sevra"), title: "Shop")
  try expect(book.title == "Shop")
  try expect(try Workbook(book.url).revision() == 0)
}
guard book != nil else { exit(1) }
check("decimal arithmetic and error propagation") {
  try expect(try Numbers.calculate("0.1+0.2") == "0.3")
  try expect(try Numbers.calculate("(2+3)*4-SUM(1,2)") == "17")
  try expect(
    try Numbers.calculate(
      "[unit cost]*quantity", values: ["unit cost": .string("2.45"), "quantity": .string("3")])
      == "7.35")
  try refuses("division_by_zero") { _ = try Numbers.calculate("1/0") }
  try refuses("missing_value") { _ = try Numbers.calculate("missing+1") }
  try refuses { _ = try Numbers.calculate("system('ls')") }
}
check("source, lineage and current heads") {
  source = try book.addItem(
    category: "source", kind: "observation", title: "Opening count", text: "We counted 20 bolts.",
    status: "accepted")
  try book.setOpeningBalance(
    subject: "bolts", quantity: "20", effective: "2026-01-01T00:00:00Z", sourceID: source.id)
  let derived = try book.addItem(
    category: "record", kind: "analysis", title: "Stock observation", text: "20 bolts",
    inputs: [source.id])
  try expect(try book.lineage(derived.id).count == 1)
  try refuses("lineage") {
    _ = try book.addItem(category: "record", kind: "analysis", title: "Unfounded")
  }
}
check("draft has no inventory effect; acceptance applies once") {
  let handover = try book.addItem(
    category: "source", kind: "observation", title: "Handover", text: "Two bolts handed over.",
    status: "accepted")
  movement = try book.movement(
    subject: "bolts", quantity: "-2", occurrence: "sale-1", effective: "2026-01-02T00:00:00Z",
    input: handover.id)
  try expect(try book.balance(subject: "bolts")["quantity"].text == "20")
  movement = try book.accept(movement.id, token: "accept-1")
  try expect(try book.balance(subject: "bolts")["quantity"].text == "18")
}
check("duplicate evidence cannot duplicate effect") {
  try refuses("duplicate_effect") {
    _ = try book.movement(
      subject: "bolts", quantity: "-2", occurrence: "sale-1", effective: "2026-01-02T00:00:00Z",
      input: source.id, status: "accepted")
  }
  try expect(try book.balance(subject: "bolts")["quantity"].text == "18")
}
check("accepted forecast remains estimate") {
  let forecast = try book.movement(
    subject: "bolts", quantity: "-100", occurrence: "forecast-1", effective: "2026-01-03T00:00:00Z",
    input: source.id, meaning: "estimate")
  let accepted = try book.accept(forecast.id)
  try expect(accepted.meaning == "estimate" && accepted.status == "accepted")
  try expect(try book.balance(subject: "bolts")["quantity"].text == "18")
}
check("correction supersedes rather than adds") {
  let correction = try book.addItem(
    category: "source", kind: "correction", title: "Handover correction",
    text: "Only one bolt handed over.", status: "accepted")
  movement = try book.movement(
    subject: "bolts", quantity: "-1", occurrence: "sale-1", effective: "2026-01-02T00:00:00Z",
    input: correction.id, status: "accepted", supersedes: movement.id)
  try expect(try book.balance(subject: "bolts")["quantity"].text == "19")
}
check("withdrawing and undoing a correction preserve the prior accepted inventory effect") {
  let b = try Workbook.create(
    at: temp.appendingPathComponent("ReviewCorrection.sevra"), title: "Review")
  let s = try b.addItem(category: "source", kind: "observation", title: "Count", status: "accepted")
  try b.setOpeningBalance(subject: "stock", quantity: "20", effective: "2026-01-01", sourceID: s.id)
  let first = try b.movement(
    subject: "stock", quantity: "-2", occurrence: "delivery", effective: "2026-01-02", input: s.id,
    status: "accepted")
  let correction = try b.movement(
    subject: "stock", quantity: "-1", occurrence: "delivery", effective: "2026-01-02", input: s.id,
    supersedes: first.id)
  try expect(try b.balance(subject: "stock")["quantity"].text == "18")
  let withdrawn = try b.withdrawDraft(correction.id, token: "decline-correction")
  try expect(try b.withdrawDraft(correction.id, token: "decline-correction").id == withdrawn.id)
  try expect(try b.balance(subject: "stock")["quantity"].text == "18")
  try expect(withdrawn.status == "accepted" && withdrawn.data["quantity"].text == "-2")
  let restoredDraft = try b.undoItem(withdrawn.id)
  try expect(restoredDraft.status == "draft" && restoredDraft.data["quantity"].text == "-1")
  try expect(try b.balance(subject: "stock")["quantity"].text == "18")
  let accepted = try b.accept(restoredDraft.id)
  try expect(try b.balance(subject: "stock")["quantity"].text == "19")
  let undone = try b.undoItem(accepted.id)
  try expect(undone.status == "accepted" && undone.data["quantity"].text == "-2")
  try expect(try b.balance(subject: "stock")["quantity"].text == "18")
  try expect(try b.item(correction.id).status == "draft")
  try expect(try Workbook(b.url).balance(subject: "stock")["quantity"].text == "18")
  let args = Value.object([
    "subject": .string("stock"), "quantity": .string("-1"), "occurrence": .string("delivery"),
    "effective": .string("2026-01-02"), "input": .string(s.id), "supersedes": .string(undone.id),
  ])
  let revised = try WorkbookTools(b).execute("propose_movement", args)
  try expect(revised["supersedes"].text == undone.id && revised["status"].text == "draft")
  try expect(try b.balance(subject: "stock")["quantity"].text == "18")
  try refuses("stale_revision") { _ = try WorkbookTools(b).execute("propose_movement", args) }
  try refuses("movement_revision") {
    _ = try b.movement(
      subject: "different stock", quantity: "-1", occurrence: "delivery", effective: "2026-01-02",
      input: s.id, supersedes: revised["id"].text)
  }
  _ = try b.withdrawDraft(revised["id"].text)
  try expect(try b.balance(subject: "stock")["quantity"].text == "18")
  try expect(try b.verify()["ok"] == .bool(true))
}
check("citation snapshots preserve exact historical versions and current state without mutation") {
  let b = try Workbook.create(
    at: temp.appendingPathComponent("Citations.sevra"), title: "Citations")
  let input = try b.addItem(category: "source", kind: "assumption", title: "Sales assumption")
  let first = try b.addItem(
    category: "record", kind: "forecast", title: "Projection", meaning: "estimate",
    inputs: [input.id])
  let current = try b.withdrawDraft(first.id)
  let revision = try b.revision()
  let snapshot = try b.citationVersions([first.id, first.id, current.id])
  let historical = snapshot["versions"].array.first { $0["cited"]["id"].text == first.id }!
  try expect(snapshot["versions"].array.count == 2)
  try expect(historical["cited"]["status"].text == "draft")
  try expect(historical["current"]["status"].text == "rejected")
  try expect(historical["current"]["meaning"].text == "estimate")
  try expect(historical["isCurrentVersion"] == .bool(false))
  try expect(try b.item(first.id) == first)
  try expect(try b.revision() == revision)
  try refuses("citation_version") { _ = try b.citationVersions([first.logicalID]) }
  let cancelled = Cancellation()
  cancelled.cancel()
  try refuses("cancelled") { _ = try b.citationVersions([first.id], cancellation: cancelled) }
}
check("unknown basis does not become zero") {
  try refuses("unknown_basis") { _ = try book.balance(subject: "unknown") }
}
check("idempotency requires identical request") {
  let a = try book.addItem(
    category: "source", kind: "note", title: "Once", text: "same", token: "once")
  let b = try book.addItem(
    category: "source", kind: "note", title: "Once", text: "same", token: "once")
  try expect(a.id == b.id)
  try refuses("idempotency") {
    _ = try book.addItem(category: "source", kind: "note", title: "Changed", token: "once")
  }
}
check("stale concurrent revision rejected") {
  let rev = try book.revision()
  let second = try Workbook(book.url)
  _ = try second.addItem(category: "source", kind: "note", title: "Concurrent writer")
  try refuses("stale_revision") {
    _ = try book.addItem(
      category: "source", kind: "note", title: "Old state", expectedRevision: rev)
  }
}
check("include file, extract, Unicode FTS and filename substring") {
  let file = temp.appendingPathComponent("invoice-cafe-8324.txt")
  try "Café shipment includes brass bolts and delivery costs.".write(
    to: file, atomically: true, encoding: .utf8)
  fileItem = try book.importFile(file)
  try book.extract(fileItem.id)
  try FileManager.default.removeItem(at: file)
  try expect(try book.search("cafe bolts").hits.contains { $0.itemID == fileItem.id })
  try expect(try book.search("8324").hits.contains { $0.itemID == fileItem.id })
  try expect(try book.assetURL(fileItem.assetID!, verify: true).path.hasPrefix(book.url.path))
}
check("FTS escaping and empty queries") {
  _ = try book.search("\" OR * - : [ ]")
  try expect(try book.search("").hits.isEmpty)
  try refuses("query_limit") { _ = try book.search(String(repeating: "x", count: 3000)) }
}
check("external references detect changed and missing bytes") {
  let file = temp.appendingPathComponent("external.txt")
  try "original".write(to: file, atomically: true, encoding: .utf8)
  let linked = try book.importFile(file, linked: true)
  _ = try book.assetURL(linked.assetID!)
  try "changed".write(to: file, atomically: true, encoding: .utf8)
  try refuses("changed_asset") { _ = try book.assetURL(linked.assetID!) }
  try FileManager.default.removeItem(at: file)
  try refuses("missing_asset") { _ = try book.assetURL(linked.assetID!) }
}
check("cancelled import creates no reference") {
  let file = temp.appendingPathComponent("cancel.txt")
  try "cancel".write(to: file, atomically: true, encoding: .utf8)
  let before = try book.counts()
  let cancel = Cancellation()
  cancel.cancel()
  try refuses("cancelled") { _ = try book.importFile(file, cancellation: cancel) }
  try expect(try book.counts() == before)
}
check("Unicode and embedded zero bytes survive database round trips") {
  let text = "Café Bogotá 🌿 before\0after"
  let item = try book.addItem(
    category: "source", kind: "note", title: "Unicode fixture", text: text)
  try expect(try Workbook(book.url).item(item.id).text == text)
  try expect(try book.search("after").hits.contains { $0.itemID == item.id })
}
check("CSV quoted newlines, escaped quotes and CRLF") {
  let rows = try CSV.parse("name,note\r\nA,\"one\ntwo\"\r\nB,\"say \"\"yes\"\"\"\r\n")
  try expect(rows.count == 3 && rows[1][1] == "one\ntwo" && rows[2][1] == "say \"yes\"")
  try expect(try CSV.parse(CSV.encode(rows)) == rows)
  try refuses("csv") { _ = try CSV.parse("a,\"unterminated") }
}
check("table values, formulas, edits, undo and reopen") {
  table = try book.createDataset(
    title: "Purchases",
    columns: [
      .init(id: "name", title: "Name"), .init(id: "quantity", title: "Quantity", type: "decimal"),
      .init(id: "unit_cost", title: "Unit cost", type: "decimal"),
      .init(id: "total", title: "Total", type: "decimal", formula: "quantity*unit_cost"),
    ], rows: [["name": .string("Bolts"), "quantity": .string("3"), "unit_cost": .string("2.45")]],
    sourceID: source.id)
  let row = try book.rows(table.id)[0]
  try expect(book.calculatedValues(row, columns: table.columns)["total"]?.text == "7.35")
  var values = row.data.object
  values["quantity"] = .string("4")
  let edited = try book.editRow(row.id, values: values)
  try expect(book.calculatedValues(edited, columns: table.columns)["total"]?.text == "9.8")
  _ = try book.undoItem(edited.id)
  try expect(try Workbook(book.url).rows(table.id)[0].data["quantity"].text == "3")
}
check("native space validation and persistence") {
  let id = try book.saveSpace(
    title: "Purchases",
    definition: .init(components: [
      .init(type: "table", title: "Purchases", datasetID: table.id),
      .init(type: "chart", title: "Cost", datasetID: table.id, x: "name", y: "total"),
    ]))
  try expect(try Workbook(book.url).spaces().contains { $0.id == id })
  try refuses("view") {
    _ = try book.saveSpace(
      title: "Unsafe", definition: .init(components: [.init(type: "javascript", title: "Code")]))
  }
}
check("main conversation, chapter, tangent and bookmark") {
  let id = try book.addMessage("Plan purchasing", role: "user")
  try book.chapter(title: "Purchasing", message: id)
  try book.chapter(title: "Useful question", message: id, bookmark: true)
  let tangent = try book.tangent(title: "Hiring", parentMessage: id)
  _ = try book.addMessage("Hypothetical discussion", role: "user", conversation: tangent)
  try expect(try book.messages().count == 1)
  try expect(try book.messages(conversation: tangent).count == 1)
}

check("thread commands preserve titles and do not interpret quoted or negated instructions") {
  try expect(
    ConversationCommand.parse("Let’s explore this separately.") == .startThread(title: nil))
  try expect(ConversationCommand.parse("Go back to our main conversation!") == .backToConversation)
  try expect(
    ConversationCommand.parse("Start a thread called What if we raise prices?")
      == .startThread(title: "What if we raise prices?"))
  try expect(ConversationCommand.parse("tangent Hiring") == .startThread(title: "Hiring"))
  try expect(
    ConversationCommand.parse("Share summary with conversation: Keep prices at $12.")
      == .shareSummary(text: "Keep prices at $12."))
  for text in [
    "Don't go back to our main conversation", "Can a thread share workbook data?",
    "What does ‘Let's explore this separately’ mean?", "\"start a thread\"",
  ] {
    try expect(ConversationCommand.parse(text) == nil)
  }
}

check(
  "selected thread summary preserves origin and does not change business state or history scope"
) {
  let b = try Workbook.create(at: temp.appendingPathComponent("Summary.sevra"), title: "Summary")
  let original = try b.addMessage("Review next month's prices", role: "user")
  let thread = try b.tangent(title: "What if we raise prices?", parentMessage: original)
  let answer = try b.addMessage(
    "Estimate A: 12. Estimate B: 14. Neither is accepted.",
    role: "assistant", conversation: thread)
  let source = try b.addItem(
    category: "source", kind: "observation", title: "Count", status: "accepted")
  try b.setOpeningBalance(
    subject: "stock", quantity: "20", effective: "2026-01-01", sourceID: source.id)
  let before = try b.items().map(\.id).sorted()
  let balance = try b.balance(subject: "stock")
  let returned = try b.shareSummary(message: answer, text: "Use 12 as an estimate, pending review.")
  let shared = try b.messages().last!
  try expect(shared.id == returned && shared.body.contains("Use 12 as an estimate"))
  try expect(!shared.body.contains("Estimate B"))
  try expect(shared.body.contains("sevra://conversation/\(thread)?message=\(answer)"))
  try expect(try b.messages(conversation: thread).count == 1)
  try expect(try b.items().map(\.id).sorted() == before)
  try expect(try b.balance(subject: "stock") == balance)
  try expect(try b.agentRuns().isEmpty)
  try refuses("history_scope") { _ = try b.historyMessage(answer, conversation: "main") }
  let payload = try b.messagePayload(returned)
  try expect(payload["referenceOnly"] == .bool(true))
  let incomplete = try b.addMessage(
    "Not finished", role: "assistant", conversation: thread, state: "interrupted")
  try refuses("summary") { _ = try b.shareSummary(message: incomplete, text: "Pretend done") }
  try refuses("conversation") { _ = try b.shareSummary(message: original, text: "Already here") }
  try refuses("summary") { _ = try b.shareSummary(message: answer, text: "   ") }
  try expect(try Workbook(b.url).messages().last?.id == returned)
}

check("undo acceptance withdraws effect; later draft does not erase accepted state") {
  let b = try Workbook.create(at: temp.appendingPathComponent("Undo.sevra"), title: "Undo")
  let s = try b.addItem(category: "source", kind: "observation", title: "Count", status: "accepted")
  try b.setOpeningBalance(subject: "stock", quantity: "20", effective: "2026-01-01", sourceID: s.id)
  let draft = try b.movement(
    subject: "stock", quantity: "-2", occurrence: "one", effective: "2026-01-02", input: s.id)
  let accepted = try b.accept(draft.id)
  _ = try b.undoItem(accepted.id)
  try expect(try b.balance(subject: "stock")["quantity"].text == "20")
  let second = try b.movement(
    subject: "stock", quantity: "-2", occurrence: "two", effective: "2026-01-03", input: s.id,
    status: "accepted")
  _ = try b.movement(
    subject: "stock", quantity: "-1", occurrence: "two", effective: "2026-01-03", input: s.id,
    supersedes: second.id)
  try expect(try b.balance(subject: "stock")["quantity"].text == "18")
  _ = try b.movement(
    subject: "stock", quantity: "-2", occurrence: "three", effective: "2026-01-04", input: s.id,
    status: "accepted")
  try expect(try b.balance(subject: "stock")["quantity"].text == "16")
  try refuses("date") {
    _ = try b.movement(
      subject: "stock", quantity: "1", occurrence: "bad-date", effective: "tomorrow", input: s.id)
  }
  try expect(
    try BusinessTime.normalized("2026-01-01T19:00:00-05:00")
      == BusinessTime.normalized("2026-01-02"))
}
check("atomic paste, typed validation, one-step undo and redo") {
  let t = try book.createDataset(
    title: "Paste",
    columns: [
      .init(id: "name", title: "Name"), .init(id: "price", title: "Price", type: "decimal"),
    ],
    rows: [
      ["name": .string("A"), "price": .string("10")],
      ["name": .string("B"), "price": .string("2")],
    ], sourceID: source.id)
  let rows = try book.rows(t.id)
  let rev = try book.revision()
  try refuses("number") {
    _ = try book.editRows(
      t.id,
      edits: [
        .init(id: rows[0].id, values: ["name": .string("changed"), "price": .string("12")]),
        .init(id: rows[1].id, values: ["price": .string("wrong")]),
      ])
  }
  try expect(try book.revision() == rev)
  try expect(try book.rows(t.id)[0].data["name"].text == "A")
  let change = try book.editRows(
    t.id,
    edits: [
      .init(id: rows[0].id, values: ["name": .string("changed"), "price": .string("12")]),
      .init(id: rows[1].id, values: ["name": .string("second"), "price": .string("3")]),
    ])
  try expect(try book.rows(t.id, query: "changed").count == 1)
  try expect(try book.rows(t.id, sort: "price")[0].data["price"].text == "3")
  let inverse = try book.undoTableChange(change.id)
  try expect(try book.rows(t.id)[0].data["name"].text == "A")
  _ = try book.undoTableChange(inverse.id)
  try expect(try book.rows(t.id)[0].data["name"].text == "changed")
  try refuses("stale_revision") { _ = try book.undoTableChange(change.id) }
}
check("table proposal acceptance, retry, undo and redo preserve exact values") {
  let t = try book.createDataset(
    title: "Reviewed changes",
    columns: [
      .init(id: "quantity", title: "Quantity", type: "decimal"),
      .init(id: "cost", title: "Cost", type: "decimal"),
      .init(id: "total", title: "Total", type: "decimal", formula: "quantity*cost"),
    ], rows: [["quantity": .string("2"), "cost": .string("3")]], sourceID: source.id)
  let row = try book.rows(t.id)[0]
  let edits = [RowEdit(id: row.id, values: ["quantity": .string("4")])]
  let proposal = try book.proposeTableEdit(t.id, edits: edits, token: "proposal-retry")
  try expect(
    try book.proposeTableEdit(t.id, edits: edits, token: "proposal-retry").id == proposal.id)
  try expect(try book.rows(t.id)[0].data["quantity"].text == "2")
  let accepted = try book.accept(proposal.id, token: "accept-proposal-retry")
  try expect(try book.accept(proposal.id, token: "accept-proposal-retry").id == accepted.id)
  let changed = try book.rows(t.id)[0]
  try expect(changed.data["cost"].text == "3")
  try expect(book.calculatedValues(changed, columns: t.columns)["total"]?.text == "12")
  let undone = try book.undoItem(accepted.id)
  try expect(undone.status == "rejected")
  try expect(try book.rows(t.id)[0].data["quantity"].text == "2")
  let redone = try book.undoItem(undone.id)
  try expect(redone.status == "accepted")
  try expect(try book.rows(t.id)[0].data["quantity"].text == "4")
  _ = try book.undoItem(redone.id)
  try expect(try book.rows(t.id)[0].data["quantity"].text == "2")
}
check(
  "new table proposals preserve estimate meaning, formulas, provenance and reversible visibility"
) {
  let proposal = try book.proposeTable(
    title: "Revenue forecast",
    columns: [
      .init(id: "units", title: "Units", type: "decimal"),
      .init(id: "revenue", title: "Revenue", type: "decimal", formula: "units*12"),
    ], rows: [["units": .string("3")]], meaning: "estimate", inputs: [source.id])
  try expect(try !book.datasets().contains { $0.title == "Revenue forecast" })
  let accepted = try book.accept(proposal.id, token: "accept-table-creation")
  try expect(try book.accept(proposal.id, token: "accept-table-creation").id == accepted.id)
  let tableID = accepted.data["datasetID"].text
  let table = try book.dataset(tableID)
  let row = try book.rows(tableID)[0]
  try expect(row.meaning == "estimate" && row.scenario == "planning" && row.status == "accepted")
  try expect(book.calculatedValues(row, columns: table.columns)["revenue"]?.text == "36")
  try expect(try book.lineage(row.id).contains { $0["parent"].text == proposal.id })
  let withdrawn = try book.undoItem(accepted.id)
  try expect(try !book.datasets().contains { $0.id == tableID })
  try expect(try book.rows(tableID)[0].id == row.id)
  try refuses("stale_revision") { _ = try book.accept(accepted.id) }
  try refuses("rejected") { _ = try book.accept(withdrawn.id) }
  _ = try book.undoItem(withdrawn.id)
  try expect(try book.datasets().contains { $0.id == tableID })
}
check("agent table creation uses the preserved user request as evidence") {
  let request = try book.addItem(
    category: "source", kind: "request", title: "User request",
    text: "Plan ten brass units next month", meaning: "plan", status: "accepted")
  let tools = WorkbookTools(book, runID: "table-tool-fixture", requestSourceID: request.id)
  let result = try tools.execute(
    "propose_table",
    .object([
      "title": .string("Production plan"), "meaning": .string("plan"), "inputs": .array([]),
      "columns": .array([
        .object(["id": .string("units"), "title": .string("Units"), "type": .string("decimal")])
      ]), "rows": .array([.object(["units": .string("10")])]),
    ]))
  try expect(try book.lineage(result["id"].text).contains { $0["parent"].text == request.id })
  try expect(try !book.search("next month").hits.contains { $0.itemID == request.id })
  try expect(
    try book.search("next month", kind: "request").hits.contains { $0.itemID == request.id })
}
check("stale table proposal and stale undo roll back every change") {
  let t = try book.createDataset(
    title: "Concurrent proposal", columns: [.init(id: "n", title: "Number", type: "decimal")],
    rows: [["n": .string("1")], ["n": .string("2")]], sourceID: source.id)
  let rows = try book.rows(t.id)
  let proposal = try book.proposeTableEdit(
    t.id,
    edits: [
      .init(id: rows[0].id, values: ["n": .string("10")]),
      .init(id: rows[1].id, values: ["n": .string("20")]),
    ])
  let other = try book.editRow(rows[1].id, values: ["n": .string("3")])
  let revision = try book.revision()
  try refuses("stale_revision") { _ = try book.accept(proposal.id) }
  try expect(try book.revision() == revision)
  try expect(try book.rows(t.id)[0].id == rows[0].id)
  let valid = try book.proposeTableEdit(
    t.id, edits: [.init(id: other.id, values: ["n": .string("4")])])
  let accepted = try book.accept(valid.id)
  _ = try book.editRow(book.rows(t.id)[1].id, values: ["n": .string("5")])
  let latest = try book.revision()
  try refuses("stale_revision") { _ = try book.undoItem(accepted.id) }
  try expect(try book.revision() == latest)
  try expect(try book.rows(t.id)[1].data["n"].text == "5")
}
check("include linked evidence preserves indexed content and original history") {
  let file = temp.appendingPathComponent("include-linked.txt")
  try "Copper washers SKU-X94".write(to: file, atomically: true, encoding: .utf8)
  let linked = try book.importFile(file, linked: true)
  try book.extract(linked.id)
  let included = try book.includeLinked(linked.id)
  try FileManager.default.removeItem(at: file)
  try expect(try book.asset(included.assetID!).mode == "included")
  try expect(try book.search("copper").hits.contains { $0.itemID == included.id })
  try expect(included.supersedes == linked.id)
}
check("cancelled extraction retains the last usable index") {
  let c = Cancellation()
  c.cancel()
  try refuses("cancelled") { try book.extract(fileItem.id, cancellation: c) }
  try expect(try book.search("brass").hits.contains { $0.itemID == fileItem.id })
  try expect(try book.extractionStatus(fileItem.id)["state"].text == "partial")
}
check("XLSX shared strings, inline text, sparse cells, dates and cached formulas") {
  let path = temp.appendingPathComponent("sample.xlsx")
  let archive = try Archive(url: path, accessMode: .create)
  let parts = [
    "xl/workbook.xml":
      #"<workbook xmlns:r="r"><workbookPr date1904="0"/><sheets><sheet name="Orders" r:id="rId1"/></sheets></workbook>"#,
    "xl/_rels/workbook.xml.rels":
      #"<Relationships><Relationship Id="rId1" Type="x/worksheet" Target="worksheets/sheet1.xml"/></Relationships>"#,
    "xl/sharedStrings.xml":
      #"<sst><si><t>Café parts</t></si><si><r><t>Brass</t></r><r><t> bolts</t></r></si></sst>"#,
    "xl/styles.xml":
      #"<styleSheet><cellXfs><xf numFmtId="0"/><xf numFmtId="14"/></cellXfs></styleSheet>"#,
    "xl/worksheets/sheet1.xml":
      #"<worksheet><sheetData><row r="1"><c r="A1" t="s"><v>0</v></c><c r="C1" t="inlineStr"><is><t>Quantity</t></is></c></row><row r="3"><c r="A3" t="s"><v>1</v></c><c r="B3" s="1"><v>61</v></c><c r="C3"><v>2</v></c><c r="D3"><f>C3*3</f><v>6</v></c></row></sheetData></worksheet>"#,
  ]
  for (name, text) in parts {
    let bytes = Data(text.utf8)
    try archive.addEntry(
      with: name, type: .file, uncompressedSize: Int64(bytes.count),
      provider: { position, count in bytes.subdata(in: Int(position)..<Int(position) + count) })
  }
  let sheets = try XLSX.read(path)
  try expect(sheets.count == 1 && sheets[0].rows[0] == ["Café parts", "", "Quantity"])
  try expect(sheets[0].rows[1] == ["Brass bolts", "1900-03-01T00:00:00Z", "2", "6"])
  try expect(sheets[0].rowNumbers == [1, 3] && sheets[0].formulas["D3"] == "C3*3")
  let item = try book.importFile(path)
  try book.extract(item.id)
  let tables = try book.importXLSX(item.id)
  try expect(tables.count == 1 && tables[0].rowCount == 2)
  try expect(try book.search("cafe").hits.contains { $0.itemID == item.id })
}
check("XLSX refuses overflowing coordinates and expanded shared-string output") {
  func fixture(_ name: String, rows: String, shared: String = "") throws -> URL {
    let path = temp.appendingPathComponent(name + ".xlsx")
    let archive = try Archive(url: path, accessMode: .create)
    let parts = [
      "xl/workbook.xml":
        #"<workbook xmlns:r="r"><sheets><sheet name="Input" r:id="r1"/></sheets></workbook>"#,
      "xl/_rels/workbook.xml.rels":
        #"<Relationships><Relationship Id="r1" Type="x/worksheet" Target="worksheets/sheet1.xml"/></Relationships>"#,
      "xl/worksheets/sheet1.xml": "<worksheet><sheetData>" + rows + "</sheetData></worksheet>",
      "xl/sharedStrings.xml": "<sst><si><t>" + shared + "</t></si></sst>",
    ]
    for (name, text) in parts {
      let bytes = Data(text.utf8)
      try archive.addEntry(
        with: name, type: .file, uncompressedSize: Int64(bytes.count),
        provider: { position, count in bytes.subdata(in: Int(position)..<Int(position) + count) })
    }
    return path
  }
  let column = try fixture(
    "overflow-column",
    rows: "<row r=\"1\"><c r=\"" + String(repeating: "Z", count: 100) + "1\"><v>2</v></c></row>")
  try refuses("xlsx_limit") { _ = try XLSX.read(column) }
  let row = try fixture(
    "overflow-row",
    rows:
      "<row r=\"9223372036854775807\"><c r=\"A1\"><v>2</v></c></row><row><c r=\"A2\"><v>3</v></c></row>"
  )
  try refuses("xlsx_limit") { _ = try XLSX.read(row) }
  let invalidRow = try fixture(
    "noninteger-row",
    rows: "<row r=\"99999999999999999999999999999\"><c r=\"A1\"><v>2</v></c></row>")
  try refuses("xlsx_limit") { _ = try XLSX.read(invalidRow) }
  let rows = (1...1000).map { "<row r=\"\($0)\"><c r=\"A\($0)\" t=\"s\"><v>0</v></c></row>" }
    .joined()
  let expanded = try fixture(
    "expanded-text", rows: rows, shared: String(repeating: "x", count: 33_000))
  try refuses("structured_output") { _ = try XLSX.read(expanded) }
}
check("package metadata symlinks are refused before opening SQLite") {
  let folder = temp.appendingPathComponent("Symlink.sevra")
  try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
  try FileManager.default.createSymbolicLink(
    at: folder.appendingPathComponent("manifest.json"),
    withDestinationURL: book.url.appendingPathComponent("manifest.json"))
  try refuses("package_path") { _ = try Workbook(folder) }
}

check("rebuild search preserves results") {
  let hits = try book.search("brass").hits
  try book.rebuildSearch()
  try expect(try book.search("brass").hits.map(\.itemID) == hits.map(\.itemID))
}
check("coherent export and reopen with included bytes") {
  let archive = temp.appendingPathComponent("Shop.sevraz")
  try book.export(to: archive)
  let reopened = try Workbook.openArchive(archive, at: temp.appendingPathComponent("Shared.sevra"))
  try expect(try reopened.balance(subject: "bolts")["quantity"].text == "19")
  try expect(try reopened.search("brass").hits.count > 0)
  _ = try reopened.assetURL(fileItem.assetID!, verify: true)
}
check("archive expansion budget") {
  try refuses("archive_limit") {
    _ = try Workbook.openArchive(
      temp.appendingPathComponent("Shop.sevraz"), at: temp.appendingPathComponent("TooSmall.sevra"),
      maxBytes: 10)
  }
}
func runSQLite(_ database: URL, _ sql: String) throws {
  let process = Process()
  process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
  process.arguments = [database.path, sql]
  try process.run()
  process.waitUntilExit()
  try expect(process.terminationStatus == 0)
}
check("reject unexpected schema before writes") {
  for (name, sql) in [
    ("bad", "CREATE TABLE unexpected(secret TEXT);"),
    // "_" in a LIKE test would exempt a planted trigger that only looks internal.
    ("planted", "CREATE TRIGGER sqlite3evil AFTER INSERT ON items BEGIN DELETE FROM items; END;"),
  ] {
    let bad = temp.appendingPathComponent(name + ".sevra")
    try FileManager.default.copyItem(at: book.url, to: bad)
    try runSQLite(bad.appendingPathComponent("workbook.sqlite"), sql)
    try refuses("schema") { _ = try Workbook(bad) }
  }
}

check("conditional formulas are lazy, ranges resolve and rounding is explicit") {
  try expect(try Numbers.calculate("IF(2>1,ROUND(2.455,2),1/0)") == "2.46")
  try expect(try Numbers.calculate("IF(0,missing,7)") == "7")
  try refuses("precision") { _ = try Numbers.decimal("1.123456789012345678901234567890123456789") }
  let t = try book.createDataset(
    title: "Cell references",
    columns: [
      .init(id: "a", title: "A", type: "decimal"),
      .init(id: "b", title: "B", type: "decimal", formula: "A1+A2"),
    ], rows: [["a": .string("2")], ["a": .string("3")]], sourceID: source.id)
  try expect(try book.cellValue(t.id, address: "B1") == "5")
  try expect(
    try Numbers.calculate(
      "SUM(A1:A2)", resolve: { try Numbers.decimal(book.cellValue(t.id, address: $0)) }) == "5")
  try book.setColumns(
    t.id,
    columns: [
      .init(id: "a", title: "A", type: "decimal", formula: "B1"),
      .init(id: "b", title: "B", type: "decimal", formula: "A1"),
    ])
  try refuses("formula_cycle") { _ = try book.cellValue(t.id, address: "A1") }
}
check("search deduplicates chunks, paginates and rejects a stale cursor") {
  let s = try book.addItem(
    category: "source", kind: "note", title: "Pagination source",
    text: String(repeating: "pagination needle ", count: 500))
  let second = try book.addItem(
    category: "source", kind: "note", title: "Pagination second", text: "pagination needle")
  let first = try book.search("pagination", limit: 1)
  try expect(first.hits.count == 1 && first.nextCursor != nil)
  let next = try book.search("pagination", limit: 1, cursor: first.nextCursor)
  try expect(
    next.hits.count == 1 && next.hits[0].itemID != first.hits[0].itemID && next.nextCursor == nil)
  try expect(Set([first.hits[0].itemID, next.hits[0].itemID]) == Set([s.id, second.id]))
  _ = try book.addItem(category: "source", kind: "note", title: "Another source")
  try refuses("stale_cursor") { _ = try book.search("pagination", cursor: first.nextCursor) }
}

check("supplier comparison uses the expensive quote as its percentage denominator") {
  let t = try book.createDataset(
    title: "Prices",
    columns: [
      .init(id: "name", title: "Name"), .init(id: "price", title: "Price", type: "decimal"),
    ],
    rows: [
      ["name": .string("Oak"), "price": .string("24")],
      ["name": .string("Cedar"), "price": .string("27.5")],
    ], sourceID: source.id)
  let comparison = try book.compareRows(t.id, labelColumn: "name", valueColumn: "price")
  try expect(comparison["minimum"]["label"].text == "Oak")
  try expect(comparison["difference"].text == "3.5")
  try expect(comparison["percentageDenominator"].text == "27.5")
  try expect(comparison["percentCheaper"].text.hasPrefix("12.727272"))
  try expect(comparison["inputs"].array.count == 2)
}
check("CSV export preserves calculated values and quoted multiline cells") {
  let t = try book.createDataset(
    title: "Export",
    columns: [
      .init(id: "name", title: "Name"), .init(id: "price", title: "Price", type: "decimal"),
      .init(id: "total", title: "Total", type: "decimal", formula: "B1+B2"),
    ],
    rows: [
      ["name": .string("A, \"quoted\"\nname"), "price": .string("2.4")],
      ["name": .string("B"), "price": .string("2.75")],
    ], sourceID: source.id)
  let csv = temp.appendingPathComponent("calculated.csv")
  try book.exportCSV(t.id, to: csv)
  let rows = try CSV.parse(String(contentsOf: csv, encoding: .utf8))
  try expect(rows.count == 3 && rows[1][0] == "A, \"quoted\"\nname")
  try expect(rows[1][2] == "5.15" && rows[2][2] == "5.15")
  try refuses("exists") { try book.exportCSV(t.id, to: csv) }
}

check("live metric changes while a pinned result preserves values and evidence") {
  let t = try book.createDataset(
    title: "Metric", columns: [.init(id: "value", title: "Value", type: "decimal", unit: "kg")],
    rows: [["value": .string("2")], ["value": .string("3")]], sourceID: source.id)
  let c = Component(
    type: "metric", title: "Weight", datasetID: t.id, y: "value", aggregation: "SUM")
  let space = try book.saveSpace(title: "Live", definition: .init(components: [c]))
  let pinnedID = try book.pinSpace(space)
  let pinned = try book.spaces().first { $0.id == pinnedID }!.definition.components[0]
  let first = try book.rows(t.id)[0]
  _ = try book.editRow(first.id, values: ["value": .string("7")])
  try expect(try book.componentMetric(c, data: book.componentData(c)) == "10")
  try expect(try book.componentMetric(pinned, data: book.componentData(pinned)) == "5")
  try expect(pinned.snapshot?.rows[0].id == first.id)
  try expect(pinned.snapshot?.columns[0].unit == "kg")
}
check("column type changes validate existing data and formula history restores") {
  let t = try book.createDataset(
    title: "Types",
    columns: [.init(id: "name", title: "Name"), .init(id: "n", title: "Number", type: "decimal")],
    rows: [["name": .string("Oak"), "n": .string("2")]], sourceID: source.id)
  try refuses {
    try book.setColumns(
      t.id,
      columns: [
        .init(id: "name", title: "Name", type: "decimal"),
        .init(id: "n", title: "Number", type: "decimal"),
      ])
  }
  try book.setColumns(
    t.id,
    columns: [
      .init(id: "name", title: "Name"),
      .init(id: "n", title: "Number", type: "decimal", formula: "2+3"),
    ])
  try expect(try book.columnHistory(t.id).count == 2)
  try book.restoreColumns(t.id, version: 1)
  try expect(try book.dataset(t.id).columns[1].formula == nil)
}
check("structured import resumes committed batches without duplicating rows") {
  let s = try book.addItem(category: "source", kind: "fixture", title: "Resumable intake")
  let data = (0..<2500).map { ["n": Value.string(String($0))] }
  let columns = [Column(id: "n", title: "N", type: "decimal")]
  let cancel = Cancellation()
  try refuses("cancelled") {
    _ = try book.importDataset(
      title: "Resumable", columns: columns, rows: data, sourceID: s.id, cancellation: cancel,
      progress: { done, _ in if done == 1000 { cancel.cancel() } })
  }
  let partial = try book.intakeStatus().first { $0["sourceID"].text == s.id }!
  try expect(partial["completed"].int == 1000 && partial["state"].text == "partial")
  let resumed = try book.importDataset(
    title: "Resumable", columns: columns, rows: data, sourceID: s.id)
  let retried = try book.importDataset(
    title: "Resumable", columns: columns, rows: data, sourceID: s.id)
  try expect(resumed.rowCount == 2500 && resumed.id == retried.id && retried.rowCount == 2500)
}
check("structured import batches by value bytes and reports only committed rows") {
  let s = try book.addItem(category: "source", kind: "fixture", title: "Wide intake")
  let note = String(repeating: "n", count: 16_000)
  let data = (0..<800).map { ["n": Value.string(String($0)), "note": Value.string(note)] }
  let columns = [Column(id: "n", title: "N", type: "decimal"), Column(id: "note", title: "Note")]
  let cancel = Cancellation()
  var seen: [Int] = []
  try refuses("cancelled") {
    _ = try book.importDataset(
      title: "Wide", columns: columns, rows: data, sourceID: s.id, cancellation: cancel,
      progress: { done, _ in
        seen.append(done)
        cancel.cancel()
      })
  }
  let partial = try book.intakeStatus().first { $0["sourceID"].text == s.id }!
  let table = try book.dataset(partial["datasetID"].text)
  try expect(seen == [374] && table.rowCount == 374 && table.unfinishedImportTotal == 800)
  let resumed = try book.importDataset(
    title: "Wide", columns: columns, rows: data, sourceID: s.id,
    progress: { done, _ in seen.append(done) })
  try expect(seen == [374, 374, 748, 800] && resumed.rowCount == 800)
  try expect(resumed.unfinishedImportTotal == nil)
  try expect(try book.rows(table.id, offset: 373, limit: 2).map { $0.data["n"].text } == ["373", "374"])
}
check("multi-sheet XLSX import reports rows across every sheet") {
  let path = temp.appendingPathComponent("Two sheets.xlsx")
  let archive = try Archive(url: path, accessMode: .create)
  func sheet(_ rows: Int) -> String {
    let cells = (1...rows).map { #"<row r="\#($0)"><c r="A\#($0)"><v>\#($0)</v></c></row>"# }
    return "<worksheet><sheetData>" + cells.joined() + "</sheetData></worksheet>"
  }
  let parts = [
    "xl/workbook.xml":
      #"<workbook xmlns:r="r"><sheets><sheet name="One" r:id="r1"/><sheet name="Two" r:id="r2"/></sheets></workbook>"#,
    "xl/_rels/workbook.xml.rels":
      #"<Relationships><Relationship Id="r1" Type="x/worksheet" Target="worksheets/sheet1.xml"/><Relationship Id="r2" Type="x/worksheet" Target="worksheets/sheet2.xml"/></Relationships>"#,
    "xl/worksheets/sheet1.xml": sheet(3), "xl/worksheets/sheet2.xml": sheet(2),
  ]
  for (name, text) in parts {
    let bytes = Data(text.utf8)
    try archive.addEntry(
      with: name, type: .file, uncompressedSize: Int64(bytes.count),
      provider: { position, count in bytes.subdata(in: Int(position)..<Int(position) + count) })
  }
  let source = try book.importFile(path)
  try book.extract(source.id)
  var seen: [String] = []
  let tables = try book.importXLSX(source.id, progress: { seen.append("\($0)/\($1)") })
  try expect(tables.map(\.rowCount) == [3, 2] && seen == ["3/5", "5/5"])
}
check("copy cancellation and extraction deadlines leave the workbook usable") {
  let file = temp.appendingPathComponent("cancel-large.bin")
  try Data(repeating: 42, count: 4_000_000).write(to: file)
  let cancel = Cancellation()
  let before = try book.items(limit: 500).count
  try refuses("cancelled") {
    _ = try book.importFile(file, cancellation: cancel, progress: { _, _ in cancel.cancel() })
  }
  try expect(try book.items(limit: 500).count == before)
  try expect(
    try FileManager.default.contentsOfDirectory(
      atPath: book.url.appendingPathComponent("staging").path
    ).isEmpty)
  try refuses("deadline") {
    _ = try Extractor.extract(file, cancellation: Cancellation(deadlineAfterSeconds: 0))
  }
}
check("native PDF text and image OCR create searchable exact source locators") {
  func draw(_ context: CGContext) {
    context.setFillColor(CGColor(gray: 1, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: 1000, height: 300))
    context.textPosition = CGPoint(x: 40, y: 150)
    let line = CTLineCreateWithAttributedString(
      NSAttributedString(
        string: "INVOICE BRASS 1042",
        attributes: [
          NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName(
            "Helvetica" as CFString, 48, nil),
          NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(
            gray: 0, alpha: 1),
        ]))
    CTLineDraw(line, context)
  }
  let pdf = temp.appendingPathComponent("invoice.pdf")
  var box = CGRect(x: 0, y: 0, width: 1000, height: 300)
  let context = CGContext(pdf as CFURL, mediaBox: &box, nil)!
  context.beginPDFPage(nil)
  draw(context)
  context.endPDFPage()
  context.closePDF()
  let pdfSource = try book.importFile(pdf)
  try book.extract(pdfSource.id)
  let bitmap = CGContext(
    data: nil, width: 1000, height: 300, bitsPerComponent: 8, bytesPerRow: 4000,
    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
  draw(bitmap)
  let png = temp.appendingPathComponent("receipt.png")
  let destination = CGImageDestinationCreateWithURL(png as CFURL, "public.png" as CFString, 1, nil)!
  CGImageDestinationAddImage(destination, bitmap.makeImage()!, nil)
  try expect(CGImageDestinationFinalize(destination))
  let imageSource = try book.importFile(png)
  try book.extract(imageSource.id)
  let hits = try book.search("invoice brass").hits
  try expect(hits.contains { $0.itemID == pdfSource.id && $0.locator.contains("page=1") })
  try expect(hits.contains { $0.itemID == imageSource.id && $0.locator.contains("image") })
}
check("explicit archive intake preserves member lineage and retry identity") {
  let file = temp.appendingPathComponent("members.zip")
  let archive = try Archive(url: file, accessMode: .create)
  let contents = [
    "quotes/parts.csv": "name,cost\nBrass,12\n", "terms.txt": "Delivery excludes shipping.",
  ]
  for (path, text) in contents {
    let bytes = Data(text.utf8)
    try archive.addEntry(
      with: path, type: .file, uncompressedSize: Int64(bytes.count),
      provider: { position, size in bytes.subdata(in: Int(position)..<(Int(position) + size)) })
  }
  let source = try book.importFile(file)
  try expect(try book.archiveMembers(source.id).count == 2)
  let included = try book.includeArchiveMembers(source.id, paths: ["quotes/parts.csv"])
  let tables = try book.datasets().count
  let retried = try book.includeArchiveMembers(source.id, paths: ["quotes/parts.csv"])
  try expect(included.map(\.id) == retried.map(\.id))
  try expect(try book.datasets().count == tables)
  try expect(try book.lineage(included[0].id).contains { $0["parent"].text == source.id })
  try expect(try book.search("brass").hits.contains { $0.itemID == included[0].id })
  try refuses("archive_member") {
    _ = try book.includeArchiveMembers(source.id, paths: ["../missing"])
  }
  let cancel = Cancellation()
  cancel.cancel()
  try refuses("cancelled") {
    _ = try book.includeArchiveMembers(source.id, paths: ["terms.txt"], cancellation: cancel)
  }
}
check("archive traversal entries cannot escape their destination") {
  let file = temp.appendingPathComponent("hostile.sevraz")
  let archive = try Archive(url: file, accessMode: .create)
  try archive.addEntry(
    with: "../escaped.txt", type: .file, uncompressedSize: Int64(3),
    provider: { _, _ in Data("bad".utf8) }
  )
  try refuses {
    _ = try Workbook.openArchive(file, at: temp.appendingPathComponent("Hostile.sevra"))
  }
  try expect(
    !FileManager.default.fileExists(atPath: temp.appendingPathComponent("escaped.txt").path))
}

check("deep JSON and long dependency chains are refused by name on a worker stack") {
  /// The last column comes first, so nothing is cached on the way down.
  func chain(_ length: Int, _ extra: String = "") -> [Column] {
    ((1..<length).map {
      Column(id: "c\($0)", title: "C\($0)", type: "decimal", formula: "c\($0 - 1)" + extra)
    } + [Column(id: "c0", title: "Base", type: "decimal")]).reversed()
  }
  let row = try book.addItem(
    category: "source", kind: "observation", title: "Row", data: .object(["c0": .string("1")]))
  try expect(book.calculatedValues(row, columns: chain(100))["c99"] == .string("1"))
  let refused = book.calculatedValues(row, columns: chain(200))["c199"]?.text ?? ""
  try expect(refused.contains("exceeds 128"), refused)
  var failure: Error?
  let finished = DispatchSemaphore(value: 0)
  let worker = Thread {
    do {
      func nested(_ depth: Int, _ open: String, _ close: String) -> String {
        String(repeating: open, count: depth) + String(repeating: close, count: depth)
      }
      try expect(try Value.parse(nested(128, "[", "]")) != .null)
      for depth in [129, 423, 5000] {
        try refuses("json_depth") { _ = try Value.parse(nested(depth, "[", "]")) }
        try refuses("json_depth") { _ = try Value.parse(nested(depth, "{\"a\":", "}")) }
      }
      // Every other decoder reaches nested data through Value too.
      try refuses("json_depth") {
        _ = try JSONDecoder().decode(Value.self, from: Data(nested(300, "[", "]").utf8))
      }
      try expect(try Value.parse("\"" + String(repeating: "[", count: 300) + "\"") != .null)
      try refuses("json_depth") { try Value.requireDepth(nested(150, "{\"children\":[", "]}")) }
      // Column chains multiply each formula's own depth. Here that stops at the stack it has.
      for extra in ["", String(repeating: "+1", count: 60)] {
        let long = book.calculatedValues(row, columns: chain(400, extra))["c399"]?.text ?? ""
        try expect(long.hasPrefix("#ERROR"), long)
      }
    } catch { failure = error }
    finished.signal()
  }
  worker.stackSize = 512 * 1024
  worker.start()
  finished.wait()
  if let failure { throw failure }
}

check("formulas that can never evaluate are refused when saved") {
  func function(_ terms: Int) throws -> ApplicationDefinition {
    try book.saveApplicationDefinition(
      logicalID: identifier(),
      content: .object([
        "kind": .string("function"), "title": .string("Sum"), "description": .string("Long"),
        "parameters": .array([]),
        "payload": .object([
          "expression": .string(Array(repeating: "1", count: terms).joined(separator: "+"))
        ]),
      ]))
  }
  try refuses("formula_limit") { _ = try function(65) }
  try expect(try book.evaluateApplicationDefinition(function(64).id)["result"].text == "64")
}

check("saved URLs hide secrets by name and keep every other parameter's exact bytes") {
  let saved = Workbook.safeOrigin(
    URL(string: "https://a.example/x?APIKey=1&client_secret=2&Refresh_Token=3&q=a%2Bb&r=c+d#f")!)
  try expect(
    saved == "https://a.example/x?APIKey=REDACTED&client_secret=REDACTED&Refresh_Token=REDACTED"
      + "&q=a%2Bb&r=c+d")
  let words = Workbook.safeOrigin(
    URL(string: "https://a.example/x?auth=1&api-key=2&sig=3&keyword=shoes&design=a&author=b")!)
  try expect(
    words == "https://a.example/x?auth=REDACTED&api-key=REDACTED&sig=REDACTED"
      + "&keyword=shoes&design=a&author=b")
}
check("an archive cannot choose an outside file for this Mac to read") {
  let folder = temp.appendingPathComponent("LinkedArchive")
  try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
  let outside = folder.appendingPathComponent("outside.txt")
  try Data("Outside the workbook".utf8).write(to: outside)
  let source = try Workbook.create(
    at: folder.appendingPathComponent("Source.sevra"), title: "Source")
  _ = try source.importFile(outside, linked: true)
  let clean = folder.appendingPathComponent("clean.sevraz")
  try source.export(to: clean)
  // A cleared link is portable: it stays visible as a file to reconnect.
  let opened = try Workbook.openArchive(clean, at: folder.appendingPathComponent("Clean.sevra"))
  try expect(try opened.verify()["database"] == .string("ok"))
  for (name, field, value) in [("path", "path", outside.path), ("bookmark", "bookmark", "AAAA")] {
    let unpacked = folder.appendingPathComponent(name)
    let hostile = folder.appendingPathComponent(name + ".sevraz")
    let written = try Archive(url: hostile, accessMode: .create)
    for entry in try Archive(url: clean, accessMode: .read) {
      _ = try Archive(url: clean, accessMode: .read).extract(
        entry, to: unpacked.appendingPathComponent(entry.path))
    }
    try runSQLite(
      unpacked.appendingPathComponent("workbook.sqlite"),
      "UPDATE assets SET \(field)='\(value)' WHERE mode='linked';")
    for name in ["manifest.json", "workbook.sqlite"] {
      try written.addEntry(with: name, relativeTo: unpacked)
    }
    try refuses("archive_linked") {
      _ = try Workbook.openArchive(hostile, at: folder.appendingPathComponent("Open-" + name))
    }
  }
}
check("a file rewritten in place during import is refused, not stored torn") {
  let file = temp.appendingPathComponent("rewritten.bin")
  try Data(repeating: 65, count: 3 * 1024 * 1024).write(to: file)
  var rewritten = false
  try refuses("changed_file") {
    _ = try book.importFile(file) { _, _ in
      guard !rewritten else { return }
      rewritten = true
      let handle = try! FileHandle(forWritingTo: file)
      try! handle.seek(toOffset: 2 * 1024 * 1024)
      try! handle.write(contentsOf: Data("Newer".utf8))
      try! handle.close()
    }
  }
  try expect(rewritten)
  _ = try book.importFile(file)
}

check("search cancellation and deadline preserve the next query") {
  let cancelled = Cancellation()
  cancelled.cancel()
  try refuses("cancelled") { _ = try book.search("brass", cancellation: cancelled) }
  try refuses("deadline") { _ = try book.search("brass", deadlineSeconds: 0) }
  try expect(try !book.search("brass").hits.isEmpty)
}
check("pinning retries return the original snapshot") {
  let id = try book.saveSpace(
    title: "Pin retry",
    definition: .init(components: [.init(type: "text", title: "Memo", text: "Original")]))
  let first = try book.pinSpace(id, title: "Saved", token: "pin-once")
  _ = try book.saveSpace(
    id: id, title: "Changed",
    definition: .init(components: [.init(type: "text", title: "Memo", text: "Changed")]),
    expectedVersion: 1)
  let retried = try book.pinSpace(id, title: "Saved", token: "pin-once")
  try expect(first == retried)
  try expect(
    try book.spaces().first { $0.id == first }?.definition.components[0].text == "Original")
}
checkSpaceSnapshots(at: temp)
checkAssetPreview(at: temp)
checkAssetCopies(at: temp)
checkRecentItems(at: temp)
checkSearchSnippets(at: temp)
checkConversationContext(at: temp)
checkConversationNavigation(at: temp)
checkContinuationEvidence(at: temp)
checkToolReceipts(at: temp)
checkDocumentComposition(at: temp)
checkDocumentCopyChoices(at: temp)
checkFoldersAndTemplates(at: temp)
checkReferences(at: temp)
checkInlineReferences(at: temp)
checkFileReferences(at: temp)
checkAgentReferences(at: temp)
checkContextualIntake(at: temp)
checkTableIntake(at: temp)
checkManagedDatasets(at: temp)
checkDatasetDefinitions(at: temp)
checkSheetFormulas(at: temp)
checkDatasetQueries(at: temp)
checkApplicationDefinitions(at: temp)
checkApplicationActions(at: temp)
checkDocumentActions(at: temp)
checkDefinitionTools(at: temp)
checkWorkflowTools(at: temp)
checkWorkflowInterpretations(at: temp)
checkWorkflowExtractions(at: temp)
checkWorkflowIntakes(at: temp)
checkDefinitionResults(at: temp)
checkWorkflows(at: temp)
checkPersistence(at: temp)
checkBusinessEvents(at: temp)
checkInventoryEventState(at: temp)
checkInventoryConditions(at: temp)
checkAutomaticAncestry(at: temp)
checkSpaceEditing(at: temp)
checkCalendarSchedules()
checkConditionTransitions()
checkAutomationDefinitions(at: temp)
checkAutomationPlanning(at: temp)
checkAutomationExecution(at: temp)
checkAutomationCausality(at: temp)
checkSharedBusinessAdmissions(at: temp)
checkConditionInputs(at: temp)
checkDerivationRoles(at: temp)
checkBusinessOrigins(at: temp)
checkConditionOrigins(at: temp)
checkBusinessInputs(at: temp)
checkConditionCauses(at: temp)
checkConditionDispatch(at: temp)
print("\(passed) passed; \(failed) failed")
exit(failed == 0 ? 0 : 1)
