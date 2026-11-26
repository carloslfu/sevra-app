import Foundation

/// Discoverable operations, shared by conversation and the existing domain implementations.
public enum ChatOperations {
  public static let appOperationGuidance =
    "Active space is a programmable native app. For business operations, use workspace_actions domain=app and app.inspect. Read the full current request and map its supplied values to EVERY required action input before invoking it. A reference or name can follow the operation directly without a field label. Empty visual form drafts are not missing chat inputs. Do not ask again for a value already supplied in the current request. If any business value is missing, finish with a question listing the missing values; do not invoke the action with placeholders or guessed defaults. Earlier transactions and nearby records are not defaults for a new transaction unless the user explicitly asks to reuse them. For interface edits, use read_native_app with this exact ID, then save_native_app with its current version and tests."
  public struct Operation: Sendable {
    public let name: String
    public let summary: String
    public let required: [String]
    public let optional: [String]
    public let readOnly: Bool
    public let host: Bool
    init(
      _ name: String, _ summary: String, _ required: [String] = [], _ optional: [String] = [],
      readOnly: Bool = false, host: Bool = false
    ) {
      self.name = name
      self.summary = summary
      self.required = required
      self.optional = optional
      self.readOnly = readOnly
      self.host = host
    }
  }
  public static let operations: [Operation] = [
    .init(
      "visual.open_source",
      "Open an exact captured image's source or a captured visual's referenced row in the workbook window.",
      ["messageID", "index"], ["sourceID", "point", "panel", "offset"], readOnly: true, host: true),
    .init(
      "visual.expand", "Open the exact captured chart in the workbook window.",
      ["messageID", "index"], readOnly: true, host: true),
    .init(
      "visual.open_current",
      "Open the corresponding live Home or enabled app view, if still available.",
      ["messageID", "index"], readOnly: true, host: true),
    .init(
      "visual.image_view", "Open, fit, zoom or retry a captured image in the workbook window.",
      ["messageID", "index", "mode"], ["zoom"], readOnly: true, host: true),
    .init(
      "visual.export",
      "Export a captured chart from an exact chat message as PNG, PDF or CSV, to a path the user wrote, or without a path to let them choose in a save panel.",
      ["messageID", "index"], ["path"], host: true),
    .init(
      "visual.inspect", "Inspect a saved visual and current work record versions.",
      ["id", "componentID"], ["cursor", "offset", "panel"], readOnly: true),
    .init(
      "visual.relationships",
      "Inspect one captured diagram’s records and incident relationships. Optionally filter by exact node key.",
      ["messageID", "index"], ["node", "offset"], readOnly: true),
    .init(
      "visual.live_sources",
      "Page exact contributors to a live Home chart point. Refresh after a data or filter change.",
      ["id", "componentID", "snapshot", "queryHash", "point"], ["offset", "panel"], readOnly: true),
    .init(
      "visual.change_record", "Move or reschedule a record through a saved work view.",
      ["id", "componentID", "expectedVersion", "recordID", "value"], ["end", "cursor"]),
    .init(
      "visual.app_capture", "Capture a declared view through its active app permission.",
      ["id", "expectedVersion", "viewID"], ["presentationID"], readOnly: true, host: true),
    .init(
      "visual.app_sources", "Page exact contributors to a currently enabled app chart point.",
      ["id", "expectedVersion", "viewID", "snapshot", "queryHash", "point"],
      ["presentationID", "offset", "panel"], readOnly: true, host: true),
    .init(
      "visual.app_diagram_positions",
      "Inspect positions and exact node keys in an enabled diagram.",
      ["id", "expectedVersion", "viewID"], ["presentationID", "offset"], readOnly: true, host: true),
    .init(
      "visual.app_pin", "Pin the enabled app's declared view to Home with the same access.",
      ["id", "expectedVersion", "viewID", "homeVersion"], ["presentationID"], host: true),
    .init(
      "visual.app_select",
      "Select a labeled group in an enabled app chart or clear it. Changes linked views in this window.",
      ["id", "expectedVersion", "viewID"], ["presentationID", "point", "snapshot", "queryHash"],
      host: true),
    .init(
      "visual.app_filter",
      "Change declared filter values in this window’s linked views. Omit filters to restore the saved values.",
      ["id", "expectedVersion", "viewID"], ["presentationID", "filters"], host: true),
    .init(
      "visual.app_preset",
      "Save a separate chart or diagram presentation, or edit an exact saved preset version.",
      ["id", "expectedVersion", "viewID"],
      ["presetVersionID", "title", "style", "filters", "positions"], host: true),
    .init(
      "visual.app_restore_preset",
      "Restore a prior display preset as a new version. Business data stays the same.",
      ["id", "expectedVersion", "viewID", "presetVersionID", "restoreVersionID"], host: true),
    .init(
      "visual.app_preset_info", "Inspect a preset’s current version and recent display history.",
      ["id", "expectedVersion", "viewID", "presentationID"], readOnly: true, host: true),
    .init(
      "visual.app_archive_preset", "Archive an exact preset version. Placements can be restored.",
      ["id", "expectedVersion", "viewID", "presetVersionID"], host: true),
    .init(
      "visual.schema", "Read the native visual authoring contract.", [], ["family"], readOnly: true),
    .init(
      "visual.evaluate", "Capture a native visual for this chat answer.", [],
      [
        "sourceID", "chart", "work", "diagram", "overview", "text", "aggregate", "caption",
        "accessibilityDescription",
      ], readOnly: true),
    .init(
      "visual.sources", "Inspect one captured chart point’s exact contributing source versions.",
      ["messageID", "index", "point"], ["offset", "panel"], readOnly: true),
    .init(
      "visual.pin",
      "Add an included image or typed live visual to Home at its exact current version.",
      ["expectedVersion"],
      [
        "sourceID", "chart", "work", "diagram", "overview", "text", "aggregate", "title", "caption",
        "accessibilityDescription",
      ]),
    .init(
      "visual.promote", "Add the exact visual from a saved chat message as a live Home view.",
      ["messageID", "index", "expectedVersion"]),
    .init(
      "visual.replace_image", "Replace the included original for an exact saved image component.",
      ["id", "componentID", "expectedVersion", "sourceID"], ["caption", "accessibilityDescription"]),
    .init(
      "visual.configure",
      "Update a saved visual's labels, chart mark or calendar month without replacing its binding.",
      ["id", "componentID", "expectedVersion"],
      [
        "title", "caption", "accessibilityDescription", "style", "threshold", "month",
        "annotations", "columns", "blocks", "dataBars", "positions",
      ]),
    .init(
      "visual.filter",
      "Replace the typed presentation filters on a saved workbook chart or work view. Use an empty array to clear the filters. Workbook source scope stays fixed.",
      ["id", "componentID", "expectedVersion", "filters"]),
    .init(
      "app.browse",
      "Filter, sort or page a mini-app table without clicking. Use a table target from app.inspect. sort is a column ID (empty clears sorting), offset is a zero-based row offset; each page has at most 200 rows. The optional view uses the same state.",
      ["id", "target"], ["search", "sort", "descending", "offset"], readOnly: true, host: true),
    .init(
      "chat.pending",
      "Inspect the exact pending conversational approval, including its preview and inputs. Only the human can confirm it.",
      readOnly: true),
    .init(
      "app.inspect",
      "Inspect a mini app's actions, typed inputs, current values and displayed results. id is its exact space ID/name.",
      ["id"], readOnly: true, host: true),
    .init(
      "app.run",
      "Run a discovered named action ONLY after every required input is supplied by the user or a record they explicitly identified for that value. Ask for missing inputs with request_input when available before calling this tool. Never send TODO/placeholders, invent references, or copy another transaction's customer, amount or time as defaults. A validation error is not permission to choose replacement business values. inputs is its typed argument object. Follow each input valueType: decimal inputs are JSON strings, for example quantity:\"3\". No visual view required.",
      ["id", "expectedVersion", "action", "inputs"], host: true),
    .init(
      "app.set",
      "Set an exact discovered input by target and typed value, invoking the same validation as its control.",
      ["id", "expectedVersion", "target", "value"], host: true),
    .init(
      "app.fill",
      "Supply several discovered inputs in order without leaving chat. inputs is [{target:exactInputName,value:typedValue}]. Stops on failure and reports any earlier saved changes.",
      ["id", "expectedVersion", "inputs"], host: true),
    .init(
      "app.select",
      "Select a current row only on a table with a discovered onSelect handler. Use the exact rowID from app.browse. Run named actions directly with their typed inputs.",
      ["id", "expectedVersion", "target", "rowID"], host: true),
    .init(
      "app.activate",
      "Invoke an existing discovered action by target, or a table row/Canvas region. This calls its handler without clicking.",
      ["id", "expectedVersion", "target"], ["rowID", "region"], host: true),
    .init(
      "app.drop",
      "Move a named canvas region by movement deltas x,y through its saved drop handler.",
      ["id", "expectedVersion", "target", "region", "x", "y"], host: true),
    .init(
      "app.undo",
      "Undo the app's latest saved transaction when canUndo is true. Pass transaction for an exact receipt. After Undo, use app.redo to restore it; a second Undo never redoes it.",
      ["id", "expectedVersion"], ["transaction"], host: true),
    .init(
      "app.redo",
      "Restore the app's last undone transaction when canRedo is true. Pass its reversal transaction for an exact receipt.",
      ["id", "expectedVersion"], ["transaction"], host: true),
    .init(
      "app.enable",
      "Prepare exact-version table-access approval in chat. The user confirms in conversation.",
      ["id", "expectedVersion"], host: true),
    .init(
      "app.disable", "Revoke this app version's local execution permission.",
      ["id", "expectedVersion"], host: true),
    .init(
      "app.restart", "Restart the current approved app version, restoring saved inputs.",
      ["id", "expectedVersion"], host: true),
    .init(
      "record.review",
      "Prepare a conversational decision for an exact inspected item version. decision: accept or undo. User confirmation applies it. To take a draft or anything else out of the workbook, use remove.",
      ["id", "decision"], host: true),
    .init(
      "remove",
      "Take a document, record, table, view, app, form, workflow, function, rule, automation or saved tool out of the workbook, by its id. History keeps it and restore brings it back. The person confirms in chat.",
      ["id"], host: true),
    .init(
      "restore",
      "Bring back something removed, by the id read kind=removed lists. The person confirms in chat.",
      ["id"], host: true),
    .init(
      "form.inspect", "Inspect a saved form's named inputs and current target, without opening it.",
      ["id"], readOnly: true),
    .init(
      "form.submit",
      "Fill and submit all typed form inputs through chat. Previews the exact effect for conversational confirmation.",
      ["id", "inputs"], ["preview"], host: true),
    .init(
      "document.edit",
      "Edit an exact generated document version; preserves originals and detects stale edits.",
      ["id", "text"], ["separate"]),
    .init(
      "table.schema",
      "Inspect the full current table schema, including exact version and definition ID.", ["id"],
      readOnly: true),
    .init(
      "table.history", "Inspect saved table schemas.", ["id"], ["beforeVersion"], readOnly: true),
    .init(
      "table.edit_schema",
      "Add/change/remove columns or formulas, rename/archive/restore a table. Supply complete columns only if changing columns; preserve unrelated columns.",
      ["id", "expectedVersion", "expectedDefinitionID"], ["title", "columns", "archived"]),
    .init(
      "table.restore_schema", "Restore an exact historical schema as a new version.",
      ["id", "definitionID", "expectedVersion", "expectedDefinitionID"]),
    .init("table.undo", "Undo a saved table edit by its change ID.", ["id"]),
    .init("table.undo_sql", "Undo everything one sql call saved, by its undo value.", ["token"]),
    .init(
      "table.confirm_change",
      "Apply a sql call or script that waited for the person's confirmation. Only the host prepares it.",
      ["tool", "call"], host: true),
    .init(
      "tool.undo",
      "Undo saving a tool, by the definitionID its save returned: restores the earlier version, or removes a new tool.",
      ["id"]),
    .init(
      "table.change_rows",
      "Atomically insert/update/delete up to 64 rows in an inspected table. operations:[{op:insert,values:{...}}|{op:update,id:exactRowVersion,values:{changedFields}}|{op:delete,id:exactRowVersion}]. Existing formulas recalculate. Only do explicitly requested changes; use proposals when the user requests review first.",
      ["id", "expectedDefinitionID", "operations"]),
    .init(
      "table.undo_rows",
      "Undo a conversation row transaction by its returned token; current schema and row versions must still match.",
      ["id", "expectedDefinitionID", "token"]),
    .init(
      "workflow.continue",
      "Execute a queued workflow through its next review, clarification or completion. Supplies the same foreground execution as Continue.",
      ["id"]),
    .init(
      "workflow.run",
      "Start and execute an exact saved workflow definition through its next review, clarification or completion. id is the definition version, inputs are its declared parameters. Use this when asked to run a workflow; start_workflow only queues.",
      ["id", "inputs"], host: true),
    .init(
      "workflow.retry", "Retry a failed workflow and continue through its next stopping point.",
      ["id"]),
    .init("workflow.cancel", "Cancel remaining workflow work; preserve completed results.", ["id"]),
    .init(
      "workflow.answer",
      "Supply requested clarification inputs and reason to the paused workflow, preparing conversational confirmation.",
      ["id", "values", "reason"], ["target"], host: true),
    .init(
      "automation.inspect", "Inspect a saved automation and this Mac's grants.", ["id"],
      readOnly: true, host: true),
    .init(
      "automation.enable",
      "Prepare conversational approval of a saved automation on this Mac, including whether local AI may run.",
      ["id", "generation", "allowAI"], [], host: true),
    .init("automation.pause", "Pause this Mac's exact automation grant.", ["id"], host: true),
    .init("file.include", "Include a previously linked original in this workbook.", ["id"]),
    .init("file.transcribe", "Transcribe an included recording locally.", ["id"], host: true),
    .init(
      "intake.inspect", "Inspect saved file intake jobs and their next required inputs.", [],
      ["sourceID"], readOnly: true),
    .init("intake.run", "Continue indexing a saved intake job.", ["id"]),
    .init(
      "intake.use",
      "Choose how to use an included source: reference, analysis, values (table), or update. Starts and runs that intake without a dialog.",
      ["sourceID", "role"]),
    .init(
      "intake.table_source",
      "Inspect an included CSV/Excel source's sheets, headings and column mapping choices.",
      ["sourceID"], ["headerRow", "sheet"], readOnly: true),
    .init(
      "intake.preview_update",
      "Preview append/replace/merge into a table. mapping is [{position:zeroBasedIndex,target:targetColumnIDOrNull}] using the inspected contract; keys are target matching columns. Inspect source and mapping suggestions first.",
      ["sourceID", "datasetID", "mode", "mapping"], ["keys", "headerRow", "sheet"], readOnly: true),
    .init(
      "intake.suggest_mapping",
      "Get the native mapping suggestion for an inspected source and table.",
      ["sourceID", "datasetID"], ["headerRow", "sheet"], readOnly: true),
    .init(
      "intake.propose_update",
      "Save the exact previewed append/replace/merge as a reviewable table update. Use preview revision/fingerprint and explicit new-row meaning/scenario.",
      [
        "sourceID", "datasetID", "mode", "mapping", "expectedRevision", "expectedFingerprint",
        "meaning", "scenario",
      ], ["keys", "headerRow", "sheet"]),
    .init(
      "file.export_workbook",
      "Export a portable workbook to the user's supplied absolute .sevraz path, or without a path to let them choose in a save panel. Never overwrites.",
      [], ["path"], host: true),
    .init(
      "file.export_original",
      "Save a byte-verified copy of an included original to the user's supplied absolute path, or without a path to let them choose in a save panel.",
      ["id"], ["path"], host: true),
    .init(
      "file.export_table",
      "Export a table as CSV, named by its id or its name under Tables for sql, to the user's supplied absolute path, or without a path to let them choose in a save panel.",
      ["id"], ["path"], host: true),
    .init(
      "file.export_app",
      "Export a mini-app template to the user's supplied absolute .sevraapp path, or without a path to let them choose in a save panel. Records are excluded.",
      ["id"], ["path"], host: true),
    .init(
      "excel.inspect", "Inspect a saved Excel import and its current plan, tables and state.",
      ["id"], readOnly: true),
    .init("excel.list", "List saved Excel imports.", readOnly: true),
    .init(
      "excel.begin", "Begin or resume an Excel workspace from an included original.", ["sourceID"]),
    .init(
      "excel.add_example",
      "Add an included recalculated Excel example with action and argument values for behavior comparison.",
      ["id", "sourceID", "action", "inputs", "expectedVersion"]),
    .init(
      "excel.remove_example", "Remove a comparison example from a specific import version.",
      ["id", "index", "expectedVersion"]),
    .init(
      "excel.analyze",
      "Understand or rethink an Excel workflow using the user's purpose/clarification text.",
      ["id"], ["purpose"], host: true),
    .init("excel.use_tables", "Use the imported worksheet tables without creating an app.", ["id"]),
    .init(
      "excel.build", "Build the reviewed Excel workspace with local AI in this conversation.",
      ["id"], host: true),
  ]
  /// Operations only the host prepares, as the action of a confirmation it shows the person.
  /// No model is offered them, so a change cannot skip the confirmation it waits for.
  public static let hostPrepared: Set<String> = ["table.confirm_change"]
  /// The operations a model or outside agent may name.
  public static var offered: [Operation] { operations.filter { !hostPrepared.contains($0.name) } }

