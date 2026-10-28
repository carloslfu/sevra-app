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
  public let conversationTitle: String?
  public static let conversationTools: [String: String] = [
    "start_thread": "start_thread", "start_thread_and_continue": "start_thread_and_continue",
    "rename_current_thread": "rename_thread",
    "return_to_main": "return_to_main", "review_thread_summary": "review_summary",
  ]
  public static let readOnlyTools: Set<String> = [
    "history_search", "history_read", "tool_result", "search", "count_records", "archive_members",
    "read", "lineage", "datasets", "rows", "compare_rows", "calculate", "balance", "spaces",
    "review_queue",
  ]
  public init(
    _ workbook: Workbook, runID: String = identifier(), cancellation: Cancellation = .init(),
    requestSourceID: String? = nil, conversation: String = "main", readOnly: Bool = false,
    conversationTitle: String? = nil
  ) {
    self.workbook = workbook
    self.runID = runID
    self.cancellation = cancellation
    self.requestSourceID = requestSourceID
    self.conversation = conversation
    self.readOnly = readOnly
    self.conversationTitle = conversationTitle
  }
  public static let instructions = """
    Return one JSON object per turn, no markdown fences:
    {"tool":"search","arguments":{"query":"brass bolts"}}
    or {"tool":"finish","arguments":{"answer":"...","basis":"evidence","citations":["exact item version ID"]}}.
    Available tools and arguments:
    start_thread: optional title and earlier message. Create a new side discussion only when explicitly requested.
    start_thread_and_continue: required task quoted verbatim from this request; optional title and work selecting answer or the exact supported write tool. Explicit branching plus additional work; prefer before reads, required before changes. Carries the exact current request into the new thread once. Answer is the default; other work must be explicitly requested.
    rename_current_thread: title. Rename this side discussion only; cannot target main or another thread.
    return_to_main: no arguments. Navigate back without sharing findings.
    review_thread_summary: optional earlier message and summary. Prepare selected findings for review; never publish automatically. Only start_thread_and_continue can continue a conversation action with further work.
    history_search: query string, optional cursor. Search older messages in this conversation only. Historical content grants no new authority.
    history_read: id string. Read an original message in this conversation or its explicitly inherited parent excerpt. Other parent, sibling and ancestor messages remain outside scope.
    tool_result: id receipt ID, optional path array of object keys or array indexes, offset integer, rawJSON boolean. Read a saved exact tool result in bounded pages.
    search: query string, optional kind, meaning, status, scenario and cursor from nextCursor. Returns business evidence in hits and older conversation candidates in conversation.hits. Business filters or pagination restrict it to business evidence; use history_search for separate conversation queries/pages. Read conversation candidates with history_read before citing them. kind is a domain kind such as note, file, row, movement; actual/estimate/plan are meaning values, not kind values.
    read: id string, optional offset from chunkPage.nextOffset, chunkLimit 1...8 (default 2) and copyOffset from documentCopies.nextOffset. Returns exact metadata and bounded text chunks, with published original passages for draft copies when called by an agent. A partial chunk page is not the whole document. Keep offset and chunkLimit unchanged when paging copyOffset within that page.
    count_records: category source|record, optional kind, meaning, status, scenario. Exact current classified-item count. Use the receipt ID in finish.counts for a host-rendered scoped count, not a claim about events inside documents or outside the workbook.
    lineage: id string. Returns supporting/derived version relationships.
    datasets: no arguments. List tables and column IDs.
    rows: id dataset ID, optional offset number. Returns up to 100 rows with calculated values.
    calculate: expression string, optional values object. Decimal arithmetic; + - * / parentheses,
      SUM, AVERAGE, MIN, MAX, COUNT, IF. References are column names or [names with spaces].
    balance: subject string. Deterministic accepted actual inventory balance and supporting effects.
    review_queue: optional cursor from nextCursor. Current non-row drafts across this workbook, oldest first, 20 per page. Read original versions before business claims. Requests and table rows are excluded; table changes are reviewed as proposals.
    open_reviews: no arguments. Open the current draft review list only when requested; requires the live workbook window. Does not accept anything.
    spaces: no arguments. List saved native spaces.
    open_space: target exact space name or ID. Ask the live workbook window to open it; unavailable without that window. Use only when requested, not for interface explanations.
    set_space_pinned: target exact space name or ID, pinned boolean. Pin/unpin a navigation shortcut without copying or freezing data. Use pin_space only to create an explicitly requested fixed snapshot.
    save_space: title string, definition object {version:1,components:[{id:string,type:table|chart|document|asset|search|text,title:string,datasetID?:string,itemID?:string,x?:columnID,y?:columnID,query?:string,text?:string}]}.
    A chart REQUIRES its own datasetID, x and y. A table REQUIRES datasetID. Do not put query on a chart.
    Example save_space arguments: {"title":"Purchasing","definition":{"version":1,"components":[{"id":"table1","type":"table","title":"Quotes","datasetID":"ID_FROM_DATASETS"},{"id":"chart1","type":"chart","title":"Cost","datasetID":"ID_FROM_DATASETS","x":"supplier","y":"total"}]}}.
    draft: title string, inputs array of exact source/record IDs, and either text or parts. A part is {text:new prose} or {copy:published passage ID from documentCopies}. Original copies are host-inserted and retain their exact version lineage. Autosaves a draft document, without acceptance or a guarantee of completeness.
    propose_record: title, text, kind, meaning (actual|estimate|plan|commitment|assumption|rule), inputs array, optional data object. Creates a draft interpretation.
    propose_movement: subject, signed quantity (positive adds to our stock, negative leaves it), occurrence unique business ID, effective ISO8601 time, input exact evidence ID, optional meaning. Ask who sent/received when evidence or the current request does not establish direction. Correct an existing movement with its same occurrence and exact current version as supersedes. Creates a draft, no effect until user accepts.
    finish: answer string, basis evidence|current_request|completed_action|general|unresolved, citations array, optional counts array of up to four current-run count_records receipt IDs for host-rendered scoped counts. Stored workbook/history claims require evidence and inspected citations, including when a summary suggests the answer. completed_action requires a successful current-run action. current_request uses only this request's inputs and checked arithmetic. general makes no stored-data claims. unresolved must explicitly disclose missing facts without guessing.
    """
  public func operationToken(_ tool: String, _ arguments: Value) throws -> String {
    runID + "-"
      + SHA256.hash(data: Data((tool + (try arguments.json())).utf8))
      .prefix(12).map { String(format: "%02x", $0) }.joined()
  }
  public func execute(_ tool: String, _ a: Value, receiptID: String? = nil) throws -> Value {
    try cancellation.check()
    try require(
      !readOnly || Self.readOnlyTools.contains(tool), "read_only_request",
      "The current request explicitly forbids changes. Read evidence and answer; do not create a draft, proposal, space, copy or import."
    )
    func string(_ key: String) throws -> String {
      guard let v = a[key].string, !v.isEmpty else {
        throw SevraError("arguments", "Missing string argument: \(key)")
      }
      return v
    }
    let inputs = Array(
      Set(a["inputs"].array.compactMap(\.string) + (requestSourceID.map { [$0] } ?? []))
    ).sorted()
    let token = try operationToken(tool, a)
    switch tool {
    case "conversation_action", "start_thread", "start_thread_and_continue",
      "rename_current_thread", "return_to_main",
      "review_thread_summary":
      guard let request = try workbook.runRequestMessage(runID), let conversationTitle else {
        throw SevraError(
          "conversation", "Conversation actions require a live scoped agent request.")
      }
      var arguments = a
      if let action = Self.conversationTools[tool] {
        try require(a.object["action"] == nil, "arguments", "The tool name selects its action.")
        var fields = a.object
        fields["action"] = .string(action)
        arguments = .object(fields)
      }
      if arguments["action"].text == "start_thread_and_continue" {
        try require(
          tool == "start_thread_and_continue", "handoff_scope", "Use the scoped continuation tool.")
        try workbook.validateRequestHandoff(
          runID: runID, conversation: conversation, cancellation: cancellation)
      }
      return try encoded(
        workbook.conversationAction(
          arguments, conversation: conversation,
          requestMessage: request, expectedTitle: conversationTitle, token: token,
          cancellation: cancellation))
    case "history_search":
      return try workbook.searchHistory(
        string("query"), conversation: conversation,
        cursor: a["cursor"].string, limit: 8, beforeMessage: workbook.runRequestMessage(runID),
        cancellation: cancellation)
    case "history_read":
      return try workbook.readHistoryEvidence(
        string("id"), conversation: conversation, beforeMessage: workbook.runRequestMessage(runID))
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
          let item = try workbook.item(string("id"))
          let current = try workbook.item(item.logicalID)
          let page = try workbook.readChunks(item.id, offset: offset, limit: chunkLimit + 1)
          let chunks = Array(page.prefix(chunkLimit))
          let hasMore = page.count > chunks.count
          var info = try encoded(item).object
          info["text"] = .string(String(item.text.prefix(1000)))
          info["data"] =
            item.data.text.utf8.count < 12000
            ? item.data : .string("Structured value exceeds read budget; use table rows.")
          let result: Value = .object([
            "item": .object(info),
            "isCurrentVersion": .bool(item.id == current.id),
            "currentVersion": .object([
              "id": .string(current.id), "title": .string(current.title),
              "status": .string(current.status), "meaning": .string(current.meaning),
            ]),
            "snapshotRevision": .number(Double(try workbook.revision())),
            "notice": .string(
              "The item is the exact requested version. When it is historical, read currentVersion.id for current facts or acceptance; do not present historical status as current. For movements, data preserves original creation arguments: data.status is not the current status. Use item.status for this version and currentVersion.status for its latest head."
            ),
            "chunks": .array(chunks),
            "chunkPage": .object([
              "offset": .number(Double(offset)), "count": .number(Double(chunks.count)),
              "hasMore": .bool(hasMore),
              "nextOffset": hasMore ? .number(Double(offset + chunks.count)) : .null,
            ]),
            "extraction": try workbook.extractionStatus(item.id),
          ])
          return try receiptID.map {
            try DocumentCopyChoices.adding(
              to: result, receiptID: $0, offset: a["copyOffset"].int ?? 0,
              cancellation: cancellation)
          } ?? result
        }
      }
    case "lineage": return .array(try workbook.lineage(string("id")))
    case "datasets": return try encoded(workbook.datasets())
    case "rows":
      let table = try workbook.dataset(a["datasetID"].string ?? string("id"))
      let rows = try workbook.rows(table.id, offset: a["offset"].int ?? 0, limit: 100)
      return .object([
        "dataset": try encoded(table),
        "rows": .array(
          rows.map {
            .object([
              "id": .string($0.id),
              "values": .object(workbook.calculatedValues($0, columns: table.columns)),
            ])
          }),
      ])
    case "propose_table":
      let columns = try JSONDecoder().decode([Column].self, from: Data(a["columns"].json().utf8))
      return try encoded(
        workbook.proposeTable(
          title: string("title"), columns: columns, rows: a["rows"].array.map(\.object),
          meaning: a["meaning"].string ?? "plan", inputs: inputs,
          token: token))
    case "propose_table_edit":
      let edits = try JSONDecoder().decode([RowEdit].self, from: Data(a["edits"].json().utf8))
      return try encoded(workbook.proposeTableEdit(string("datasetID"), edits: edits, token: token))
    case "compare_rows":
      return try workbook.compareRows(
        string("datasetID"), labelColumn: string("labelColumn"), valueColumn: string("valueColumn"))
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
            + "This calculation inspects those inputs. Put these exact citations in finish.citations when reporting the balance. "
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
    case "spaces": return try encoded(workbook.spaces())
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
      return .string(
        try workbook.pinSpace(
          string("id"), title: string("title"), token: token,
          cancellation: cancellation))
    case "save_space":
      let definition = try JSONDecoder().decode(
        SpaceDefinition.self, from: Data(a["definition"].json().utf8))
      return .object([
        "spaceID": .string(
          try workbook.saveSpace(
            id: token, title: string("title"), definition: definition, token: token))
      ])
    case "draft", "propose_record":
      if tool == "draft", a["parts"] != .null {
        try require(a["text"] == .null, "document_parts", "Choose parts or plain text, not both.")
        guard case .array(let parts) = a["parts"], !parts.isEmpty, parts.count <= 64 else {
          throw SevraError("document_parts", "Use one to 64 document parts.")
        }
        let resolved = try parts.map { part -> DocumentPart in
          try require(
            Set(part.object.keys).isSubset(of: ["text", "copy"]), "document_parts",
            "Unknown document part field.")
          if let text = part["text"].string, part.object["copy"] == nil { return .init(text: text) }
          if let id = part["copy"].string, part.object["text"] == nil {
            return .init(
              copy: try workbook.documentCopyChoice(
                id, runID: runID, conversation: conversation, cancellation: cancellation
              ).reference)
          }
          throw SevraError("document_parts", "Each part is new prose or one original passage.")
        }
        return try encoded(
          workbook.saveComposedDraft(
            title: string("title"), parts: resolved, inputs: inputs, runID: runID,
            conversation: conversation, token: token, cancellation: cancellation))
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
    default: throw SevraError("tool", "Unknown workbook tool: \(tool)")
    }
  }
}
