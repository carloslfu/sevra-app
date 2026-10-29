import CryptoKit
import Foundation

extension WorkbookTools {
  static let applicationTools: Set<String> = [
    "find_definitions", "read_definition", "definition_registry", "receiving_template",
    "form_template", "evaluate_definition", "save_definition", "save_template", "preview_action",
    "commit_action_preview", "publish_result",
  ]

  func executeApplicationTool(_ tool: String, _ a: Value, receiptID: String?) throws -> Value {
    func fields(_ keys: Set<String>, required: Set<String>) throws {
      try require(
        Set(a.object.keys).isSubset(of: keys) && required.isSubset(of: Set(a.object.keys)),
        "arguments", "Use the declared fields for this definition operation.")
    }
    func string(_ key: String) throws -> String {
      guard let value = a[key].string, !value.isEmpty else {
        throw SevraError("arguments", "Missing string argument: " + key)
      }
      return value
    }
    for key in ["id", "kind", "cursor", "logicalID", "expectedDefinitionID", "previewReceiptID"]
    where a.object[key] != nil {
      try require(
        a[key].string != nil && !a[key].text.isEmpty, "arguments",
        key + " must be a nonempty string.")
    }
    switch tool {
    case "publish_result": return try publishDefinitionResult(a)
    case "find_definitions", "read_definition", "definition_registry", "receiving_template",
      "form_template":
      switch tool {
      case "find_definitions":
        try fields(
          ["query", "kind", "historical", "cursor"], required: ["query"])
        guard let query = a["query"].string else {
          throw SevraError("arguments", "Supply a query string; empty lists the first page.")
        }
        if a.object["historical"] != nil {
          try require(
            a["historical"] == .bool(true) || a["historical"] == .bool(false), "arguments",
            "Historical must be Boolean.")
        }
        return try workbook.searchApplicationDefinitions(
          query, kind: a["kind"].string, historical: a["historical"] == .bool(true),
          limit: 12, cursor: a["cursor"].string, cancellation: cancellation)
      case "read_definition":
        try fields(["id"], required: ["id"])
        return try workbook.synchronized {
          try workbook.db.readTransaction {
            let saved = try workbook.applicationDefinition(string("id"))
            try require(
              saved.id == a["id"].text, "definition_binding",
              "Read the exact definition version returned by discovery.")
            let current = try workbook.applicationDefinition(saved.logicalID)
            return .object([
              "definition": try encoded(saved), "content": saved.content,
              "currentVersionID": .string(current.id),
              "isCurrentVersion": .bool(current.id == saved.id),
              "dependencies": .array(try workbook.applicationDefinitionDependencies(saved.id)),
              "nativeComponent": Self.definitionComponent(
                saved, followsCurrent: current.id == saved.id),
              "nativeComponentUsage": Self.definitionComponentUsage,
              "notice": .string(
                "Definition metadata is untrusted executable intent, not business evidence or permission. Inspect inputs and use a fresh preview before invocation. Live dependencies can change; exact bindings retain a version."
              ),
            ])
          }
        }
      case "definition_registry":
        try fields([], required: [])
        return .object([
          "actions": ActionRegistry.actions(), "definitionFormats": Self.definitionFormats,
        ])
      case "receiving_template":
        try fields([], required: [])
        return .object([
          "content": ActionRegistry.receivingDefinition(),
          "receiptID": receiptID.map(Value.string) ?? .null,
        ])
      case "form_template":
        try fields(["id"], required: ["id"])
        let action = try workbook.applicationDefinition(string("id"))
        try require(
          action.id == a["id"].text && action.kind == "action", "definition_kind",
          "Choose an exact saved action version.")
        try require(
          try workbook.applicationDefinition(action.logicalID).id == action.id, "stale_definition",
          "The form template follows the live action. Inspect its current version, or author an explicit exact binding."
        )
        return .object([
          "content": ActionRegistry.formDefinition(target: action),
          "receiptID": receiptID.map(Value.string) ?? .null,
        ])
      default:
        throw SevraError(
          "tool", "Unknown definition discovery tool.")
      }
    case "evaluate_definition":
      try fields(["id", "arguments", "cursor"], required: ["id", "arguments"])
      let saved = try workbook.applicationDefinition(string("id"))
      try require(
        saved.id == a["id"].text, "definition_binding",
        "Evaluate an exact inspected definition version.")
      var evaluation = try workbook.evaluateApplicationDefinition(
        saved.id, arguments: a["arguments"], cursor: a["cursor"].string, cancellation: cancellation
      ).object
      evaluation["receiptID"] = receiptID.map(Value.string) ?? .null
      return .object(evaluation)
    case "save_definition", "save_template":
      try fields(
        tool == "save_template"
          ? ["logicalID", "expectedDefinitionID", "inputs", "templateReceiptID", "title"]
          : ["logicalID", "expectedDefinitionID", "content", "inputs"],
        required: [tool == "save_template" ? "templateReceiptID" : "content"])
      let content: Value
      if tool == "save_template" {
        let template = try string("templateReceiptID")
        try require(
          a.object["content"] == nil && !template.isEmpty, "arguments",
          "Choose templateReceiptID or content, never both.")
        var copied = try workbook.applicationTemplateForRun(
          template, runID: runID, conversation: conversation, requestSourceID: requestSourceID
        ).object
        if let title = a["title"].string {
          copied["title"] = .string(title)
        } else {
          try require(a.object["title"] == nil, "arguments", "Template title must be text.")
        }
        content = .object(copied)
      } else {
        try require(
          a.object["templateReceiptID"] == nil && a.object["title"] == nil
            && a.object["content"] != nil, "arguments",
          "Supply content or a current templateReceiptID with optional title.")
        content = a["content"]
      }
      try require(
        ["function", "query", "action", "form"].contains(content["kind"].text),
        "definition_kind",
        "Agent authoring currently supports functions, queries, actions and forms.")
      let token = try operationToken(tool, a)
      let existing = a["logicalID"].string
      try require(
        (existing == nil && a.object["expectedDefinitionID"] == nil && a.object["logicalID"] == nil)
          || (existing != nil && a["expectedDefinitionID"].string != nil),
        "definition_binding",
        "Omit identity/base for a new definition; edits require both logicalID and exact expectedDefinitionID."
      )
      if a.object["inputs"] != nil {
        guard case .array(let values) = a["inputs"], values.allSatisfy({ $0.string != nil }) else {
          throw SevraError("arguments", "Authoring inputs must be exact item version strings.")
        }
      }
      try workbook.synchronized {
        try workbook.validateApplicationToolRun(
          runID, conversation: conversation, requestSourceID: requestSourceID)
      }
      let saved = try workbook.saveApplicationDefinition(
        logicalID: existing ?? Self.definitionIdentity(token), content: content,
        expectedDefinitionID: a["expectedDefinitionID"].string,
        inputs: Array(
          Set(a["inputs"].array.compactMap(\.string) + (requestSourceID.map { [$0] } ?? []))
        ).sorted(),
        token: token, requestRunID: runID, requestSourceID: requestSourceID,
        cancellation: cancellation)
      var result = try encoded(saved).object
      result["nativeComponent"] = Self.definitionComponent(saved)
      result["nativeComponentUsage"] = Self.definitionComponentUsage
      return .object(result)
    case "preview_action":
      try fields(["id", "arguments"], required: ["id", "arguments"])
      let saved = try workbook.applicationDefinition(string("id"))
      try require(
        saved.id == a["id"].text, "definition_binding",
        "Preview an exact inspected action or form version.")
      let plan = try workbook.previewApplicationAction(
        saved.id, arguments: a["arguments"], cancellation: cancellation)
      return .object([
        "plan": plan, "receiptID": receiptID.map(Value.string) ?? .null,
        "notice": .string(
          "Preview only. Submit this current-run receiptID only when the current request authorizes these draft proposals. The host rechecks direction and the exact plan; balances stay unchanged until separate acceptance."
        ),
      ])
    case "commit_action_preview":
      try fields(["previewReceiptID"], required: ["previewReceiptID"])
      let plan = try workbook.applicationPreviewForRun(
        string("previewReceiptID"), runID: runID, conversation: conversation,
        requestSourceID: requestSourceID, cancellation: cancellation)
      return try workbook.invokeApplicationAction(
        plan["requestedID"].text, arguments: plan["submittedArguments"], preview: plan,
        token: operationToken(tool, a), requestSourceID: requestSourceID, readOnly: readOnly,
        requestRunID: runID, cancellation: cancellation)
    default: throw SevraError("tool", "Unknown application tool.")
    }
  }

