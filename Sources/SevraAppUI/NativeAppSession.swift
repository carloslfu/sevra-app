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
  public var onFrame: ((NativeAppTree, Set<String>) -> Void)?
  public var onData: ((Set<String>) -> Void)?
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
  public var canUndo: Bool { lastUndo != nil && !activeRequests.contains("native-undo") }
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
  public init(book: Workbook, space: Space, defaults: UserDefaults = .standard) {
    self.book = book
    self.space = space
    self.defaults = defaults
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
    defaults.set(UUID().uuidString, forKey: grantKey)
    start()
  }
  public func revoke() {
    defaults.removeObject(forKey: grantKey)
    stop()
    status = "disabled"
  }
  public func stop() {
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
    activeRequests = []
  }
  public func start() {
    guard let grant = NativeAppDeviceGrant(defaults: defaults, key: grantKey) else { return }
    stop()
    self.grant = grant
    error = nil
    status = "starting"
    tree = NativeAppTree()
    sequence = 0
    onFrame?(tree, [])
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
            try book.nativeAppFingerprints(access)
          )
        }.value
        guard epoch == current else {
          access.revoke()
          return
        }
        self.access = access
        revision = state.1
        fingerprints = state.2
        draftValues = state.0.object
        nativeEdits = [:]
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
    guard let connection else { return }
    let current = epoch
    let expected = sequence
    busy = true
    var object = payload.object
    object["session"] = .string(current)
    object["sequence"] = .number(Double(expected))
    do {
      let data = try NativeAppWire.encode(.object(object))
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
      tree = next
      onFrame?(next, changed)
      sequence += 1
      busy = false
      status = "running"
      process(response["frame"]["messages"].array, epoch: current)
      if poll == nil { beginPolling() }
      flush()
    } catch { fail(error.localizedDescription, epoch: current) }
  }
  public func event(
    node: String, handler: String, value: Value = .null, editRevision: Int = 0,
    extra: [String: Value] = [:]
  ) {
    guard status == "running", tree.interactionEnabled[node] == true else { return }
    nativeEdits[node] = editRevision
    if handler == "onChange", let key = tree.nodes[node]?.props["draftKey"].string {
      draftValues[key] = value
      saveDraft()
    }
    enqueue(
      .object(
        extra.merging([
          "kind": .string("event"), "node": .string(node), "handler": .string(handler),
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
    guard !busy, !pending.isEmpty, connection != nil else { return }
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
          lastUndo = result["token"].text
          await checkRevision()
        }
        enqueue(.object(["kind": .string("result"), "id": message["id"], "value": result]))
      } catch {
        guard epoch == current else { return }
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
  public func page(_ request: Value, completion: @escaping (Result<Value, Error>) -> Void) {
    guard let access else { return }
    let current = epoch
    Task {
      let result = await Task.detached { [book] in
        Result { try book.nativeAppPage(access, request: request) }
      }.value
      guard epoch == current else { return }
      completion(result)
    }
  }
  public func undo() {
    guard canUndo, let lastUndo else { return }
    request(
      .object([
        "id": .string("native-undo"), "method": .string("transaction"),
        "args": .object([
          "operations": .array([]), "undo": .string(lastUndo),
          "revision": .number(Double(revision)), "token": .string(UUID().uuidString),
        ]),
      ]), epoch: epoch)
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
      onData?(changed)
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
