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
  public init(
    _ workbook: Workbook, runID: String = identifier(), cancellation: Cancellation = .init(),
    requestSourceID: String? = nil
  ) {
    self.workbook = workbook
    self.runID = runID
    self.cancellation = cancellation
    self.requestSourceID = requestSourceID
  }
  public static let instructions = """
    Return one JSON object per turn, no markdown fences:
    {"tool":"search","arguments":{"query":"brass bolts"}}
    or {"tool":"finish","arguments":{"answer":"...","citations":["exact item version ID"]}}.
    Available tools and arguments:
    search: query string, optional kind, meaning, status, scenario and cursor from nextCursor. Returns evidence snippets and indexing coverage. kind is a domain kind such as note, file, row, movement; actual/estimate/plan are meaning values, not kind values.
    read: id string, optional offset number. Returns exact record metadata and at most 8 text chunks.
    lineage: id string. Returns supporting/derived version relationships.
    datasets: no arguments. List tables and column IDs.
    rows: id dataset ID, optional offset number. Returns up to 100 rows with calculated values.
    calculate: expression string, optional values object. Decimal arithmetic; + - * / parentheses,
      SUM, AVERAGE, MIN, MAX, COUNT, IF. References are column names or [names with spaces].
    balance: subject string. Deterministic accepted actual inventory balance and supporting effects.
    spaces: no arguments. List saved native spaces.
    save_space: title string, definition object {version:1,components:[{id:string,type:table|chart|document|asset|search|text,title:string,datasetID?:string,itemID?:string,x?:columnID,y?:columnID,query?:string,text?:string}]}.
    A chart REQUIRES its own datasetID, x and y. A table REQUIRES datasetID. Do not put query on a chart.
    Example save_space arguments: {"title":"Purchasing","definition":{"version":1,"components":[{"id":"table1","type":"table","title":"Quotes","datasetID":"ID_FROM_DATASETS"},{"id":"chart1","type":"chart","title":"Cost","datasetID":"ID_FROM_DATASETS","x":"supplier","y":"total"}]}}.
    draft: title string, text string, inputs array of exact source/record IDs. Autosaves a draft document.
    propose_record: title, text, kind, meaning (actual|estimate|plan|commitment|assumption|rule), inputs array, optional data object. Creates a draft interpretation.
    propose_movement: subject, quantity decimal string, occurrence unique business ID, effective ISO8601 time, input exact evidence ID, optional meaning. Creates a draft, no effect until user accepts.
    finish: answer string, citations array. Cite only inspected evidence. Explain incomplete coverage.
    """
  public func execute(_ tool: String, _ a: Value) throws -> Value {
    func string(_ key: String) throws -> String {
      guard let v = a[key].string, !v.isEmpty else {
        throw SevraError("arguments", "Missing string argument: \(key)")
      }
      return v
    }
    let inputs = Array(
      Set(a["inputs"].array.compactMap(\.string) + (requestSourceID.map { [$0] } ?? []))
    ).sorted()
    let token =
      runID + "-"
      + SHA256.hash(data: Data((tool + (try a.json())).utf8)).prefix(12).map {
        String(format: "%02x", $0)
      }.joined()
    switch tool {
    case "search":
      return try encoded(
        workbook.search(
          string("query"), kind: a["kind"].string, meaning: a["meaning"].string,
          offset: a["offset"].int ?? 0, cursor: a["cursor"].string, status: a["status"].string,
          scenario: a["scenario"].string, cancellation: cancellation))
    case "archive_members":
      return try encoded(workbook.archiveMembers(string("id"), cancellation: cancellation))
    case "include_archive_members":
      return try encoded(
        workbook.includeArchiveMembers(
          string("id"), paths: a["paths"].array.compactMap(\.string), cancellation: cancellation))
    case "read":
      let item = try workbook.item(string("id"))
      var info = try encoded(item).object
      info["text"] = .string(String(item.text.prefix(1000)))
      info["data"] =
        item.data.text.utf8.count < 12000
        ? item.data : .string("Structured value exceeds read budget; use table rows.")
      return .object([
        "item": .object(info),
        "chunks": .array(try workbook.readChunks(item.id, offset: a["offset"].int ?? 0)),
        "extraction": try workbook.extractionStatus(item.id),
      ])
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
    case "balance": return try workbook.balance(subject: string("subject"))
    case "spaces": return try encoded(workbook.spaces())
    case "pin_space":
      return .string(try workbook.pinSpace(string("id"), title: string("title"), token: token))
    case "save_space":
      let definition = try JSONDecoder().decode(
        SpaceDefinition.self, from: Data(a["definition"].json().utf8))
      return .object([
        "spaceID": .string(
          try workbook.saveSpace(
            id: token, title: string("title"), definition: definition, token: token))
      ])
    case "draft", "propose_record":
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
          meaning: a["meaning"].string ?? "actual", token: token))
    default: throw SevraError("tool", "Unknown workbook tool: \(tool)")
    }
  }
}
