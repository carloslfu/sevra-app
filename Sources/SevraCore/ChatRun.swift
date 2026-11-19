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

  public func chatRun(
    code: String, readOnly: Bool, token: String, requestSourceID: String?,
    host: (_ method: String, _ arguments: Value) throws -> Value,
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
      try ChatSQLSession(self, readOnly: readOnly, cancellation: cancellation)
    }
    defer { session.close() }
    // A script works on rows, so it reads more of them than a model is shown, as numbers.
    session.scratch.shownRows = 5_000
    session.scratch.shownBytes = 1_000_000
    session.scratch.numbers = true
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
        let result = try synchronized(cancellation: cancellation) {
          try session.run([statement], inputs: arguments["values"].object)
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
      case "search", "read": return try host(call["method"].text, arguments)
      default: throw SevraError("run", "A script can call sql, search, read and action.")
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
          "today": .string(day.string(from: now)),
        ]), cancellation: cancellation)
      let calls = reply["calls"].array
      try require(
        calls.count >= asked.count && Array(calls.prefix(asked.count)) == asked, "run",
        "The script must make the same calls each time it runs. Nothing was changed.")
      if reply["done"] == .bool(true) {
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
          requestSourceID: requestSourceID, cancellation: cancellation
        ).object
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
        }
        asked.append(call)
      }
    }
  }
}