  public static func catalog(_ domain: String? = nil, allowed: Set<String>? = nil) throws -> Value {
    let all = offered.filter { allowed?.contains($0.name) ?? true }
    let matching = all.filter { operation in
      domain == nil || domain!.isEmpty || operation.name.hasPrefix(domain! + ".")
    }
    // A ref that names no domain, such as a table's id, lists every action rather than none.
    return .array(
      (matching.isEmpty ? all : matching).map { operation in
        .object([
          "action": .string(operation.name), "description": .string(operation.summary),
          "required": .array(operation.required.map(Value.string)),
          "optional": .array(operation.optional.map(Value.string)),
          "types": .object(
            Dictionary(
              uniqueKeysWithValues: (operation.required + operation.optional).map {
                ($0, .string(argumentType(operation.name, $0)))
              })),
          "readOnly": .bool(operation.readOnly),
        ])
      })
  }
  private static func argumentType(_ name: String, _ key: String) -> String {
    if key == "value" { return name == "visual.change_record" ? "string" : "value" }
    if key == "expectedVersion" { return name.hasPrefix("excel.") ? "string" : "integer" }
    if key == "inputs" { return name == "app.fill" ? "array" : "object" }
    if key == "target" && name == "workflow.answer" { return "object" }
    if key == "call" && name == "table.confirm_change" { return "object" }
    if ["values", "preview", "chart", "work", "diagram", "overview", "aggregate", "positions"]
      .contains(key)
    {
      return "object"
    }
    if key == "text" && ["visual.evaluate", "visual.pin"].contains(name) { return "object" }
    if key == "columns" && name == "visual.configure" { return "integer" }
    if ["blocks", "columns", "operations", "mapping", "keys", "filters", "annotations"].contains(
      key)
    {
      return "array"
    }
    if ["archived", "separate", "allowAI", "descending", "dataBars"].contains(key) {
      return "boolean"
    }
    if [
      "beforeVersion", "headerRow", "expectedRevision", "generation", "index", "point", "offset",
      "panel", "homeVersion",
    ].contains(
      key)
    {
      return "integer"
    }
    if ["x", "y"].contains(key) { return "number" }
    return "string"
  }
  public static func validate(_ name: String, arguments: Value, readOnly: Bool) throws -> Operation
  {
    guard let operation = operations.first(where: { $0.name == name }) else {
      throw SevraError("chat_action", "Discover available workspace actions first.")
    }
    guard case .object(let fields) = arguments else {
      throw SevraError("arguments", "Supply the declared input fields.")
    }
    try require(
      !readOnly || operation.readOnly, "read_only_request", "This request forbids changes.")
    let missing = Set(operation.required).subtracting(fields.keys).sorted()
    let unexpected = Set(fields.keys).subtracting(operation.required + operation.optional).sorted()
    if !missing.isEmpty || !unexpected.isEmpty {
      // A rejected envelope never reaches the domain handler. Describe its exact
      // contract so the model can repair this call without guessing field names.
      let required = operation.required.map { $0 + ":" + argumentType(name, $0) }.joined(
        separator: ", ")
      let optional = operation.optional.map { $0 + ":" + argumentType(name, $0) }.joined(
        separator: ", ")
      throw SevraError(
        "arguments",
        name + " was not invoked."
          + (missing.isEmpty ? "" : " Missing fields: " + missing.joined(separator: ", ") + ".")
          + (unexpected.isEmpty
            ? "" : " Unexpected fields: " + unexpected.joined(separator: ", ") + ".")
          + " Required arguments: {" + required + "}. Optional arguments: {" + optional
          + "}. Read workspace_actions for this operation; preserve the user's values.")
    }
    for (key, value) in fields {
      let type = argumentType(name, key)
      let valid: Bool
      switch (type, value) {
      case ("value", _), ("string", .string), ("object", .object), ("array", .array),
        ("boolean", .bool):
        valid = true
      case ("integer", .number(let number)):
        valid =
          number.isFinite && number.rounded() == number && abs(number) <= 9_007_199_254_740_991
      case ("number", .number(let number)): valid = number.isFinite
      default: valid = false
      }
      try require(valid, "arguments", "Supply " + key + " as " + type + ".")
    }
    return operation
  }
}

