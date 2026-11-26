import Darwin
import Foundation
import SevraAI
import SevraCore

/// `sevra mcp [WORKBOOK]`: the chat tools an outside agent may call, served over MCP on stdio.
///
/// One JSON-RPC message per line. Each tool has the declaration Sevra's chat model is shown,
/// plus a `workbook` path that defaults to the one named at start. A call opens the workbook,
/// runs exactly what `sevra tool` runs and closes it again, so the app and other agents see
/// each change as soon as it is saved. Only protocol messages go to stdout.
enum MCPServer {
  static let versions = ["2025-06-18", "2025-03-26", "2024-11-05"]

  static func serve(_ args: [String], cancellation: Cancellation) async -> Int32 {
    // The client stops the server by closing stdin or with a signal; a blocked read must not
    // keep it alive, and every write is already its own committed transaction.
    for number in [SIGINT, SIGTERM, SIGHUP] { signal(number, SIG_DFL) }
    guard args.count <= 2, args.count < 2 || !args[1].hasPrefix("-") else {
      fputs("Usage: sevra mcp [WORKBOOK]\n", stderr)
      return 2
    }
    var fallback: URL?
    if args.count == 2 {
      let url = URL(fileURLWithPath: args[1]).standardizedFileURL
      guard FileManager.default.fileExists(atPath: url.path) else {
        fputs("sevra mcp: no workbook at \(url.path)\n", stderr)
        return 1
      }
      fallback = url
    }
    while let line = readLine(strippingNewline: true) {
      guard !line.allSatisfy(\.isWhitespace) else { continue }
      if let reply = handle(line, fallback: fallback, cancellation: cancellation) {
        send(reply)
      }
    }
    return 0
  }

  static func send(_ message: Value) {
    guard let text = try? message.json() else { return }
    FileHandle.standardOutput.write(Data((text + "\n").utf8))
  }

  /// The reply to one message, or nil for a notification.
  static func handle(_ line: String, fallback: URL?, cancellation: Cancellation) -> Value? {
    guard let message = try? Value.parseExact(line), case .object = message else {
      return failure(.null, -32700, "The message is not a JSON object.")
    }
    let id = message["id"]
    guard id != .null else { return nil }
    let params = message["params"]
    switch message["method"].string {
    case "initialize":
      let asked = params["protocolVersion"].string ?? ""
      return success(
        id,
        .object([
          "protocolVersion": .string(versions.contains(asked) ? asked : versions[0]),
          "capabilities": .object(["tools": .object(["listChanged": .bool(false)])]),
          "serverInfo": .object(["name": .string("sevra"), "version": .string("0.1.0-dev")]),
          "instructions": .string(AgentGuide.guide),
        ]))
    case "ping":
      return success(id, .object([:]))
    case "tools/list":
      do {
        return success(id, .object(["tools": .array(try tools(fallback: fallback))]))
      } catch {
        return failure(id, -32603, failureDescription(error))
      }
    case "tools/call":
      return success(id, call(params, fallback: fallback, cancellation: cancellation))
    default:
      return failure(id, -32601, "Unknown method: \(message["method"].text).")
    }
  }

  static func tools(fallback: URL?) throws -> [Value] {
    try AgentGuide.declarations().map { tool in
      var schema = tool.parameters.object
      var properties = schema["properties"]?.object ?? [:]
      properties["workbook"] = .object([
        "type": .string("string"),
        "description": .string(
          "Path to the .sevra workbook."
            + (fallback.map { " Defaults to \($0.path)." } ?? "")),
      ])
      schema["type"] = .string("object")
      schema["properties"] = .object(properties)
      if fallback == nil {
        schema["required"] = .array(
          [.string("workbook")] + (schema["required"]?.array ?? []))
      }
      return .object([
        "name": .string(tool.name), "description": .string(tool.description),
        "inputSchema": .object(schema),
      ])
    }
  }

  /// A tool's result, or its error as a tool error the agent can read and correct.
  static func call(_ params: Value, fallback: URL?, cancellation: Cancellation) -> Value {
    func result(_ text: String, error: Bool) -> Value {
      .object([
        "content": .array([.object(["type": .string("text"), "text": .string(text)])]),
        "isError": .bool(error),
      ])
    }
    let name = params["name"].text
    var arguments = params["arguments"].object
    let path = arguments.removeValue(forKey: "workbook")?.string
    guard AgentGuide.tools.contains(name) || ["ask", "finish"].contains(name) else {
      return result(
        "Unknown tool: \(name). The tools are " + AgentGuide.tools.joined(separator: ", ") + ".",
        error: true)
    }
    guard let url = path.map({ URL(fileURLWithPath: $0).standardizedFileURL }) ?? fallback else {
      return result("Name the workbook: give workbook as the path to a .sevra file.", error: true)
    }
    do {
      let book = try Workbook(url, cancellation: cancellation)
      let value = try CLI.callTool(book, name: name, arguments: .object(arguments))
      return result(try AgentGuide.pretty(value), error: false)
    } catch let error as SevraError {
      return result("\(error.code): \(error.message)", error: true)
    } catch {
      return result(failureDescription(error), error: true)
    }
  }

  static func success(_ id: Value, _ result: Value) -> Value {
    .object(["jsonrpc": .string("2.0"), "id": id, "result": result])
  }

  static func failure(_ id: Value, _ code: Int, _ message: String) -> Value {
    .object([
      "jsonrpc": .string("2.0"), "id": id,
      "error": .object(["code": .number(Double(code)), "message": .string(message)]),
    ])
  }
}
