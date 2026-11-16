import AppKit
import CryptoKit
import Foundation
import SevraAppProtocol
import SevraCore
import SwiftUI

@MainActor public final class NativeAppSession: ObservableObject {
  @Published public private(set) var status = "disabled"
  @Published public private(set) var error: String?
  @Published public private(set) var tree = NativeAppTree()
  public let book: Workbook
  public let space: Space
  public struct ViewObserver {
    public var frame: (NativeAppTree, Set<String>) -> Void
    public var data: (Set<String>) -> Void
    public var tablePresentation: (String) -> Void
    public var interactionAvailability: () -> Void
  }
  private var viewObservers: [UUID: ViewObserver] = [:]
  public func observeView(_ observer: ViewObserver) -> UUID {
    let id = UUID()
    viewObservers[id] = observer
    return id
  }
  public func removeViewObserver(_ id: UUID) { viewObservers[id] = nil }
  private var tablePresentations: [String: (signature: Value, request: Value)] = [:]
  public private(set) var access: NativeAppAccess?
  private var connection: NSXPCConnection?
  private var sequence = 0
  private var epoch = UUID().uuidString
  private var busy = false
  private var pending: [Value] = []
  private var subscriptions: [String: Value] = [:]
  private var subscriptionGeneration: [String: Int] = [:]
  private var runningSubscriptions = Set<String>()
  private var revision = -1
  private var fingerprints: [String: String] = [:]
  private var poll: Task<Void, Never>?
  @Published private var lastUndo: String?
  @Published private var reversalIsRedo = false
  private var canReverse: Bool { lastUndo != nil && !activeRequests.contains("native-undo") }
  public var canUndo: Bool { canReverse && !reversalIsRedo }
  public var canRedo: Bool { canReverse && reversalIsRedo }
  private var activeRequests = Set<String>()
  private var draftValues: [String: Value] = [:]
  private var nativeEdits: [String: Int] = [:]
  private var draftSave: Task<Void, Never>?
  private var budgetStarted = Date()
  private var budgetFrames = 0
  private var budgetBytes = 0
  private var budgetCommands = 0
  private let defaults: UserDefaults
  private var grant: NativeAppDeviceGrant?
  private var actionCatalog: Value = .array([])
  private var interactionCatalog: Value = .array([])
  private var commandResults: [String: Value] = [:]
  private var commandReceipts: [Value] = []
  private var commandFailures: [String] = []
  @Published public private(set) var conversationBusy = false {
    didSet { for observer in Array(viewObservers.values) { observer.interactionAvailability() } }
  }
  private let exchangeOverride: (@Sendable (Data) async throws -> Data)?
  public init(
    book: Workbook, space: Space, defaults: UserDefaults = .standard,
    exchange: (@Sendable (Data) async throws -> Data)? = nil
  ) {
    self.book = book
    self.space = space
    self.defaults = defaults
    exchangeOverride = exchange
  }
  public var package: NativeAppPackage { space.definition.app! }
  private var grantKey: String {
    let physical = (try? NativeAppAccess.physicalIdentity(book)) ?? UUID().uuidString
    let identity = "\(book.id):\(physical):\(space.id):\(space.version):\(package.digest)"
    return "native-app-grant:"
      + SHA256.hash(data: Data(identity.utf8)).map { String(format: "%02x", $0) }.joined()
  }
  public var isGranted: Bool { NativeAppDeviceGrant(defaults: defaults, key: grantKey) != nil }
  public func enable() {
    stop()
    defaults.set(UUID().uuidString, forKey: grantKey)
    start()
  }
  public func revoke() {
    defaults.removeObject(forKey: grantKey)
    stop()
    status = "disabled"
  }
  public func stop() {
    status = "disabled"
    access?.revoke()
    access = nil
    grant = nil
    poll?.cancel()
    poll = nil
    connection?.invalidationHandler = nil
    connection?.interruptionHandler = nil
    connection?.invalidate()
    connection = nil
    epoch = UUID().uuidString
    pending = []
    busy = false
    subscriptions = [:]
    subscriptionGeneration = [:]
    runningSubscriptions = []
    lastUndo = nil
    reversalIsRedo = false
    activeRequests = []
    tablePresentations = [:]
  }
  public func start() {
    guard status != "running" && status != "starting" else { return }
    guard let grant = NativeAppDeviceGrant(defaults: defaults, key: grantKey) else { return }
    stop()
    self.grant = grant
    error = nil
    status = "starting"
    tree = NativeAppTree()
    sequence = 0
    for observer in Array(viewObservers.values) { observer.frame(tree, []) }
    budgetStarted = Date()
    budgetFrames = 0
    budgetBytes = 0
    budgetCommands = 0
    let current = epoch
    let previousSave = draftSave
    Task {
      do {
        await previousSave?.value
        let access = try NativeAppAccess(
          workbook: book, space: space, permission: { grant.isCurrent })
        let state = try await Task.detached { [book] in
          (
            try book.nativeAppDraft(access), try book.revision(),
            try book.nativeAppFingerprints(access), try book.nativeAppLastTransaction(access)
          )
        }.value
        guard epoch == current else {
          access.revoke()
          return
        }
        self.access = access
        revision = state.1
        fingerprints = state.2
        lastUndo = state.3?.token
        reversalIsRedo = state.3?.redo ?? false
        draftValues = state.0.object
        nativeEdits = [:]
        if exchangeOverride == nil {
          let connection = NSXPCConnection(serviceName: NativeAppWire.service)
          connection.remoteObjectInterface = NSXPCInterface(with: NativeAppWorkerProtocol.self)
          connection.interruptionHandler = { [weak self] in
            Task { @MainActor in
              self?.fail(
                "The app worker stopped. Your saved data is safe; restart the app.", epoch: current)
            }
          }
          connection.invalidationHandler = { [weak self] in
            Task { @MainActor in
              self?.fail("The app worker disconnected. Restart to try again.", epoch: current)
            }
          }
          connection.resume()
          self.connection = connection
        }
        transmit(
          .object([
            "kind": .string("start"), "source": .string(package.source),
            "state": .object(["draft": state.0, "revision": .number(Double(state.1))]),
          ]))
      } catch { fail(error.localizedDescription, epoch: current) }
    }
  }
  private func fail(_ message: String, epoch expected: String) {
    guard epoch == expected else { return }
    stop()
    error = message
    status = "failed"
  }
  private func transmit(_ payload: Value) {
    guard connection != nil || exchangeOverride != nil else { return }
    let current = epoch
    let expected = sequence
    busy = true
    var object = payload.object
    object["session"] = .string(current)
    object["sequence"] = .number(Double(expected))
    do {
      let data = try NativeAppWire.encode(.object(object))
      if let exchangeOverride {
        Task {
          do {
            received(try await exchangeOverride(data), epoch: current, sequence: expected)
          } catch { fail(error.localizedDescription, epoch: current) }
        }
        return
      }
      guard let connection else { throw SevraError("app_service", "The app is unavailable.") }
      guard
        let worker = connection.remoteObjectProxyWithErrorHandler({ [weak self] error in
          Task { @MainActor in self?.fail(error.localizedDescription, epoch: current) }
        }) as? NativeAppWorkerProtocol
      else { throw SevraError("app_service", "Cannot connect to the app worker.") }
      worker.exchange(data) { [weak self] response in
        Task { @MainActor in self?.received(response, epoch: current, sequence: expected) }
      }
      Task { [weak self] in
        try? await Task.sleep(nanoseconds: 4_000_000_000)
        guard let self, self.epoch == current, self.busy, self.sequence == expected else { return }
        self.fail("The app exceeded its response deadline. Restart to recover.", epoch: current)
      }
    } catch { fail(error.localizedDescription, epoch: current) }
  }
  private func received(_ data: Data, epoch current: String, sequence expected: Int) {
    guard epoch == current && sequence == expected else { return }
    do {
      if Date().timeIntervalSince(budgetStarted) >= 1 {
        budgetStarted = Date()
        budgetFrames = 0
        budgetBytes = 0
        budgetCommands = 0
      }
      budgetFrames += 1
      budgetBytes += data.count
      try require(
        budgetFrames <= 120 && budgetBytes <= 8_388_608, "app_budget",
        "This app exceeded its update rate. Restart it after reducing its work.")
      let response = try NativeAppWire.decode(data)
      if let error = response["error"].string { throw SevraError("app_script", error) }
      try require(
        response["session"].text == current && response["sequence"].int == expected,
        "app_protocol", "The worker returned an invalid session or sequence.")
      var next = tree
      let changed = try next.apply(response["frame"])
      for id in changed where tree.nodes[id]?.mountID != next.nodes[id]?.mountID {
        nativeEdits.removeValue(forKey: id)
      }
      tree = next
      try require(
        response["frame"]["actions"].array.count <= 64
          && response["frame"]["interactions"].array.count <= 512,
        "app_protocol", "The app exposes too many operations.")
      actionCatalog = response["frame"]["actions"]
      interactionCatalog = response["frame"]["interactions"]
      for observer in Array(viewObservers.values) { observer.frame(next, changed) }
      sequence += 1
      busy = false
      status = "running"
      process(response["frame"]["messages"].array, epoch: current)
      if poll == nil { beginPolling() }
      flush()
    } catch { fail(error.localizedDescription, epoch: current) }
  }
  /// A field can be edited in Home, its app and chat. All views use one edit clock.
  public func nextInputRevision(for node: String) -> Int {
    max(nativeEdits[node] ?? 0, tree.nodes[node]?.props["editRevision"].int ?? 0) + 1
  }
  public func event(
    node: String, handler: String, value: Value = .null, editRevision: Int = 0,
    extra: [String: Value] = [:]
  ) {
    guard status == "running", !conversationBusy, tree.interactionEnabled[node] == true else {
      return
    }
    nativeEdits[node] = editRevision
    if handler == "onChange", let key = tree.nodes[node]?.props["draftKey"].string {
      draftValues[key] = value
      saveDraft()
    }
    enqueue(
      .object(
        extra.merging([
          "kind": .string("event"), "node": .string(node), "handler": .string(handler),
          "mountID": .number(Double(tree.nodes[node]!.mountID)),
          "event": .string(handler == "onChange" ? "change" : "action"), "value": value,
          "editRevision": .number(Double(editRevision)),
        ]) { _, new in new }))
  }
  private func enqueue(_ message: Value) {
    // Only consecutive edits may coalesce. Never move a later edit ahead of a Save action.
    if message["kind"].text == "event" && message["event"].text == "change",
      let last = pending.last,
      last["kind"] == message["kind"], last["node"] == message["node"],
      last["event"] == message["event"]
    {
      pending[pending.count - 1] = message
    } else {
      pending.append(message)
    }
    if pending.count > 128 {
      fail("This app generated too many pending events.", epoch: epoch)
      return
    }
    Task { [weak self] in self?.flush() }
  }
  private func flush() {
    guard !busy, !pending.isEmpty, connection != nil || exchangeOverride != nil else { return }
    let messages = pending
    pending = []
    transmit(.object(["kind": .string("events"), "messages": .array(messages)]))
  }
  private func process(_ messages: [Value], epoch current: String) {
    if let values = messages.last(where: { $0["kind"].text == "draft" })?["values"] {
      var merged = values.object
      for (id, edit) in nativeEdits {
        if let node = tree.nodes[id], let key = node.props["draftKey"].string,
          (node.props["editRevision"].int ?? 0) < edit
        {
          merged[key] = draftValues[key]
        }
      }
      draftValues = merged
      saveDraft()
    }
    for message in messages where message["kind"].text != "draft" {
      switch message["kind"].text {
      case "commandResult":
        guard conversationBusy, commandResults.count < 64 else {
          fail("Unexpected app command result.", epoch: current)
          return
        }
        commandResults[message["id"].text] = message
      case "request": request(message, epoch: current)
      case "unsubscribe":
        let id = message["id"].text
        subscriptions.removeValue(forKey: id)
        subscriptionGeneration.removeValue(forKey: id)
      case "subscribe":
        let id = message["id"].text
        guard
          !id.isEmpty && id.utf8.count <= 128
            && (subscriptions.count < 32 || subscriptions[id] != nil)
        else {
          fail("Too many live queries.", epoch: current)
          return
        }
        subscriptions[id] = message
        refreshSubscription(id)
      default:
        fail("Unknown app message.", epoch: current)
        return
      }
    }
  }
  private func saveDraft() {
    guard let access else { return }
    let previous = draftSave
    let values = Value.object(draftValues)
    let current = epoch
    draftSave = Task {
      await previous?.value
      do {
        try await Task.detached { [book] in try book.saveNativeAppDraft(access, values: values) }
          .value
      } catch {
        if epoch == current {
          self.error = "Draft could not be saved: " + error.localizedDescription
        }
      }
    }
  }
  private func request(_ message: Value, epoch current: String) {
    guard let access else { return }
    if message["method"].text == "transaction" {
      budgetCommands += 1
      guard budgetCommands <= 16 else {
        fail("This app exceeded its command rate.", epoch: current)
        return
      }
    }
    let requestID = message["id"].text
    guard !requestID.isEmpty, requestID.utf8.count <= 128, activeRequests.count < 32,
      activeRequests.insert(requestID).inserted
    else {
      fail("App request limit or duplicate request identifier.", epoch: current)
      return
    }
    Task {
      defer { if epoch == current { activeRequests.remove(requestID) } }
      let result: Value
      do {
        result = try await Task.detached { [book] () -> Value in
          let args = message["args"]
          switch message["method"].text {
          case "page": return try book.nativeAppPage(access, request: args)
          case "query": return try book.nativeAppQuery(access, request: args)
          case "calculate":
            return .string(
              try Numbers.calculate(args["expression"].text, values: args["values"].object))
          case "transaction":
            return try book.nativeAppTransaction(
              access, operations: args["operations"].array,
              expectedRevision: args["revision"].int ?? -1, token: args["token"].text,
              undo: args["undo"].string)
          default:
            throw SevraError("app_permission", "The app requested an unavailable capability.")
          }
        }.value
        guard epoch == current else { return }
        if message["method"].text == "transaction" {
          if conversationBusy { commandReceipts.append(result) }
          let reversal = try await Task.detached { [book] in
            try book.nativeAppLastTransaction(access)
          }.value
          guard epoch == current else { return }
          lastUndo = reversal?.token
          reversalIsRedo = reversal?.redo ?? false
          await checkRevision()
        }
        enqueue(.object(["kind": .string("result"), "id": message["id"], "value": result]))
      } catch {
        guard epoch == current else { return }
        if conversationBusy { commandFailures.append(error.localizedDescription) }
        if message["id"].text == "native-undo" { self.error = error.localizedDescription }
        enqueue(
          .object([
            "kind": .string("result"), "id": message["id"],
            "error": .string(error.localizedDescription),
          ]))
      }
    }
  }
  private func refreshSubscription(_ id: String) {
    guard let message = subscriptions[id], let access else { return }
    let generation = (subscriptionGeneration[id] ?? 0) + 1
    subscriptionGeneration[id] = generation
    guard runningSubscriptions.insert(id).inserted else { return }
    let current = epoch
    Task {
      var result: [String: Value] = ["kind": .string("subscription"), "id": .string(id)]
      do {
        result["value"] = try await Task.detached { [book] in
          if message["method"].text == "page" {
            return try book.nativeAppPage(access, request: message["args"])
          }
          try require(message["method"].text == "query", "app_query", "Unsupported subscription.")
          return try book.nativeAppQuery(access, request: message["args"])
        }.value
      } catch { result["error"] = .string(error.localizedDescription) }
      guard epoch == current else { return }
      runningSubscriptions.remove(id)
      guard subscriptionGeneration[id] == generation else {
        refreshSubscription(id)
        return
      }
      enqueue(.object(result))
    }
  }
  public func page(
    _ request: Value, columnLabels: Value,
    completion: @escaping (Result<Value, Error>) -> Void
  ) {
    guard let access else { return }
    let current = epoch
    Task {
      let result = await Task.detached { [book] in
        Result { try book.nativeAppPage(access, request: request, columnLabels: columnLabels) }
      }.value
      guard epoch == current else { return }
      completion(result)
    }
  }
  /// The optional native table and conversation share this exact page request.
  public func tableRequest(_ node: NativeAppNode) -> Value {
    let signature: Value = .array([
      .number(Double(node.mountID)), node.props["table"], node.props["search"], node.props["sort"],
      node.props["descending"], node.props["columns"],
    ])
    if let saved = tablePresentations[node.id], saved.signature == signature {
      return saved.request
    }
    var fields: [String: Value] = [
      "table": node.props["table"],
      "search": node.props["search"].string.map(Value.string) ?? .string(""), "offset": .number(0),
      "limit": .number(200),
    ]
    if let sort = node.props["sort"].string {
      fields["sort"] = .string(sort)
      fields["descending"] = .bool(node.props["descending"] == .bool(true))
    }
    let request = Value.object(fields)
    tablePresentations[node.id] = (signature, request)
    return request
  }
  public func setTableRequest(_ node: NativeAppNode, request: Value, notify: Bool = false) {
    _ = tableRequest(node)
    tablePresentations[node.id]?.request = request
    if notify {
      for observer in Array(viewObservers.values) { observer.tablePresentation(node.id) }
    }
  }
  public func undo() {
    guard canUndo else { return }
    reverseLastChange()
  }
  public func redo() {
    guard canRedo else { return }
    reverseLastChange()
  }
  private func reverseLastChange() {
    guard canReverse, let lastUndo else { return }
    request(
      .object([
        "id": .string("native-undo"), "method": .string("transaction"),
        "args": .object([
          "operations": .array([]), "undo": .string(lastUndo),
          "revision": .number(Double(revision)), "token": .string(UUID().uuidString),
        ]),
      ]), epoch: epoch)
  }

