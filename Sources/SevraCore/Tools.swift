import CryptoKit
import Foundation

public func encoded<T: Encodable>(_ value: T) throws -> Value {
  try JSONDecoder().decode(Value.self, from: JSONEncoder().encode(value))
}
public struct WorkbookTools {
  public let workbook: Workbook
  public let runID: String
  public let cancellation: Cancellation
  public let requestSourceID: String?
  public let conversation: String
  public let readOnly: Bool
  public let excelConversion: ExcelConversionBuild?
  static let guides: [String: String] = [
    "rule": """
      A rule watches the stock of one inventory item. When the stock crosses a level, it drafts an alert for the user to read in Reviews, or runs a saved workflow. It never runs until the user enables it.
      1. subject is the item as the stock table names it. If unsure, read it with sql: SELECT subject FROM stock.
      2. For an alert, run action template.rule with {alert: one sentence the user will read, subject: the item, operator: "<" or "<=" or ">" or ">=", threshold: the level as a number}. Example: {alert: "Brass bolts are below 10. Reorder them.", subject: "brass bolts", operator: "<", threshold: 10}.
      3. Only when the user names a saved workflow to run instead: find it with search in=definitions, using one or two words of its title. In the hit, id is the workflow's exact version ID; never use logical_id or source_id. read kind=definition with ref set to that id. Then run action template.rule with {workflowID: that id, arguments: the workflow's inputs or {}, subject, operator, threshold}, without alert.
      4. template.rule returns a template receipt and changes nothing. save with template: {templateReceiptID: that receipt's ID, title: a short title}. Saving does not enable the rule; tell the user to enable it.
      """,
    "receiving": """
      Receiving records a delivery as draft stock movements, one per line. The stock changes only after the user accepts them in Reviews.
      1. The workbook needs the Receive delivery action. Find it with search in=definitions for "Receive delivery". If there is none, run action template.receiving, then save with template: {templateReceiptID: that receipt's ID}. The saved action's id is its exact version ID.
      2. The evidence is the document or record that lists the delivery, such as a packing slip. Find its id with search.
      3. run action action.prepare with {id: the action's id, arguments: {delivery: the delivery's number or name, effective: the date it arrived as YYYY-MM-DD, evidence: that id, lines: one {line, subject, quantity} per item}}. subject is the item as the stock table names it; quantity is the count as text.
      Example: a slip for delivery D-104 that arrived on 2026-11-18 with 40 brass bolts and 25 hex nuts gives {delivery: "D-104", effective: "2026-11-18", evidence: the slip's id, lines: [{line: "1", subject: "brass bolts", quantity: "40"}, {line: "2", subject: "hex nuts", quantity: "25"}]}.
      4. Tell the user the movements wait for review.
      """,
    "view": """
      A view is a saved page of up to 16 components. save with view: {title, definition: {version: 1, components}}. Every component has a short id of its own, a type and a visible title, and the fields its type uses. Saving a view does not open it.
      table: datasetID, a table's id from SELECT name, id FROM tables.
      chart: datasetID, x and y. x and y are column ids of that table from SELECT table_name, name, id FROM columns: x the categories, y a number. The chart adds up y for each x itself. chartStyle is bar or line, and bar when left out.
      metric: datasetID, y and aggregation, one of SUM, AVERAGE, MIN, MAX or COUNT. Add unit only when the request or the evidence states one.
      document, asset: itemID, the exact ID of that document or file.
      text: text, its content. search: query, its words.
      app: spaceID, the saved app's exact ID. To show one declared view of the app, add viewID and its viewVersion.
      comparison: children, two or three components side by side.
      form, calculation, query: read kind=definition with ref set to the saved definition's ID, copy the nativeComponent it returns and fill its arguments. Keep its definitionBinding.
      Example: {title: "Purchasing", definition: {version: 1, components: [{id: "table1", type: "table", title: "Quotes", datasetID: the table's id}, {id: "chart1", type: "chart", title: "Total by supplier", datasetID: the table's id, x: "supplier", y: "total"}]}}.
      To change a saved view, read kind=views for its id and version, then run action view.edit.
      """,
  ]
  public static let readOnlyTools: Set<String> = [
    "history_search", "history_read", "tool_result", "search", "count_records", "archive_members",
    "read", "lineage", "datasets", "rows", "calculate", "balance", "spaces",
    "review_queue", "references", "space_history", "find_definitions", "read_definition",
    "definition_registry", "receiving_template", "form_template", "workflow_template",
    "inventory_automation_template",
    "evaluate_definition", "native_app_sdk", "read_native_app", "workspace_actions",
    "preview_action", "workflow_activity", "read_workflow",
  ]
  public init(
    _ workbook: Workbook, runID: String = identifier(), cancellation: Cancellation = .init(),
    requestSourceID: String? = nil, conversation: String, readOnly: Bool = false,
    excelConversion: ExcelConversionBuild? = nil
  ) {
    self.workbook = workbook
    self.runID = runID
    self.cancellation = cancellation
    self.requestSourceID = requestSourceID
    self.conversation = conversation
    self.readOnly = readOnly
    self.excelConversion = excelConversion
  }
  public func operationToken(_ tool: String, _ arguments: Value) throws -> String {
    try Self.operationToken(runID: runID, tool, arguments)
  }
  /// A call's identity within its run, the same for a retry with the same arguments.
  public static func operationToken(runID: String, _ tool: String, _ arguments: Value) throws
    -> String
  {
    runID + "-"
      + SHA256.hash(data: Data((tool + (try arguments.json())).utf8))
      .prefix(12).map { String(format: "%02x", $0) }.joined()
  }
  public func execute(
    _ tool: String, _ a: Value, receiptID: String? = nil, nativeAppCheck: Value? = nil,
    inspectionOnly: Bool = false
  ) throws -> Value {
    let model = try workbook.synchronized {
      try workbook.db.scalar("SELECT model FROM agent_runs WHERE id=?", [.string(runID)]).string
    }
    let actor =
      model.map {
        ChangeActor.ai(
          "WorkbookTools", model: $0,
          policy: tool == "save_native_app"
            ? "native-app-authoring-v1"
            : ["workspace_action", "sql", "run"].contains(tool)
              ? "chat-workspace-actions-v1" : "workbook-tools-draft-policy-v1")
      } ?? .programmatic("WorkbookTools")
    return try ChangeAttribution.$actor.withValue(actor) {
      try executeAttributed(
        tool, a, receiptID: receiptID, nativeAppCheck: nativeAppCheck,
        inspectionOnly: inspectionOnly)
    }
  }
  private func executeAttributed(
    _ tool: String, _ a: Value, receiptID: String?, nativeAppCheck: Value?,
    inspectionOnly: Bool = false
  ) throws -> Value {
    try cancellation.check()
    if let build = excelConversion {
      try workbook.validateExcelConversionBuild(build)
      try require(
        [
          "native_app_sdk", "read_native_app", "datasets", "rows", "calculate", "save_native_app",
          "inspect_excel_evidence", "compare_excel_behavior", "tool_result",
        ]
        .contains(tool),
        "excel_scope",
        "This build can only inspect its imported tables and save its checked native workspace.")
      if tool == "rows" {
        try require(
          build.tables.contains { $0.id == (a["datasetID"].string ?? a["id"].text) },
          "excel_scope", "Only this import's tables can be read during conversion.")
      }
      if tool == "read_native_app" {
        try require(
          workbook.spaceTarget(a["id"].text, cancellation: cancellation).id == build.conversionID,
          "excel_scope", "Only this conversion's existing app can be read.")
      }
      if tool == "tool_result" {
        let call = try workbook.toolCall(a["id"].text, conversation: conversation)
        try require(
          call["run_id"].text == runID, "excel_scope",
          "This conversion can read only tool results from its current build request.")
      }
    }
    try require(
      !readOnly || Self.readOnlyTools.contains(tool)
        || ["workspace_action", "sql", "run", "guide"].contains(tool),
      "read_only_request",
      "The current request explicitly forbids changes. Read evidence and answer; do not create a draft, proposal, space, copy or import."
    )
    func string(_ key: String) throws -> String {
      guard let v = a[key].string, !v.isEmpty else {
        throw SevraError("arguments", "Missing string argument: \(key)")
      }
      return v
    }
    // A copy belongs to one exact source version, so as an input it means that version.
    let inputs = Array(
      Set(
        try a["inputs"].array.compactMap(\.string).map { id in
          guard id.hasPrefix("copy:") else { return id }
          return try workbook.documentCopyChoice(
            id, runID: runID, conversation: conversation, cancellation: cancellation
          ).sourceVersionID
        } + (requestSourceID.map { [$0] } ?? []))
    ).sorted()
    let token = try operationToken(tool, a)
    if Self.applicationTools.contains(tool) {
      return try executeApplicationTool(tool, a, receiptID: receiptID)
    }
    switch tool {
    case "workspace_actions": return try ChatOperations.catalog(a["domain"].string)
    case "workspace_action":
      return try executeChatOperation(string("action"), arguments: a["arguments"])
    case "history_search":
      return try workbook.searchHistory(
        string("query"), conversation: conversation,
        cursor: a["cursor"].string, limit: 8, beforeMessage: workbook.runRequestMessage(runID),
        cancellation: cancellation)
    case "history_read":
      let evidence: Value
      do {
        evidence = try workbook.readHistoryEvidence(
          string("id"), conversation: conversation,
          beforeMessage: workbook.runRequestMessage(runID))
      } catch let error as SevraError where ["message", "history_scope"].contains(error.code) {
        guard
          let stopped = try workbook.unreadStoppedRequest(
            conversation: conversation, runID: runID)
        else { throw error }
        throw SevraError(
          error.code, error.message + " The stopped request's messageID is \(stopped).")
      }
      guard
        let progress = try workbook.stoppedRequestProgress(
          message: string("id"), conversation: conversation, runID: runID)
      else { return evidence }
      var fields = evidence.object
      fields["stoppedRequest"] = progress
      return .object(fields)
    case "tool_result":
      if a["path"] != .null {
        guard case .array(let path) = a["path"], path.allSatisfy({ $0.string != nil }) else {
          throw SevraError(
            "result_path", "A result path must be an array of exact string keys or indexes.")
        }
      }
      return try workbook.toolResultPage(
        string("id"), conversation: conversation,
        path: a["path"].array.compactMap(\.string), offset: a["offset"].int ?? 0,
        rawJSON: a["rawJSON"] == .bool(true),
        cancellation: cancellation)
    case "search":
      return try searchEvidence(string("query"), arguments: a)
    case "references": return try referenceEvidence(a)
    case "count_records": return try workbook.countRecords(a, cancellation: cancellation)
    case "archive_members":
      return try encoded(workbook.archiveMembers(string("id"), cancellation: cancellation))
    case "include_archive_members":
      return try encoded(
        workbook.includeArchiveMembers(
          string("id"), paths: a["paths"].array.compactMap(\.string), cancellation: cancellation))
    case "read":
      let chunkLimit = a["chunkLimit"].int ?? 2
      let offset = a["offset"].int ?? 0
      try require((1...8).contains(chunkLimit), "arguments", "Read one to eight source chunks.")
      try require(
        offset >= 0 && offset <= Int.max - 9, "arguments", "Choose a valid source chunk page.")
      return try workbook.synchronized {
        try workbook.db.readTransaction {
          let item = try readableItem(string("id"))
          let current: Item?
          do { current = try readableItem(item.logicalID) } catch let error as SevraError
            where error.code == "item_scope"
          { current = nil }
          let page = try workbook.readChunks(item.id, offset: offset, limit: chunkLimit + 1)
          var info = try encoded(item).object
          info["text"] = .string(String(item.text.prefix(1000)))
          info["data"] =
            item.data.text.utf8.count < 12000
            ? item.data : .string("Structured value exceeds read budget; use table rows.")
          func assembled(_ chunks: [Value]) throws -> Value {
            let hasMore = page.count > chunks.count
            var fields: [String: Value] = [
              "item": .object(info),
              "isCurrentVersion": .bool(item.id == current?.id),
              "currentVersion": current.map { current in
                .object([
                  "id": .string(current.id), "title": .string(current.title),
                  "status": .string(current.status), "meaning": .string(current.meaning),
                ])
              } ?? .null,
              "snapshotRevision": .number(Double(try workbook.revision())),
              "references": item.kind == "request"
                ? .null : try referenceEvidence(.object(["id": .string(item.id)])),
              "notice": .string(
                "The item is the exact requested version. When it is historical, read currentVersion.id for current facts or acceptance; do not present historical status as current. A null currentVersion means the latest head is outside this read scope, not that it is absent. For movements, data preserves original creation arguments: data.status is not the current status. Use item.status for this version and currentVersion.status for its latest head."
              ),
              "chunks": .array(chunks),
              "chunkPage": .object([
                "offset": .number(Double(offset)), "count": .number(Double(chunks.count)),
                "hasMore": .bool(hasMore),
                "nextOffset": hasMore ? .number(Double(offset + chunks.count)) : .null,
              ]),
              "extraction": try workbook.extractionStatus(item.id),
            ]
            if offset == 0, item.assetID != nil, item.id == current?.id {
              fields["requestEvidence"] = try relatedOriginals(
                excluding: item.id,
                spent: try Value.object(fields).json().utf8.count)
            }
            let result: Value = .object(fields)
            return try receiptID.map {
              try DocumentCopyChoices.adding(
                to: result, receiptID: $0, offset: a["copyOffset"].int ?? 0,
                cancellation: cancellation)
            } ?? result
          }
          // A result past its limit is paged and loses every chunk to a descriptor, and their
          // copy IDs with them. Wide text fits fewer chunks, so keep what fits and page the rest.
          var chunks = Array(page.prefix(chunkLimit))
          var result = try assembled(chunks)
          while chunks.count > 1, try result.json().utf8.count > ToolResultProjection.byteLimit {
            chunks.removeLast()
            result = try assembled(chunks)
          }
          return result
        }
      }
    case "lineage": return try scopedLineage(string("id"))
    case "save":
      // The general chat tools' save. Its first kind is a workbook tool.
      try require(
        a["kind"] == .string("tool"), "arguments",
        "Choose a kind for save: tool, document, view, app, record, definition, template or result."
      )
      let statements = a["statements"].array.compactMap(\.string)
      try require(
        statements.count == a["statements"].array.count, "arguments",
        "statements is a list of SQL strings.")
      try require(
        (a["source"].string == nil) != statements.isEmpty, "arguments",
        "A tool holds SQL statements or a JavaScript source, one of the two.")
      return try workbook.chatSaveTool(
        name: string("name"), description: a["description"].text,
        inputs: a["inputs"].array.map {
          let type = $0["type"].text
          return ($0["name"].text, type == "number" ? "decimal" : type.isEmpty ? "text" : type)
        },
        statements: statements, source: a["source"].string, token: "save-" + (receiptID ?? token),
        requestSourceID: requestSourceID, cancellation: cancellation)
    case "guide":
      // Short how-to texts the general tools read on demand.
      guard let text = Self.guides[a["name"].text] else {
        throw SevraError("arguments", "No guide has that name.")
      }
      return .object(["guide": .string(text)])
    case "run":
      // The general chat tools' code tool: one script in the sandbox, or one named action.
      if let action = a["action"].string {
        try require(
          a.object["code"] == nil, "arguments", "Send either code or one action with its arguments.")
        return try executeAttributed(
          "workspace_action",
          .object(["action": .string(action), "arguments": a.object["arguments"] ?? .object([:])]),
          receiptID: receiptID, nativeAppCheck: nativeAppCheck, inspectionOnly: inspectionOnly)
      }
      let unchanging = readOnly || inspectionOnly
      if let name = a["tool"].string {
        // A saved tool by name: a script runs here, SQL statements through sql.
        try require(
          a.object["code"] == nil, "arguments", "Send either code or a saved tool with its values.")
        return try runSavedTool(
          name, values: a["values"].object, readOnly: unchanging, token: receiptID ?? token)
      }
      try require(
        a.object["values"] == nil, "arguments", "values belong to a saved tool, with tool beside them.")
      return try runScript(
        string("code"), inputs: [:], readOnly: unchanging, token: receiptID ?? token)
    case "sql":
      // The general chat tools' table tool. It refuses changes itself when none are allowed.
      if let undo = a["undo"].string {
        try require(
          a.object.count == 1 && !readOnly && !inspectionOnly, "arguments",
          readOnly || inspectionOnly
            ? "This request cannot change the workbook." : "Send undo alone.")
        return try workbook.chatSQLUndo(undo, cancellation: cancellation)
      }
      if let name = a["tool"].string {
        try require(
          a.object["statements"] == nil && a["draft"] != .bool(true), "arguments",
          "Send either statements or a saved tool with its values.")
        return try workbook.chatRunTool(
          name: name, values: a["values"].object, readOnly: readOnly || inspectionOnly,
          token: "sql-" + (receiptID ?? token), requestSourceID: requestSourceID,
          cancellation: cancellation)
      }
      try require(
        a["values"].object.isEmpty, "arguments",
        "values belong to a saved tool. For a draft, set draft to true beside statements.")
      let statements = a["statements"].array.compactMap(\.string)
      try require(
        statements.count == a["statements"].array.count, "arguments",
        "statements is a list of SQL strings.")
      return try workbook.chatSQL(
        statements: statements, readOnly: readOnly || inspectionOnly,
        draft: a["draft"] == .bool(true), token: "sql-" + (receiptID ?? token),
        requestSourceID: requestSourceID, cancellation: cancellation)
    case "datasets":
      return try encoded(
        excelConversion.map { try $0.tables.map { try workbook.dataset($0.id) } }
          ?? workbook.datasets())
    case "rows":
      let table = try workbook.dataset(a["datasetID"].string ?? string("id"))
      let rows = try workbook.rows(table.id, offset: a["offset"].int ?? 0, limit: 100)
      let formulas = try workbook.synchronized {
        try workbook.sheetFormulaPage(table.id, rows: rows)
      }
      var page: [String: Value] = [
        "dataset": try encoded(table),
        "rows": .array(
          try rows.map {
            var row: [String: Value] = [
              "id": .string($0.id),
              "values": .object(workbook.calculatedValues($0, columns: table.columns)),
            ]
            if let cells = formulas?.cells[$0.logicalID] {
              row["excelFormulas"] = try encoded(cells)
            }
            return .object(row)
          }),
      ]
      if let report = formulas?.report { page["excelFormulas"] = try encoded(report) }
      return .object(page)
    case "calculate":
      return .object([
        "result": .string(try Numbers.calculate(string("expression"), values: a["values"].object)),
        "arithmetic": .string("decimal"),
      ])
    case "balance":
      var result = try workbook.balance(subject: string("subject")).object
      let ids =
        [result["basis"]!.text]
        + result["effects"]!.array.map { $0["item_id"].text }
      result["evidence"] = .object([
        "referenceType": .string("item-version"),
        "citations": .array(ids.map(Value.string)),
        "notice": .string(
          "The basis and effects identify workbook Source/Record versions, not conversation messages. "
            + "This calculation inspects those inputs, and the host attaches them to your answer. They need no place in finish.citations. "
            + "Use read for additional source content. No history_read or count_records call is needed to cite this calculation."
        ),
      ])
      return .object(result)
    case "review_queue":
      return try encoded(
        workbook.reviewQueue(cursor: a["cursor"].string, cancellation: cancellation))
    case "open_reviews":
      return .object([
        "status": .string("resolved"),
        "notice": .string("Only the owning live window can confirm that the review list opened."),
      ])
    case "inspect_excel_evidence", "compare_excel_behavior":
      guard let build = excelConversion else {
        throw SevraError("excel_scope", "Use the active Excel import.")
      }
      if tool == "inspect_excel_evidence" {
        try require(
          Set(a.object.keys).isSubset(of: ["part", "offset"])
            && (a["part"] == .null || a["part"].string != nil)
            && (a["offset"] == .null || a["offset"].int != nil), "excel_evidence",
          "Invalid evidence arguments.")
        return try workbook.readExcelEvidence(
          build.conversionID, part: a["part"].string,
          offset: a["offset"].int ?? 0, cancellation: cancellation)
      }
      let behavior = try JSONDecoder().decode(
        ExcelBehavior.self, from: Data(a["behavior"].json().utf8))
      return try workbook.compareExcelBehavior(
        behavior, conversionID: build.conversionID, cancellation: cancellation)
    case "native_app_sdk":
      return .object([
        "sdkVersion": .number(1),
        "guide": .string(
          try excelConversion.map {
            try NativeAppAuthoring.excelGuide($0, workbook: workbook, detailed: true)
          }
            ?? NativeAppAuthoring.guide),
      ])
    case "read_native_app":
      let target: SpaceTarget
      do {
        target = try workbook.spaceTarget(string("id"), cancellation: cancellation)
      } catch let error as SevraError where error.code == "space_not_found" {
        throw SevraError(
          "app_not_found",
          "No saved app or space has that exact name. A failed build saves no app. If the current request asks to create or finish this native app, use native_app_sdk then save_native_app without id or expectedVersion. Do not use save_space for programmable controls. Inspect spaces if the intended name is uncertain."
        )
      }
      let space = try workbook.space(target.id)
      try require(
        space.definition.app != nil, "app_package", "This space is not a programmable app.")
      return .object([
        "id": .string(space.id), "version": .number(Double(space.version)),
        "package": try encoded(space.definition.app!),
        "guide": .string(NativeAppAuthoring.guide),
      ])
    case "save_native_app":
      return try NativeAppAuthoring.save(a, checkResult: nativeAppCheck, tools: self)
    case "spaces":
      return .array(
        try workbook.spaces().map { space in
          var fields = try encoded(space).object
          if let app = space.definition.app {
            fields["definition"] = .object([
              "version": .number(1),
              "app": .object([
                "name": .string(app.name), "digest": .string(app.digest),
                "notice": .string(
                  "Programmable app. Use read_native_app, then save_native_app to edit. Fixed-layout edit_space is not supported."
                ),
              ]),
            ])
          }
          return .object(fields)
        })
    case "open_automation":
      let automation = try workbook.automationTarget(string("target"))
      return .object([
        "id": .string(automation.id), "title": .string(automation.title),
        "status": .string("resolved"),
      ])
    case "open_space":
      return .object([
        "target": try encoded(workbook.spaceTarget(string("target"), cancellation: cancellation)),
        "status": .string("resolved"),
        "notice": .string(
          "Target resolved. Only the owning live window can confirm that it opened."),
      ])
    case "set_space_pinned":
      guard case .bool(let pinned) = a["pinned"] else {
        throw SevraError("arguments", "Choose whether the shortcut should be pinned.")
      }
      let target = try workbook.spaceTarget(string("target"), cancellation: cancellation)
      _ = try workbook.updateSpaceNavigation([.pin(target.id, pinned)])
      return .object([
        "spaceID": .string(target.id), "title": .string(target.title),
        "pinned": .bool(target.id != "home" && pinned),
        "notice": .string(
          target.id == "home"
            ? "Home already has a permanent shortcut."
            : "Navigation preference saved. No snapshot or business change was created."),
      ])
    case "pin_space":
      try require(
        workbook.space(string("id")).definition.app == nil, "app_edit",
        "A programmable app cannot become a fixed snapshot. Use set_space_pinned for a navigation shortcut, or read_native_app then save_native_app to edit its interface."
      )
      return .string(
        try workbook.pinSpace(
          string("id"), title: string("title"), token: token,
          cancellation: cancellation))
    case "space_history":
      return try encoded(workbook.spaceHistory(string("id"), before: a["beforeVersion"].int))
    case "edit_space":
      try require(
        workbook.space(string("id")).definition.app == nil, "app_edit",
        "This is a programmable native app. Read its source and current version with read_native_app, then use save_native_app with behavioral tests. edit_space only changes fixed layouts."
      )
      guard let version = a["expectedVersion"].int else {
        throw SevraError("arguments", "Read the current space version before editing.")
      }
      let edits = try JSONDecoder().decode([SpaceEdit].self, from: Data(a["edits"].json().utf8))
      let saved = try workbook.editSpace(
        string("id"), expectedVersion: version, edits: edits, token: token)
      return .object([
        "spaceID": .string(saved.id), "title": .string(saved.title),
        "version": .number(Double(saved.version)),
      ])
    case "restore_space":
      guard let version = a["version"].int, let expected = a["expectedVersion"].int else {
        throw SevraError("arguments", "Choose an exact saved version and current base.")
      }
      let saved = try workbook.restoreSpace(
        string("id"), version: version, expectedVersion: expected, token: token)
      return .object([
        "spaceID": .string(saved.id), "title": .string(saved.title),
        "version": .number(Double(saved.version)),
      ])
    case "save_space":
      let definition = try JSONDecoder().decode(
        SpaceDefinition.self, from: Data(a["definition"].json().utf8))
      try require(
        definition.app == nil, "app_check",
        "Use save_native_app to check and save programmable source.")
      let title = try string("title")
      // A long request can lose sight of its opening step, and a retry rarely repeats the same
      // component IDs, so its operation token alone would leave a second copy of the view.
      if let existing = try workbook.spaces().first(where: {
        $0.id != token && $0.title.lowercased() == title.lowercased()
      }) {
        throw SevraError(
          "space_duplicate",
          "A space titled \(title) already exists. Do not save it again. "
            + (existing.definition.app == nil
              ? "Use edit_space to change it, or continue with the remaining work."
              : "This is a programmable app. Use read_native_app with its exact name, then save_native_app with its ID and current version to change it.")
        )
      }
      return .object([
        "spaceID": .string(
          try workbook.saveSpace(id: token, title: title, definition: definition, token: token))
      ])
    case "draft", "propose_record":
      // A late correction or retry would otherwise leave two drafts for one request to review.
      if tool == "draft" {
        let title = try string("title")
        try require(
          !(try workbook.savedAnotherDraft(titled: title, arguments: a, runID: runID)),
          "draft_duplicate",
          "A draft titled \(title) was already saved for this work. Do not save it again. Finish, and say plainly what it still needs."
        )
      }
      if tool == "draft", a["parts"] != .null {
        guard case .array(let parts) = a["parts"], !parts.isEmpty, parts.count <= 64 else {
          throw SevraError("document_parts", "Use one to 64 document parts.")
        }
        let resolved = try parts.map { part -> (part: DocumentPart, words: String?) in
          try require(
            Set(part.object.keys).isSubset(of: ["text", "copy"]), "document_parts",
            "Unknown document part field.")
          if let text = part["text"].string, part.object["copy"] == nil {
            return (.init(text: text), nil)
          }
          if let id = part["copy"].string, part.object["text"] == nil {
            let copy = try workbook.documentCopyChoice(
              id, runID: runID, conversation: conversation, cancellation: cancellation)
            return (.init(copy: copy.reference), copy.text)
          }
          throw SevraError("document_parts", "Each part is new prose or one original passage.")
        }
        return try encoded(
          workbook.saveComposedDraft(
            title: string("title"), parts: DocumentPart.placed(resolved, in: a["text"].text),
            inputs: inputs, runID: runID, conversation: conversation, token: token,
            cancellation: cancellation))
      }
      let item = try workbook.addItem(
        category: "record", kind: tool == "draft" ? "document" : string("kind"),
        title: string("title"), text: string("text"),
        data: a["data"] == .null ? .object([:]) : a["data"],
        meaning: a["meaning"].string ?? "estimate", status: "draft",
        inputs: inputs,
        transformation: "local-agent-v1; run=" + runID, token: token)
      return try encoded(item)
    case "propose_movement":
      return try encoded(
        workbook.movement(
          subject: string("subject"), quantity: string("quantity"),
          occurrence: string("occurrence"), effective: string("effective"), input: string("input"),
          meaning: a["meaning"].string ?? "actual", supersedes: a["supersedes"].string,
          token: token, requestSourceID: requestSourceID))
    default:
      // A name that is not a built-in tool may be one of the workbook's own saved tools.
      return try runSavedTool(
        tool, values: a.object, readOnly: readOnly || inspectionOnly, token: receiptID ?? token)
    }
  }

