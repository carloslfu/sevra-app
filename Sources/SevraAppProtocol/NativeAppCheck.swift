import Foundation
import SevraCore

/// Production preflight uses the same sandboxed service and typed data broker as the UI.
/// It never receives a real workbook, a device grant, or real table bindings.
public enum NativeAppCheck {
  public static func run(
    package: NativeAppPackage, steps: [Value], fixtures: Value = .object([:]),
    cancellation: Cancellation = .init(), excelCoordinates: [[Int]]? = nil,
    requireUnselectedExcelActions: Bool = false
  ) async throws -> Value {
    try cancellation.check()
    try package.validate()
    guard case .object = fixtures else {
      throw SevraError("app_check", "Fixtures must be an object of table aliases and row arrays.")
    }
    try require(
      (1...32).contains(steps.count) && steps.contains { $0["kind"].text.hasPrefix("expect_") }
        && Value.array(steps).json().utf8.count <= 65_536
        && fixtures.json().utf8.count <= 65_536,
      "app_check",
      "Supply 1 to 32 test steps including an assertion, with small synthetic fixtures.")
    try require(
      Set(fixtures.object.keys).isSubset(of: Set(package.datasets.keys)),
      "app_check", "Fixtures must name declared table aliases.")
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      "sevra-app-check-" + identifier())
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: root) }
    let book = try Workbook.create(
      at: root.appendingPathComponent("Check.sevra"), title: "Disposable app check")
    var isolated = package
    for alias in isolated.datasets.keys {
      isolated.datasets[alias]!.datasetID = nil
      isolated.datasets[alias]!.writable = true
    }
    var space = try book.installNativeAppContents(isolated)
    var access = try NativeAppAccess(workbook: book, space: space)
    var paddedRows = 0
    var seeds: [Value] = []
    for (alias, rows) in fixtures.object {
      guard case .array = rows,
        rows.array.allSatisfy({
          if case .object = $0 { return true }
          return false
        })
      else {
        throw SevraError("app_check", "Each fixture must be an array of row objects.")
      }
      try require(rows.array.count <= 32, "app_check", "Use up to 32 synthetic rows per table.")
      seeds += rows.array.map {
        .object(["op": .string("insert"), "table": .string(alias), "values": $0])
      }
    }
    try require(seeds.count <= 64, "app_check", "Use up to 64 synthetic fixture rows.")
    if package.excelBehavior != nil, let coordinates = excelCoordinates {
      try require(
        coordinates.reduce(0) { $0 + $1.count } <= 2000,
        "app_check", "Reconstructed app checks support up to 2,000 stored worksheet rows.")
      for (index, numbers) in coordinates.enumerated() {
        let alias = "sheet\(index + 1)"
        let supplied = fixtures[alias].array.count
        try require(
          supplied <= numbers.count, "app_check",
          "\(alias) has \(numbers.count) original stored rows, but \(supplied) fixture rows were supplied. Keep the original row order and remove extra fixture rows."
        )
        guard let binding = isolated.datasets[alias] else {
          throw SevraError("app_check", "Missing worksheet alias.")
        }
        let blank = Value.object(
          Dictionary(uniqueKeysWithValues: binding.columns.map { ($0.id, Value.string("")) }))
        // Invented test rows never copy business values. Untested original positions remain blank.
        for _ in supplied..<numbers.count {
          seeds.append(
            .object(["op": .string("insert"), "table": .string(alias), "values": blank]))
          paddedRows += 1
        }
      }
    }
    for start in stride(from: 0, to: seeds.count, by: 64) {
      _ = try book.nativeAppTransaction(
        access, operations: Array(seeds[start..<min(start + 64, seeds.count)]),
        expectedRevision: book.revision(), token: identifier())
    }
    access.revoke()
    isolated = space.definition.app!
    for alias in isolated.datasets.keys {
      isolated.datasets[alias]!.writable = package.datasets[alias]!.writable
    }
    space = try book.installNativeAppContents(
      isolated, spaceID: space.id, expectedVersion: space.version)
    try book.attachSyntheticExcelBehavior(space.definition.app!, coordinates: excelCoordinates)
    access = try NativeAppAccess(workbook: book, space: space)
    defer { access.revoke() }
    let connection = NativeAppCheckConnection()
    defer { connection.close() }
    let session = identifier()
    var sequence = 0
    var requests = 0
    var transactions = 0
    var assertions = 0
    var tableRowWasSelected = false
    var checkingInteraction = false
    var unselectedExcelActions = Set<String>()
    let deadline = ProcessInfo.processInfo.systemUptime + 20
    var tree = NativeAppTree()
    var subscriptions: [String: Value] = [:]
    var draft: Value = .object([:])
    func available(_ node: NativeAppNode) -> Bool {
      if node.props["hidden"] == .bool(true) { return false }
      var child = node.id
      while let parent = tree.nodes.values.first(where: { $0.children.contains(child) }) {
        if parent.props["hidden"] == .bool(true) { return false }
        child = parent.id
      }
      return true
    }
    func visible(_ node: NativeAppNode) -> Bool {
      if node.props["hidden"] == .bool(true) { return false }
      var child = node.id
      while let parent = tree.nodes.values.first(where: { $0.children.contains(child) }) {
        if parent.props["hidden"] == .bool(true) { return false }
        if parent.type == "disclosure", parent.props["value"] == .bool(false) { return false }
        if parent.type == "tabs",
          parent.children.firstIndex(of: child) != (parent.props["value"].int ?? 0)
        {
          return false
        }
        child = parent.id
      }
      return true
    }
    func read(_ message: Value) throws -> Value {
      switch message["method"].text {
      case "page": return try book.nativeAppPage(access, request: message["args"])
      case "query": return try book.nativeAppQuery(access, request: message["args"])
      default: throw SevraError("app_check", "Unknown read method.")
      }
    }
    func exchange(_ messages: [Value]?, source: String? = nil) async throws -> Value {
      try cancellation.check()
      try require(
        ProcessInfo.processInfo.systemUptime < deadline && sequence < 128, "app_check",
        "App check exceeded its bounded work budget.")
      var request: [String: Value] = [
        "session": .string(session), "sequence": .number(Double(sequence)),
      ]
      if let source {
        request["kind"] = .string("start")
        request["source"] = .string(source)
        request["state"] = .object([
          "revision": .number(Double(try book.revision())), "draft": draft,
        ])
      } else {
        request["kind"] = .string("events")
        request["messages"] = .array(messages ?? [])
      }
      let result = try NativeAppWire.decode(
        await connection.exchange(NativeAppWire.encode(.object(request))))
      try require(result["error"] == .null, "app_check", result["error"].text)
      try require(
        result["session"].text == session && result["sequence"].int == sequence,
        "app_check", "Unexpected worker response.")
      sequence += 1
      _ = try tree.apply(result["frame"])
      try require(tree.root != nil, "app_check", "Mount one native root with Sevra.mount.")
      for node in tree.nodes.values where node.type == "table" {
        try require(
          package.datasets[node.props["table"].text] != nil, "app_check",
          "Native table uses an undeclared alias.")
      }
      return result["frame"]
    }
    func settle(_ initial: Value) async throws {
      var frame = initial
      while !frame["messages"].array.isEmpty {
        var replies: [Value] = []
        var changed = false
        for message in frame["messages"].array {
          try cancellation.check()
          requests += 1
          try require(requests <= 256, "app_check", "Too many requests during app check.")
          let kind = message["kind"].text
          let id = message["id"].text
          if kind == "draft" {
            draft = message["values"]
            try book.saveNativeAppDraft(access, values: draft)
            continue
          }
          if kind == "unsubscribe" {
            subscriptions.removeValue(forKey: id)
            continue
          }
          try require(["request", "subscribe"].contains(kind), "app_check", "Unknown SDK message.")
          if kind == "subscribe" {
            subscriptions[id] = message
            try require(subscriptions.count <= 32, "app_check", "Too many subscriptions.")
          }
          var reply: [String: Value] = [
            "kind": .string(kind == "subscribe" ? "subscription" : "result"), "id": .string(id),
          ]
          do {
            switch message["method"].text {
            case "page", "query": reply["value"] = try read(message)
            case "calculate":
              try require(
                kind == "request", "app_check", "Calculations are requests, not subscriptions.")
              reply["value"] = .string(
                try Numbers.calculate(
                  message["args"]["expression"].text, values: message["args"]["values"].object))
            case "transaction":
              try require(kind == "request", "app_check", "Writes cannot be subscriptions.")
              transactions += 1
              try require(transactions <= 16, "app_check", "Too many test transactions.")
              let args = message["args"]
              reply["value"] = try book.nativeAppTransaction(
                access, operations: args["operations"].array,
                expectedRevision: args["revision"].int ?? -1, token: args["token"].text,
                undo: args["undo"].string)
              // Fixed-cell actions do not receive a selected table row. Publication
              // must exercise them through an interaction before any table selection,
              // rather than trusting a model's readiness verdict or self-selected tests.
              // Failed transactions and mount-time writes cannot satisfy this coverage.
              if checkingInteraction && !tableRowWasSelected && args["undo"] == .null {
                unselectedExcelActions.formUnion(
                  args["operations"].array.filter { $0["op"] == .string("excel_action") }
                    .map { $0["action"].text })
              }
              changed = true
            default:
              throw SevraError("app_check", "Unsupported SDK request: " + message["method"].text)
            }
          } catch {
            // Invalid action write sets/result types are broken programs, not expected
            // business validation. Catching them in UI code must not hide that defect.
            if (error as? SevraError)?.code == "excel_behavior_result" { throw error }
            reply["error"] = .string(error.localizedDescription)
          }
          replies.append(.object(reply))
        }
        if changed {
          replies.append(
            .object(["kind": .string("revision"), "revision": .number(Double(try book.revision()))])
          )
          for (id, message) in subscriptions.sorted(by: { $0.key < $1.key }) {
            replies.append(
              .object([
                "kind": .string("subscription"), "id": .string(id), "value": try read(message),
              ]))
          }
        }
        guard !replies.isEmpty else { break }
        frame = try await exchange(replies)
      }
    }
    do {
      try await settle(exchange(nil, source: package.source))
    } catch {
      let message = error.localizedDescription
      if message.hasPrefix("SyntaxError:"),
        let range = message.range(of: #"sevra-app\.js:[0-9]+"#, options: .regularExpression),
        let reported = Int(message[range].split(separator: ":").last ?? "")
      {
        // NativeAppRuntime prepends one capability-removal line before source.
        let lines = package.source.components(separatedBy: "\n")
        let line = max(1, min(lines.count, reported - 1))
        let excerpt = (max(1, line - 3)...min(lines.count, line + 2)).map {
          "\($0): " + String(lines[$0 - 1].prefix(500))
        }.joined(separator: "\n")
        throw SevraError(
          "app_check",
          message
            + "\nNo test steps ran. Correct the JavaScript syntax before resubmitting; do not repeat unchanged source. Inspect delimiter balance near these source lines (host prelude excluded):\n"
            + excerpt)
      }
      throw error
    }
    var lastSelection = ""
    for (index, step) in steps.enumerated() {
      do {
        try cancellation.check()
        let kind = step["kind"].text
        func control() throws -> NativeAppNode {
          let target = step["target"].text
          let matches = tree.nodes.values.filter {
            visible($0)
              && ($0.id == target || $0.props["label"].string == target
                || $0.props["title"].string == target)
          }
          try require(
            !target.isEmpty && matches.count == 1, "app_check",
            "Target must match one control label/title or node ID: " + target)
          let node = matches[0]
          return node
        }
        switch kind {
        case "expect_text":
          let text = step["value"].text
          try require(!text.isEmpty, "app_check", "Supply a nonempty text expectation.")
          try require(
            tree.nodes.values.contains {
              $0.type == "text" && visible($0) && $0.props["text"].text.contains(text)
            },
            "app_check_assertion", "Expected visible text: " + text)
          assertions += 1
        case "expect_control":
          try require(
            !step["target"].text.isEmpty, "app_check", "Supply a control label to expect.")
          do { _ = try control() } catch {
            throw SevraError("app_check_assertion", error.localizedDescription)
          }
          assertions += 1
        case "drop", "expect_region", "press_region":
          let node = try control()
          try require(
            node.type == "canvas"
              && (kind == "expect_region" || tree.interactionEnabled[node.id] == true), "app_check",
            "This step targets an enabled canvas.")
          let target = step["value"].text
          let regions = node.props["regions"].array.filter {
            $0["id"].text == target || $0["label"].string == target
          }
          try require(
            !target.isEmpty && regions.count == 1, "app_check",
            "Choose one canvas region by its ID or label.")
          let region = regions[0]
          let x: Value = kind == "press_region" ? .number(0) : step["x"]
          let y: Value = kind == "press_region" ? .number(0) : step["y"]
          for value in [x, y] {
            guard case .number(let number) = value, number.isFinite, abs(number) <= 100_000 else {
              throw SevraError("app_check", "Canvas coordinates must be bounded numbers.")
            }
          }
          if kind == "expect_region" {
            try require(
              region["x"] == x && region["y"] == y, "app_check_assertion",
              "Canvas region position did not match.")
            assertions += 1
          } else {
            checkingInteraction = true
            defer { checkingInteraction = false }
            try await settle(
              exchange([
                .object([
                  "kind": .string("event"), "node": .string(node.id), "event": .string("action"),
                  "mountID": .number(Double(node.mountID)),
                  "handler": .string(kind == "drop" ? "onDrop" : "onClick"), "value": region["id"],
                  "x": x, "y": y,
                ])
              ]))
          }
        case "expect_enabled":
          guard case .bool(let expected) = step["value"] else {
            throw SevraError("app_check", "Supply a boolean enabled expectation.")
          }
          let node = try control()
          let selectionHint =
            expected && lastSelection.isEmpty
              && tree.nodes.values.contains(where: { $0.type == "table" })
            ? " No table row has been selected. For a row editor, select an editable data row before expecting its input to be enabled; an initially disabled editor is correct. A fixed-cell action form must instead work without selection. Match the test to the requested workflow."
            : ""
          try require(
            tree.interactionEnabled[node.id] == expected, "app_check_assertion",
            "Expected " + step["target"].text + (expected ? " to be enabled." : " to be disabled.")
              + selectionHint)
          assertions += 1
        case "expect_value":
          try require(
            control().props["value"] == step["value"], "app_check_assertion",
            "Control value did not match.")
          assertions += 1
        case "expect_rows":
          try require(
            step["count"].int.map { $0 >= 0 } == true, "app_check",
            "expect_rows requires count: a nonnegative integer.")
          let page = try book.nativeAppPage(
            access, request: .object(["table": step["table"], "limit": .number(200)]))
          let values = step["values"].object
          try require(
            values.isEmpty || (page["total"].int ?? 0) <= 200, "app_check",
            "Narrow this bounded row assertion.")
          let count =
            values.isEmpty
            ? page["total"].int
            : page["rows"].array.filter { row in
              values.allSatisfy { row["values"][$0.key] == $0.value }
            }.count
          try require(
            count == step["count"].int, "app_check_assertion",
            "Expected \(step["count"].int!) matching rows; found \(count ?? 0). This table started with \(fixtures[step["table"].text].array.count) fixture rows before any test actions. Fixtures are starting data, not expected outputs. Check the saved values and column types."
              + " Observed row values: "
              + String(
                try Value.array(
                  page["rows"].array.prefix(4).map { row in
                    .object(row["values"].object.filter { values.isEmpty || values[$0.key] != nil })
                  }
                ).json().prefix(2000))
          )
          assertions += 1
        case "change", "click", "select", "activate":
          let node = try control()
          try require(
            tree.interactionEnabled[node.id] == true, "app_check",
            "Target is disabled: " + step["target"].text
              + ". Check its enabled predicate and the prior selection/input steps.")
          var value = step["value"]
          let handler: String
          if kind == "click" {
            try require(node.type == "button", "app_check", "Click targets a button.")
            handler = "onClick"
          } else if ["select", "activate"].contains(kind) && node.type == "table" {
            var args = node.props.object
            args["limit"] = .number(200)
            let rows = try book.nativeAppPage(access, request: .object(args))["rows"].array
            guard let offset = value.int, rows.indices.contains(offset) else {
              throw SevraError("app_check", "Select a valid zero-based row.")
            }
            value = rows[offset]
            tableRowWasSelected = true
            lastSelection =
              "Last table selection: " + step["target"].text + " row \(offset), values "
              + String(try value["values"].json().prefix(1800))
              + ". Fixture positions include headers; select an editable data row for input changes."
            handler = kind == "activate" ? "onActivate" : "onSelect"
          } else {
            try require(
              kind != "select" || ["picker", "tabs"].contains(node.type), "app_check",
              "Select targets a table, picker or tabs.")
            try require(kind != "activate", "app_check", "Activate targets a native table.")
            try require(
              [
                "textField", "textEditor", "toggle", "picker", "slider", "date", "tabs",
                "disclosure",
              ].contains(node.type), "app_check", "Change targets an input control.")
            switch node.type {
            case "textField", "textEditor":
              try require(value.string != nil, "app_check", "Text input requires a string.")
            case "toggle", "disclosure":
              guard case .bool = value else {
                throw SevraError("app_check", "This control requires a boolean.")
              }
            case "picker":
              try require(
                node.props["options"].array.contains(value), "app_check",
                "Choose an available picker option.")
            case "tabs":
              try require(
                value.int.map { node.children.indices.contains($0) } == true, "app_check",
                "Choose an available tab index.")
            case "slider":
              guard case .number(let number) = value else {
                throw SevraError("app_check", "Sliders require numbers.")
              }
              try require(
                number.isFinite && number >= (Double(node.props["min"].text) ?? 0)
                  && number <= (Double(node.props["max"].text) ?? 100), "app_check",
                "Slider value is outside its range.")
            case "date":
              try require(
                ISO8601DateFormatter().date(from: value.text) != nil, "app_check",
                "Use a full ISO date/time.")
            default: break
            }
            handler = "onChange"
          }
          checkingInteraction = true
          defer { checkingInteraction = false }
          try await settle(
            exchange([
              .object([
                "kind": .string("event"), "node": .string(node.id), "handler": .string(handler),
                "mountID": .number(Double(node.mountID)),
                "event": .string(handler == "onChange" ? "change" : "action"), "value": value,
                "editRevision": .number(Double(index + 1)),
              ])
            ]))
        default: throw SevraError("app_check", "Unknown test step: " + kind)
        }
      } catch {
        let code = (error as? SevraError)?.code ?? "app_check"
        let labels = tree.nodes.values.sorted { $0.id < $1.id }.filter(visible).map { node in
          [
            node.props["label"].string, node.props["title"].string, node.props["text"].string,
            node.props["value"].string,
          ].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " = ")
        }.filter { !$0.isEmpty }.joined(separator: "; ")
        throw SevraError(
          ["app_check_assertion", "excel_behavior_result"].contains(code) ? code : "app_check",
          "Test step \(index + 1): \(error.localizedDescription) Controls/text: "
            + String(labels.prefix(1500))
            + (lastSelection.isEmpty ? "" : "\n" + lastSelection))
      }
    }
    try cancellation.check()
    if requireUnselectedExcelActions {
      let missing = (package.excelBehavior?.actions ?? []).map(\.id)
        .filter { !unselectedExcelActions.contains($0) }
      try require(
        missing.isEmpty, "app_check",
        "No successful user-triggered test before table selection for fixed-cell Excel actions: "
          + missing.joined(separator: ", ")
          + ". Start the tests by entering valid action arguments, clicking its button and asserting saved values WITHOUT selecting or activating a table row first. Remove copied row-selection guards from fixed-cell action inputs and handlers. Test row editors afterward. Picker/tab navigation is allowed; mount-time writes and rejected transactions do not count."
      )
    }
    return .object([
      "status": .string("passed"), "assertions": .number(Double(assertions)),
      "paddedSyntheticRows": .number(Double(paddedRows)),
      "steps": .number(Double(steps.count)), "transactions": .number(Double(transactions)),
      "digest": .string(package.digest),
      "unselectedExcelActions": .array(unselectedExcelActions.sorted().map(Value.string)),
      "tables": .array(
        Array(
          Set(
            tree.nodes.values.filter { $0.type == "table" && available($0) }
              .compactMap { $0.props["table"].string })
        ).sorted().map(Value.string)),
      "notice": .string(
        "Checked only these synthetic cases in an isolated workbook. No real rows were read or changed. This does not prove every behavior or visual quality."
      ),
    ])
  }
}

