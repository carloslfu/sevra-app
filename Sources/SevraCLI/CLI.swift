import Foundation
import SevraAI
import SevraCore

@main struct CLI {
  static func main() async {
    do {
      let args = Array(CommandLine.arguments.dropFirst())
      let result = try await run(args)
      print(
        try Value.object(["schemaVersion": .number(1), "ok": .bool(true), "result": result]).json())
    } catch {
      let e = error as? SevraError ?? SevraError("operation", error.localizedDescription)
      let result: Value = .object([
        "schemaVersion": .number(1), "ok": .bool(false),
        "error": .object(["code": .string(e.code), "message": .string(e.message)]),
      ])
      fputs(((try? result.json()) ?? "{}") + "\n", stderr)
      exit(1)
    }
  }
  static func run(_ args: [String]) async throws -> Value {
    guard let command = args.first else { return .string(help) }
    if command == "help" || command == "--help" { return .string(help) }
    if command == "version" || command == "--version" {
      return .object(["version": .string("0.1.0-dev"), "engine": .string(LocalModel.revision)])
    }
    func arg(_ i: Int) throws -> String {
      guard args.count > i else { throw SevraError("usage", help) }
      return args[i]
    }
    func url(_ i: Int) throws -> URL { URL(fileURLWithPath: try arg(i)).standardizedFileURL }
    if command == "create" {
      let book = try Workbook.create(
        at: url(1),
        title: args.count > 2 ? args[2] : url(1).deletingPathExtension().lastPathComponent)
      return .object(["path": .string(book.url.path)])
    }
    if command == "open-archive" {
      let book = try Workbook.openArchive(url(1), at: url(2))
      return .object(["path": .string(book.url.path)])
    }
    if command == "calculate" {
      return .string(
        try Numbers.calculate(arg(1), values: args.count > 2 ? Value.parse(args[2]).object : [:]))
    }
    if command == "model-status" {
      let dir = args.count > 1 ? try url(1) : LocalModel.defaultDirectory
      return .object([
        "directory": .string(dir.path),
        "present": .bool(await LocalModel.shared.installed(at: dir)),
        "downloadBytes": .string(String(LocalModel.downloadBytes)),
      ])
    }
    if command == "model-setup" {
      let dir = args.count > 1 ? try url(1) : LocalModel.defaultDirectory
      try await LocalModel.shared.setup(
        at: dir, cancellation: .init(), progress: { fputs($0 + "\n", stderr) })
      return .bool(true)
    }
    if command == "demo" { return try Demo.create(at: url(1)) }
    let book = try Workbook(url(1))
    switch command {
    case "inspect": return try book.counts()
    case "intake-status":
      return .object([
        "tables": .array(try book.intakeStatus()),
        "extraction": .array(try book.pendingExtractions()),
      ])
    case "resume-intake":
      try book.resumeIntake(arg(2))
      return .bool(true)
    case "runs": return .array(try book.agentRuns())
    case "pin-space":
      return .string(try book.pinSpace(arg(2), title: args.count > 3 ? args[3] : nil))
    case "column-history": return .array(try book.columnHistory(arg(2)))
    case "verify": return try book.verify()
    case "import":
      let item = try book.importFile(url(2), linked: args.contains("--link"))
      try book.extract(item.id)
      if ["csv", "tsv"].contains(try url(2).pathExtension.lowercased()) {
        return .object([
          "source": try encoded(item), "dataset": try encoded(book.importCSV(item.id)),
        ])
      }
      if try url(2).pathExtension.lowercased() == "xlsx" {
        return .object([
          "source": try encoded(item), "datasets": try encoded(book.importXLSX(item.id)),
        ])
      }
      return try encoded(item)
    case "capture-url":
      guard let target = URL(string: try arg(2)) else { throw SevraError("url", "Invalid URL.") }
      return try encoded(await book.captureURL(target))
    case "link-url":
      guard let target = URL(string: try arg(2)) else { throw SevraError("url", "Invalid URL.") }
      return try encoded(
        book.linkURL(target, title: args.count > 3 ? args[3] : target.host ?? "Link"))
    case "include": return try encoded(book.includeLinked(arg(2)))
    case "relink":
      try book.relinkAsset(arg(2), to: url(3))
      return .bool(true)
    case "search":
      return try encoded(book.search(arg(2), offset: args.count > 3 ? Int(args[3]) ?? 0 : 0))
    case "read": return try WorkbookTools(book).execute("read", .object(["id": .string(arg(2))]))
    case "records": return try encoded(book.items(kind: args.count > 2 ? args[2] : nil))
    case "tables": return try encoded(book.datasets())
    case "rows":
      return try encoded(book.rows(arg(2), offset: args.count > 3 ? Int(args[3]) ?? 0 : 0))
    case "add":
      let v = try Value.parse(arg(2))
      return try encoded(
        book.addItem(
          category: v["category"].string ?? "source", kind: v["kind"].string ?? "note",
          title: v["title"].text, text: v["text"].text,
          data: v["data"] == .null ? .object([:]) : v["data"],
          meaning: v["meaning"].string ?? "actual", status: v["status"].string ?? "draft",
          inputs: v["inputs"].array.compactMap(\.string), token: v["token"].string ?? identifier(),
          expectedRevision: v["expectedRevision"].int))
    case "edit-row":
      return try encoded(
        book.editRow(
          arg(2), values: Value.parse(arg(3)).object,
          expectedRevision: args.count > 4 ? Int(args[4]) : nil))
    case "accept":
      return try encoded(book.accept(arg(2), token: args.count > 3 ? args[3] : identifier()))
    case "undo": return try encoded(book.undoItem(arg(2)))
    case "balance": return try book.balance(subject: arg(2))
    case "opening":
      try book.setOpeningBalance(
        subject: arg(2), quantity: arg(3), effective: arg(4), sourceID: arg(5))
      return .bool(true)
    case "movement":
      let a = try Value.parse(arg(2))
      return try encoded(
        book.movement(
          subject: a["subject"].text, quantity: a["quantity"].text,
          occurrence: a["occurrence"].text, effective: a["effective"].text, input: a["input"].text,
          meaning: a["meaning"].string ?? "actual", status: a["status"].string ?? "draft",
          supersedes: a["supersedes"].string, token: a["token"].string ?? identifier()))
    case "lineage": return .array(try book.lineage(arg(2)))
    case "spaces": return try encoded(book.spaces())
    case "space":
      let definition = try JSONDecoder().decode(SpaceDefinition.self, from: Data(arg(3).utf8))
      return .string(try book.saveSpace(title: arg(2), definition: definition))
    case "conversation":
      return try encoded(book.messages(conversation: args.count > 2 ? args[2] : "main"))
    case "chapter":
      try book.chapter(title: arg(2), message: arg(3))
      return .bool(true)
    case "tangent": return .string(try book.tangent(title: arg(2), parentMessage: arg(3)))
    case "reindex":
      try book.rebuildSearch()
      return .bool(true)
    case "export":
      try book.export(to: url(2))
      return .bool(true)
    case "export-csv":
      try book.exportCSV(arg(2), to: url(3))
      return .bool(true)
    case "tool":
      return try WorkbookTools(book).execute(
        arg(2), args.count > 3 ? Value.parse(args[3]) : .object([:]))
    case "ask":
      let result = try await WorkbookAgent.run(
        arg(2), workbook: book,
        modelDirectory: args.count > 3 ? url(3) : LocalModel.defaultDirectory,
        progress: { fputs($0 + "\n", stderr) })
      return .object([
        "answer": .string(result.answer), "citations": .array(result.citations.map(Value.string)),
        "steps": .number(Double(result.steps)),
      ])
    default: throw SevraError("usage", help)
    }
  }
  static let help = """
    Sevra 0.1.0 development CLI. Every result is JSON; errors exit nonzero.
    create PATH.sevra [TITLE] | demo PATH.sevra | inspect WORKBOOK | verify WORKBOOK
    capture-url WORKBOOK URL | link-url WORKBOOK URL [TITLE] | include WORKBOOK ITEM_ID | relink WORKBOOK ASSET_ID FILE
    import WORKBOOK FILE [--link] | search WORKBOOK QUERY [OFFSET] | read WORKBOOK ID
    records WORKBOOK [KIND] | tables WORKBOOK | rows WORKBOOK TABLE_ID [OFFSET]
    add WORKBOOK JSON | edit-row WORKBOOK ITEM_ID VALUES_JSON [EXPECTED_REVISION]
    accept WORKBOOK ID [TOKEN] | undo WORKBOOK ID | lineage WORKBOOK ID
    opening WORKBOOK SUBJECT QUANTITY ISO_DATE SOURCE_ID | movement WORKBOOK JSON
    balance WORKBOOK SUBJECT | calculate EXPRESSION [VALUES_JSON]
    spaces WORKBOOK | space WORKBOOK TITLE DEFINITION_JSON | pin-space WORKBOOK SPACE_ID [TITLE]
    column-history WORKBOOK TABLE_ID | intake-status WORKBOOK | resume-intake WORKBOOK SOURCE_ID
    runs WORKBOOK
    conversation WORKBOOK [CONVERSATION_ID] | chapter WORKBOOK TITLE MESSAGE_ID
    tangent WORKBOOK TITLE MESSAGE_ID | reindex WORKBOOK
    export WORKBOOK PATH.sevraz | open-archive PATH.sevraz DEST.sevra
    export-csv WORKBOOK TABLE_ID PATH.csv | tool WORKBOOK TOOL [ARGS_JSON]
    model-status [MODEL_DIRECTORY] | model-setup [MODEL_DIRECTORY]
    ask WORKBOOK QUESTION [MODEL_DIRECTORY]
    """
}