  /// Uses the same live worker and scoped data broker as the optional native surface.
  /// No renderer, accessibility event, pointer or keyboard input is involved.
  public func converse(
    _ operation: String, arguments: Value = .object([:]),
    readOnly: Bool = false, cancellation: Cancellation = .init()
  ) async throws -> Value {
    try require(!conversationBusy, "app_busy", "This app is already handling a request.")
    conversationBusy = true
    defer {
      conversationBusy = false
      commandResults = [:]
    }
    return try await performConversationOperation(
      operation, arguments: arguments, readOnly: readOnly, cancellation: cancellation)
  }

  private func performConversationOperation(
    _ operation: String, arguments: Value, readOnly: Bool, cancellation: Cancellation
  ) async throws -> Value {
    try cancellation.check()
    try require(
      ["inspect", "browse"].contains(operation) || !readOnly, "read_only_request",
      "This request forbids changes.")
    let current = try book.space(space.id)
    try require(
      current.version == space.version, "stale_app", "The app changed. Inspect its current version."
    )
    if operation == "fill" {
      guard case .array(let inputs) = arguments["inputs"], (1...32).contains(inputs.count),
        inputs.allSatisfy({
          Set($0.object.keys) == Set(["target", "value"]) && $0["target"].string != nil
        })
      else { throw SevraError("app_input", "Supply 1 to 32 named inputs and their values.") }
      var changes: [Value] = []
      var result: Value = .null
      for field in inputs {
        do {
          result = try await performConversationOperation(
            "set", arguments: field, readOnly: readOnly, cancellation: cancellation)
          changes += result["changes"].array
          if result["outcome"] == .string("failed") { break }
        } catch {
          return .object([
            "outcome": .string("failed"), "errors": .array([.string(error.localizedDescription)]),
            "changes": .array(changes), "input": field["target"],
          ])
        }
      }
      var fields = result.object
      fields["changes"] = .array(changes)
      return .object(fields)
    }
    if operation == "disable" {
      revoke()
      return conversationSnapshot()
    }
    if operation == "enable" { enable() }
    if operation == "restart" {
      stop()
      start()
    }
    if status != "running" && isGranted && !readOnly && !["inspect", "browse"].contains(operation) {
      start()
    }
    if status == "disabled" {
      try require(
        operation == "inspect", "app_permission",
        isGranted
          ? "This approved app is stopped. Use app.restart for requested work; inspection does not execute saved code."
          : "This app is disabled. Prepare app.enable and ask the user to confirm its access in chat."
      )
      return conversationSnapshot()
    }
    try await settleConversation(cancellation)
    // Saved chat receipts also advance the workbook revision.
    // Refresh the worker before a command, rather than waiting for its periodic poll.
    await checkRevision()
    try await settleConversation(cancellation)
    if ["inspect", "enable", "restart"].contains(operation) { return conversationSnapshot() }
    commandResults = [:]
    commandReceipts = []
    commandFailures = []
    var answer: Value = .null
    var invocationInputContract: Value = .null
    let commandBaseRevision = revision
    do {
      if operation == "undo" || operation == "redo" {
        try require(operation == "undo" ? canUndo : canRedo, "app_undo",
          "There is no app change to \(operation). Only the latest saved transaction can be reversed.")
        if operation == "undo" { undo() } else { redo() }
        try await settleConversation(cancellation)
      } else if operation == "run" {
        let id = arguments["action"].text
        guard let action = actionCatalog.array.first(where: { $0["id"].text == id }) else {
          throw SevraError("app_action", "Inspect the app and choose an available action.")
        }
        // Preserve the pre-invocation SDK contract, even if the action changes
        // its UI/catalog before finishing. Used only to report repaired inputs.
        invocationInputContract = action["inputs"]
        answer = try await conversationCommand(
          [
            "action": .string(id),
            "arguments": arguments["inputs"] == .null ? .object([:]) : arguments["inputs"],
          ], cancellation: cancellation)
      } else {
        try require(
          ["set", "select", "activate", "drop", "browse"].contains(operation), "app_action",
          "Unknown app operation.")
        let target = arguments["target"].text
        let matches = tree.nodes.values.filter {
          $0.id == target || $0.props["label"].string == target
            || $0.props["title"].string == target
            || ($0.type == "table" && ["browse", "select", "activate"].contains(operation)
              && $0.props["table"].string == target)
        }
        try require(
          matches.count == 1, "app_target", "Use one exact input/action name from app.inspect.")
        let node = matches[0]
        try require(
          tree.interactionEnabled[node.id] == true, "app_disabled",
          "This input is currently unavailable.")
        if operation == "browse" {
          try require(node.type == "table", "app_table", "Choose a table target from app.inspect.")
          guard let access else { throw SevraError("app_permission", "Enable this app first.") }
          var query = tableRequest(node).object
          if ["search", "sort", "descending"].contains(where: { arguments.object[$0] != nil }) {
            query["offset"] = .number(0)
          }
          for key in ["search", "sort", "descending", "offset"] where arguments.object[key] != nil {
            query[key] = arguments[key]
          }
          if query["sort"] == .string("") { query.removeValue(forKey: "sort") }
          let request = Value.object(query)
          let page = try await Task.detached { [book] in
            try book.nativeAppPage(access, request: request, columnLabels: node.props["columnLabels"])
          }.value
          try cancellation.check()
          setTableRequest(node, request: request, notify: true)
          return .object([
            "kind": .string("app_table_page"), "status": .string("shown"), "id": .string(space.id),
            "datasetID": package.datasets[node.props["table"].text]?.datasetID.map(Value.string)
              ?? .null, "table": node.props["table"], "request": request, "page": page,
          ])
        }
        let handler =
          operation == "set"
          ? "onChange"
          : operation == "select"
            ? "onSelect"
            : operation == "drop" ? "onDrop" : node.type == "table" ? "onActivate" : "onClick"
        let hasHandler = interactionCatalog.array.contains {
          $0["id"].text == node.id && $0["handlers"].array.contains(.string(handler))
        }
        if !hasHandler, operation == "select", node.type == "table", let access {
          let alias = node.props["table"]
          let row = try book.nativeAppConversationRow(
            access, alias: alias.text, id: arguments["rowID"].text,
            columnLabels: node.props["columnLabels"])
          return .object([
            "id": .string(space.id), "version": .number(Double(space.version)),
            "outcome": .string("failed"), "changes": .array([]),
            "errors": .array([.string("This table has no row-selection action.")]),
            "unavailableSelection": .object(["table": alias, "key": row["key"]]),
          ])
        }
        try require(hasHandler, "app_action", "That operation is not available on this input.")
        var value = arguments["value"]
        var extra: [String: Value] = [:]
        if node.type == "table" {
          guard let access else { throw SevraError("app_permission", "Enable this app first.") }
          value = try book.nativeAppConversationRow(
            access, alias: node.props["table"].text, id: arguments["rowID"].text,
            columnLabels: node.props["columnLabels"])
        } else if node.type == "canvas" {
          let id = arguments["region"].text
          guard let region = node.props["regions"].array.first(where: { $0["id"].text == id })
          else {
            throw SevraError("app_region", "Choose a named region from the app.")
          }
          value = region["id"]
          extra = [
            "x": arguments["x"] == .null ? .number(0) : arguments["x"],
            "y": arguments["y"] == .null ? .number(0) : arguments["y"],
          ]
          for point in extra.values {
            guard case .number(let number) = point, number.isFinite, abs(number) <= 100_000 else {
              throw SevraError("app_input", "Use bounded numeric movement distances.")
            }
          }
        } else if operation == "set" {
          try Self.validateConversationInput(node, value: value)
        }
        nativeEdits[node.id] = nextInputRevision(for: node.id)
        extra.merge([
          "node": .string(node.id), "mountID": .number(Double(node.mountID)),
          "handler": .string(handler), "value": value,
          "editRevision": .number(Double(nativeEdits[node.id]!)),
        ]) { _, new in new }
        answer = try await conversationCommand(extra, cancellation: cancellation)
      }
    } catch {
      if cancellation.isCancelled { stop() }
      throw error
    }
    var snapshot = conversationSnapshot().object
    snapshot["result"] = answer
    if invocationInputContract != .null {
      snapshot["invocationInputContract"] = invocationInputContract
    }
    snapshot["changes"] = .array(commandReceipts)
    snapshot["errors"] = .array(commandFailures.map(Value.string))
    snapshot["outcome"] = .string(commandFailures.isEmpty ? "completed" : "failed")
    if operation == "run", commandFailures.isEmpty {
      let updatedRows: [Value] = commandReceipts
        .filter { ($0["revision"].int ?? 0) > commandBaseRevision }
        .flatMap { receipt in
          receipt["inverse"].array.compactMap { change in
            guard change["op"] == .string("update"),
              let saved = try? book.item(change["id"].text)
            else { return nil }
            return .object(["table": change["table"], "key": .string(saved.logicalID)])
          }
        }
      if !updatedRows.isEmpty { snapshot["updatedRows"] = .array(updatedRows) }
    }
    return .object(snapshot)
  }