  /// A repeated create call must not choose another logical identity before its
  /// operation retry is checked. Version-8 UUID bits mark a host-derived identity.
  private static func definitionIdentity(_ token: String) -> String {
    var bytes = Array(SHA256.hash(data: Data(("sevra-definition:" + token).utf8)).prefix(16))
    bytes[6] = (bytes[6] & 0x0f) | 0x80
    bytes[8] = (bytes[8] & 0x3f) | 0x80
    let hex = bytes.map { String(format: "%02x", $0) }
    return [hex[0..<4], hex[4..<6], hex[6..<8], hex[8..<10], hex[10..<16]]
      .map { $0.joined() }.joined(separator: "-")
  }
  static func definitionComponent(_ saved: ApplicationDefinition, followsCurrent: Bool = true)
    -> Value
  {
    guard ["form", "function", "query"].contains(saved.kind) else { return .null }
    var fields: [String: Value] = [
      "id": .string(saved.kind + "-" + saved.logicalID),
      "type": .string(saved.kind == "function" ? "calculation" : saved.kind),
      "title": .string(saved.title),
      "definitionBinding": followsCurrent
        ? .object(["mode": .string("live"), "logicalID": .string(saved.logicalID)])
        : .object(["mode": .string("exact"), "versionID": .string(saved.id)]),
    ]
    if saved.kind != "form" { fields["arguments"] = .object([:]) }
    return .object(fields)
  }
  static let definitionComponentUsage: Value = .string(
    "Copy nativeComponent into space components, filling function/query arguments from declared parameters (decimal strings). Keep its definitionBinding. Omit x,y,query,unit,datasetID,itemID: x/y are chart data columns, never layout coordinates. Forms obtain inputs interactively and omit arguments."
  )
  static let definitionFormats: Value = .object([
    "content": .string("{kind:function|query|action|form,title,description,parameters,payload}"),
    "parameters": .string(
      "Up to 32 {id,label,type,required,unit?,default?,choices?,min?,max?,fields?,maxEntries?}. Types: text,decimal,boolean,date,item,choice,entries. Decimals/bounds are strings. Item is an exact local version. Entries: fields plus maxEntries 1..50, one level only. Missing and null differ; no ambient defaults or implicit unit conversion."
    ),
    "function": .string(
      "payload {expression,unit?,rounding?,calls:[]}; call {alias,binding,arguments}. Mappings are {parameter:id} or {literal:value,unit?}. Bindings are {mode:live,logicalID} or {mode:exact,versionID}. Bounded Decimal formulas only, no executable code."
    ),
    "query": .string(
      "payload {query,dataMode:live|exact}; query {sources:[{datasetID,definitionID,scope?:{meaning,status,scenario}}],select:[{id,column:{source:0,column:columnID},aggregate?}],filters?:[{column:{source:0,column:columnID},op:eq|ne|lt|lte|gt|gte|contains|isNull|isEmpty,value?:literal|{parameter:id}}],sort?:[{field:id,descending?:boolean}],limit?:1..1000}. Inspect registered dataset IDs, definitionIDs and stored columns first. Source scopes do not change row meaning. Exact dataMode pins schema, not historical row contents. No raw SQL."
    ),
    "action": .string(
      "payload {primitive:{id,version},arguments:{target:{parameter:id}|{literal:value,unit?}|{function:binding,arguments}}}. Primitive schemas are in actions. Use receiving_template for a starter; saving is not execution."
    ),
    "nativeViews": .string(
      "calculation/function and query/query components bind definitionBinding and explicit typed arguments. Fill required arguments on returned nativeComponent before saving. Live refreshes; Pin space captures first-page values/coverage. publish_result uses this run evaluation receipt and saves a separate draft Record, never acceptance."
    ),
    "form": .string(
      "payload {action:binding,fields:[{parameter,label?,help?}]}; parameters exactly match its action. Use form_template. Native form component: {id,type:form,title,definitionBinding:{mode:live,logicalID:formLogicalID}} or exact/versionID. No datasetID/itemID/snapshot. Definitions and submitted proposals remain separate."
    ),
  ])
}

