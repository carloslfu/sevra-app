import Darwin
import Foundation
import SevraAutomationUI
import SevraCore

func expect(_ condition: Bool, _ message: String = "Invariant failed") throws {
  try require(condition, "fixture", message)
}
func refuses(_ operation: () throws -> Void) throws {
  do { try operation() } catch let error as SevraError where error.code != "fixture" {
    return
  } catch is CocoaError { return }
  throw SevraError("fixture", "The operation did not refuse.")
}
let start = ISO8601DateFormatter().date(from: "2026-10-01T08:00:00Z")!
let due = ISO8601DateFormatter().date(from: "2026-10-01T09:00:00Z")!

func fixture(_ root: URL, _ name: String) throws -> (Workbook, ApplicationDefinition) {
  let book = try Workbook.create(at: root.appendingPathComponent(name + ".sevra"), title: name)
  let function = try book.saveApplicationDefinition(
    logicalID: identifier(),
    content: .object([
      "kind": .string("function"), "title": .string("Daily total"),
      "description": .string("Synthetic native schedule"), "parameters": .array([]),
      "payload": .object(["expression": .string("1+2"), "unit": .string("items")]),
    ]))
  let workflow = try book.saveApplicationDefinition(
    logicalID: identifier(),
    content: .object([
      "kind": .string("workflow"), "title": .string("Daily total"),
      "description": .string("Synthetic calculation"), "parameters": .array([]),
      "payload": .object([
        "readPolicy": .string("latest-at-step"),
        "steps": .array([
          .object([
            "id": .string("calculate"), "kind": .string("evaluate"),
            "binding": .object(["mode": .string("exact"), "versionID": .string(function.id)]),
            "arguments": .object([:]),
          ])
        ]),
      ]),
    ]))
  let automation = try book.saveApplicationDefinition(
    logicalID: identifier(),
    content: .object([
      "kind": .string("automation"), "title": .string(name),
      "description": .string("Synthetic schedule"), "parameters": .array([]),
      "payload": .object([
        "policy": .string("calendar-drafts-v1"),
        "workflow": .object(["mode": .string("exact"), "versionID": .string(workflow.id)]),
        "arguments": .object([:]),
        "schedule": .object([
          "policy": .string("native-calendar-v1"), "timeZone": .string("UTC"),
          "hour": .number(9), "minute": .number(0),
          "recurrence": .object(["kind": .string("daily")]),
        ]),
      ]),
    ]))
  return (book, automation)
}
func enable(
  _ registry: AutomationDeviceRegistry, _ book: Workbook, _ definition: ApplicationDefinition
)
  throws -> AutomationDeviceGrant
{
  let session = try book.authorizeAutomationExecution(
    definition.id, expectedGeneration: 0,
    after: start, token: "enable", actor: .human("synthetic-native-enable"))
  return try registry.register(book, session: session)
}

