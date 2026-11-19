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
    "definition_guide": "definition_registry",
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
      if kind == "actions" {
        return (target, a["id"].string.map { .object(["domain": .string($0)]) } ?? .object([:]))
      }
      return (target, rest(without: "kind"))
    case "run":
      guard let action = a["action"].string else { return (tool, a) }
      let arguments = a.object["arguments"] ?? .object([:])
      if let target = actions[action] { return (target, arguments) }
      return ("workspace_action", .object(["action": .string(action), "arguments": arguments]))
    case "save":
      guard let kind = a["kind"].string, let target = saves[kind] else { return (tool, a) }
      // `sources` names the items a saved thing comes from. The operations call it inputs.
      if let sources = fields.removeValue(forKey: "sources") { fields["inputs"] = sources }
      fields["kind"] = fields.removeValue(forKey: "recordKind")
      return (target, .object(fields))
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
    for (kind, target) in reads where kind != "item" { phrases[target] = "read kind=" + kind }
    for (kind, target) in saves { phrases[target] = "save kind=" + kind }
    for (action, target) in actions { phrases[target] = "run action=" + action }
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
    readOnly: Bool = false
  ) -> [WorkbookToolDefinition] {
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
          "kind": schema("string", "Optional kind filter."),
          "status": schema("string", "Optional status filter."),
          "cursor": schema("string", "Next page, from an earlier result."),
        ], required: ["query"]))
    let read = WorkbookToolDefinition(
      name: "read",
      description:
        "Read one thing by ID. With no kind: a document or record, with offset for later parts. kind=message: an earlier message. result: a page of a long saved tool result. app, definition, workflow: that saved thing. views, reviews, workflows: those lists, with no id. references, lineage, archive: what an item links to, came from, or contains. actions: the actions run can perform, with id as an optional group such as table, app, visual, file, workflow. app_guide: how to write an app. definition_guide: the kinds of saved definitions.",
      parameters: object(
        [
          "id": schema("string", "The exact ID. Lists and guides need none."),
          "kind": choice(reads.keys.sorted(), "Default item."),
          "offset": schema("integer", "Where to continue a long document or result."),
          "path": .object([
            "type": .string("array"), "items": .object(["type": .string("string")]),
            "description": .string("For kind=result: the field to page into."),
          ]),
        ], required: []))
    let run = WorkbookToolDefinition(
      name: "run",
      description: NativeTools.runDefinition.description
        + " Or send action with arguments to perform one named action instead of code: charts, files, imports, apps, workflows, threads, views and undo. read kind=actions lists them with their inputs. Thread actions: thread.start {title, message}, thread.start_and_continue {task, work, title}, thread.rename {title}, thread.return {}. View actions: view.open {target}, view.pin {target, pinned}. Stock: stock.balance {subject}.",
      parameters: object(
        [
          "code": NativeTools.runDefinition.parameters["properties"]["code"],
          "action": choice((operations + named).sorted(), "One named action, instead of code."),
          "arguments": .object([
            "type": .string("object"), "description": .string("The action's inputs."),
          ]),
        ], required: []))
    let kinds = (["tool"] + saves.keys.sorted()).filter { apps || $0 != "app" }
    let save = WorkbookToolDefinition(
      name: "save",
      description:
        "Save a named thing in the workbook. kind=tool: SQL statements to run again, such as a report, a check or a form that adds rows, with name, description, inputs and statements that use each input as :name. document: a note, summary or report, with title, text and sources. view: a page of existing tables and charts, with title and definition. app: a small app with its own controls, with package and tests, after read kind=app_guide. record: one drafted fact, with title, text, recordKind, meaning and sources. definition: a form, workflow, function or rule, with content, after read kind=definition_guide. template: a template a template action returned, with templateReceiptID. result: an evaluated result, with evaluationReceiptID, title and meaning.",
      parameters: object(
        [
          "kind": choice(kinds, "What to save."),
          "name": schema("string", "tool: lower case with underscores, such as low_stock."),
          "description": schema("string", "tool: one sentence on what it does."),
          "inputs": NativeTools.saveDefinition.parameters["properties"]["inputs"],
          "statements": NativeTools.saveDefinition.parameters["properties"]["statements"],
          "title": schema("string", "The visible title."),
          "text": schema("string", "document or record: the full text."),
          "sources": ids,
          "parts": property("draft", "parts"),
          "definition": property("save_space", "definition"),
          "package": property("save_native_app", "package"),
          "tests": property("save_native_app", "tests"),
          "fixtures": property("save_native_app", "fixtures"),
          "id": schema("string", "app: the saved app to replace."),
          "expectedVersion": schema("integer", "app: the version being replaced."),
          "recordKind": schema("string", "record: its kind."),
          "meaning": schema("string", "record or result: actual, plan or another meaning."),
          "data": property("propose_record", "data"),
          "content": property("save_definition", "content"),
          "expectedDefinitionID": schema("string", "definition or template: the one replaced."),
          "templateReceiptID": schema("string", "template: the receipt of its template action."),
          "evaluationReceiptID": schema("string", "result: the receipt of its evaluation."),
          "scenario": schema("string", "result: its scenario."),
        ].filter { apps || !["package", "tests", "fixtures", "expectedVersion"].contains($0.key) },
        required: ["kind"]))
    let question = ask.map {
      WorkbookToolDefinition(
        name: "ask",
        description:
          "Ask the user for what is missing, as one question or a few typed fields. Nothing is changed.",
        parameters: $0.parameters)
    }
    return [search, read, NativeTools.sqlDefinition, run, save] + (question.map { [$0] } ?? [])
      + [finish]
  }
}
