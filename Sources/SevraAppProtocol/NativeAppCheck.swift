import Foundation
import SevraCore

/// Production preflight uses the same sandboxed service and typed data broker as the UI.
/// It never receives a real workbook, a device grant, or real table bindings.
public enum NativeAppCheck {
  package static func hasAssertion(_ steps: [Value]) -> Bool {
    steps.contains {
      $0["kind"].text.hasPrefix("expect_")
        || ($0["kind"].text == "run_action"
          && (!$0["error"].text.isEmpty || $0["reject"] == .bool(true)))
    }
  }

  public static func run(
    package: NativeAppPackage, steps: [Value], fixtures: Value = .object([:]),
    cancellation: Cancellation = .init(), excelCoordinates: [[Int]]? = nil,
    excelHeadings: [String: Value] = [:],
    requireUnselectedExcelActions: Bool = false, excelFormulas: ExcelCheckFormulas? = nil,
    testProgress: (Int) -> Void = { _ in }
  ) async throws -> Value {
    try await run(
      package: package, steps: steps, fixtures: fixtures, cancellation: cancellation,
      excelCoordinates: excelCoordinates, excelHeadings: excelHeadings,
      requireUnselectedExcelActions: requireUnselectedExcelActions,
      excelFormulas: excelFormulas, expectFinalActionSuccess: false, testProgress: testProgress)
  }