@MainActor func runChecks() async throws -> Int {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(
    "sevra-automation-ui-" + identifier())
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: root) }
  var failures = 0
  var checks = 0
  func check(_ name: String, _ body: () async throws -> Void) async {
    checks += 1
    do {
      try await body()
      print(try! Value.object(["check": .string(name), "passed": .bool(true)]).json())
    } catch {
      failures += 1
      print(
        try! Value.object([
          "check": .string(name), "passed": .bool(false),
          "error": .string(error.localizedDescription),
        ]).json())
    }
  }
  func registry(_ name: String) -> AutomationDeviceRegistry {
    .init(directory: root.appendingPathComponent(name, isDirectory: true))
  }
  let runner: NativeAutomationController.Runner = { book, session, control in
    try await Task.detached {
      var run = try book.workflowRun(session.runID)
      for _ in 0..<16 {
        if ["completed", "cancelled", "waiting_review", "needs_attention"].contains(
          run["state"].text)
        {
          if run["state"] != .string("waiting_review") { return run }
        }
        run = try book.advanceWorkflow(session, owner: "synthetic-native", cancellation: control)
        if run["state"] == .string("waiting_review") { return run }
      }
      return run
    }.value
  }
  await check("persistent exact grant restores on a new connection without another authorization") {
    let (book, definition) = try fixture(root, "Reopen")
    let store = registry("Registry-Reopen")
    let grant = try enable(store, book, definition)
    let revision = try book.revision()
    let restored = try AutomationDeviceRegistry(directory: store.directory).restore(grant)
    try expect(restored.0 !== book && restored.0.id == book.id)
    try expect(restored.1.planning.generation == 1 && book.revision() == revision)
    let attrs = try FileManager.default.attributesOfItem(
      atPath: store.directory.appendingPathComponent("automations.json").path)
    try expect((attrs[.posixPermissions] as? Int) == 0o600)
    _ = try book.verify()
  }
  await check("rename follows physical identity but a copied workbook cannot borrow permission") {
    let (book, definition) = try fixture(root, "Rename")
    let store = registry("Registry-Rename")
    let grant = try enable(store, book, definition)
    let copy = root.appendingPathComponent("Copied.sevra")
    try FileManager.default.copyItem(at: book.url, to: copy)
    let copied = try Workbook(copy)
    try expect(try !store.matches(grant, workbook: copied))
    let copiedSession = try copied.authorizeAutomationExecution(
      definition.id, expectedGeneration: 1,
      after: start, token: "copy-enable")
    try refuses { _ = try store.register(copied, session: copiedSession) }
    let renamed = root.appendingPathComponent("Renamed.sevra")
    try FileManager.default.moveItem(at: book.url, to: renamed)
    let reopened = try store.restore(grant)
    try expect(reopened.0.url.path == renamed.path && reopened.0.id == book.id)
    _ = try reopened.0.verify()
  }
  await check("same-path package replacement and symbolic aliases stay inactive") {
    let (book, definition) = try fixture(root, "Replace")
    let store = registry("Registry-Replace")
    let grant = try enable(store, book, definition)
    let backup = root.appendingPathComponent("Replacement.sevra")
    try FileManager.default.copyItem(at: book.url, to: backup)
    let moved = root.appendingPathComponent("Held.sevra")
    try FileManager.default.moveItem(at: book.url, to: moved)
    try FileManager.default.moveItem(at: backup, to: book.url)
    let replacement = try Workbook(book.url)
    try expect(try !store.matches(grant, workbook: replacement))
    // Bookmarks may correctly find the original moved package. They must never
    // redirect permission to the replacement at the original path.
    do {
      let resolved = try store.restore(grant)
      try expect(resolved.0.url.path == moved.path)
    } catch let error as SevraError where error.code == "automation_file" {
      // Passive bookmark resolution may prefer the replaced original path.
      // Refusal is correct; never search the disk or grant the replacement.
    }
    let alias = root.appendingPathComponent("Alias.sevra")
    try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: moved)
    let linked = try Workbook(alias)
    let session = try linked.authorizeAutomationExecution(
      definition.id, expectedGeneration: 1,
      after: start, token: "alias-enable")
    try refuses { _ = try store.register(linked, session: session) }
  }
  await check("removed registry entry fences an already-restored worker before publication") {
    let (book, definition) = try fixture(root, "Fence")
    let store = registry("Registry-Fence")
    let grant = try enable(store, book, definition)
    let (connection, session) = try store.restore(grant)
    _ = try connection.planAutomationOccurrences(session.planning, through: due, token: "plan")
    let dispatch = try connection.dispatchAutomationOccurrence(
      session, observedAt: due, token: "dispatch")
    let worker = try connection.authorizeAutomationWorkflowExecution(
      session, runID: dispatch["runID"].text)
    let claim = try connection.claimWorkflowStep(worker, owner: "late")
    try expect(try store.remove(grant))
    let revision = try connection.revision()
    try refuses { _ = try connection.completeWorkflowStep(worker, claim: claim) }
    try expect(try connection.revision() == revision)
    try expect(try connection.workflowRun(worker.runID)["state"] == .string("running"))
    _ = try connection.verify()
  }
  await check("device permission removed at the prepared checkpoint rolls back publication") {
    let (book, definition) = try fixture(root, "CommitFence")
    let store = registry("Registry-CommitFence")
    let grant = try enable(store, book, definition)
    let (connection, session) = try store.restore(grant)
    _ = try connection.planAutomationOccurrences(session.planning, through: due, token: "plan")
    let dispatch = try connection.dispatchAutomationOccurrence(
      session, observedAt: due, token: "dispatch")
    let worker = try connection.authorizeAutomationWorkflowExecution(
      session, runID: dispatch["runID"].text)
    let claim = try connection.claimWorkflowStep(worker, owner: "commit-fence")
    let revision = try connection.revision()
    try WorkflowPublicationProbe.$observer.withValue({ stage, _ in
      if stage == .prepared { _ = try? store.remove(grant) }
    }) {
      try refuses { _ = try connection.completeWorkflowStep(worker, claim: claim) }
    }
    try expect(try connection.revision() == revision)
    try expect(try connection.workflowRun(worker.runID)["state"] == .string("running"))
    _ = try connection.verify()
  }
  await check("independent pause and generation replacement refuse saved device authority") {
    let (book, definition) = try fixture(root, "Generation")
    let store = registry("Registry-Generation")
    let grant = try enable(store, book, definition)
    _ = try book.pauseAutomation(grant.id, expectedGeneration: 1, token: "pause")
    try refuses { _ = try store.restore(grant) }
    let fresh = try book.authorizeAutomationExecution(
      definition.id, expectedGeneration: 2,
      after: start, token: "new")
    let current = try store.register(book, session: fresh)
    try expect(try !store.remove(grant))
    _ = try store.restore(current)
    try expect(try book.automationState(definition.id)["generation"].int == 3)
  }
  await check("database replacement in the same package refuses the old identity") {
    let (book, definition) = try fixture(root, "Database")
    let store = registry("Registry-Database")
    let grant = try enable(store, book, definition)
    let database = book.url.appendingPathComponent("workbook.sqlite")
    let copied = book.url.appendingPathComponent("replacement.sqlite")
    try FileManager.default.copyItem(at: database, to: copied)
    try FileManager.default.removeItem(at: database)
    try FileManager.default.moveItem(at: copied, to: database)
    try refuses { _ = try store.restore(grant) }
  }
  await check("registry corruption and oversized or symbolic permission files are preserved") {
    let store = registry("Registry-Corrupt")
    _ = try store.grants()
    let file = store.directory.appendingPathComponent("automations.json")
    for bytes in [Data("broken".utf8), Data(repeating: 32, count: 2_097_153)] {
      try bytes.write(to: file)
      try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
      try refuses { _ = try store.grants() }
      try expect(try Data(contentsOf: file) == bytes)
    }
    let held = store.directory.appendingPathComponent("held.json")
    try FileManager.default.moveItem(at: file, to: held)
    try FileManager.default.createSymbolicLink(at: file, withDestinationURL: held)
    try refuses { _ = try store.grants() }
  }
  await check("independent registry writers preserve every explicit registration") {
    let store = registry("Registry-Concurrent")
    var inputs: [(Workbook, ApplicationDefinition)] = []
    for index in 0..<6 { inputs.append(try fixture(root, "Concurrent-\(index)")) }
    try await withThrowingTaskGroup(of: AutomationDeviceGrant.self) { group in
      for (book, definition) in inputs {
        group.addTask {
          let child = Process()
          child.executableURL = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
          child.arguments = ["--register", book.url.path, store.directory.path, definition.id]
          child.standardOutput = FileHandle.nullDevice
          let errors = Pipe()
          child.standardError = errors
          try child.run()
          let watchdog = Task.detached {
            do { try await Task.sleep(nanoseconds: 10_000_000_000) } catch { return }
            if child.isRunning { kill(child.processIdentifier, SIGKILL) }
          }
          defer { watchdog.cancel() }
          child.waitUntilExit()
          let diagnostic = String(
            decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
          try expect(
            child.terminationStatus == 0, "Independent registration worker failed: " + diagnostic)
          guard let grant = try store.grants().first(where: { $0.workbookID == book.id }) else {
            throw SevraError("fixture", "Worker permission was not published")
          }
          return grant
        }
      }
      for try await _ in group {}
    }
    try expect(try store.grants().count == 6)
  }
  await check("reconstruction keeps intent and saved history but cannot acquire device permission")
  {
    let (book, definition) = try fixture(root, "Replay")
    let store = registry("Registry-Replay")
    let grant = try enable(store, book, definition)
    let target = root.appendingPathComponent("Replayed.sevra")
    _ = try book.reconstruct(to: target)
    let replay = try Workbook(target)
    try expect(replay.id == book.id && (try replay.workflowRuns()).isEmpty)
    try expect(try !store.matches(grant, workbook: replay))
    try expect(try replay.automationState(definition.id)["state"] == .string("armed"))
    _ = try replay.verify()
  }
  await check("driver defers while inactive, stays write-free while idle and completes one due run")
  {
    let (book, definition) = try fixture(root, "Driver")
    let owner = NativeAutomationController(registry: registry("Registry-Driver"), runner: runner)
    try await owner.enable(
      book, exactID: definition.id, expectedGeneration: 0, allowAI: false, now: start)
    let revision = try book.revision()
    owner.poll(now: due, deferral: "Inactive")
    await owner.waitForCurrentPoll()
    try expect(try book.workflowRuns().isEmpty && book.revision() == revision)
    owner.poll(now: start)
    await owner.waitForCurrentPoll()
    try expect(try book.revision() == revision)
    owner.poll(now: due)
    await owner.waitForCurrentPoll()
    let runs = try book.workflowRuns()
    try expect(runs.count == 1 && runs[0]["state"] == .string("completed"))
    let reopened = NativeAutomationController(registry: owner.registry, runner: runner)
    reopened.poll(now: due)
    await reopened.waitForCurrentPoll()
    try expect(try book.workflowRuns().count == 1)
    try expect(try book.automationState(definition.id)["generation"].int == 1)
    _ = try book.verify()
  }
  await check("prepared-but-undispatched occurrence resumes after owner recreation") {
    let (book, definition) = try fixture(root, "Pending")
    let store = registry("Registry-Pending")
    let grant = try enable(store, book, definition)
    let restored = try store.restore(grant)
    _ = try restored.0.planAutomationOccurrences(
      restored.1.planning, through: due, token: "prepared")
    let owner = NativeAutomationController(registry: store, runner: runner)
    let revision = try book.revision()
    owner.poll(now: start)
    await owner.waitForCurrentPoll()
    try expect(
      try book.revision() == revision && book.workflowRuns().isEmpty,
      "Clock rollback created writes or dispatched a future request")
    owner.poll(now: due)
    await owner.waitForCurrentPoll()
    let runs = try book.workflowRuns()
    try expect(runs.count == 1 && runs[0]["state"] == .string("completed"))
    _ = try book.verify()
  }
  await check("registry save failure retains workbook history and cannot start the driver") {
    let (book, definition) = try fixture(root, "SaveFailure")
    let store = registry("Registry-SaveFailure")
    _ = try store.grants()
    let file = store.directory.appendingPathComponent("automations.json")
    let bytes = Data("broken-registry".utf8)
    try bytes.write(to: file)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    let owner = NativeAutomationController(registry: store, runner: runner)
    do {
      try await owner.enable(
        book, exactID: definition.id, expectedGeneration: 0, allowAI: false, now: start)
      throw SevraError("fixture", "Corrupt device registry was replaced")
    } catch let error as SevraError where error.code == "automation_registry" {}
    owner.poll(now: due)
    await owner.waitForCurrentPoll()
    try expect(try book.workflowRuns().isEmpty)
    try expect(try book.automationState(definition.id)["state"] == .string("armed"))
    try expect(try Data(contentsOf: file) == bytes)
    _ = try book.verify()
  }
  await check(
    "driver waits without spinning writes for review and resumes after explicit acceptance"
  ) {
    let (book, original) = try fixture(root, "Review")
    let tools = WorkbookTools(book)
    let receipt = try tools.execute("receiving_template", .object([:]))
    let action = try book.saveApplicationDefinition(
      logicalID: identifier(), content: receipt["content"])
    let workflowContent = try tools.execute(
      "workflow_template", .object(["id": .string(action.id)]))["content"]
    let workflow = try book.saveApplicationDefinition(
      logicalID: identifier(), content: workflowContent)
    let evidence = try book.addItem(
      category: "source", kind: "observation", title: "Synthetic receipt",
      text: "Received two units for delivery synthetic-review.")
    var content = original.content.object
    var payload = original.payload.object
    payload["workflow"] = .object(["mode": .string("exact"), "versionID": .string(workflow.id)])
    payload["arguments"] = .object([
      "delivery": .string("synthetic-review"), "effective": .string("2026-10-01"),
      "evidence": .string(evidence.id),
      "lines": .array([
        .object([
          "line": .string("one"), "subject": .string("synthetic-bolts"), "quantity": .string("2"),
        ])
      ]),
    ])
    content["payload"] = .object(payload)
    let definition = try book.saveApplicationDefinition(
      logicalID: original.logicalID,
      content: .object(content), expectedDefinitionID: original.id)
    let owner = NativeAutomationController(registry: registry("Registry-Review"), runner: runner)
    try await owner.enable(
      book, exactID: definition.id, expectedGeneration: 0, allowAI: false, now: start)
    owner.poll(now: due)
    await owner.waitForCurrentPoll()
    let run = try book.workflowRuns()[0]
    try expect(run["state"] == .string("waiting_review"), "Run did not wait for review")
    let revision = try book.revision()
    owner.poll(now: due.addingTimeInterval(11))
    await owner.waitForCurrentPoll()
    try expect(try book.revision() == revision, "Review wait created repeated writes")
    let full = try book.workflowRun(run["id"].text)
    let proposal = full["steps"].array[0]["output"]["value"]["proposals"].array[0].text
    _ = try book.accept(proposal)
    owner.poll(now: due.addingTimeInterval(22))
    await owner.waitForCurrentPoll()
    try expect(try book.workflowRun(run["id"].text)["state"] == .string("completed"))
    _ = try book.verify()
  }
  for stage in ["prepared", "committed"] {
    await check("registry SIGKILL at " + stage + " preserves atomic device authority") {
      let (book, definition) = try fixture(root, "Crash-" + stage)
      let store = registry("Registry-Crash-" + stage)
      let child = Process()
      child.executableURL = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
      child.arguments = [
        "--registry-crash", book.url.path, store.directory.path, definition.id, stage,
      ]
      let pipe = Pipe()
      child.standardOutput = pipe
      child.standardError = FileHandle.nullDevice
      try child.run()
      let watchdog = Task.detached {
        do { try await Task.sleep(nanoseconds: 10_000_000_000) } catch { return }
        if child.isRunning { kill(child.processIdentifier, SIGKILL) }
      }
      defer { watchdog.cancel() }
      defer {
        if child.isRunning {
          kill(child.processIdentifier, SIGKILL)
          child.waitUntilExit()
        }
      }
      let marker = try await Task.detached { try pipe.fileHandleForReading.read(upToCount: 6) }
        .value
      try expect(marker == Data("READY\n".utf8), "Worker did not reach the publication barrier")
      kill(child.processIdentifier, SIGKILL)
      child.waitUntilExit()
      try expect(child.terminationReason == .uncaughtSignal && child.terminationStatus == SIGKILL)
      let grants = try store.grants()
      try expect(grants.count == (stage == "prepared" ? 0 : 1))
      try expect(try book.workflowRuns().isEmpty)
      try expect(try book.automationState(definition.id)["generation"].int == 1)
      if stage == "committed" {
        let owner = NativeAutomationController(registry: store, runner: runner)
        owner.poll(now: due)
        await owner.waitForCurrentPoll()
        try expect(try book.workflowRuns().count == 1)
        try expect(try book.automationState(definition.id)["generation"].int == 1)
      }
      _ = try book.verify()
    }
  }
  await check("focus loss cancels an admitted synthetic runner and prevents late completion") {
    let (book, definition) = try fixture(root, "Cancel")
    let admitted = Cancellation()
    let owner = NativeAutomationController(registry: registry("Registry-Cancel")) {
      book, session, control in
      let claim = try book.claimWorkflowStep(session, owner: "delayed")
      admitted.cancel()
      while !control.isCancelled { try await Task.sleep(nanoseconds: 1_000_000) }
      // Deliberately omit the caller cancellation to test the live device fence.
      return try book.completeWorkflowStep(session, claim: claim)
    }
    try await owner.enable(
      book, exactID: definition.id, expectedGeneration: 0, allowAI: false, now: start)
    owner.poll(now: due)
    let deadline = Date().addingTimeInterval(10)
    while !admitted.isCancelled && Date() < deadline {
      try await Task.sleep(nanoseconds: 1_000_000)
    }
    try expect(admitted.isCancelled, "Runner was not admitted")
    owner.deferWork("Inactive")
    await owner.waitForCurrentPoll()
    let runs = try book.workflowRuns()
    try expect(runs.count == 1 && runs[0]["state"] != .string("completed"))
    _ = try book.verify()
  }
  print(
    try Value.object([
      "checks": .number(Double(checks)), "failures": .number(Double(failures)),
      "scope": .string(
        "synthetic native controller and real file registry; no model or visible OS lifecycle"),
    ]).json())
  return failures
}

