import Foundation
import SevraCore
import SevraPreviewUI

@MainActor func checkFormDrafts() async throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(
    "sevra-form-drafts-" + identifier())
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: root) }
  let b = try Workbook.create(at: root.appendingPathComponent("Forms.sevra"), title: "Forms")
  let s = try b.addItem(
    category: "source", kind: "observation", title: "Receipt", status: "accepted")
  let action = try b.saveApplicationDefinition(
    logicalID: identifier(), content: ActionRegistry.receivingDefinition())
  let form = try b.saveApplicationDefinition(
    logicalID: identifier(), content: ActionRegistry.formDefinition(target: action))
  func inputs(_ number: String) -> Value {
    .object([
      "delivery": .string(number), "effective": .string("2026-10-28"), "evidence": .string(s.id),
      "lines": .array([
        .object(["line": .string("1"), "subject": .string("bolts"), "quantity": .string("5")])
      ]),
    ])
  }
  let firstKey = try FormDraftState.componentKey(spaceID: "home:component:x", componentID: "y")
  let secondKey = try FormDraftState.componentKey(spaceID: "home", componentID: "x:component:y")
  try require(
    firstKey != secondKey, "form_check", "Structured locations collided through delimiter text")
  let maximumKey = try FormDraftState.componentKey(
    spaceID: String(repeating: "s", count: 256), componentID: String(repeating: "c", count: 256))
  try require(
    maximumKey.utf8.count < 512, "form_check", "Maximum legal component IDs exceed draft key limits"
  )
  let scope = FormDraftScope()
  let saved1 = await scope.open(b)
  try require(saved1, "form_check", "Cannot open scope")
  let first = scope.session("Home:receiving")!
  await first.open(form.logicalID)
  first.update(
    .object([
      "delivery": .string("unsent café 日本語"),
      "lines": .array([.object(["quantity": .string("not a number yet")])]),
    ]))
  let before = try b.revision()
  let saved2 = await scope.flush()
  try require(saved2, "form_check", "Cannot flush incomplete draft")
  try require(try b.revision() == before, "form_check", "Keystrokes changed business revision")
  let reopened = try Workbook(b.url)
  let second = FormDraftSession(workbook: reopened, key: "Home:receiving")
  await second.open(form.id)
  try require(
    second.state?.arguments == first.state?.arguments, "form_check",
    "Recovery lost incomplete exact inputs")
  await second.prepare()
  try require(
    second.preview == nil && second.failure != nil
      && second.state?.arguments == first.state?.arguments,
    "form_check", "Validation failure dropped the draft")
  first.update(inputs("first-window"))
  let saved3 = await first.flush()
  try require(saved3, "form_check", "First writer failed")
  second.update(inputs("second-window"))
  let secondSaved = await second.flush()
  try require(!secondSaved && second.conflict, "form_check", "Concurrent form overwrite was silent")
  await second.keepBoth()
  try require(
    !second.conflict && second.state?.alternatives.count == 1
      && second.state?.alternatives[0].arguments == first.state?.arguments,
    "form_check", "Keep both lost inputs")
  await second.prepare()
  try require(second.preview != nil, "form_check", second.failure ?? "No preview")
  await second.submit()
  try require(
    second.state?.lastReceipt?["proposals"].array.count == 1, "form_check",
    second.failure ?? "No submitted receipt")
  let saved4 = await second.flush()
  try require(saved4, "form_check", "Submitted state did not save")
  let submittedRevision = try b.revision()
  let recovered = FormDraftSession(workbook: try Workbook(b.url), key: "Home:receiving")
  await recovered.open(form.id)
  try require(
    recovered.state?.lastReceipt == second.state?.lastReceipt, "form_check",
    "Submitted receipt did not recover")
  await recovered.prepare()
  await recovered.submit()
  try require(
    try b.revision() == submittedRevision, "form_check", "Recovered submitted form ran twice")

  let isolated = FormDraftScope()
  let isolatedOpened = await isolated.open(b)
  try require(isolatedOpened, "form_check", "Cannot open isolated draft scope")
  let locationOne = isolated.session(firstKey)!
  let locationTwo = isolated.session(secondKey)!
  await locationOne.open(form.id)
  await locationTwo.open(form.id)
  locationOne.update(.object(["delivery": .string("location one")]))
  locationTwo.update(.object(["delivery": .string("location two")]))
  let isolatedSaved = await isolated.flush()
  try require(isolatedSaved, "form_check", "Cannot flush distinct locations")
  try require(
    try b.formDraft(firstKey)?.arguments["delivery"] == .string("location one")
      && b.formDraft(secondKey)?.arguments["delivery"] == .string("location two"),
    "form_check", "Distinct components shared an incomplete draft")
  let otherBook = try Workbook.create(
    at: root.appendingPathComponent("Other.sevra"), title: "Other")
  let switched = await isolated.open(otherBook)
  try require(
    switched && isolated.session(firstKey) !== locationOne, "form_check",
    "Workbook switch retained an old session")
  try require(
    try otherBook.formDraft(firstKey) == nil, "form_check",
    "Workbook switch copied another workbook's draft")

  // Simulate a crash after the business transaction and before the presentation checkpoint.
  let crash = FormDraftSession(workbook: b, key: "Crash")
  await crash.open(form.id)
  crash.update(inputs("crash-delivery"))
  let saved5 = await crash.flush()
  try require(saved5, "form_check", "Cannot save retry identity")
  let crashState = crash.state!
  let preview = try b.previewFormDraft(crashState)
  let receipt = try b.invokeApplicationAction(
    crashState.definitionID, arguments: crashState.arguments,
    preview: preview, token: crashState.invocationToken, actor: .human("SevraNativeForm"))
  let crashRecovered = FormDraftSession(workbook: try Workbook(b.url), key: "Crash")
  await crashRecovered.open(form.id)
  try require(
    crashRecovered.state?.lastReceipt == receipt, "form_check",
    "Crash recovery did not reconcile the already saved receipt")

  let stale = FormDraftSession(workbook: b, key: "Stale")
  await stale.open(form.id)
  stale.update(inputs("stale-delivery"))
  let saved6 = await stale.flush()
  try require(saved6, "form_check", "Cannot save stale test inputs")
  var actionContent = action.content.object
  actionContent["description"] = .string("Changed live dependency")
  _ = try b.saveApplicationDefinition(
    logicalID: action.logicalID, content: .object(actionContent), expectedDefinitionID: action.id)
  await stale.prepare()
  try require(
    stale.preview == nil && stale.state?.arguments == inputs("stale-delivery"), "form_check",
    "Live edit silently retargeted a draft")
  await stale.useCurrent(form.id, carryInputs: true)
  await stale.prepare()
  try require(
    stale.preview != nil && stale.state?.alternatives.count == 1, "form_check",
    "Explicit refresh failed to retain old inputs")
  // A form that changed after its preview offers Preview again, then the current form.
  let late = FormDraftSession(workbook: b, key: "Late")
  await late.open(form.id)
  late.update(inputs("late-delivery"))
  await late.prepare()
  try require(late.preview != nil, "form_check", late.failure ?? "No preview")
  let liveAction = try b.applicationDefinition(action.logicalID)
  actionContent["description"] = .string("Changed after the preview")
  _ = try b.saveApplicationDefinition(
    logicalID: action.logicalID, content: .object(actionContent),
    expectedDefinitionID: liveAction.id)
  await late.submit()
  try require(
    late.preview == nil && late.failure != nil && late.state?.lastReceipt == nil, "form_check",
    "A refused submission kept showing its old preview")
  await late.prepare()
  try require(late.stale, "form_check", "A changed live action offered no way forward")
  await late.useCurrent(form.id, carryInputs: true)
  try require(!late.stale, "form_check", "The current form still reports a stale definition")
  await late.prepare()
  try require(late.preview != nil, "form_check", late.failure ?? "No current preview")

  // Keep both leaves two drafts that can each be sent.
  let left = FormDraftSession(workbook: b, key: "Both")
  await left.open(form.id)
  left.update(inputs("both-left"))
  let leftSaved = await left.flush()
  let right = FormDraftSession(workbook: try Workbook(b.url), key: "Both")
  await right.open(form.id)
  left.update(inputs("both-left-edited"))
  let leftEdited = await left.flush()
  right.update(inputs("both-right"))
  let rightRefused = await right.flush()
  try require(leftSaved && leftEdited && !rightRefused, "form_check", "No draft conflict")
  await right.keepBoth()
  await right.prepare()
  await right.submit()
  try require(right.state?.lastReceipt != nil, "form_check", right.failure ?? "Right not sent")
  await right.restoreAlternative(right.state!.alternatives[0].id)
  await right.prepare()
  await right.submit()
  try require(
    right.state?.lastReceipt != nil && right.state?.arguments == inputs("both-left-edited"),
    "form_check", right.failure ?? "The kept draft could not be sent")

  // A draft whose retry identity went to other inputs still opens, inputs intact.
  var spent = try b.newFormDraft(form.id)
  spent.invocationToken = right.state!.invocationToken
  spent.arguments = inputs("spent-identity")
  _ = try b.saveFormDraft("Spent", state: spent, expected: nil)
  let recoveredSpent = FormDraftSession(workbook: b, key: "Spent")
  await recoveredSpent.open(form.id)
  await recoveredSpent.prepare()
  await recoveredSpent.submit()
  try require(
    recoveredSpent.state?.arguments == inputs("spent-identity")
      && recoveredSpent.state?.lastReceipt != nil,
    "form_check", recoveredSpent.failure ?? "A spent retry identity stranded its inputs")

  // Only unsent inputs hold a draft slot.
  let slots = try Workbook.create(at: root.appendingPathComponent("Slots.sevra"), title: "Slots")
  let slotAction = try slots.saveApplicationDefinition(
    logicalID: identifier(), content: ActionRegistry.receivingDefinition())
  let slotForm = try slots.saveApplicationDefinition(
    logicalID: identifier(), content: ActionRegistry.formDefinition(target: slotAction))
  let viewed = FormDraftSession(workbook: slots, key: "viewed")
  await viewed.open(slotForm.id)
  let viewedFlushed = await viewed.flush()
  try require(
    try viewedFlushed && slots.formDraft("viewed") == nil, "form_check",
    "Viewing a form took a draft slot")
  viewed.update(.object(["delivery": .string("typed")]))
  let typedFlushed = await viewed.flush()
  try require(
    try typedFlushed && slots.formDraft("viewed") != nil, "form_check",
    "A first edit was not saved")
  let blank = try slots.newFormDraft(slotForm.id)
  var typed = blank
  typed.arguments = .object(["delivery": .string("typed")])
  for index in 1..<256 { _ = try slots.saveFormDraft("slot-\(index)", state: typed, expected: nil) }
  do {
    _ = try slots.saveFormDraft("slot-256", state: typed, expected: nil)
    throw SevraError("form_check", "A 257th unsent draft was saved")
  } catch let error as SevraError where error.code == "form_draft_limit" {}
  _ = try slots.saveFormDraft("slot-1", state: blank, expected: typed)
  _ = try slots.saveFormDraft("slot-256", state: typed, expected: nil)
  try require(
    try slots.formDraft("slot-1") == nil && slots.formDraft("slot-256") != nil, "form_check",
    "An empty draft kept its slot from a form with inputs")

  // An optional number or date can be emptied. A required field and plain text stay text.
  func field(_ type: String, required: Bool) -> Value {
    .object(["type": .string(type), "required": .bool(required)])
  }
  try require(
    formFieldValue("", parameter: field("decimal", required: false)) == .null
      && formFieldValue("", parameter: field("date", required: false)) == .null
      && formFieldValue("2", parameter: field("decimal", required: false)) == .string("2")
      && formFieldValue("", parameter: field("decimal", required: true)) == .string("")
      && formFieldValue("", parameter: field("text", required: false)) == .string(""),
    "form_check", "An emptied optional field kept an empty string")

  let reconstruct = try b.reconstruct(to: root.appendingPathComponent("Reconstructed.sevra"))
  try require(
    try reconstruct.formDraft("Home:receiving") == b.formDraft("Home:receiving"), "form_check",
    "Reconstruction lost form checkpoints")
  try require(
    try reconstruct.formDraft("Crash")?.lastReceipt == receipt, "form_check",
    "Reconstruction lost crash reconciliation")
  _ = try reconstruct.verify()
  print(
    "PASS form drafts: structured component identity isolation, workbook-switch ownership, incomplete input recovery, concurrent keep-both, exact bindings, read-only preview, atomic submission and crash receipt reconciliation"
  )
}