  private func conversationCommand(_ fields: [String: Value], cancellation: Cancellation)
    async throws -> Value
  {
    let id = UUID().uuidString
    enqueue(
      .object(fields.merging(["kind": .string("command"), "id": .string(id)]) { _, new in new }))
    let deadline = Date().addingTimeInterval(15)
    while commandResults[id] == nil {
      try cancellation.check()
      try require(
        status == "running", "app_script",
        error
          ?? "The app stopped before this action finished. Inspect saved changes before retrying.")
      guard Date() < deadline else {
        stop()
        throw SevraError(
          "app_timeout",
          "The action did not finish. Inspect saved records before retrying; completed changes are preserved."
        )
      }
      try await Task.sleep(nanoseconds: 10_000_000)
    }
    let result = commandResults.removeValue(forKey: id)!
    if let error = result["error"].string { commandFailures.append(error) }
    try await settleConversation(cancellation)
    return result["value"]
  }

  private func settleConversation(_ cancellation: Cancellation) async throws {
    let deadline = Date().addingTimeInterval(15)
    while status == "starting" || busy || !pending.isEmpty || !activeRequests.isEmpty
      || !runningSubscriptions.isEmpty
    {
      try cancellation.check()
      guard Date() < deadline else {
        stop()
        throw SevraError("app_timeout", "The app did not finish its pending work.")
      }
      try await Task.sleep(nanoseconds: 10_000_000)
    }
    try require(status == "running", "app_script", error ?? "Enable the app before using it.")
    await draftSave?.value
  }