if CommandLine.arguments.count == 5, CommandLine.arguments[1] == "--register" {
  do {
    let book = try Workbook(URL(fileURLWithPath: CommandLine.arguments[2]))
    let store = AutomationDeviceRegistry(directory: URL(fileURLWithPath: CommandLine.arguments[3]))
    _ = try enable(store, book, book.applicationDefinition(CommandLine.arguments[4]))
    exit(0)
  } catch {
    fputs(String(error.localizedDescription.prefix(3000)) + "\n", stderr)
    exit(1)
  }
}
if CommandLine.arguments.count == 6, CommandLine.arguments[1] == "--registry-crash" {
  let book = try Workbook(URL(fileURLWithPath: CommandLine.arguments[2]))
  let store = AutomationDeviceRegistry(directory: URL(fileURLWithPath: CommandLine.arguments[3]))
  let stage = CommandLine.arguments[5]
  let observer: @Sendable (AutomationRegistryPublicationProbe.Stage) -> Void = { current in
    if (current == .prepared && stage == "prepared")
      || (current == .committed && stage == "committed")
    {
      FileHandle.standardOutput.write(Data("READY\n".utf8))
      while true { pause() }
    }
  }
  _ = try AutomationRegistryPublicationProbe.$observer.withValue(observer) {
    try enable(store, book, book.applicationDefinition(CommandLine.arguments[4]))
  }
  exit(0)
}
let failures = try await runChecks()
exit(failures == 0 ? 0 : 1)