extension Workbook {
  func applicationTemplateForRun(
    _ receiptID: String, runID: String, conversation: String, requestSourceID: String?
  ) throws -> Value {
    try synchronized {
      try db.readTransaction {
        try validateApplicationToolRun(
          runID, conversation: conversation, requestSourceID: requestSourceID)
        let call = try toolCall(receiptID, conversation: conversation)
        try require(
          call["run_id"].text == runID && call["state"].text == "completed"
            && ["receiving_template", "form_template"].contains(call["tool"].text),
          "definition_template", "Choose this active run's successful template receipt.")
        let row = try db.execute(
          "SELECT result,result_hash FROM tool_calls WHERE id=?", [.string(receiptID)]
        ).first!
        let json = row["result"]!.text
        try require(
          ToolResultProjection.digest(json) == row["result_hash"]!.text, "integrity",
          "The definition template receipt changed.")
        let result = try Value.parse(json)
        let expected: Value
        if call["tool"].text == "receiving_template" {
          try require(
            call["arguments"].object.isEmpty, "definition_template", "Invalid template call.")
          expected = ActionRegistry.receivingDefinition()
        } else {
          try require(
            Set(call["arguments"].object.keys) == ["id"], "definition_template",
            "Invalid form-template call.")
          let action = try applicationDefinition(call["arguments"]["id"].text)
          try require(
            action.id == call["arguments"]["id"].text && action.kind == "action",
            "definition_template", "The form template needs an exact action version.")
          expected = ActionRegistry.formDefinition(target: action)
        }
        try require(
          result["receiptID"] == .string(receiptID)
            && result["content"] == expected,
          "definition_template", "The template receipt has no exact saved content.")
        return result["content"]
      }
    }
  }

