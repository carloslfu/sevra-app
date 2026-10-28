import Darwin
import Foundation
import SevraAI
import SevraCore
import SevraProduct

@main struct CLI {
  static func main() async {
    let cancellation = Cancellation()
    signal(SIGINT, SIG_IGN)
    let interrupt = DispatchSource.makeSignalSource(
      signal: SIGINT, queue: .global(qos: .userInitiated))
    interrupt.setEventHandler { cancellation.cancel() }
    interrupt.resume()
    defer { interrupt.cancel() }
    do {
      let args = Array(CommandLine.arguments.dropFirst())
      let result = try await run(args, cancellation: cancellation)
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
  static func run(_ args: [String], cancellation: Cancellation) async throws -> Value {
    guard let command = args.first else { return .string(help) }
    if command == "check-resources" {
      return try await ProductAI.checkResources(validateMetal: !args.contains("--paths-only"))
    }
    if command == "help" || command == "--help" { return .string(help) }
    if command == "version" || command == "--version" {
      return .object(["version": .string("0.1.0-dev"), "engine": .string(ProductAI.revision)])
    }
    func arg(_ i: Int) throws -> String {
      guard args.count > i else { throw SevraError("usage", help) }
      return args[i]
    }
    func integer(_ i: Int) throws -> Int {
      let raw = try arg(i)
      guard let value = Int(raw), value > 0 else {
        throw SevraError("arguments", "Choose a positive integer version.")
      }
      return value
    }
    func url(_ i: Int) throws -> URL { URL(fileURLWithPath: try arg(i)).standardizedFileURL }
    if command == "create" {
      let book = try Workbook.create(
        at: url(1),
        title: args.count > 2 ? args[2] : url(1).deletingPathExtension().lastPathComponent)
      return .object(["path": .string(book.url.path)])
    }
    if command == "open-archive" {
      let book = try Workbook.openArchive(url(1), at: url(2), cancellation: cancellation)
      return .object(["path": .string(book.url.path)])
    }
    if command == "calculate" {
      return .string(
        try Numbers.calculate(arg(1), values: args.count > 2 ? Value.parse(args[2]).object : [:]))
    }
    if command == "model-status" {
      try require(
        args.count <= 2 && (args.count == 1 || !args[1].hasPrefix("--")), "usage",
        "model-status [MODEL_DIRECTORY]")
      let dir = args.count > 1 ? try url(1) : ProductAI.defaultDirectory
      return .object([
        "directory": .string(dir.path),
        "present": .bool(await ProductAI.shared.installed(at: dir)),
        "downloadBytes": .string(String(ProductAI.downloadBytes)),
      ])
    }
    if command == "model-setup" {
      try require(
        args.count <= 2 || (args.count == 4 && args[2] == "--reuse"), "usage",
        "model-setup [MODEL_DIRECTORY] [--reuse EXISTING_FAST_DIRECTORY]")
      try require(
        (args.count == 1 || !args[1].hasPrefix("--"))
          && (args.count != 4 || !args[3].hasPrefix("--")), "usage",
        "Model setup needs a folder path, not an option.")
      let dir = args.count > 1 ? try url(1) : ProductAI.defaultDirectory
      try await ProductAI.shared.setup(
        at: dir, reusing: args.count == 4 ? try url(3) : nil,
        cancellation: cancellation, progress: { fputs($0 + "\n", stderr) })
      return .bool(true)
    }
    if command == "demo" { return try Demo.create(at: url(1)) }
    let book = try Workbook(url(1))
    if command == "commits" {
      try require(args.count == 2 || args.count == 3, "usage", "commits WORKBOOK [LIMIT]")
      return .array(try book.committedHistory(limit: args.count == 3 ? Int(args[2]) ?? 0 : 100))
    }
    if command == "reconstruct" {
      try require(args.count == 3, "usage", "reconstruct WORKBOOK NEW_WORKBOOK")
      let restored = try book.reconstruct(to: url(2), cancellation: cancellation)
      return .object([
        "path": .string(restored.url.path), "workbookID": .string(restored.id),
        "revision": .number(Double(try restored.revision())), "execution": .string("inert"),
      ])
    }
    if let result = try runTableIntakeCommand(
      command, book: book, args: args, cancellation: cancellation)
    {
      return result
    }
    if let result = try runReferenceCommand(
      command, book: book, args: args, cancellation: cancellation)
    {
      return result
    }
    switch command {
    case "inspect": return try book.counts()
    case "intake-status":
      return .object([
        "tables": .array(try book.intakeStatus()),
        "extraction": .array(try book.pendingExtractions()),
        "jobs": try encoded(book.intakeJobs()),
      ])
    case "intake-use":
      guard let role = IntakeRole(rawValue: try arg(3)) else {
        throw SevraError("intake_role", "Choose reference, analysis, values or update.")
      }
      let job = try book.chooseIntakeRole(
        arg(2), role: role,
        token: args.count > 4 ? args[4] : identifier())
      return try encoded(book.runIntake(job.id, cancellation: cancellation))
    case "intake-from-source":
      guard let role = IntakeRole(rawValue: try arg(3)) else {
        throw SevraError("intake_role", "Choose reference, analysis, values or update.")
      }
      let job = try book.beginIntake(
        sourceID: arg(2), role: role,
        token: args.count > 4 ? args[4] : identifier())
      return try encoded(book.runIntake(job.id, cancellation: cancellation))
    case "intake-resume":
      return try encoded(book.runIntake(arg(2), cancellation: cancellation))
    case "resume-intake":
      try book.resumeIntake(arg(2), cancellation: cancellation)
      return try encoded(book.intakeJobs(sourceID: arg(2)))
    case "runs": return .array(try book.agentRuns())
    case "pin-space":
      return .string(
        try book.pinSpace(
          arg(2), title: args.count > 3 ? args[3] : nil,
          cancellation: cancellation))
    case "column-history": return .array(try book.columnHistory(arg(2)))
    case "verify": return try book.verify()
    case "extract":
      try require(args.count == 3, "usage", "extract WORKBOOK VERSION_ID")
      try book.extract(arg(2), cancellation: cancellation)
      return try book.extractionStatus(arg(2))
    case "import":
      var role: IntakeRole?
      if let index = args.firstIndex(of: "--role") {
        guard args.count > index + 1, let choice = IntakeRole(rawValue: args[index + 1]) else {
          throw SevraError("intake_role", "Choose --role reference, analysis, values or update.")
        }
        role = choice
      }
      var token = identifier()
      if let index = args.firstIndex(of: "--token") { token = try arg(index + 1) }
      let job = try book.captureIntake(
        url(2), linked: args.contains("--link"), role: role, token: token,
        cancellation: cancellation)
      let item = try book.item(job.sourceID)
      return .object([
        "source": try encoded(item),
        "intake": try encoded(book.runIntake(job.id, cancellation: cancellation)),
      ])
    case "capture-url":
      guard let target = URL(string: try arg(2)) else { throw SevraError("url", "Invalid URL.") }
      return try encoded(await book.captureURL(target, cancellation: cancellation))
    case "link-url":
      guard let target = URL(string: try arg(2)) else { throw SevraError("url", "Invalid URL.") }
      return try encoded(
        book.linkURL(target, title: args.count > 3 ? args[3] : target.host ?? "Link"))
    case "transcribe":
      try await book.transcribe(arg(2), cancellation: cancellation)
      return try book.extractionStatus(arg(2))
    case "archive-members":
      return try encoded(book.archiveMembers(arg(2), cancellation: cancellation))
    case "include-members":
      return try encoded(
        book.includeArchiveMembers(
          arg(2), paths: Value.parse(arg(3)).array.compactMap(\.string), cancellation: cancellation)
      )
    case "include": return try encoded(book.includeLinked(arg(2), cancellation: cancellation))
    case "relink":
      try book.relinkAsset(arg(2), to: url(3), cancellation: cancellation)
      return .bool(true)
    case "search":
      return try encoded(book.search(arg(2), offset: args.count > 3 ? Int(args[3]) ?? 0 : 0))
    case "read": return try WorkbookTools(book).execute("read", .object(["id": .string(arg(2))]))
    case "records": return try encoded(book.items(kind: args.count > 2 ? args[2] : nil))
    case "edit-document":
      let version = try arg(2)
      let file = try url(3)
      var separate = false
      var token = identifier()
      var expected: Int?
      var references: [ReferenceSelection]?
      var seen: Set<String> = []
      var index = 4
      while index < args.count {
        let option = args[index]
        try require(seen.insert(option).inserted, "usage", "Duplicate document edit option.")
        switch option {
        case "--separate": separate = true
        case "--references":
          index += 1
          let referenceFile = try url(index)
          try require(
            try referenceFile.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true,
            "usage", "Choose a regular JSON selection file.")
          let referenceHandle = try FileHandle(forReadingFrom: referenceFile)
          defer { try? referenceHandle.close() }
          let referenceBytes = try referenceHandle.read(upToCount: 400_001) ?? Data()
          try require(
            referenceBytes.count <= 400_000, "usage", "Reference JSON is limited to 400,000 bytes.")
          references = try decodeReferenceSelections(
            JSONDecoder().decode(Value.self, from: referenceBytes))
        case "--token":
          index += 1
          token = try arg(index)
          try require(
            !token.isEmpty && token.utf8.count <= 1024, "usage", "Invalid operation token.")
        case "--revision":
          index += 1
          guard let value = Int(try arg(index)), value >= 0 else {
            throw SevraError("usage", "Expected a nonnegative workbook revision.")
          }
          expected = value
        default: throw SevraError("usage", "Unknown document edit option: " + option)
        }
        index += 1
      }
      try cancellation.check()
      try require(
        try file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true,
        "document_file", "Choose a regular UTF-8 text file.")
      let handle = try FileHandle(forReadingFrom: file)
      defer { try? handle.close() }
      var bytes = Data()
      while bytes.count <= 16_000_000 {
        try cancellation.check()
        let chunk = try handle.read(upToCount: min(256 * 1024, 16_000_001 - bytes.count)) ?? Data()
        if chunk.isEmpty { break }
        bytes.append(chunk)
      }
      try require(
        bytes.count <= 16_000_000, "limit", "Document text exceeds 16,000,000 UTF-8 bytes.")
      guard let text = String(data: bytes, encoding: .utf8) else {
        throw SevraError("encoding", "Document text must be valid UTF-8.")
      }
      return try encoded(
        book.editDocument(
          version, text: text, separate: separate, token: token, expectedRevision: expected,
          cancellation: cancellation, references: references))
    case "tables": return try encoded(book.datasets())
    case "table-schema":
      try require(args.count == 3, "usage", "table-schema WORKBOOK DATASET_ID")
      return try book.datasetSchema(arg(2))
    case "table-rebuild":
      try require(
        args.count == 5 && Int(args[3]).map { $0 >= 0 } == true,
        "usage", "table-rebuild WORKBOOK DATASET_ID EXPECTED_REVISION TOKEN")
      try book.rebuildDataset(
        arg(2), expectedRevision: Int(args[3])!, token: arg(4), cancellation: cancellation)
      return try book.datasetSchema(arg(2))
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
          scenario: v["scenario"].string ?? "actual",
          inputs: v["inputs"].array.compactMap(\.string), supersedes: v["supersedes"].string,
          token: v["token"].string ?? identifier(),
          expectedRevision: v["expectedRevision"].int,
          references: v.object.keys.contains("references")
            ? decodeReferenceSelections(v["references"]) : nil))
    case "edit-row":
      return try encoded(
        book.editRow(
          arg(2), values: Value.parse(arg(3)).object,
          expectedRevision: args.count > 4 ? Int(args[4]) : nil))
    case "accept":
      return try encoded(
        book.accept(
          arg(2), token: args.count > 3 ? args[3] : identifier(), cancellation: cancellation))
    case "undo":
      return try encoded(
        book.undoItem(
          arg(2), token: args.count > 3 ? args[3] : identifier(), cancellation: cancellation))
    case "withdraw":
      return try encoded(book.withdrawDraft(arg(2), token: args.count > 3 ? args[3] : identifier()))
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
    case "space-history":
      return try encoded(book.spaceHistory(arg(2), before: args.count > 3 ? integer(3) : nil))
    case "space-edit":
      let edits = try JSONDecoder().decode([SpaceEdit].self, from: Data(arg(4).utf8))
      return try encoded(
        book.editSpace(
          arg(2), expectedVersion: integer(3), edits: edits,
          token: args.count > 5 ? args[5] : identifier()))
    case "space-restore":
      return try encoded(
        book.restoreSpace(
          arg(2), version: integer(3), expectedVersion: integer(4),
          token: args.count > 5 ? args[5] : identifier()))
    case "space":
      let definition = try JSONDecoder().decode(SpaceDefinition.self, from: Data(arg(3).utf8))
      return .string(try book.saveSpace(title: arg(2), definition: definition))
    case "conversation":
      return try encoded(book.messages(conversation: args.count > 2 ? args[2] : "main"))
    case "history":
      return try encoded(
        book.historySlice(
          conversation: args.count > 2 ? args[2] : "main",
          after: args.count > 3 ? args[3] : nil,
          cancellation: cancellation))
    case "history-search":
      return try book.searchHistory(
        arg(3), conversation: arg(2),
        cursor: args.count > 4 ? args[4] : nil, cancellation: cancellation)
    case "history-read":
      return .object([
        "message": try encoded(book.historyMessage(arg(3), conversation: arg(2))),
        "payload": try book.messagePayload(arg(3), conversation: arg(2)),
      ])
    case "unresolved-calls":
      return .array(
        try book.unresolvedToolCalls(conversation: args.count > 2 ? args[2] : "main", limit: 20))
    case "tool-receipt":
      return try book.toolCall(arg(3), conversation: arg(2))
    case "tool-result":
      let positional = args.filter { $0 != "--raw-json" }
      let pathValue = positional.count > 4 ? try Value.parse(positional[4]) : .array([])
      guard case .array(let values) = pathValue, values.allSatisfy({ $0.string != nil }) else {
        throw SevraError("result_path", "A result path must be a JSON array of strings.")
      }
      let path = values.compactMap(\.string)
      return try book.toolResultPage(
        arg(3), conversation: arg(2), path: path,
        offset: positional.count > 5 ? Int(positional[5]) ?? -1 : 0,
        rawJSON: args.contains("--raw-json"), cancellation: cancellation)
    case "checkpoints":
      return .array(try book.contextCheckpoints(conversation: args.count > 2 ? args[2] : "main"))
    case "checkpoint":
      return try book.contextCheckpoint(arg(3), conversation: arg(2))
    case "chapter":
      try book.chapter(title: arg(2), message: arg(3))
      return .bool(true)
    case "thread", "tangent": return .string(try book.tangent(title: arg(2), parentMessage: arg(3)))
    case "start-thread":
      return .string(
        try book.startThread(parentMessage: arg(2), title: args.count > 3 ? args[3] : nil))
    case "rename-thread":
      try book.renameThread(arg(2), title: arg(3))
      return .bool(true)
    case "share-summary": return .string(try book.shareSummary(message: arg(2), text: arg(3)))
    case "reindex":
      try book.rebuildSearch()
      return .bool(true)
    case "export":
      try book.export(to: url(2), cancellation: cancellation)
      return .bool(true)
    case "export-csv":
      try book.exportCSV(arg(2), to: url(3))
      return .bool(true)
    case "tool":
      return try WorkbookTools(book).execute(
        arg(2), args.count > 3 ? Value.parse(args[3]) : .object([:]))
    case "ask":
      let result = try await ProductAI.shared.run(
        arg(2), workbook: book,
        modelDirectory: args.count > 3 ? url(3) : ProductAI.defaultDirectory,
        cancellation: cancellation,
        progress: { fputs($0 + "\n", stderr) })
      return .object([
        "answer": .string(result.answer), "citations": .array(result.citations.map(Value.string)),
        "steps": .number(Double(result.steps)), "state": .string(result.state),
        "conversationAction": try result.conversationAction.map(encoded) ?? .null,
      ])
    default: throw SevraError("usage", help)
    }
  }
  static let help = """
    Sevra 0.1.0 development CLI. Every result is JSON; errors exit nonzero.
    create PATH.sevra [TITLE] | demo PATH.sevra | inspect WORKBOOK | verify WORKBOOK
    transcribe WORKBOOK ITEM_ID | extract WORKBOOK VERSION_ID
    archive-members WORKBOOK ITEM_ID | include-members WORKBOOK ITEM_ID JSON_PATHS
    capture-url WORKBOOK URL | link-url WORKBOOK URL [TITLE] | include WORKBOOK ITEM_ID | relink WORKBOOK ASSET_ID FILE
    import WORKBOOK FILE [--link] [--role reference|analysis|values|update] [--token TOKEN]
    intake-use WORKBOOK JOB_ID ROLE [TOKEN] | intake-from-source WORKBOOK SOURCE_ID ROLE [TOKEN]
    intake-resume WORKBOOK JOB_ID | search WORKBOOK QUERY [OFFSET] | read WORKBOOK ID
    table-update-preview WORKBOOK SOURCE_ID TABLE_ID OPTIONS_JSON
    table-update-inspect WORKBOOK SOURCE_ID [HEADER_RECORD]
    table-update-propose WORKBOOK SOURCE_ID TABLE_ID OPTIONS_JSON
    records WORKBOOK [KIND] | tables WORKBOOK | rows WORKBOOK TABLE_ID [OFFSET]
    add WORKBOOK JSON | edit-row WORKBOOK ITEM_ID VALUES_JSON [EXPECTED_REVISION]
    edit-document WORKBOOK VERSION_ID UTF8_FILE [--separate] [--token TOKEN] [--revision REVISION] [--references JSON_FILE]
    references WORKBOOK VERSION_ID [OPTIONS_JSON] | backlinks WORKBOOK VERSION_ID [OPTIONS_JSON]
    reference-snapshot WORKBOOK VERSION_ID [SNAPSHOT_ID] | reference-resolve WORKBOOK VERSION_ID REFERENCE_ID [SNAPSHOT_ID]
    reference-history WORKBOOK VERSION_ID [OPTIONS_JSON] | annotate-references WORKBOOK VERSION_ID JSON
    file-reference-snapshot WORKBOOK VERSION_ID [SNAPSHOT_ID] | file-reference-history WORKBOOK VERSION_ID [OPTIONS_JSON]
    file-reference-resolve WORKBOOK VERSION_ID REFERENCE_ID [SNAPSHOT_ID]
    file-reference-region WORKBOOK VERSION_ID JSON | annotate-file-references WORKBOOK VERSION_ID JSON
    index-references WORKBOOK VERSION_ID | index-reference-bodies WORKBOOK [OPTIONS_JSON] | rebuild-references WORKBOOK
    accept WORKBOOK ID [TOKEN] | withdraw WORKBOOK ID [TOKEN] | undo WORKBOOK ID [TOKEN] | lineage WORKBOOK ID
    opening WORKBOOK SUBJECT QUANTITY ISO_DATE SOURCE_ID | movement WORKBOOK JSON
    balance WORKBOOK SUBJECT | calculate EXPRESSION [VALUES_JSON]
    spaces WORKBOOK | space WORKBOOK TITLE DEFINITION_JSON | pin-space WORKBOOK SPACE_ID [TITLE]
    space-edit WORKBOOK SPACE_ID BASE_VERSION EDITS_JSON [TOKEN]
    space-history WORKBOOK SPACE_ID [BEFORE_VERSION]
    space-restore WORKBOOK SPACE_ID SAVED_VERSION BASE_VERSION [TOKEN]
    column-history WORKBOOK TABLE_ID | intake-status WORKBOOK | resume-intake WORKBOOK SOURCE_ID
    runs WORKBOOK
    conversation WORKBOOK [CONVERSATION_ID] | chapter WORKBOOK TITLE MESSAGE_ID
    history WORKBOOK [CONVERSATION_ID [AFTER_MESSAGE_ID]]
    history-search WORKBOOK CONVERSATION_ID QUERY [CURSOR] | history-read WORKBOOK CONVERSATION_ID MESSAGE_ID
    unresolved-calls WORKBOOK [CONVERSATION_ID] | tool-receipt WORKBOOK CONVERSATION_ID RECEIPT_ID
    tool-result WORKBOOK CONVERSATION_ID RECEIPT_ID [PATH_JSON [OFFSET]] [--raw-json]
    checkpoints WORKBOOK [CONVERSATION_ID] | checkpoint WORKBOOK CONVERSATION_ID CHECKPOINT_ID
    thread WORKBOOK TITLE MESSAGE_ID | share-summary WORKBOOK MESSAGE_ID TEXT | reindex WORKBOOK
    start-thread WORKBOOK MESSAGE_ID [TITLE] | rename-thread WORKBOOK THREAD_ID TITLE
    export WORKBOOK PATH.sevraz | open-archive PATH.sevraz DEST.sevra
    commits WORKBOOK [LIMIT] | reconstruct WORKBOOK NEW_WORKBOOK
    table-schema WORKBOOK DATASET_ID
    table-rebuild WORKBOOK DATASET_ID EXPECTED_REVISION TOKEN
    export-csv WORKBOOK TABLE_ID PATH.csv | tool WORKBOOK TOOL [ARGS_JSON]
    model-status [MODEL_DIRECTORY] | model-setup [MODEL_DIRECTORY] [--reuse EXISTING_FAST_DIRECTORY]
    ask WORKBOOK QUESTION [MODEL_DIRECTORY]
    """
}
