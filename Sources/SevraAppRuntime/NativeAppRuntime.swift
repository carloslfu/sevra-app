import CQuickJS
import Foundation
import SevraAppProtocol
import SevraCore

/// Owned by one serial service queue. This target is never linked into the desktop app.
public final class NativeAppRuntime {
  private var engine: OpaquePointer?
  private var sequence = 0
  private var session: String?
  public init() {}
  deinit { if let engine { sevra_js_destroy(engine) } }
  private func evaluate(_ source: String) throws -> Value {
    guard let engine,
      let output = source.withCString({ sevra_js_eval(engine, $0, source.utf8.count, 500) })
    else {
      throw SevraError("app_runtime", "Cannot allocate the app runtime.")
    }
    defer { sevra_js_free(output) }
    let text = String(cString: output)
    if text.hasPrefix("!") { throw SevraError("app_script", String(text.dropFirst())) }
    return try Value.parse(text)
  }
  public func exchange(_ data: Data) -> Data {
    do {
      let message = try NativeAppWire.decode(data)
      let next = message["sequence"].int ?? -1
      let kind = message["kind"].text
      if kind == "start" {
        try require(
          engine == nil && next == 0 && message["session"].string != nil,
          "app_session", "Start a new isolated connection.")
        let source = message["source"].text
        try require(source.utf8.count <= 524_288, "app_package", "App source exceeds its budget.")
        session = message["session"].text
        engine = sevra_js_create()
        let installed = Bundle.main.resourceURL.flatMap {
          Bundle(url: $0.appendingPathComponent("Sevra_SevraAppRuntime.bundle"))
        }
        let resources = installed ?? Bundle.module
        guard let resource = resources.url(forResource: "sdk", withExtension: "js") else {
          throw SevraError("app_runtime", "The native SDK resource is missing.")
        }
        let sdk = try String(contentsOf: resource, encoding: .utf8)
        _ = try evaluate(sdk + "\nSevra.__initialize(" + (try message["state"].json()) + ");")
        let frame = try evaluate(
          "globalThis.Atomics=undefined;globalThis.SharedArrayBuffer=undefined;\n" + source)
        return try response(frame, sequence: next)
      }
      try require(
        message["session"].text == session && next == sequence + 1,
        "app_session", "Stale or out-of-order app message.")
      try require(
        kind == "events" && message["messages"].array.count <= 128,
        "app_protocol", "Unsupported app request.")
      return try response(
        evaluate("Sevra.__receive(" + message["messages"].json() + ");"), sequence: next)
    } catch {
      // A failed runtime is poisoned: do not resume partially executed commands or effects.
      if let engine {
        sevra_js_destroy(engine)
        self.engine = nil
      }
      return (try? NativeAppWire.encode(.object(["error": .string(error.localizedDescription)])))
        ?? Data()
    }
  }
  private func response(_ frame: Value, sequence: Int) throws -> Data {
    self.sequence = sequence
    return try NativeAppWire.encode(
      .object(["session": .string(session!), "sequence": .number(Double(sequence)), "frame": frame])
    )
  }
}
