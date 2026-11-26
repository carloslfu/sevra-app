import Darwin
import Foundation
import SevraAI
import SevraCore
import SevraProduct

@main struct CLI {
  static func main() async {
    let cancellation = Cancellation()
    // A closed terminal or a plain kill stops like Control-C, so copies in progress clean up.
    let stops = [SIGINT, SIGTERM, SIGHUP].map { number in
      signal(number, SIG_IGN)
      let stop = DispatchSource.makeSignalSource(
        signal: number, queue: .global(qos: .userInitiated))
      stop.setEventHandler { cancellation.cancel() }
      stop.resume()
      return stop
    }
    defer { stops.forEach { $0.cancel() } }
    let args = Array(CommandLine.arguments.dropFirst())
    // These two speak to agents directly: the guide as plain text, and MCP over stdio.
    if args == ["agent"] {
      do {
        print(try AgentGuide.text(), terminator: "")
        return
      } catch {
        fputs("sevra agent: \(failureDescription(error))\n", stderr)
        exit(1)
      }
    }
    if args.first == "mcp" {
      exit(await MCPServer.serve(args, cancellation: cancellation))
    }
    do {
      let result = try await run(args, cancellation: cancellation)
      await ProductAI.shared.unload()
      print(
        try Value.object(["schemaVersion": .number(1), "ok": .bool(true), "result": result]).json())
    } catch {
      await ProductAI.shared.unload()
      let e = error as? SevraError ?? SevraError("operation", failureDescription(error))
      let result: Value = .object([
        "schemaVersion": .number(1), "ok": .bool(false),
        "error": .object(["code": .string(e.code), "message": .string(e.message)]),
      ])
      fputs(((try? result.json()) ?? "{}") + "\n", stderr)
      exit(1)
    }
  }
  static func run(_ args: [String], cancellation: Cancellation) async throws -> Value {
    guard let command = args.first else { return .string(start) }
    if let counts = argumentCounts[command] {
      try require(counts.contains(args.count), "usage", help)
    }
    if command == "check-resources" {
      return try await ProductAI.checkResources(validateMetal: !args.contains("--paths-only"))
    }
    if command == "header" {
      // header make DIRECTORY [MODEL_DIRECTORY] | header status [DIRECTORY]
      let action = args.count > 1 ? args[1] : ""
      if action == "make", args.count == 3 || args.count == 4 {
        return try await ProductAI.makeHeader(
          output: URL(fileURLWithPath: args[2]).standardizedFileURL,
          modelsRoot: args.count == 4
            ? URL(fileURLWithPath: args[3]).standardizedFileURL : ProductAI.defaultDirectory,
          progress: { fputs($0 + "\n", stderr) })
      }
      if action == "status", args.count <= 3 {
        return try ProductAI.headerStatus(
          at: args.count == 3 ? URL(fileURLWithPath: args[2]).standardizedFileURL : nil)
      }
      throw SevraError("usage", "header make DIRECTORY [MODEL_DIRECTORY] | header status [DIRECTORY]")
    }
    if command == "help" || command == "--help" {
      return .string(args.dropFirst().first == "all" ? help : start)
    }
    if command == "version" || command == "--version" {
      return .object(["version": .string("0.1.0-dev"), "engine": .string(ProductAI.revision)])
    }
    if command == "schedule-preview" {
      return try runSchedulePreview(args, cancellation: cancellation)
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
    func url(_ i: Int) throws -> URL {
      let path = try arg(i)
      try require(
        !path.isEmpty && !path.hasPrefix("-"), "usage",
        "Expected a path, not an option. Write ./" + path + " for a file with that name.")
      return URL(fileURLWithPath: path).standardizedFileURL
    }
    func directory(_ path: String) throws -> URL {
      try require(
        !path.isEmpty && !path.hasPrefix("-"), "usage",
        "Expected a path, not an option. Write ./" + path + " for a folder with that name.")
      return URL(fileURLWithPath: path).standardizedFileURL
    }
    func offset(_ i: Int) throws -> Int {
      guard args.count > i else { return 0 }
      guard let value = Int(args[i]), value >= 0 else {
        throw SevraError("usage", "Expected a nonnegative offset.")
      }
      return value
    }
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
        try Numbers.calculate(
          arg(1), values: args.count > 2 ? Value.parseExact(args[2]).object : [:]))
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
    let book = try Workbook(url(1), cancellation: cancellation)
    /// A chat named at position i, or the most recently active one.
    func chat(_ i: Int) throws -> String {
      if args.count > i { return args[i] }
      return try latestChat()
    }
    func latestChat() throws -> String { try book.chats().first?.id ?? book.createChat() }
    if command == "business-origins" {
      try require(
        (3...18).contains(args.count), "usage", "business-origins WORKBOOK ITEM_ID [ITEM_ID...]")
      return try book.businessOrigins(inputs: Array(args.dropFirst(2)), cancellation: cancellation)
    }
    if command == "automation-ancestry" {
      try require(
        args.count >= 3 && args.count <= 18, "usage",
        "automation-ancestry WORKBOOK ITEM_ID [ITEM_ID...]")
      return try book.automaticDerivationAncestry(
        inputs: Array(args.dropFirst(2)), cancellation: cancellation)
    }
    if ["business-batches", "business-batch"].contains(command) {
      return try runBusinessFeed(args, book: book, cancellation: cancellation)
    }
    if command == "automation-run-once" {
      return try await runAutomationOnce(args, book: book, cancellation: cancellation)
    }
    if command == "automation-preview" {
      return try runAutomationPreview(args, book: book, cancellation: cancellation)
    }
    if command.hasPrefix("automation-"),
      let result = try runAutomationInspection(args, book: book, cancellation: cancellation)
    {
      return result
    }
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
    if let result = try await runWorkflowCommand(
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
    case "table-formulas":
      guard let report = try book.sheetFormulaReport(arg(2)) else {
        throw SevraError("not_found", "This table has no Excel formulas.")
      }
      return try encoded(report)
    case "verify":
      let report = try book.verify(cancellation: cancellation)
      let issues = report["assetIssues"].array.map { $0["name"].text + ": " + $0["error"].text }
      try require(
        issues.isEmpty, "asset_issues",
        "\(issues.count) file(s) failed verification. "
          + issues.prefix(20).joined(separator: "; "))
      return report
    case "extract":
      try require(args.count == 3, "usage", "extract WORKBOOK VERSION_ID")
      try book.extract(arg(2), cancellation: cancellation)
      return try book.extractionStatus(arg(2))
    case "import":
      var role: IntakeRole?
      var token = identifier()
      var linked = false
      var seen: Set<String> = []
      var index = 3
      while index < args.count {
        let option = args[index]
        try require(seen.insert(option).inserted, "usage", "Duplicate import option.")
        switch option {
        case "--link": linked = true
        case "--role":
          index += 1
          guard args.count > index, let choice = IntakeRole(rawValue: args[index]) else {
            throw SevraError("intake_role", "Choose --role reference, analysis, values or update.")
          }
          role = choice
        case "--token":
          index += 1
          token = try arg(index)
        default: throw SevraError("usage", "Unknown import option: " + option)
        }
        index += 1
      }
      let job = try book.captureIntake(
        url(2), linked: linked, role: role, token: token, cancellation: cancellation)
      let item = try book.item(job.sourceID)
      return .object([
        "source": try encoded(item),
        "intake": try encoded(book.runIntake(job.id, cancellation: cancellation)),
      ])
    case "capture-url":
      guard let target = URL(string: try arg(2)) else { throw SevraError("url", "Invalid URL.") }
      let captured = try await book.captureURL(target, cancellation: cancellation)
      try require(
        captured.data["captureState"].string != "failed", "capture_failed",
        captured.text + " Saved as " + captured.id + ".")
      return try encoded(captured)
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
          arg(2), paths: Value.parseExact(arg(3)).array.compactMap(\.string),
          cancellation: cancellation)
      )
    case "include": return try encoded(book.includeLinked(arg(2), cancellation: cancellation))
    case "relink":
      try book.relinkAsset(arg(2), to: url(3), cancellation: cancellation)
      return .bool(true)
    case "search":
      return try encoded(book.search(arg(2), offset: offset(3)))
    case "read":
      return try WorkbookTools(book, conversation: latestChat()).execute(
        "read", .object(["id": .string(arg(2))]))
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
    case "tables":
      try require(
        args.count == 2 || (args.count == 3 && args[2] == "--archived"), "usage",
        "tables WORKBOOK [--archived]")
      return try encoded(book.datasets(archived: args.count == 3))
    case "definition-input-issues":
      try require(args.count == 4, "usage", "definition-input-issues WORKBOOK ID ARGUMENTS_JSON")
      return .array(try book.applicationInputIssues(args[2], arguments: Value.parseExact(args[3])))
    case "form-template":
      try require(args.count == 3, "usage", "form-template WORKBOOK ACTION_OR_WORKFLOW_ID")
      let action = try book.applicationDefinition(args[2])
      try require(
        ["action", "workflow"].contains(action.kind), "definition_kind",
        "Choose an action or workflow definition.")
      return ActionRegistry.formDefinition(target: action)
    case "form-draft-new":
      try require(args.count == 3, "usage", "form-draft-new WORKBOOK FORM_ID")
      return try encoded(book.newFormDraft(args[2], cancellation: cancellation))
    case "form-draft-submit":
      try require(args.count == 4, "usage", "form-draft-submit WORKBOOK STATE_JSON PREVIEW_JSON")
      let state = try JSONDecoder().decode(FormDraftState.self, from: Data(args[2].utf8))
      return try book.submitFormDraft(
        state, preview: Value.parseExact(args[3]), actor: .programmatic("SevraCLI.form"),
        cancellation: cancellation)
    case "form-draft-read":
      try require(args.count == 3, "usage", "form-draft-read WORKBOOK DRAFT_KEY")
      return try book.formDraft(args[2]).map { try encoded($0) } ?? .null
    case "form-draft-save":
      try require(
        args.count == 5 || (args.count == 6 && args[5] == "--keep-both"), "usage",
        "form-draft-save WORKBOOK DRAFT_KEY STATE_JSON EXPECTED_JSON [--keep-both]")
      let state = try JSONDecoder().decode(FormDraftState.self, from: Data(args[3].utf8))
      let expected =
        args[4] == "null"
        ? nil : try JSONDecoder().decode(FormDraftState.self, from: Data(args[4].utf8))
      return try encoded(
        book.saveFormDraft(args[2], state: state, expected: expected, keepOther: args.count == 6))
    case "form-draft-preview":
      try require(args.count == 3, "usage", "form-draft-preview WORKBOOK STATE_JSON")
      let state = try JSONDecoder().decode(FormDraftState.self, from: Data(args[2].utf8))
      return try book.previewFormDraft(state, cancellation: cancellation)
    case "action-registry":
      try require(args.count == 2, "usage", "action-registry WORKBOOK")
      return ActionRegistry.actions()
    case "action-preview":
      try require(args.count == 4, "usage", "action-preview WORKBOOK ID ARGUMENTS_JSON")
      return try book.previewApplicationAction(
        args[2], arguments: Value.parseExact(args[3]), cancellation: cancellation)
    case "action-invoke":
      try require(
        args.count == 6, "usage", "action-invoke WORKBOOK ID ARGUMENTS_JSON PREVIEW_JSON TOKEN")
      return try book.invokeApplicationAction(
        args[2], arguments: Value.parseExact(args[3]), preview: Value.parseExact(args[4]),
        token: args[5],
        cancellation: cancellation)
    case "definition-save":
      try require(
        (6...7).contains(args.count), "usage",
        "definition-save WORKBOOK LOGICAL_ID CONTENT_JSON BASE_ID_OR_NEW TOKEN [INPUTS_JSON]")
      var inputs: [String] = []
      if args.count == 7 {
        let value = try Value.parseExact(args[6])
        guard case .array(let array) = value, array.allSatisfy({ $0.string != nil }) else {
          throw SevraError("arguments", "Authoring inputs must be an array of exact item IDs.")
        }
        inputs = array.map(\.text)
      }
      return try encoded(
        book.saveApplicationDefinition(
          logicalID: args[2], content: Value.parseExact(args[3]),
          expectedDefinitionID: args[4] == "new" ? nil : args[4], inputs: inputs,
          token: args[5], cancellation: cancellation))
    case "definition-read", "definition-dependencies":
      try require(args.count == 3, "usage", "definition-read/definition-dependencies WORKBOOK ID")
      if command == "definition-read" { return try encoded(book.applicationDefinition(args[2])) }
      return .array(try book.applicationDefinitionDependencies(args[2]))
    case "definition-history":
      try require(
        (3...4).contains(args.count), "usage",
        "definition-history WORKBOOK LOGICAL_ID [BEFORE_VERSION]")
      return .array(
        try book.applicationDefinitionHistory(
          args[2], beforeVersion: args.count == 4 ? integer(3) : nil
        ).map { try encoded($0) })
    case "definition-restore":
      try require(
        args.count == 6, "usage", "definition-restore WORKBOOK LOGICAL_ID VERSION_ID BASE_ID TOKEN")
      return try encoded(
        book.restoreApplicationDefinition(
          args[2], versionID: args[3], expectedDefinitionID: args[4], token: args[5],
          cancellation: cancellation))
    case "definition-evaluate":
      try require(
        (4...5).contains(args.count), "usage",
        "definition-evaluate WORKBOOK ID ARGUMENTS_JSON [CURSOR]")
      return try book.evaluateApplicationDefinition(
        args[2], arguments: Value.parseExact(args[3]), cursor: args.count == 5 ? args[4] : nil,
        cancellation: cancellation)
    case "component-evaluate":
      try require(
        (3...4).contains(args.count), "usage", "component-evaluate WORKBOOK COMPONENT_JSON [CURSOR]"
      )
      try Value.requireDepth(args[2])
      let component = try JSONDecoder().decode(Component.self, from: Data(args[2].utf8))
      return try book.componentDefinitionResult(
        component, cursor: args.count == 4 ? args[3] : nil, cancellation: cancellation)
    case "definition-publish":
      try require(
        args.count == 4, "usage", "definition-publish WORKBOOK REQUEST_JSON_OR_@FILE TOKEN")
      let raw: String
      if args[2].hasPrefix("@") {
        let data = try Data(
          contentsOf: URL(fileURLWithPath: String(args[2].dropFirst())), options: .mappedIfSafe)
        try require(
          data.count <= 1_048_576, "definition_limit", "Publication request exceeds 1 MiB.")
        guard let text = String(data: data, encoding: .utf8) else {
          throw SevraError("arguments", "Use UTF-8 JSON.")
        }
        raw = text
      } else {
        raw = args[2]
      }
      let request = try Value.parseExact(raw)
      let fields = request.object
      try require(
        Set(fields.keys).isSubset(of: [
          "id", "arguments", "evaluation", "title", "meaning", "scenario", "inputs",
        ])
          && ["id", "arguments", "evaluation", "title", "meaning"].allSatisfy { fields[$0] != nil },
        "arguments", "Use declared publication fields.")
      for key in ["id", "title", "meaning", "scenario"] where fields[key] != nil {
        try require(fields[key]?.string != nil, "arguments", key + " must be text.")
      }
      if let inputs = fields["inputs"] {
        guard case .array(let values) = inputs, values.allSatisfy({ $0.string != nil }) else {
          throw SevraError("arguments", "Inputs must be exact version strings.")
        }
      }
      return try encoded(
        book.publishApplicationResult(
          request["id"].text, arguments: request["arguments"], evaluation: request["evaluation"],
          title: request["title"].text, meaning: request["meaning"].text,
          scenario: fields["scenario"]?.text ?? "actual",
          inputs: request["inputs"].array.map(\.text), token: args[3],
          actor: .programmatic("SevraCLI.definition-publish"), cancellation: cancellation))
    case "definition-search":
      try require(
        (3...4).contains(args.count), "usage", "definition-search WORKBOOK QUERY [OPTIONS_JSON]")
      let options = args.count == 4 ? try Value.parseExact(args[3]) : .object([:])
      guard case .object(let fields) = options,
        Set(fields.keys).isSubset(of: ["kind", "historical", "limit", "cursor"]),
        fields["kind"] == nil || fields["kind"]?.string != nil,
        fields["cursor"] == nil || fields["cursor"]?.string != nil,
        fields["historical"] == nil || fields["historical"] == .bool(true)
          || fields["historical"] == .bool(false),
        fields["limit"] == nil
          || fields["limit"]?.int.map({ fields["limit"] == .number(Double($0)) }) == true
      else { throw SevraError("arguments", "Use typed definition search options.") }
      return try book.searchApplicationDefinitions(
        args[2], kind: fields["kind"]?.string,
        historical: fields["historical"] == .bool(true), limit: fields["limit"]?.int ?? 20,
        cursor: fields["cursor"]?.string, cancellation: cancellation)
    case "table-query", "table-query-plan", "table-optimize":
      try require(
        (3...4).contains(args.count) && (args.count == 3 || args[0] == "table-query"),
        "usage",
        "table-query WORKBOOK QUERY_JSON [CURSOR]; table-query-plan/table-optimize WORKBOOK QUERY_JSON"
      )
      let request = try Value.parseExact(arg(2))
      if args[0] == "table-query-plan" {
        return try book.datasetQueryPlan(request, cancellation: cancellation)
      }
      if args[0] == "table-optimize" {
        return try book.optimizeDatasetQuery(request, cancellation: cancellation)
      }
      return try book.queryDataset(
        request, cursor: args.count == 4 ? arg(3) : nil, cancellation: cancellation)
    case "table-clear-indexes":
      try require(args.count == 3, "usage", "table-clear-indexes WORKBOOK DATASET_ID")
      return try book.removeDatasetQueryIndexes(arg(2), cancellation: cancellation)
    case "table-schema":
      try require(args.count == 3, "usage", "table-schema WORKBOOK DATASET_ID")
      return try book.datasetSchema(arg(2))
    case "table-schema-history":
      try require(
        (3...4).contains(args.count), "usage",
        "table-schema-history WORKBOOK DATASET_ID [BEFORE_VERSION]")
      return try encoded(
        book.datasetDefinitions(arg(2), beforeVersion: args.count == 4 ? integer(3) : nil))
    case "table-edit-schema":
      try require(
        args.count == 7, "usage",
        "table-edit-schema WORKBOOK DATASET_ID BASE_VERSION BASE_DEFINITION_ID OPTIONS_JSON TOKEN")
      let options = try Value.parseExact(arg(5))
      guard case .object(let fields) = options else {
        throw SevraError("arguments", "Schema options must be an object.")
      }
      try require(
        !fields.isEmpty && Set(fields.keys).isSubset(of: ["title", "columns", "archived"]),
        "arguments", "Choose title, columns or archived as schema options.")
      if let title = fields["title"] {
        try require(title.string != nil, "arguments", "Title must be text.")
      }
      if let archived = fields["archived"] {
        guard case .bool = archived else {
          throw SevraError("arguments", "Archived must be true or false.")
        }
      }
      let columns = try fields["columns"].map {
        guard case .array(let columns) = $0 else {
          throw SevraError("arguments", "Columns must be an array.")
        }
        for column in columns {
          guard case .object(let definition) = column else {
            throw SevraError("arguments", "Each column must be an object.")
          }
          try require(
            Set(definition.keys).isSubset(of: [
              "id", "title", "type", "formula", "unit", "required", "unique",
            ]),
            "arguments", "Unknown column definition field.")
        }
        return try JSONDecoder().decode([Column].self, from: Data($0.json().utf8))
      }
      return try encoded(
        book.updateDatasetDefinition(
          arg(2), expectedVersion: integer(3),
          expectedDefinitionID: arg(4), title: fields["title"]?.string, columns: columns,
          archived: fields["archived"].map { $0 == .bool(true) }, token: arg(6),
          cancellation: cancellation))
    case "table-restore-schema":
      try require(
        args.count == 7, "usage",
        "table-restore-schema WORKBOOK DATASET_ID SAVED_DEFINITION_ID BASE_VERSION BASE_DEFINITION_ID TOKEN"
      )
      return try encoded(
        book.restoreDatasetDefinition(
          arg(2), definitionID: arg(3),
          expectedVersion: integer(4), expectedDefinitionID: arg(5), token: arg(6),
          cancellation: cancellation))
    case "table-rebuild":
      try require(
        args.count == 5 && Int(args[3]).map { $0 >= 0 } == true,
        "usage", "table-rebuild WORKBOOK DATASET_ID EXPECTED_REVISION TOKEN")
      try book.rebuildDataset(
        arg(2), expectedRevision: Int(args[3])!, token: arg(4), cancellation: cancellation)
      return try book.datasetSchema(arg(2))
    case "rows":
      return try encoded(book.rows(arg(2), offset: offset(3)))
    case "observe":
      try require(args.count == 3, "usage", "observe WORKBOOK OBSERVATION_JSON")
      let observation = try Value.parseExact(arg(2))
      try require(
        Set(observation.object.keys).isSubset(of: ["title", "text", "data", "token"]),
        "business_input", "An independent observation cannot replace or claim existing inputs.")
      try checkFields(observation, text: ["title", "text", "token"], other: ["data"])
      return try encoded(
        book.recordBusinessObservation(
          title: observation["title"].text, text: observation["text"].text,
          data: observation["data"] == .null ? .object([:]) : observation["data"],
          token: observation["token"].string ?? identifier(), cancellation: cancellation))
    case "add":
      let v = try Value.parseExact(arg(2))
      try checkFields(
        v,
        text: [
          "category", "kind", "title", "text", "meaning", "status", "scenario", "supersedes",
          "token",
        ],
        other: ["data", "inputs", "expectedRevision", "references"])
      if let inputs = v.object["inputs"] {
        guard case .array(let values) = inputs, values.allSatisfy({ $0.string != nil }) else {
          throw SevraError("arguments", "Inputs must be an array of exact item IDs.")
        }
      }
      if let revision = v.object["expectedRevision"] {
        guard let value = revision.int, value >= 0, revision == .number(Double(value)) else {
          throw SevraError("arguments", "expectedRevision must be a nonnegative whole number.")
        }
      }
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
      guard case .object(let values) = try Value.parseExact(arg(3)) else {
        throw SevraError("arguments", "Give the columns to change as a JSON object.")
      }
      var expected: Int?
      if args.count > 4 {
        guard let value = Int(args[4]), value >= 0 else {
          throw SevraError("usage", "Expected a nonnegative workbook revision.")
        }
        expected = value
      }
      return try encoded(book.editRow(arg(2), values: values, expectedRevision: expected))
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
    case "lineage": return .array(try book.lineage(arg(2)))
    case "app-install":
      try require(
        args.count == 3 || args.count == 5, "usage",
        "app-install WORKBOOK PACKAGE [SPACE_ID BASE_VERSION]")
      let package = try NativeAppPackage.load(from: url(2))
      return try encoded(
        book.installNativeApp(
          package, spaceID: args.count == 5 ? arg(3) : identifier(),
          expectedVersion: args.count == 5 ? integer(4) : nil))
    case "app-export":
      try require(args.count == 4, "usage", "app-export WORKBOOK SPACE_ID DESTINATION")
      return .string(try book.exportNativeAppTemplate(arg(2), to: url(3)).path)
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
      try Value.requireDepth(arg(3))
      let definition = try JSONDecoder().decode(SpaceDefinition.self, from: Data(arg(3).utf8))
      return .string(try book.saveSpace(title: arg(2), definition: definition))
    case "metric":
      // The number a view's metric shows, by the app's own rule.
      guard let component = try book.space(arg(2)).definition.component(arg(3)),
        component.type == "metric"
      else { throw SevraError("view", "Choose a metric on a saved view.") }
      return .string(try book.componentMetric(component, data: try book.componentData(component)))
    case "press":
      // A view's button, pressed as a person presses it: values fill the inputs it leaves open.
      return try book.pressButton(
        spaceID: arg(2), componentID: arg(3),
        values: args.count > 4 ? Value.parseExact(args[4]).object : [:],
        actor: .human("Sevra command line"))
    case "chats": return try encoded(book.chats())
    case "chat-new": return .string(try book.createChat())
    case "chat-rename":
      try book.renameChat(arg(2), title: arg(3))
      return .bool(true)
    case "chat-delete": return .string(try book.deleteChat(arg(2)))
    case "conversation":
      return try encoded(book.messages(conversation: chat(2)))
    case "history":
      return try encoded(
        book.historySlice(
          conversation: chat(2),
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
        try book.unresolvedToolCalls(conversation: chat(2), limit: 20))
    case "tool-receipt":
      return try book.toolCall(arg(3), conversation: arg(2))
    case "tool-result":
      let positional = args.filter { $0 != "--raw-json" }
      try require((4...6).contains(positional.count), "usage", help)
      let pathValue = positional.count > 4 ? try Value.parseExact(positional[4]) : .array([])
      guard case .array(let values) = pathValue, values.allSatisfy({ $0.string != nil }) else {
        throw SevraError("result_path", "A result path must be a JSON array of strings.")
      }
      let path = values.compactMap(\.string)
      return try book.toolResultPage(
        arg(3), conversation: arg(2), path: path,
        offset: positional.count > 5 ? Int(positional[5]) ?? -1 : 0,
        rawJSON: args.contains("--raw-json"), cancellation: cancellation)
    case "checkpoints":
      return .array(try book.contextCheckpoints(conversation: chat(2)))
    case "checkpoint":
      return try book.contextCheckpoint(arg(3), conversation: arg(2))
    case "reindex":
      try book.rebuildSearch(cancellation: cancellation)
      return .bool(true)
    case "export":
      try book.export(to: url(2), cancellation: cancellation)
      return .bool(true)
    case "export-csv":
      try book.exportCSV(arg(2), to: url(3), cancellation: cancellation)
      return .bool(true)
    case "tools":
      // The workbook's saved tools, and whether this Mac has granted each.
      return .array(
        try book.savedTools().map {
          .object([
            "name": .string($0.name), "definitionID": .string($0.definitionID),
            "version": .number(Double(try book.applicationDefinition($0.definitionID).version)),
            "language": .string($0.language), "enabled": .bool($0.enabled),
            "inputs": .array($0.inputs.map { .string($0.name + " " + $0.type) }),
          ])
        })
    case "tool-enable", "tool-disable", "tool-remove":
      // The person's own steps for a tool: a tool from a copied workbook runs once enabled here.
      guard let tool = try book.savedTools().first(where: { $0.name == (try arg(2)) }) else {
        throw SevraError("tool", "No saved tool is named \(try arg(2)).")
      }
      switch command {
      case "tool-enable": try book.enableTool(tool.definitionID)
      case "tool-disable": try book.disableTool(tool.definitionID)
      default: _ = try book.retireTool(tool.name)
      }
      return .object(["tool": .string(tool.name), "done": .string(String(command.dropFirst(5)))])
    case "tool":
      return try callTool(
        book, name: arg(2), arguments: args.count > 3 ? Value.parseExact(args[3]) : .object([:]))
    case "ask":
      // ask WORKBOOK PROMPT [MODEL_DIRECTORY] [--chat CHAT_ID]: the latest chat unless one is named.
      var positional = Array(args.prefix(2))
      var named: String?
      var index = 2
      while index < args.count {
        if args[index] == "--chat" {
          try require(named == nil && index + 1 < args.count, "usage", help)
          named = args[index + 1]
          index += 2
        } else {
          positional.append(args[index])
          index += 1
        }
      }
      try require((3...4).contains(positional.count), "usage", help)
      let conversation = try named ?? latestChat()
      let result = try await ProductAI.shared.run(
        positional[2], workbook: book, conversation: conversation,
        modelDirectory: positional.count > 3 ? try directory(positional[3]) : ProductAI.defaultDirectory,
        cancellation: cancellation,
        progress: { fputs($0 + "\n", stderr) })
      return .object([
        "answer": .string(result.answer), "citations": .array(result.citations.map(Value.string)),
        "steps": .number(Double(result.steps)), "state": .string(result.state),
        "chat": .string(conversation),
      ])
    default: throw SevraError("usage", help)
    }
  }
  /// A JSON argument names only these fields, and those in `text` hold text.
  static func checkFields(_ value: Value, text: Set<String>, other: Set<String> = []) throws {
    guard case .object(let fields) = value else {
      throw SevraError("arguments", "Give the fields as a JSON object.")
    }
    for (name, field) in fields {
      try require(
        text.contains(name) || other.contains(name), "arguments", "Unknown field: " + name)
      try require(!text.contains(name) || field.string != nil, "arguments", name + " must be text.")
    }
  }
  /// How many arguments each command takes, counting itself. Others check their own.
  static let argumentCounts: [String: ClosedRange<Int>] = [
    "create": 2...3, "demo": 2...2, "open-archive": 3...3, "calculate": 2...3,
    "inspect": 2...2, "intake-status": 2...2, "intake-use": 4...5, "intake-from-source": 4...5,
    "intake-resume": 3...3, "resume-intake": 3...3, "runs": 2...2, "pin-space": 3...4,
    "column-history": 3...3, "table-formulas": 3...3, "verify": 2...2,
    "capture-url": 3...3, "link-url": 3...4, "transcribe": 3...3, "archive-members": 3...3,
    "include-members": 4...4, "include": 3...3, "relink": 4...4, "search": 3...4, "read": 3...3,
    "records": 2...3, "rows": 3...4, "add": 3...3, "edit-row": 4...5, "accept": 3...4,
    "undo": 3...4, "withdraw": 3...4,
    "lineage": 3...3, "spaces": 2...2, "space-history": 3...4, "space-edit": 5...6,
    "space-restore": 5...6, "space": 4...4, "conversation": 2...3, "history": 2...4,
    "history-search": 4...5, "history-read": 4...4, "unresolved-calls": 2...3,
    "tool-receipt": 4...4, "checkpoints": 2...3, "checkpoint": 4...4, "chats": 2...2,
    "chat-new": 2...2, "chat-rename": 4...4, "chat-delete": 3...3, "reindex": 2...2,
    "export": 3...3, "export-csv": 4...4, "tool": 3...4, "ask": 3...6, "tools": 2...2, "tool-enable": 3...3, "tool-disable": 3...3,
    "tool-remove": 3...3,
  ]
  /// One call of a chat tool, as `sevra tool` and `sevra mcp` make it. The seven general tools
  /// are accepted by name, and so is the operation behind each.
  static func callTool(_ book: Workbook, name: String, arguments: Value) throws -> Value {
    if name == "ask" || name == "finish" {
      throw SevraError(
        "chat_only",
        "\(name) is how Sevra's chat model talks to the person during a chat turn. Talk to the person yourself, or use sevra ask WORKBOOK QUESTION to ask Sevra's model."
      )
    }
    let call = GeneralTools.route(name, arguments)
    let chat = try book.chats().first?.id ?? book.createChat()
    let result = try WorkbookTools(book, conversation: chat).execute(call.tool, call.arguments)
    // An action the app window performs does nothing here, so it must not report success.
    if let action = result["hostAction"].string {
      let instead: [String: String] = [
        "file.export_table": "export-csv WORKBOOK TABLE_ID PATH.csv",
        "file.export_workbook": "export WORKBOOK PATH.sevraz",
        "workflow.continue": "workflow-continue WORKBOOK RUN_ID",
        "workflow.retry": "workflow-retry WORKBOOK RUN_ID TOKEN",
      ]
      throw SevraError(
        "app_only",
        "\(action) runs in the Sevra window, so nothing happened."
          + (instead[action].map { " Use sevra \($0) instead." } ?? ""))
    }
    return worded(result)
  }

  /// Guidance in a tool result names the operations behind the tools, as it does for the app's
  /// model before the app rewords it. Only guidance text is reworded; data is left exact.
  static func worded(_ value: Value) -> Value {
    switch value {
    case .object(let fields):
      return .object(
        fields.reduce(into: [:]) { out, field in
          if ["notice", "detail", "hint"].contains(field.key), case .string(let text) = field.value {
            out[field.key] = .string(GeneralTools.wording(text))
          } else {
            out[field.key] = worded(field.value)
          }
        })
    case .array(let items): return .array(items.map(worded))
    default: return value
    }
  }

  /// The front page: the tools Sevra's chat model uses, then the commands for whole workbooks.
  static let start = """
    Sevra 0.1.0 development CLI. Every result is JSON; errors exit nonzero.
    Agents: run sevra agent first. It prints how to use these tools in this version, as plain text.
    MCP: sevra mcp [WORKBOOK] serves search, read, sql, run and save over stdio.
    Work in a workbook with the tools Sevra's chat model uses:
      tool WORKBOOK search '{"query":"a few words"}'
      tool WORKBOOK read '{"id":"ID"}'            read '{"kind":"actions"}' lists what run can do
      tool WORKBOOK sql '{"statements":["SELECT name, id FROM tables"]}'
      tool WORKBOOK run '{"code":"return await sql('SELECT 1')"}'   or '{"action":"NAME","arguments":{}}'
      tool WORKBOOK save '{"tool":{"name":"…","description":"…","inputs":[],"statements":["…"]}}'
    Whole workbooks:
      create PATH.sevra [TITLE] | demo PATH.sevra | inspect WORKBOOK | verify WORKBOOK
      import WORKBOOK FILE [--role values|analysis|reference|update] [--link]
      export WORKBOOK PATH.sevraz | open-archive PATH.sevraz DEST.sevra | export-csv WORKBOOK TABLE_ID PATH.csv
      tools WORKBOOK | tool-enable WORKBOOK NAME | tool-disable WORKBOOK NAME | tool-remove WORKBOOK NAME
      chats WORKBOOK | history WORKBOOK [CHAT_ID] | ask WORKBOOK QUESTION [MODEL_DIRECTORY] [--chat CHAT_ID]
      model-status [MODEL_DIRECTORY] | version
    help all lists every command, including lower-level inspection and repair.
    """
  static let help = """
    Sevra 0.1.0 development CLI. Every result is JSON; errors exit nonzero.
    agent (the agent guide as plain text) | mcp [WORKBOOK] (the chat tools over MCP on stdio)
    header make DIRECTORY [MODEL_DIRECTORY] | header status [DIRECTORY]
    tools WORKBOOK | tool-enable WORKBOOK NAME | tool-disable WORKBOOK NAME | tool-remove WORKBOOK NAME
    create PATH.sevra [TITLE] | demo PATH.sevra | inspect WORKBOOK | verify WORKBOOK
    transcribe WORKBOOK ITEM_ID | extract WORKBOOK VERSION_ID
    archive-members WORKBOOK ITEM_ID | include-members WORKBOOK ITEM_ID JSON_PATHS
    capture-url WORKBOOK URL | link-url WORKBOOK URL [TITLE] | include WORKBOOK ITEM_ID | relink WORKBOOK ASSET_ID FILE
    import WORKBOOK FILE [--link] [--role reference|analysis|values|update] [--token TOKEN]
    intake-use WORKBOOK JOB_ID ROLE [TOKEN] | intake-from-source WORKBOOK SOURCE_ID ROLE [TOKEN]
    intake-resume WORKBOOK JOB_ID | search WORKBOOK QUERY [OFFSET] | read WORKBOOK ID
    table-update-preview WORKBOOK SOURCE_ID TABLE_ID OPTIONS_JSON
    table-update-inspect WORKBOOK SOURCE_ID [HEADER_RECORD [SHEET]]
    table-update-suggest WORKBOOK SOURCE_ID TABLE_ID [HEADER_RECORD [SHEET]]
    table-update-propose WORKBOOK SOURCE_ID TABLE_ID OPTIONS_JSON
    table-update-draft WORKBOOK SOURCE_ID | table-update-draft-save WORKBOOK DRAFT_JSON
    table-update-draft-discard WORKBOOK SOURCE_ID
    records WORKBOOK [KIND] | tables WORKBOOK [--archived] | rows WORKBOOK TABLE_ID [OFFSET]
    observe WORKBOOK OBSERVATION_JSON
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
    calculate EXPRESSION [VALUES_JSON]
    schedule-preview SCHEDULE_JSON_OR_@FILE AFTER_ISO [COUNT] [HORIZON_DAYS]
    automation-preview WORKBOOK EXACT_DEFINITION_ID AFTER_ISO [COUNT] [HORIZON_DAYS]
    automation-activation WORKBOOK ACTIVATION_ID
    automation-list WORKBOOK [AFTER_ID_OR_-] [LIMIT]
    automation-occurrences WORKBOOK ACTIVATION_ID [AFTER_ID_OR_-] [LIMIT]
    automation-events WORKBOOK [AFTER_SEQUENCE] [LIMIT]
    automation-pause WORKBOOK ACTIVATION_ID EXPECTED_GENERATION TOKEN
    automation-run-once WORKBOOK EXACT_DEFINITION_ID EXPECTED_GENERATION START_AFTER OBSERVED_AT TOKEN [--allow-ai [MODEL_DIRECTORY]]
    app-install WORKBOOK PACKAGE [SPACE_ID BASE_VERSION]
    app-export WORKBOOK SPACE_ID DESTINATION
    spaces WORKBOOK | space WORKBOOK TITLE DEFINITION_JSON | pin-space WORKBOOK SPACE_ID [TITLE]
    press WORKBOOK SPACE_ID COMPONENT_ID [VALUES_JSON] | metric WORKBOOK SPACE_ID COMPONENT_ID
    space-edit WORKBOOK SPACE_ID BASE_VERSION EDITS_JSON [TOKEN]
    space-history WORKBOOK SPACE_ID [BEFORE_VERSION]
    space-restore WORKBOOK SPACE_ID SAVED_VERSION BASE_VERSION [TOKEN]
    column-history WORKBOOK TABLE_ID | table-formulas WORKBOOK TABLE_ID
    intake-status WORKBOOK | resume-intake WORKBOOK SOURCE_ID
    runs WORKBOOK
    chats WORKBOOK | chat-new WORKBOOK | chat-rename WORKBOOK CHAT_ID TITLE | chat-delete WORKBOOK CHAT_ID
    A command without CHAT_ID uses the most recently active chat.
    conversation WORKBOOK [CHAT_ID] | history WORKBOOK [CHAT_ID [AFTER_MESSAGE_ID]]
    history-search WORKBOOK CHAT_ID QUERY [CURSOR] | history-read WORKBOOK CHAT_ID MESSAGE_ID
    unresolved-calls WORKBOOK [CHAT_ID] | tool-receipt WORKBOOK CHAT_ID RECEIPT_ID
    tool-result WORKBOOK CHAT_ID RECEIPT_ID [PATH_JSON [OFFSET]] [--raw-json]
    checkpoints WORKBOOK [CHAT_ID] | checkpoint WORKBOOK CHAT_ID CHECKPOINT_ID | reindex WORKBOOK
    export WORKBOOK PATH.sevraz | open-archive PATH.sevraz DEST.sevra
    commits WORKBOOK [LIMIT] | reconstruct WORKBOOK NEW_WORKBOOK
    business-batches WORKBOOK [AFTER_BATCH_ID|-] [LIMIT] [SCOPE_KIND SCOPE_KEY]
    business-batch WORKBOOK BATCH_ID [AFTER_ORDINAL|-] [LIMIT]
    business-origins WORKBOOK ITEM_ID [ITEM_ID...]
    automation-ancestry WORKBOOK ITEM_ID [ITEM_ID...]
    automation-causality WORKBOOK RUN_ID
    table-schema WORKBOOK DATASET_ID
    table-schema-history WORKBOOK DATASET_ID [BEFORE_VERSION]
    table-edit-schema WORKBOOK DATASET_ID BASE_VERSION BASE_DEFINITION_ID OPTIONS_JSON TOKEN
    table-restore-schema WORKBOOK DATASET_ID SAVED_DEFINITION_ID BASE_VERSION BASE_DEFINITION_ID TOKEN
    table-rebuild WORKBOOK DATASET_ID EXPECTED_REVISION TOKEN
    table-query WORKBOOK QUERY_JSON [CURSOR]
    definition-input-issues WORKBOOK ID ARGUMENTS_JSON
    form-template WORKBOOK ACTION_ID
    form-draft-new WORKBOOK FORM_ID
    form-draft-read WORKBOOK DRAFT_KEY
    form-draft-save WORKBOOK DRAFT_KEY STATE_JSON EXPECTED_JSON [--keep-both]
    form-draft-preview WORKBOOK STATE_JSON
    action-registry WORKBOOK
    action-preview WORKBOOK ACTION_OR_FORM_ID ARGUMENTS_JSON
    action-invoke WORKBOOK ACTION_OR_FORM_ID ARGUMENTS_JSON PREVIEW_JSON TOKEN
    definition-save WORKBOOK LOGICAL_ID CONTENT_JSON BASE_ID_OR_NEW TOKEN [INPUTS_JSON]
    definition-read WORKBOOK LOGICAL_OR_VERSION_ID
    definition-history WORKBOOK LOGICAL_ID [BEFORE_VERSION]
    definition-dependencies WORKBOOK VERSION_ID
    definition-restore WORKBOOK LOGICAL_ID VERSION_ID BASE_ID TOKEN
    definition-evaluate WORKBOOK LOGICAL_OR_VERSION_ID ARGUMENTS_JSON [CURSOR]
    component-evaluate WORKBOOK COMPONENT_JSON [CURSOR]
    definition-publish WORKBOOK REQUEST_JSON_OR_@FILE TOKEN
    definition-search WORKBOOK QUERY [OPTIONS_JSON]
    form-draft-submit WORKBOOK STATE_JSON PREVIEW_JSON
    workflow-start WORKBOOK EXACT_DEFINITION_ID ARGUMENTS_JSON TOKEN
    workflow-activity WORKBOOK [STATE|- [CURSOR]] | workflow-inspect WORKBOOK RUN_ID
    workflow-continue WORKBOOK RUN_ID [MODEL_DIRECTORY]
    workflow-read WORKBOOK RUN_ID
    workflow-clarification WORKBOOK RUN_ID
    workflow-clarify WORKBOOK RUN_ID TARGET_JSON VALUES_JSON REASON TOKEN
    workflow-list WORKBOOK [STATE]
    workflow-advance WORKBOOK RUN_ID
    workflow-claim WORKBOOK RUN_ID OWNER LEASE_SECONDS TOKEN
    workflow-finish WORKBOOK RUN_ID CLAIM_JSON
    workflow-heartbeat WORKBOOK RUN_ID CLAIM_JSON LEASE_SECONDS TOKEN
    workflow-retry WORKBOOK RUN_ID TOKEN
    workflow-cancel WORKBOOK RUN_ID TOKEN
    workflow-events WORKBOOK [AFTER_SEQUENCE]
    table-query-plan WORKBOOK QUERY_JSON
    table-optimize WORKBOOK QUERY_JSON | table-clear-indexes WORKBOOK DATASET_ID
    export-csv WORKBOOK TABLE_ID PATH.csv | tool WORKBOOK TOOL [ARGS_JSON]
    model-status [MODEL_DIRECTORY] | model-setup [MODEL_DIRECTORY] [--reuse EXISTING_FAST_DIRECTORY]
    ask WORKBOOK QUESTION [MODEL_DIRECTORY] [--chat CHAT_ID]
    """
}