  private func conversationSnapshot() -> Value {
    .object([
      "id": .string(space.id), "version": .number(Double(space.version)),
      "name": .string(package.name), "status": .string(status), "enabled": .bool(isGranted),
      "runtimeNotice": .string(
        status == "disabled" && isGranted
          ? "Approved but stopped. app.restart starts it for requested work. Inspection does not execute saved code."
          : ""),
      "actions": actionCatalog, "canUndo": .bool(canUndo), "canRedo": .bool(canRedo),
      "inputs": .array(
        interactionCatalog.array.compactMap { item in
          guard let node = tree.nodes[item["id"].text] else { return nil }
          return .object([
            "target": .string(node.id), "type": .string(node.type), "fields": node.props,
            "enabled": .bool(tree.interactionEnabled[node.id] == true),
            "handlers": item["handlers"],
          ])
        }),
      "display": .array(
        tree.nodes.values.filter { $0.type == "text" }.sorted { $0.id < $1.id }.map {
          $0.props["text"]
        }),
      "tables": .array(
        tree.nodes.values.filter { $0.type == "table" }.sorted { $0.id < $1.id }.map {
          .object([
            "target": .string($0.id), "label": $0.props["label"], "table": $0.props["table"],
            "request": tableRequest($0),
          ])
        }),
      "access": .object(
        package.datasets.mapValues { binding in
          .object([
            "datasetID": binding.datasetID.map(Value.string) ?? .null,
            "writable": .bool(binding.writable),
          ])
        }),
    ])
  }

