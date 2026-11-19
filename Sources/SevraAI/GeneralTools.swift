import Foundation
import SevraCore

/// The seven general chat tools: what the model is offered, and which existing operation
/// does the work of each call.
///
/// A general call is routed to the operation's own name and arguments before anything else
/// looks at it. The host's checks, receipts and confirmations are keyed on those names, so
/// they keep working unchanged. Nothing here executes a tool.
package enum GeneralTools {
  package static let names = ["search", "read", "sql", "run", "save", "ask", "finish"]

  /// `read` kinds and the operation behind each. An item needs no kind.
  static let reads: [String: String] = [
    "item": "read", "message": "history_read", "result": "tool_result", "app": "read_native_app",
    "views": "spaces", "view_history": "space_history", "definition": "read_definition",
    "workflow": "read_workflow", "references": "references", "lineage": "lineage",
    "archive": "archive_members", "reviews": "review_queue", "workflows": "workflow_activity",
    "actions": "workspace_actions", "app_guide": "native_app_sdk",
    "definition_guide": "definition_registry", "rule_guide": "guide",
  ]
  /// `save` kinds and the operation behind each. A tool is saved by the core's own `save`.
  static let saves: [String: String] = [
    "document": "draft", "record": "propose_record", "view": "save_space",
    "app": "save_native_app", "definition": "save_definition", "template": "save_template",
    "result": "publish_result",
  ]
  /// Named actions of `run` that are operations of their own, beside the workspace actions.
  package static let actions: [String: String] = [
    "thread.start": "start_thread", "thread.start_and_continue": "start_thread_and_continue",
    "thread.rename": "rename_current_thread", "thread.return": "return_to_main",
    "thread.summary": "review_thread_summary", "view.open": "open_space",
    "view.pin": "set_space_pinned", "view.pin_home": "pin_space", "view.edit": "edit_space",
    "view.restore": "restore_space", "reviews.open": "open_reviews",
    "automation.open": "open_automation", "archive.include": "include_archive_members",
    "definition.evaluate": "evaluate_definition", "action.preview": "preview_action",
    "action.prepare": "prepare_action", "workflow.start": "start_workflow",
    "stock.move": "propose_movement", "stock.balance": "balance",
    "records.count": "count_records", "template.receiving": "receiving_template",
    "template.form": "form_template", "template.workflow": "workflow_template",
    "template.rule": "inventory_automation_template",
  ]

  /// Named actions whose inputs the grammar enforces.
  static let exact: Set<String> = [
    "thread.start", "thread.start_and_continue", "thread.rename", "thread.summary", "view.open",
    "view.pin", "view.edit", "stock.move", "workflow.start", "definition.evaluate",
    "action.preview", "action.prepare", "template.form", "template.workflow", "template.rule",
  ]

  /// The operation a general call stands for. A call this table cannot place is returned as
  /// it came, and the tool that receives it says what is wrong.
  package static func route(_ tool: String, _ a: Value) -> (tool: String, arguments: Value) {
    var fields = a.object
    func rest(without keys: String...) -> Value {
      for key in keys { fields[key] = nil }
      return .object(fields)
    }
    switch tool {
    case "ask": return ("request_input", a)
    case "search":
      switch a["in"].string {
      case "conversation": return ("history_search", rest(without: "in", "kind", "status"))
      case "definitions": return ("find_definitions", rest(without: "in", "status"))
      default: return ("search", rest(without: "in"))
      }
    case "read":
      guard let kind = a["kind"].string, kind != "item" else { return ("read", rest(without: "kind")) }
      guard let target = reads[kind] else { return (tool, a) }
      let ref = fields.removeValue(forKey: "ref")
      if target == "guide" {
        return (target, .object(["name": .string(String(kind.dropLast("_guide".count)))]))
      }
      if kind == "actions" {
        return (target, (ref ?? a["id"]).string.map { .object(["domain": .string($0)]) } ?? .object([:]))
      }
      // `id` is a document or record. Anything else is named by `ref`.
      if !["references", "lineage", "archive"].contains(kind), let ref { fields["id"] = ref }
      return (target, rest(without: "kind"))
    case "run":
      // An action is {name, arguments}. The command line may also name it directly.
      let named = a["action"]
      guard let action = named["name"].string ?? named.string else { return (tool, a) }
      let arguments =
        (named.string == nil ? named.object["arguments"] : a.object["arguments"]) ?? .object([:])
      if let target = actions[action] {
        // A continued thread either answers or changes. The change scopes all allow the same
        // general tools, so one stands for them.
        if target == "start_thread_and_continue", arguments["work"] != .string("answer") {
          var fields = arguments.object
          fields["work"] = .string("draft")
          return (target, .object(fields))
        }
        return (target, arguments)
      }
      return ("workspace_action", .object(["action": .string(action), "arguments": arguments]))
    case "save":
      // One kind per call, each with the shape of the operation that saves it.
      let kinds = fields.keys.filter { $0 == "tool" || saves[$0] != nil }
      guard kinds.count == 1, let kind = kinds.first, case .object(var thing) = a[kind] else {
        return (tool, a)
      }
      if let target = saves[kind] { return (target, .object(thing)) }
      thing["kind"] = .string("tool")
      return ("save", .object(thing))
    default: return (tool, a)
    }
  }

  /// What a scope lets the model call, by general name. A scope that only reads still offers
  /// `run`, and the host refuses any change inside it.
  package static func allowed(
    _ tool: String, in scope: InferenceToolScope, conversationInput: Bool
  ) -> Bool {
    switch tool {
    case "ask": return scope.allows("request_input", conversationInput: conversationInput)
    case "finish": return scope.allows("finish")
    case "search": return scope.allows("search")
    case "read", "sql", "run": return scope.allows("read")
    case "save": return scope.changes
    default: return false
    }
  }

  /// Whether a routed call only reads. A script and a query refuse changes themselves.
  package static func reads(_ tool: String, _ a: Value) -> Bool {
    WorkbookTools.readOnlyTools.contains(tool)
      || ["sql", "run", "finish", "request_input"].contains(tool)
      || (tool == "workspace_action"
        && ChatOperations.operations.first { $0.name == a["action"].text }?.readOnly == true)
  }

  /// Host messages and tool results name the operation behind a call. This puts the general
  /// tool's name in their place, longest name first.
  package static func wording(_ text: String) -> String {
    guard text.contains("_") else { return text }
    return phrases.reduce(text) { $0.replacingOccurrences(of: $1.0, with: $1.1) }
  }
  private static let phrases: [(String, String)] = {
    var phrases: [String: String] = [
      "workspace_actions": "read kind=actions", "workspace_action": "run action",
      "request_input": "ask", "propose_table_edit": "sql with draft=true",
      "propose_table": "sql CREATE TABLE", "compare_rows": "sql", "search_history": "search",
      "history_search": "search in=conversation", "find_definitions": "search in=definitions",
    ]
    for (kind, target) in reads where kind != "item" && target != "guide" {
      phrases[target] = "read kind=" + kind
    }
    for (kind, target) in saves { phrases[target] = "save with " + kind }
    for (action, target) in actions { phrases[target] = "run action " + action }
    return phrases.filter { $0.key.contains("_") }.sorted {
      ($0.key.count, $0.key) > ($1.key.count, $1.key)
    }.map { ($0.key, $0.value) }
  }()

  private static func property(_ tool: String, _ name: String) -> Value {
    NativeTools.definitions.first { $0.name == tool }!.parameters["properties"][name]
  }
  private static func choice(_ values: [String], _ description: String) -> Value {
    .object([
      "type": .string("string"), "enum": .array(values.map(Value.string)),
      "description": .string(description),
    ])
  }
  private static let ids: Value = .object([
    "type": .string("array"), "items": .object(["type": .string("string")]),
  ])

  /// The seven declarations. `operations` are the workspace actions the scope allows,
  /// `threads` the thread actions this conversation allows, and `apps` whether an app can
  /// be saved here.
  package static func definitions(
    operations: [String], threads: Set<String>?, apps: Bool, ask: WorkbookToolDefinition?,
    readOnly: Bool = false, items: [String] = [], display: Bool = false
  ) -> [WorkbookToolDefinition] {
    // What the model is shown is shorter than what the grammar enforces. A shape that is not
    // shown lists its fields by name, and the grammar supplies the rest as the call is written.
    func fields(_ parameters: Value) -> String {
      let required = Set(parameters["required"].array.map(\.text))
      let names = parameters["properties"].object.keys.sorted {
        (required.contains($0) ? 0 : 1, $0) < (required.contains($1) ? 0 : 1, $1)
      }
      return "{" + names.joined(separator: ", ") + "}"
    }
    func object(_ fields: [String: Value], required: [String]) -> Value {
      NativeTools.object(fields, required: required)
    }
    let schema = NativeTools.schema
    let finish = NativeTools.definitions.first { $0.name == "finish" }!
    let named = actions.filter { name, target in
      if readOnly, !WorkbookTools.readOnlyTools.contains(target) { return false }
      guard let thread = WorkbookTools.conversationTools[target], let threads else { return true }
      return threads.contains(thread)
    }.keys.sorted()
    let search = WorkbookToolDefinition(
      name: "search",
      description:
        "Find documents, records and saved things by words. Every word must match, so use a few. in=conversation searches earlier messages, in=definitions the saved forms, workflows, functions and rules. Results give IDs to read.",
      parameters: object(
        [
          "query": schema("string", "A few words."),
          "in": choice(["workbook", "conversation", "definitions"], "Default workbook."),
          "cursor": schema("string", "Next page, from an earlier result."),
        ], required: ["query"]))
    // Item IDs come only from what a search or an earlier read returned, so the grammar
    // offers exactly those once there are any.
    var item = schema("string", "A document or record, by the exact ID a search or read gave.").object
    if !items.isEmpty { item["enum"] = .array(items.map(Value.string)) }
    let read = WorkbookToolDefinition(
      name: "read",
      description:
        "Read one thing. With id alone: a document or record, with offset for later parts. references, lineage, archive: what that item links to, came from, or contains. Other kinds name their thing with ref. message: an earlier message. result: a page of a long saved tool result. app, definition, workflow, view_history: that saved thing. views, reviews, workflows: those lists, with no ref. actions: the actions run can perform, with ref as an optional group such as table, app, visual, file, workflow. app_guide: how to write an app. definition_guide: the kinds of saved definitions. rule_guide: how to save a rule that watches stock.",
      parameters: object(
        [
          "id": .object(item),
          "kind": choice(reads.keys.sorted(), "Default item."),
          "ref": schema("string", "The exact ID of a thing that is not a document or record."),
          "offset": schema("integer", "Where to continue a long document or result."),
          "path": .object([
            "type": .string("array"), "items": .object(["type": .string("string")]),
            "description": .string("For kind=result: the field to page into."),
          ]),
        ], required: []))
    func parameters(_ tool: String) -> Value {
      NativeTools.definitions.first { $0.name == tool }!.parameters
    }
    // One shape per action: the workspace actions take the inputs read kind=actions lists,
    // and each action with an operation of its own takes that operation's inputs.
    // The grammar takes sixteen shapes. These fifteen actions get their own, and the rest
    // share the open one, where the action itself says what it is missing.
    let exact = named.filter(Self.exact.contains)
    let open = (operations + named.filter { !Self.exact.contains($0) }).sorted()
    let shapes: [Value] =
      (open.isEmpty
        ? []
        : [
          object(
            [
              "name": choice(open, "A workspace action, or an action with few inputs."),
              "arguments": .object(["type": .string("object")]),
            ], required: ["name", "arguments"])
        ])
      + exact.map { name in
        var inputs = parameters(actions[name]!).object
        if name == "template.rule" {
          // A level is a number. As free text the model wrote stray markup into it.
          var properties = inputs["properties"]!.object
          properties["threshold"] = .object(["type": .string("number")])
          inputs["properties"] = .object(properties)
        }
        return object(
          ["name": choice([name], ""), "arguments": .object(inputs)],
          required: ["name", "arguments"])
      }
    var runProperties: [String: Value] = [
      "code": NativeTools.runDefinition.parameters["properties"]["code"]
    ]
    if !shapes.isEmpty {
      runProperties["action"] =
        display
        ? object(
          [
            "name": schema("string", "The action."),
            "arguments": .object(["type": .string("object")]),
          ], required: ["name", "arguments"]
        ).object.merging([
          "description": .string(
            "One named action with its arguments, instead of code. "
              + exact.map { $0 + " " + fields(parameters(actions[$0]!)) }.joined(separator: "; ")
              + (open.isEmpty ? "" : "; and the actions read kind=actions lists.")),
        ]) { _, new in new }.wrapped
        : .object([
          "type": .string("object"), "anyOf": .array(shapes),
          "description": .string("One named action with its arguments, instead of code."),
        ])
    }
    let run = WorkbookToolDefinition(
      name: "run",
      description: NativeTools.runDefinition.description
        + " Or send action, with its name and arguments, to perform one named action instead of code: charts, files, imports, apps, workflows, threads, views and undo. read kind=actions lists the workspace actions with their inputs.",
      parameters: object(runProperties, required: []))
    var kinds: [String: Value] = [
      "tool": .object(
        NativeTools.saveDefinition.parameters.object.merging([
          "properties": .object(
            NativeTools.saveDefinition.parameters["properties"].object.filter { $0.key != "kind" }),
          "required": .array(["name", "description", "inputs", "statements"].map(Value.string)),
          "description": .string(
            "SQL statements to run again: a report, a check, or a form that adds or changes rows."),
        ]) { _, new in new })
    ]
    let about = [
      "document": "A note, summary, report or document the user asks you to write.",
      "view": "A page of existing tables and charts.",
      "app": "A small app with its own controls, after read kind=app_guide.",
      "record": "One drafted fact for the user to review.",
      "definition": "A form, workflow, function or rule, after read kind=definition_guide.",
      "template": "A template that a template action returned.",
      "result": "An evaluated result to keep.",
    ]
    for (kind, target) in saves where apps || kind != "app" {
      var shape = parameters(target).object
      shape["description"] = .string(about[kind]!)
      // The less common kinds are shown by their field names alone.
      kinds[kind] =
        display && !["document", "view"].contains(kind)
        ? .object([
          "type": .string("object"),
          "description": .string(about[kind]! + " Fields: " + fields(parameters(target)) + "."),
        ]) : .object(shape)
    }
    let save = WorkbookToolDefinition(
      name: "save",
      description:
        "Save one named thing in the workbook. Send exactly one of these, with its own fields: "
        + kinds.keys.sorted().joined(separator: ", ") + ".",
      parameters: object(kinds, required: []))
    let question = ask.map {
      WorkbookToolDefinition(
        name: "ask",
        description:
          "Ask the user for what is missing, as one question or a few typed fields. Nothing is changed.",
        parameters: $0.parameters)
    }
    // The model is not offered undo on sql itself. It is an action, so a statement and an
    // undo cannot be sent together.
    let sql = WorkbookToolDefinition(
      name: "sql", description: NativeTools.sqlDefinition.description,
      parameters: object(
        NativeTools.sqlDefinition.parameters["properties"].object.filter { $0.key != "undo" },
        required: []))
    return [search, read, sql, run, save] + (question.map { [$0] } ?? []) + [finish]
  }
}

extension [String: Value] {
  fileprivate var wrapped: Value { .object(self) }
}