extension WorkbookTools {
  func executeChatOperation(_ name: String, arguments a: Value) throws -> Value {
    let operation = try ChatOperations.validate(name, arguments: a, readOnly: readOnly)
    if operation.host || ["workflow.continue", "workflow.retry"].contains(name) {
      return .object(["hostAction": .string(name), "arguments": a])
    }
    let token = try operationToken(
      "workspace_action", .object(["action": .string(name), "arguments": a]))
    func string(_ key: String) throws -> String {
      guard let value = a[key].string, !value.isEmpty else {
        throw SevraError("arguments", "Supply " + key + ".")
      }
      return value
    }
    func integer(_ key: String) throws -> Int {
      guard let value = a[key].int, a[key] == .number(Double(value)) else {
        throw SevraError("arguments", "Supply a whole number for " + key + ".")
      }
      return value
    }
    if name.hasPrefix("visual.") { return try executeVisualOperation(name, a, token: token) }
    switch name {
    case "chat.pending":
      guard let approval = try workbook.pendingChatApproval(conversation: conversation) else {
        return .object(["status": .string("none")])
      }
      return .object([
        "status": .string("confirmation_required"), "preview": .string(approval.title),
        "action": .string(approval.action), "arguments": approval.arguments,
      ])
    case "form.inspect":
      return try workbook.applicationFormContext(string("id"), cancellation: cancellation)
    case "document.edit":
      return try encoded(
        workbook.editDocument(
          string("id"), text: a["text"].text, separate: a["separate"] == .bool(true), token: token,
          cancellation: cancellation))
    case "table.schema": return try workbook.datasetSchema(string("id"))
    case "table.history":
      return try encoded(
        workbook.datasetDefinitions(string("id"), beforeVersion: a["beforeVersion"].int))
    case "table.edit_schema":
      let columns = try a.object["columns"].map {
        try decodeDescriptor([Column].self, from: $0, named: "columns")
      }
      if a.object["archived"] != nil {
        guard case .bool = a["archived"] else {
          throw SevraError("arguments", "Archived must be true or false.")
        }
      }
      return try encoded(
        workbook.updateDatasetDefinition(
          string("id"), expectedVersion: integer("expectedVersion"),
          expectedDefinitionID: string("expectedDefinitionID"), title: a["title"].string,
          columns: columns, archived: a.object["archived"].map { $0 == .bool(true) }, token: token,
          cancellation: cancellation))
    case "table.restore_schema":
      return try encoded(
        workbook.restoreDatasetDefinition(
          string("id"), definitionID: string("definitionID"),
          expectedVersion: integer("expectedVersion"),
          expectedDefinitionID: string("expectedDefinitionID"), token: token,
          cancellation: cancellation))
    case "table.undo": return try encoded(workbook.undoTableChange(string("id")))
    case "table.undo_sql": return try workbook.chatSQLUndo(string("token"), cancellation: cancellation)
    case "tool.undo": return try workbook.undoToolSave(string("id"))
    case "table.change_rows", "table.undo_rows":
      return try workbook.chatTableTransaction(
        string("id"), expectedDefinitionID: string("expectedDefinitionID"),
        operations: name == "table.undo_rows" ? [] : a["operations"].array,
        undo: name == "table.undo_rows" ? string("token") : nil,
        token: token, requestSourceID: requestSourceID, cancellation: cancellation)
    case "workflow.cancel":
      return try workbook.cancelWorkflow(string("id"), token: token, cancellation: cancellation)
    case "file.include":
      return try encoded(workbook.includeLinked(string("id"), cancellation: cancellation))
    case "intake.inspect": return try encoded(workbook.intakeJobs(sourceID: a["sourceID"].string))
    case "intake.run":
      return try encoded(workbook.runIntake(string("id"), cancellation: cancellation))
    case "intake.use":
      guard let role = IntakeRole(rawValue: try string("role")) else {
        throw SevraError("intake_role", "Choose reference, analysis, values or update.")
      }
      let job = try workbook.beginIntake(sourceID: string("sourceID"), role: role, token: token)
      return try encoded(workbook.runIntake(job.id, cancellation: cancellation))
    case "intake.table_source", "intake.suggest_mapping":
      let source = try workbook.inspectTableUpdateSource(
        string("sourceID"), headerRow: a["headerRow"].int ?? 1, sheet: a["sheet"].string,
        cancellation: cancellation)
      if name == "intake.suggest_mapping" {
        return try encoded(source.suggestion(for: workbook.dataset(string("datasetID")).columns))
      }
      return try encoded(source)
    case "intake.preview_update", "intake.propose_update":
      guard let mode = TableUpdateMode(rawValue: try string("mode")) else {
        throw SevraError("update_mode", "Choose append, replace or merge.")
      }
      let mapping = try decodeDescriptor(
        [IntakeColumnMapping].self, from: a["mapping"], named: "mapping")
      let keys = try a.object["keys"].map { try decodeDescriptor([String].self, from: $0, named: "keys") } ?? []
      if name == "intake.preview_update" {
        return try encoded(
          workbook.previewTableUpdate(
            sourceID: string("sourceID"), datasetID: string("datasetID"), mode: mode,
            mapping: mapping, keys: keys, headerRow: a["headerRow"].int ?? 1,
            sheet: a["sheet"].string, cancellation: cancellation))
      }
      return try encoded(
        workbook.proposeTableUpdate(
          sourceID: string("sourceID"), datasetID: string("datasetID"), mode: mode,
          mapping: mapping, keys: keys, headerRow: a["headerRow"].int ?? 1,
          sheet: a["sheet"].string,
          newRowMeaning: string("meaning"), newRowScenario: string("scenario"),
          expectedRevision: integer("expectedRevision"),
          expectedFingerprint: string("expectedFingerprint"), token: token,
          cancellation: cancellation))
    case "excel.inspect": return try encoded(workbook.excelConversion(string("id")).record)
    case "excel.list": return .array(try workbook.excelConversionSummaries())
    case "excel.begin":
      return try encoded(
        workbook.beginExcelConversion(sourceID: string("sourceID"), cancellation: cancellation)
          .record)
    case "excel.add_example":
      return try encoded(
        workbook.addExcelExample(
          string("id"), sourceID: string("sourceID"), action: string("action"),
          arguments: a["inputs"], expectedVersion: string("expectedVersion"),
          cancellation: cancellation
        ).record)
    case "excel.remove_example":
      return try encoded(
        workbook.removeExcelExample(
          string("id"), index: integer("index"), expectedVersion: string("expectedVersion")
        ).record)
    case "excel.use_tables":
      return try encoded(
        workbook.importExcelConversionTables(string("id"), cancellation: cancellation).record)
    default: throw SevraError("chat_action", "This operation is unavailable.")
    }
  }
}

extension Workbook {
  /// A retry cannot duplicate an action whose result was saved, or guess what an interrupted call did.
  public func chatActionReplay(runID: String, arguments: Value, excluding receiptID: String) throws
    -> Value?
  {
    try synchronized {
      let token = try WorkbookTools.operationToken(
        runID: runID, "workspace_action", arguments)
      let prior = try db.execute(
        "SELECT state,result FROM tool_calls WHERE run_id=? AND operation_token=? AND id<>? ORDER BY rowid DESC LIMIT 1",
        [.string(runID), .string(token), .string(receiptID)]
      ).first
      guard let prior else { return nil }
      try require(
        prior["state"] == .string("completed"), "uncertain_action",
        "An earlier attempt did not report completion. Inspect its saved changes before requesting another attempt."
      )
      let saved = try Value.parse(prior["result"]!.text)
      guard case .object(var fields) = saved else { return saved }
      fields["replayed"] = .bool(true)
      fields["replayNotice"] = .string(
        "This is the earlier call's saved receipt, not a new action. Inspect again for current app state."
      )
      return .object(fields)
    }
  }
}
