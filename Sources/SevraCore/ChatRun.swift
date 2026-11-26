import Foundation

/// The `run` chat tool of the general chat tools plan: one model-written script.
///
/// The script runs in the sandboxed helper, which can reach no file, network or clock. It
/// asks this host for what it needs: `sql` on one private copy of the tables for the whole
/// script, and `search` and `read` of the saved workbook. The helper answers nothing itself.
/// Each pass lists the calls the script made, the host answers the new ones, and the script
/// runs again from the top until it returns.
///
/// Nothing is saved while the script runs. When it returns, what its statements did to the
/// copy is applied through the recorded write paths, all or nothing, with one Undo. A script
/// that throws, runs out of budget or is cancelled changes nothing.
extension Workbook {
  public static let chatRunCallLimit = 48
  public static let chatRunSeconds: TimeInterval = 30

  /// Checks a saved tool's JavaScript body for syntax in the sandboxed helper, without running it.
  public func checkChatScript(_ code: String, cancellation: Cancellation = .init()) throws {
    try require(
      !code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && code.utf8.count <= 24_000,
      "run", "Send JavaScript under 24,000 bytes.")
    let worker = ExtractionWorker(timeout: 4, maximumMemoryBytes: 256 * 1024 * 1024)
    _ = try worker.chatScript(
      .object(["source": .string(code), "answers": .array([]), "checkOnly": .bool(true)]),
      cancellation: cancellation)
  }

  /// Runs a script tool once before it is saved, on a throwaway copy, with sample inputs: text
  /// "sample", number 0, today's date, false, and null for an optional input. Nothing it does is
  /// kept. A mistake in the code, such as a name it never defined or a statement SQL refuses, is
  /// returned as the refusal to save. A failure that only the data or the sample inputs caused,
  /// such as no rows to read or a value a constraint refuses, is not.
  func rehearseChatScript(
    _ code: String, inputs: [(name: String, type: String)], optional: Set<String>,
    cancellation: Cancellation
  ) throws -> String? {
    let day = DateFormatter()
    day.calendar = Calendar(identifier: .gregorian)
    day.locale = Locale(identifier: "en_US_POSIX")
    day.dateFormat = "yyyy-MM-dd"
    var values: [String: Value] = [:]
    for input in inputs {
      let sample: Value =
        switch input.type {
        case "decimal": .number(0)
        case "boolean": .bool(false)
        case "date": .string(day.string(from: Date()))
        default: .string("sample")
        }
      values[input.name] = optional.contains(input.name) ? .null : sample
    }
    let hint =
      " The script was tried once with sample inputs and nothing was kept, so the tool was not saved. In a script, SQL functions such as date('now') go inside the sql text, and today is today's date as YYYY-MM-DD. Pass values as sql(text, {name: value}) and write each as :name in the statement; never build SQL by joining values into its text."
    let outcome: Value
    do {
      outcome = try chatRun(
        code: code, readOnly: false, token: "rehearsal-" + identifier(), requestSourceID: nil,
        inputs: values, host: { _, _ in .object(["results": .array([])]) }, rehearsal: true,
        cancellation: cancellation)
    } catch let error as SevraError where error.code == "run" {
      // A syntax error, a missing await or return: the code's own mistakes.
      return error.message + hint
    } catch let error as SevraError where error.code == "run_limit" {
      return nil
    }
    guard let message = outcome["error"].string else { return nil }
    if outcome["hostError"] == .bool(true) {
      // A statement SQL refuses is the code's mistake; a constraint or a value is the data's.
      let data = ["constraint", "datatype mismatch", "more than a script can read", "needs a value"]
      if data.contains(where: { message.localizedCaseInsensitiveContains($0) }) { return nil }
      return "The script failed: " + message + hint
    }
    let name = outcome["errorName"].text
    // A name never defined, or a value called that is not a function, is wrong whatever the
    // data. Reading a field of a row that is not there, or the script's own throw, is not.
    if ["ReferenceError", "SyntaxError"].contains(name)
      || (name == "TypeError" && message.contains("not a function"))
    {
      return "The script failed: " + message + "." + hint
    }
    return nil
  }