  package static func run(
    package: NativeAppPackage, steps: [Value], fixtures: Value,
    cancellation: Cancellation, excelCoordinates: [[Int]]?, excelHeadings: [String: Value] = [:],
    requireUnselectedExcelActions: Bool = false, excelFormulas: ExcelCheckFormulas?,
    expectFinalActionSuccess: Bool, checkActionWrites: Bool = false,
    testProgress: (Int) -> Void = { _ in }
  ) async throws -> Value {
    try cancellation.check()
    try package.validate()
    guard case .object = fixtures else {
      throw SevraError("app_check", "Fixtures must be an object of table aliases and row arrays.")
    }
    try require(
      (1...32).contains(steps.count)
        && Value.array(steps).json().utf8.count <= 65_536
        && fixtures.json().utf8.count <= 65_536,
      "app_check",
      "Supply 1 to 32 test steps including an assertion, with small synthetic fixtures.")
    if expectFinalActionSuccess {
      let final = steps.last ?? .null
      try require(
        final["kind"] == .string("run_action")
          && final["reject"] == .null && final["error"] == .null,
        "app_check", "An allowed-input check must end with a successful named action.")
    }
    try require(
      hasAssertion(steps) || expectFinalActionSuccess, "app_check",
      "These \(steps.count) test steps contain no assertion. Interactions alone do not verify behavior. Within the 32-step limit, include expect_row with exact saved values, expect_value, expect_text, or run_action with reject:true or an expected error. Remove redundant interactions to make room; do not remove assertions on repair."
    )
    try require(
      Set(fixtures.object.keys).isSubset(of: Set(package.datasets.keys)),
      "app_check", "Fixtures must name declared table aliases.")
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      "sevra-app-check-" + identifier())
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: root) }
    let book = try Workbook.create(
      at: root.appendingPathComponent("Check.sevra"), title: "Disposable app check")
    let fixtureSource = try excelCoordinates.map { _ in
      try book.addItem(category: "source", kind: "annotation", title: "Synthetic Excel fixtures")
    }
    var isolated = package
    for alias in isolated.datasets.keys.sorted() {
      var binding = isolated.datasets[alias]!
      binding.datasetID = try fixtureSource.map { source in
        let data: Value = .object(excelHeadings[alias].map { ["columnLabels": $0] } ?? [:])
        let worksheet = try book.addItem(
          category: "record", kind: "worksheet", title: binding.title,
          data: data, inputs: [source.id])
        return try book.createDataset(
          title: binding.title, columns: binding.columns, rows: [], sourceID: worksheet.id
        ).id
      }
      binding.writable = true
      isolated.datasets[alias] = binding
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
    if package.excelBehavior != nil || excelFormulas != nil, let coordinates = excelCoordinates {
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
    let startingCounts = Dictionary(grouping: seeds, by: { $0["table"].text }).mapValues(\.count)
    access.revoke()
    isolated = space.definition.app!
    for alias in isolated.datasets.keys {
      isolated.datasets[alias]!.writable = package.datasets[alias]!.writable
    }
    space = try book.installNativeAppContents(
      isolated, spaceID: space.id, expectedVersion: space.version)
    try book.attachSyntheticExcelCalculations(
      space.definition.app!, coordinates: excelCoordinates,
      formulas: excelFormulas)
    access = try NativeAppAccess(workbook: book, space: space)
    defer { access.revoke() }
    let connection = NativeAppCheckConnection()
    defer { connection.close() }
    let session = identifier()
    var sequence = 0
    var requests = 0
    var transactions = 0
    var committedTransactions = 0
    var assertions = 0
    var tableRowWasSelected = false
    var checkingInteraction = false
    var unselectedExcelActions = Set<String>()
    let deadline = ProcessInfo.processInfo.systemUptime + 20
    var tree = NativeAppTree()
    var registeredActions: [String: Value] = [:]
    var checkedActions = Set<String>()
    var actionInputs: [String: Value] = [:]
    var actionTitles: [String: Value] = [:]
    var actionInputTypes: [String: Value] = [:]
    var actionChanges: [String: Value] = [:]
    var checkedWrites: NativeAppCheckedWrites?
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
      try tree.validateVisualBindings(package)
      try require(
        result["frame"]["actions"].array.count <= 64, "app_check", "Too many named actions.")
      registeredActions.removeAll()
      for action in result["frame"]["actions"].array {
        try require(
          registeredActions[action["id"].text] == nil, "app_check", "Duplicate action ID.")
        registeredActions[action["id"].text] = action
        checkedActions.insert(action["id"].text)
        actionInputs[action["id"].text] = action["inputs"]
        actionTitles[action["id"].text] = action["title"]
        try require(checkedActions.count <= 64, "app_check", "Too many distinct named actions.")
      }
      try require(tree.root != nil, "app_check", "Mount one native root with Sevra.mount.")
      for node in tree.nodes.values where node.type == "table" {
        try require(
          package.datasets[node.props["table"].text] != nil, "app_check",
          "Native table uses an undeclared alias.")
      }
      return result["frame"]
    }
    var commandResult: Value?
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
          if kind == "commandResult" {
            commandResult = message
            continue
          }
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
              // A behavior can declare 24 actions. The 32-step suite must be able
              // to exercise each once; request, frame and time budgets still apply.
              try require(transactions <= 32, "app_check", "Too many test transactions.")
              let args = message["args"]
              let revisionBefore = try book.revision()
              let receipt = try book.nativeAppTransaction(
                access, operations: args["operations"].array,
                expectedRevision: args["revision"].int ?? -1, token: args["token"].text,
                undo: args["undo"].string)
              reply["value"] = receipt
              // A replay returns the original success receipt without a new commit.
              if let writtenRevision = receipt["revision"].int, writtenRevision > revisionBefore {
                committedTransactions += 1
                if checkedWrites != nil {
                  do { try checkedWrites?.record(receipt, request: args, book: book) } catch {
                    throw SevraError("app_check_effect_tracking", error.localizedDescription)
                  }
                }
                // Fixed-cell actions need a tested interaction before selecting a row.
                if checkingInteraction && !tableRowWasSelected && args["undo"] == .null {
                  unselectedExcelActions.formUnion(
                    args["operations"].array.filter { $0["op"] == .string("excel_action") }
                      .map { $0["action"].text })
                }
                changed = true
              }
            default:
              throw SevraError("app_check", "Unsupported SDK request: " + message["method"].text)
            }
          } catch {
            // Invalid action write sets/result types are broken programs, not expected
            // business validation. Catching them in UI code must not hide that defect.
            if ["excel_behavior_result", "app_check_effect_tracking"].contains(
              (error as? SevraError)?.code ?? "")
            {
              throw error
            }
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
        let actionHint =
          message.contains("invalid property name")
            && package.source.contains("Sevra.action")
          ? "\nAn async arrow cannot be an unnamed object property. Sevra.action takes THREE arguments: ID, a fully closed description object, then the handler. Close both inputs and description before the comma preceding async. Valid shape: Sevra.action('add',{title:'Add',inputs:{amount:{type:'decimal',title:'Amount'}}},async inputs=>{return {amount:inputs.amount};});"
          : ""
        let layoutHint =
          package.source.contains("h(Tabs,") || package.source.contains("h(Sevra.Tabs,")
          ? "\nIf the error is in a deeply nested worksheet layout, simplify only that layout using mount(h(Sevra.Workspace,{sections:[{title:'Inputs',table:'sheet1',actions:['yourRegisteredActionID']},{title:'Results',table:'sheet2'}]})); adapt existing aliases and action IDs. Preserve business handlers and tests. Workspace supplies native tabs, tables and ActionForms without nested h calls."
          : ""
        throw SevraError(
          "app_check",
          message
            + "\nNo test steps ran. Correct the JavaScript syntax before resubmitting; do not repeat unchanged source. Inspect delimiter balance near these source lines (host prelude excluded):\n"
            + excerpt + actionHint + layoutHint)
      }
      throw error
    }
    if requireUnselectedExcelActions {
      try require(
        committedTransactions == 0, "app_check",
        "The app changed workbook records before any user operation. Mount and initial subscriptions should read only. Move the write into the user-triggered action and test its saved effects."
      )
    }
    // Describe the initial native controls without source or builder-test results.
    // Independent action review must not learn its expected effects from either.
    let initialInterface: Value = .array(
      tree.nodes.values.sorted { $0.id < $1.id }.map { node in
        .object([
          "id": .string(node.id), "type": .string(node.type),
          "children": .array(node.children.map(Value.string)),
          "props": .object(
            node.props.object.filter { ["label", "title", "titles", "table"].contains($0.key) }),
        ])
      })
    var lastSelection = ""
    for (index, step) in steps.enumerated() {
      do {
        try cancellation.check()
        let kind = step["kind"].text
        if !["expect_row", "expect_rows", "expect_text", "expect_value"].contains(kind) {
          try checkedWrites?.verify()
          checkedWrites = nil
        }
        func control() throws -> NativeAppNode {
          let target = step["target"].text
          let matches = tree.nodes.values.filter {
            visible($0)
              && ($0.id == target || $0.props["label"].string == target
                || $0.props["title"].string == target)
          }
          if matches.isEmpty {
            let qualified = registeredActions.values.flatMap { action in
              action["inputs"].object.compactMap { key, input -> String? in
                guard (input["title"].string ?? key) == target else { return nil }
                return action["title"].text + ": " + target
              }
            }.filter { label in tree.nodes.values.contains { $0.props["label"] == .string(label) } }
            if !qualified.isEmpty {
              throw SevraError(
                "app_check_setup",
                "The requested input exists in an action form. Its test label includes the action title: "
                  + qualified.sorted().joined(separator: ", ")
                  + ". Use one exact label and select its tab first; do not add duplicate fields."
              )
            }
          }
          if matches.isEmpty,
            ["undo", "undo last change"].contains(target.lowercased())
          {
            throw SevraError(
              "app_check_host_control",
              "Sevra already provides the visible Undo last change control outside the generated app, using the latest successful write receipt. This isolated tree contains only generated controls. A missing app-owned Undo button is not a defect. Test the business write here; do not require or add a duplicate Undo button."
            )
          }
          if matches.isEmpty, !target.isEmpty,
            let hidden = tree.nodes.values.first(where: {
              $0.id == target || $0.props["label"].string == target
                || $0.props["title"].string == target
            })
          {
            var child = hidden.id
            while let parent = tree.nodes.values.first(where: { $0.children.contains(child) }) {
              if parent.type == "tabs", let tab = parent.children.firstIndex(of: child),
                tab != (parent.props["value"].int ?? 0)
              {
                let selection: Value = .object([
                  "kind": .string("select"),
                  "target": parent.props["label"].string.map(Value.string) ?? .string(parent.id),
                  "value": .number(Double(tab)),
                ])
                throw SevraError(
                  "app_check_inactive_tab",
                  "The control exists on an inactive tab: " + target
                    + ". Select its tab before interacting: " + (try selection.json()))
              }
              child = parent.id
            }
          }
          try require(
            !target.isEmpty && matches.count == 1, "app_check",
            "Target must match one control label/title or node ID: " + target)
          let node = matches[0]
          return node
        }
        switch kind {
        case "run_action":
          if checkActionWrites, step["reject"] == .null, step["error"] == .null {
            checkedWrites = NativeAppCheckedWrites(action: step["action"].text)
          }
          try require(
            (step["reject"] == .null || step["reject"] == .bool(true))
              && (step["reject"] == .null || step["error"] == .null)
              && (step["error"] == .null || step["error"].string?.isEmpty == false),
            "app_check", "Use reject:true or an exact error substring, not both.")
          try require(
            registeredActions[step["action"].text] != nil, "app_check",
            "Choose a registered action ID: "
              + registeredActions.keys.sorted().joined(separator: ", "))
          var inputSetupError: String?
          do {
            let declared = registeredActions[step["action"].text]!["inputs"].object
            actionInputTypes[String(index)] = .object(declared.mapValues { $0["type"] })
            let errors = inputSetupErrors(step, fields: declared)
            try require(errors.isEmpty, "app_check", errors.joined(separator: " "))
          } catch {
            // Wrong JSON types can be intentional SDK-rejection tests. They
            // cannot establish a business-rule defect when a different error
            // prevents that handler from running at all.
            guard step["error"].string != nil else { throw error }
            inputSetupError = error.localizedDescription
          }
          commandResult = nil
          let committedBefore = committedTransactions
          checkingInteraction = true
          defer { checkingInteraction = false }
          try await settle(
            exchange([
              .object([
                "kind": .string("command"), "id": .string("test-action"),
                "action": step["action"], "arguments": step["inputs"],
              ])
            ]))
          guard let result = commandResult else {
            throw SevraError("app_check", "The named action did not finish.")
          }
          actionChanges[String(index)] = .number(Double(committedTransactions - committedBefore))
          if step["reject"] == .bool(true) {
            try require(
              result["error"].string?.isEmpty == false, "app_check_assertion",
              "Expected rejection without data changes, but the action completed successfully.")
            try require(
              committedTransactions == committedBefore, "app_check_assertion",
              "The action rejected its inputs but committed a data change. Reject invalid inputs before writing."
            )
            assertions += 1
          } else if let expected = step["error"].string {
            let observed = result["error"].string ?? "The action completed successfully."
            if !result["error"].text.contains(expected), let inputSetupError {
              throw SevraError(
                "app_check_setup",
                inputSetupError + " Expected error containing: " + String(expected.prefix(500))
                  + ". Observed: " + String(observed.prefix(1500))
                  + ". Correct the test input shape before probing its business rule.")
            }
            try require(
              !expected.isEmpty && result["error"].text.contains(expected), "app_check_assertion",
              "Expected a named action error containing: " + String(expected.prefix(500))
                + ". Observed: " + String(observed.prefix(1500)))
            try require(
              committedTransactions == committedBefore, "app_check_assertion",
              "The action reported an expected error but committed a data change. Reject invalid inputs before writing; a failed action must not save partial effects."
            )
            assertions += 1
          } else {
            try require(result["error"] == .null, "app_check_assertion", result["error"].text)
            // Host-derived allowed-input checks assert handler completion.
            // Model-authored tests still need an explicit observed effect.
            if expectFinalActionSuccess && index == steps.count - 1 { assertions += 1 }
          }
        case "expect_text":
          let text = step["value"].text
          try require(!text.isEmpty, "app_check", "Supply a nonempty text expectation.")
          var tabHint = ""
          if let tabs = tree.nodes.values.first(where: {
            $0.type == "tabs" && visible($0) && $0.props["titles"].array.contains(.string(text))
          }), let index = tabs.props["titles"].array.firstIndex(of: .string(text)) {
            let selection: Value = .object([
              "kind": .string("select"),
              "target": tabs.props["label"].string.map(Value.string) ?? .string(tabs.id),
              "value": .number(Double(index)),
            ])
            tabHint =
              " This is an existing native tab title, not a Text node. Navigate with "
              + (try selection.json())
              + "; then use expect_control for its table label or expect_row for saved values. Do not add a duplicate heading just to satisfy a test of an existing tab."
          }
          try require(
            tree.nodes.values.contains {
              $0.type == "text" && visible($0) && $0.props["text"].text.contains(text)
            },
            "app_check_assertion", "Expected visible text: " + text + tabHint)
          assertions += 1
        case "expect_control":
          try require(
            !step["target"].text.isEmpty, "app_check", "Supply a control label to expect.")
          do { _ = try control() } catch {
            if ["app_check_host_control", "app_check_inactive_tab", "app_check_setup"].contains(
              (error as? SevraError)?.code ?? "")
            {
              throw error
            }
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
        case "expect_row", "expect_rows":
          let expectedCount = kind == "expect_row" ? 1 : step["count"].int
          try require(
            expectedCount.map { $0 >= 0 } == true, "app_check",
            "expect_rows requires count: a nonnegative integer.")
          if kind == "expect_row" {
            try require(
              !step["values"].object.isEmpty && step["count"] == .null,
              "app_check",
              "expect_row requires nonempty values and no count; exactly one row must match."
            )
          }
          let page = try book.nativeAppPage(
            access, request: .object(["table": step["table"], "limit": .number(200)]))
          if step["values"] != .null {
            guard case .object = step["values"] else {
              throw SevraError(
                "app_check", "Saved-row values must be an object of column/value pairs.")
            }
          }
          let values = step["values"].object
          let columns = Set(page["columns"].array.map { $0["id"].text })
          try require(
            Set(values.keys).isSubset(of: columns), "app_check",
            "expect_rows uses stored column IDs, not action input IDs. Available columns: "
              + columns.sorted().joined(separator: ", "))
          var observedRows = page["rows"].array
          if !values.isEmpty {
            guard let total = page["total"].int, (0...20_000).contains(total) else {
              throw SevraError("app_check", "Saved-row assertions support up to 20,000 rows.")
            }
            while observedRows.count < total {
              try cancellation.check()
              let next = try book.nativeAppPage(
                access,
                request: .object([
                  "table": step["table"], "limit": .number(200),
                  "offset": .number(Double(observedRows.count)),
                ]))
              try require(
                next["total"] == page["total"] && next["revision"] == page["revision"]
                  && !next["rows"].array.isEmpty
                  && observedRows.count + next["rows"].array.count <= total,
                "app_check", "Saved rows changed or returned an incomplete assertion page.")
              observedRows += next["rows"].array
            }
          }
          let matching = observedRows.filter { row in
            values.allSatisfy { row["values"][$0.key] == $0.value }
          }
          let count = values.isEmpty ? page["total"].int : matching.count
          var typeHint = ""
          if count != expectedCount, !values.isEmpty,
            let row = observedRows.first(where: { row in
              values.allSatisfy {
                let actual = row["values"][$0.key]
                let expected = $0.value
                if actual.text == expected.text { return true }
                guard actual.string == nil || expected.string == nil,
                  let left = decimalSpelling(actual.text),
                  let right = decimalSpelling(expected.text)
                else { return false }
                return left == right
              }
            })
          {
            func type(_ value: Value) -> String {
              switch value {
              case .string: return "string"
              case .number: return "number"
              case .bool: return "boolean"
              case .null: return "null"
              case .array: return "array"
              case .object: return "object"
              }
            }
            typeHint = try values.keys.sorted().compactMap { key -> String? in
              let actual = row["values"][key]
              let expected = values[key]!
              guard type(actual) != type(expected) else { return nil }
              return
                "Column \(key): expected JSON \(type(expected)) \(try expected.json()), stored JSON \(type(actual)) \(try actual.json())."
            }.joined(separator: " ")
            if !typeHint.isEmpty {
              typeHint =
                " Value TYPE mismatch: " + String(typeHint.prefix(1500))
                + " Ordinary worksheet cells are strings; convert arithmetic results with String(...), for example String(-quantity). Preserve the correct expected values."
            }
          }
          let spellingHint =
            count == expectedCount ? "" : try decimalTextHint(values, rows: observedRows)
          try require(
            count == expectedCount, "app_check_assertion",
            "Expected \(expectedCount!) matching rows; found \(count ?? 0). This table started with \(startingCounts[step["table"].text] ?? 0) rows, including \(fixtures[step["table"].text].array.count) supplied fixture rows and any blank worksheet positions. expect_row checks one matching row; expect_rows with values counts only matches. Fixtures are starting data, not expected outputs. Check the saved values and column types."
              + typeHint + spellingHint + " Observed row values: "
              + String(
                try Value.array(
                  observedRows.enumerated().sorted { lhs, rhs in
                    func score(_ row: Value) -> Int {
                      values.filter { row["values"][$0.key] == $0.value }.count
                    }
                    let left = score(lhs.element)
                    let right = score(rhs.element)
                    return left == right ? lhs.offset < rhs.offset : left > right
                  }.prefix(4).map { _, row in
                    .object(row["values"].object.filter { values.isEmpty || values[$0.key] != nil })
                  }
                ).json().prefix(2000))
          )
          try checkedWrites?.confirm(
            table: step["table"].text, matching: matching, values: values,
            expectedCount: expectedCount!, book: book)
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
            let rows = try book.nativeAppPage(
              access, request: .object(args), columnLabels: node.props["columnLabels"]
            )["rows"].array
            guard let offset = value.int, rows.indices.contains(offset) else {
              throw SevraError("app_check", "Select a valid zero-based row.")
            }
            value = rows[offset]
            tableRowWasSelected = true
            lastSelection =
              "Last table selection: " + step["target"].text + " row \(offset), values "
              + String(try value["values"].json().prefix(1800))
              + ". Select an editable row using its displayed position after filtering and sorting."
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
        testProgress(index + 1)
      } catch {
        let code = (error as? SevraError)?.code ?? "app_check"
        let labels = tree.nodes.values.sorted { $0.id < $1.id }.filter(visible).map { node in
          [
            node.props["label"].string, node.props["title"].string, node.props["text"].string,
            node.props["value"].string,
          ].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " = ")
        }.filter { !$0.isEmpty }.joined(separator: "; ")
        let asynchronousReadHint =
          (error.localizedDescription + labels).contains("not a function")
            && package.source.range(
              of:
                #"data\.(?:all|page)\([^)]*\)\s*\.\s*(?:filter|find|map|some|every|reduce|forEach)\s*\("#,
              options: .regularExpression) != nil
          ? "\nAn array method is being called directly on an asynchronous data read. Await it first: const rows=await data.all('alias'); const records=rows.filter(...); or (await data.all('alias')).filter(...). await data.all('alias').filter(...) calls filter on the Promise before awaiting. data.page also needs await, then use its .rows array. Correct the read, preserving the validation and assertions."
          : ""
        throw SevraError(
          ["app_check_assertion", "excel_behavior_result", "app_check_unverified_write"].contains(
            code)
            ? code : "app_check",
          "Test step \(index + 1): \(error.localizedDescription) Controls/text: "
            + String(labels.prefix(1500))
            + asynchronousReadHint
            + (try interactionHint(steps: steps, index: index, actions: registeredActions))
            + (lastSelection.isEmpty ? "" : "\n" + lastSelection))
      }
    }
    try checkedWrites?.verify()
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
      "actions": .array(checkedActions.sorted().map(Value.string)),
      "actionInputs": .object(actionInputs),
      "actionTitles": .object(actionTitles),
      "initialInterface": initialInterface,
      "actionInputTypes": .object(actionInputTypes),
      "actionChanges": .object(actionChanges),
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