  /// One script in the sandbox. Its sql works on one private copy, search and read see the
  /// saved workbook, and the actions it queues run after its changes are saved.
  private func runScript(
    _ code: String, inputs: [String: Value], readOnly unchanging: Bool, token: String
  ) throws -> Value {
    try workbook.chatRun(
      code: code, readOnly: unchanging, token: "run-" + token,
      requestSourceID: requestSourceID, inputs: inputs,
      host: { method, arguments in
        switch method {
        case "search", "read":
          return try executeAttributed(
            method, arguments, receiptID: nil, nativeAppCheck: nil, inspectionOnly: true)
        case "check_action":
          let operation = try ChatOperations.validate(
            arguments["action"].text, arguments: arguments["arguments"], readOnly: unchanging)
          try require(
            !operation.host, "run",
            arguments["action"].text
              + " needs the app. Call it alone with run action, not inside code. Nothing was changed.")
          return .null
        default:
          return try executeChatOperation(
            arguments["action"].text, arguments: arguments["arguments"])
        }
      }, cancellation: cancellation)
  }

  /// A workbook tool by name, enabled on this Mac: its script, or its statements through sql.
  private func runSavedTool(
    _ name: String, values: [String: Value], readOnly unchanging: Bool, token: String
  ) throws -> Value {
    let tool = try workbook.synchronized { try workbook.runnableTool(name) }
    guard tool.language == "javascript" else {
      return try workbook.chatRunTool(
        name: name, values: values, readOnly: unchanging, token: "tool-" + token,
        requestSourceID: requestSourceID, cancellation: cancellation)
    }
    var result = try runScript(
      tool.source, inputs: workbook.toolInputs(tool, values), readOnly: unchanging, token: token
    ).object
    result["tool"] = .string(tool.signature)
    return .object(result)
  }
}