  public func chatRun(
    code: String, readOnly: Bool, token: String, requestSourceID: String?,
    inputs: [String: Value] = [:], confirmLarge: ChatChangeTally? = nil,
    host: (_ method: String, _ arguments: Value) throws -> Value,
    rehearsal: Bool = false,
    cancellation: Cancellation = .init()
  ) throws -> Value {
    try require(
      !code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && code.utf8.count <= 24_000,
      "run", "Send JavaScript under 24,000 bytes.")
    let worker = ExtractionWorker(timeout: 4, maximumMemoryBytes: 256 * 1024 * 1024)
    let now = Date()
    let day = DateFormatter()
    day.calendar = Calendar(identifier: .gregorian)
    day.locale = Locale(identifier: "en_US_POSIX")
    day.dateFormat = "yyyy-MM-dd"
    let session = try synchronized(cancellation: cancellation) {
      try ChatSQLSession(self, readOnly: readOnly, now: now, cancellation: cancellation)
    }
    defer { session.close() }
    // A script works on rows, so it reads more of them than a model is shown, as numbers.
    session.scratch.shownRows = 5_000
    session.scratch.shownBytes = 1_000_000
    session.scratch.numbers = true
    session.script = true
    var hostErrors = Set<String>()
    var answers: [Value] = []
    var asked: [Value] = []
    var statements: [Value] = []
    let deadline = ProcessInfo.processInfo.systemUptime + Self.chatRunSeconds
    func answer(_ call: Value) throws -> Value {
      let arguments = call["args"]
      switch call["method"].text {
      case "sql":
        let statement = arguments["statement"].text
        try require(
          statement.utf8.count <= 8_000, "sql", "A statement is under 8,000 bytes.")
        // Values by name for :name, or a list for ? in order.
        let given = arguments["values"]
        let values =
          given.array.isEmpty
          ? given.object
          : Dictionary(
            uniqueKeysWithValues: given.array.enumerated().map { (String($0.offset + 1), $0.element) })
        let result = try synchronized(cancellation: cancellation) {
          try session.run([statement], inputs: values)
        }[0]
        statements.append(.string(statement))
        guard result.object["columns"] != nil else { return result }
        try require(
          result["rows"].array.count == result["rowCount"].int, "run_limit",
          "That query returns more than a script can read at once. Aggregate, filter, or page with LIMIT and OFFSET."
        )
        let names = result["columns"].array.map(\.text)
        return .array(
          result["rows"].array.map { row in
            .object(Dictionary(zip(names, row.array)) { first, _ in first })
          })
      case "tool":
        // A saved SQL tool runs on the script's own copy, like its sql calls.
        let tool = try synchronized(cancellation: cancellation) {
          try runnableTool(arguments["name"].text)
        }
        try require(
          tool.language == "sql", "run",
          "A script can call a saved SQL tool. Run a script tool alone, with run and tool.")
        let results = try synchronized(cancellation: cancellation) {
          try session.run(tool.statements, inputs: toolInputs(tool, arguments["values"].object))
        }
        statements += tool.statements.map(Value.string)
        guard let result = results.last, result.object["columns"] != nil else {
          return results.last ?? .null
        }
        let names = result["columns"].array.map(\.text)
        return .array(
          result["rows"].array.map { row in
            .object(Dictionary(zip(names, row.array)) { first, _ in first })
          })
      case "search", "read": return try host(call["method"].text, arguments)
      default: throw SevraError("run", "A script can call sql, tool, search, read and action.")
      }
    }
    while true {
      try cancellation.check()
      try require(
        ProcessInfo.processInfo.systemUptime < deadline, "run_limit",
        "The script ran out of time. Nothing was changed.")
      let reply = try worker.chatScript(
        .object([
          "source": .string(code), "answers": .array(answers),
          "now": .number((now.timeIntervalSince1970 * 1000).rounded()),
          "today": .string(day.string(from: now)), "inputs": .object(inputs),
        ]), cancellation: cancellation)
      let calls = reply["calls"].array
      try require(
        calls.count >= asked.count && Array(calls.prefix(asked.count)) == asked, "run",
        "The script must make the same calls each time it runs. Nothing was changed.")
      if reply["done"] == .bool(true) {
        if rehearsal {
          // Nothing of a rehearsal is kept: the copy closes with the session.
          guard let message = reply["error"].string else {
            try require(
              calls.count == asked.count, "run",
              "The script returned before a call finished. Put await before every sql, search and read.")
            return .object([:])
          }
          return .object([
            "error": .string(message), "errorName": reply["errorName"],
            "hostError": .bool(hostErrors.contains(message)),
          ])
        }
        if let message = reply["error"].string {
          throw SevraError("run", "The script failed: " + message + " Nothing was changed.")
        }
        try require(
          calls.count == asked.count, "run",
          "The script returned before a call finished. Put await before every sql, search and read. Nothing was changed."
        )
        let value = reply["value"]
        try require(
          try value.json().utf8.count <= 12_000, "run_limit",
          "The script returned more than 12,000 bytes. Return a summary or fewer rows. Nothing was changed."
        )
        let requests = reply["requests"].array
        try require(
          requests.count <= 8, "run_limit", "A script can queue at most 8 actions.")
        for request in requests {
          _ = try host("check_action", request)
        }
        var fields = try saveChatSQL(
          session.scratch, results: [], draft: false, token: token,
          requestSourceID: requestSourceID, confirmLarge: confirmLarge,
          cancellation: cancellation
        ).object
        // Nothing was saved: the person is asked first, and the script's value waits with it.
        if fields["status"] == .string("confirmation_required") { return .object(fields) }
        fields["results"] = nil
        fields["value"] = value
        fields["statements"] = .array(statements)
        if !reply["log"].array.isEmpty { fields["log"] = reply["log"] }
        if !requests.isEmpty {
          // Actions run only now, after the script succeeded and its changes are saved.
          fields["actions"] = .array(
            requests.map { request in
              do {
                return .object(["action": request["action"], "result": try host("action", request)])
              } catch {
                return .object([
                  "action": request["action"], "error": .string(error.localizedDescription),
                ])
              }
            })
        }
        return .object(fields)
      }
      let pending = calls.dropFirst(asked.count)
      try require(
        !pending.isEmpty, "run",
        "The script stopped without returning. Put await before every call and end with return. Nothing was changed."
      )
      try require(
        calls.count <= Self.chatRunCallLimit, "run_limit",
        "A script can make at most \(Self.chatRunCallLimit) calls. Do more in each sql statement. Nothing was changed."
      )
      for call in pending {
        do {
          answers.append(.object(["value": try answer(call)]))
        } catch let error as SevraError {
          // The script may catch this. If it does not, it fails and nothing is changed.
          answers.append(.object(["error": .string(error.message)]))
          hostErrors.insert(error.message)
        }
        asked.append(call)
      }
    }
  }
}