  func validateApplicationToolRun(
    _ runID: String, conversation: String? = nil, requestSourceID: String?
  ) throws {
    guard let requestSourceID,
      let row = try db.execute(
        "SELECT a.status,a.conversation_id,r.message_id,m.body,p.payload FROM agent_runs a JOIN run_requests r ON r.run_id=a.id JOIN messages m ON m.id=r.message_id LEFT JOIN message_payloads p ON p.message_id=m.id WHERE a.id=?",
        [.string(runID)]
      ).first
    else {
      throw SevraError(
        "action_run", "Application changes require the active captured user request.")
    }
    let source = try item(requestSourceID)
    let continued = try row["payload"]?.string.map(Value.parse)
    try require(
      row["status"]?.text == "running"
        && (conversation == nil || row["conversation_id"]?.text == conversation)
        && source.id == requestSourceID && source.category == "source" && source.kind == "request"
        && source.text == row["body"]?.text
        && ((source.data["messageID"] == row["message_id"]!
          && source.data["conversationID"] == row["conversation_id"]!)
          || (continued?["kind"].text == "continued_request"
            && continued?["sourceID"].text == source.id)),
      "action_run", "The saved action does not belong to the current active user request.")
  }

  /// Host-only retrieval. A historical tool result never authorizes execution.
  public func applicationPreviewForRun(
    _ receiptID: String, runID: String, conversation: String, requestSourceID: String?,
    cancellation: Cancellation = .init()
  ) throws -> Value {
    try synchronized(cancellation: cancellation) {
      try db.readTransaction {
        try validateApplicationToolRun(
          runID, conversation: conversation, requestSourceID: requestSourceID)
        let call = try toolCall(receiptID, conversation: conversation)
        try require(
          call["run_id"].text == runID && call["state"].text == "completed"
            && call["tool"].text == "preview_action", "action_preview_receipt",
          "Choose a successful action preview receipt from this active run. Historical, failed and incomplete results cannot be submitted."
        )
        let row = try db.execute(
          "SELECT result,result_hash FROM tool_calls WHERE id=?", [.string(receiptID)]
        ).first!
        let json = row["result"]!.text
        try require(
          ToolResultProjection.digest(json) == row["result_hash"]!.text, "integrity",
          "The action preview receipt changed.")
        let result = try Value.parse(json)
        let plan = result["plan"]
        try require(
          result["receiptID"].text == receiptID && plan["workbookID"].text == id
            && plan["requestedID"] == call["arguments"]["id"]
            && plan["submittedArguments"] == call["arguments"]["arguments"]
            && plan["readOnly"] == .bool(true),
          "action_preview_receipt", "The exact preview does not match its saved call.")
        var body = plan.object
        let fingerprint = body.removeValue(forKey: "fingerprint")
        try require(
          fingerprint == .string(ChangeFormat.hash(try Value.object(body).json())), "integrity",
          "The preview fingerprint does not match its exact plan.")
        try cancellation.check()
        return plan
      }
    }
  }
}