  private static func validateConversationInput(_ node: NativeAppNode, value: Value) throws {
    let valid: Bool
    switch node.type {
    case "toggle", "disclosure": if case .bool = value { valid = true } else { valid = false }
    case "slider":
      if case .number(let number) = value {
        valid =
          number.isFinite && number >= (Double(node.props["min"].text) ?? 0)
          && number <= (Double(node.props["max"].text) ?? 1)
      } else {
        valid = false
      }
    case "tabs":
      valid =
        value.int.map {
          value == .number(Double($0)) && $0 >= 0 && $0 < node.props["titles"].array.count
        } ?? false
    case "picker":
      valid = node.props["options"].array.contains { $0 == value || $0["value"] == value }
    case "textField", "textEditor", "date": valid = value.string != nil
    default: valid = false
    }
    try require(
      valid, "app_input", "Supply a value of the displayed input type and listed choices.")
  }
  private func beginPolling() {
    poll = Task { [weak self] in
      while !Task.isCancelled {
        try? await Task.sleep(nanoseconds: 500_000_000)
        guard !Task.isCancelled, let self else { return }
        await self.checkRevision()
      }
    }
  }
  public func checkRevision() async {
    guard let access else { return }
    guard grant?.isCurrent == true else {
      stop()
      status = "disabled"
      return
    }
    let current = epoch
    do {
      let next = try await Task.detached { [book] in try book.revision() }.value
      guard epoch == current && next != revision else { return }
      let prints = try await Task.detached { [book] in try book.nativeAppFingerprints(access) }
        .value
      guard epoch == current else { return }
      let changed = Set(prints.keys.filter { prints[$0] != fingerprints[$0] })
      revision = next
      fingerprints = prints
      enqueue(.object(["kind": .string("revision"), "revision": .number(Double(next))]))
      for (id, subscription) in subscriptions {
        let args = subscription["args"]
        let dependencies = Set(
          subscription["method"].text == "page"
            ? [args["table"].text] : args["sources"].array.map { $0["table"].text })
        if !changed.isDisjoint(with: dependencies) { refreshSubscription(id) }
      }
      for observer in Array(viewObservers.values) { observer.data(changed) }
    } catch { fail(error.localizedDescription, epoch: current) }
  }
}

/// UserDefaults supports concurrent reads/writes. The captured generation is immutable;
/// checking it at data admission and commit fences every session after revoke or reapproval.
private final class NativeAppDeviceGrant: @unchecked Sendable {
  private let defaults: UserDefaults
  private let key: String
  private let generation: String
  init?(defaults: UserDefaults, key: String) {
    guard let value = defaults.string(forKey: key), UUID(uuidString: value) != nil else {
      return nil
    }
    self.defaults = defaults
    self.key = key
    generation = value
  }
  var isCurrent: Bool { defaults.string(forKey: key) == generation }
}