private final class NativeAppCheckConnection: @unchecked Sendable {
  private let connection: NSXPCConnection
  init() {
    connection = NSXPCConnection(serviceName: NativeAppWire.checkService)
    connection.remoteObjectInterface = NSXPCInterface(with: NativeAppWorkerProtocol.self)
    connection.resume()
  }
  func close() { connection.invalidate() }
  func exchange(_ data: Data) async throws -> Data {
    try await withCheckedThrowingContinuation { continuation in
      let reply = CheckReply(continuation)
      DispatchQueue.global().asyncAfter(deadline: .now() + 4) {
        reply.finish(.failure(SevraError("app_check", "The app worker did not respond in time.")))
      }
      guard
        let proxy = connection.remoteObjectProxyWithErrorHandler({ reply.finish(.failure($0)) })
          as? NativeAppWorkerProtocol
      else {
        reply.finish(.failure(SevraError("app_check", "The sandboxed app worker is unavailable.")))
        return
      }
      proxy.exchange(data) { reply.finish(.success($0)) }
    }
  }
}
private final class CheckReply: @unchecked Sendable {
  private let lock = NSLock()
  private var continuation: CheckedContinuation<Data, Error>?
  init(_ continuation: CheckedContinuation<Data, Error>) { self.continuation = continuation }
  func finish(_ result: Result<Data, Error>) {
    lock.lock()
    let pending = continuation
    continuation = nil
    lock.unlock()
    pending?.resume(with: result)
  }
}
