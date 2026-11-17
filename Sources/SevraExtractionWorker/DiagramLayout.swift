import CryptoKit
import Foundation
import JavaScriptCore
import SevraCore

enum DiagramLayout {
  static func evaluate(_ url: URL) throws -> Value {
    let input = try FileHandle(forReadingFrom: url)
    defer { try? input.close() }
    guard let bytes = try input.read(upToCount: 24_001), bytes.count <= 24_000 else {
      throw SevraError("diagram_layout", "Layout input exceeds its bound.")
    }
    let value = try Value.parse(String(decoding: bytes, as: UTF8.self))
    guard let count = value["nodes"].int, value["nodes"] == .number(Double(count)),
      (0...100).contains(count), value["edges"].array.count <= 200,
      value["edges"].array.allSatisfy({ edge in
        edge.array.count == 2
          && edge.array.allSatisfy {
            guard let i = $0.int else { return false }
            return $0 == .number(Double(i)) && (0..<count).contains(i)
          }
      })
    else { throw SevraError("diagram_layout", "Invalid anonymous graph.") }
    guard let script = Bundle.module.url(forResource: "elk.bundled", withExtension: "js"),
      let context = JSContext()
    else { throw SevraError("diagram_layout", "Diagram layout is unavailable.") }
    let code = try Data(contentsOf: script, options: .mappedIfSafe)
    let digest = SHA256.hash(data: code).map { String(format: "%02x", $0) }.joined()
    guard digest == "b1032b7cfd2a57c54c6f0e8369d7665e19a579954f7cd20a6dae28f1912ea0d7",
      let source = String(data: code, encoding: .utf8)
    else { throw SevraError("diagram_layout", "The packaged layout module could not be verified.") }

    var failure = false
    var reply: String?
    context.exceptionHandler = { _, _ in failure = true }
    let timer: @convention(block) (JSValue) -> Void = { callback in
      callback.call(withArguments: [])
    }
    let complete: @convention(block) (String) -> Void = { reply = $0 }
    context.setObject(timer, forKeyedSubscript: "setTimeout" as NSString)
    context.setObject(complete, forKeyedSubscript: "complete" as NSString)
    context.setObject(try value.json(), forKeyedSubscript: "input" as NSString)
    context.evaluateScript("globalThis.self = globalThis;")
    context.evaluateScript(source)
    context.evaluateScript(
      """
      const graph = JSON.parse(input);
      const nodes = Array.from({length: graph.nodes}, (_, i) =>
        ({id: 'n' + i, width: \(DiagramGeometry.nodeWidth), height: \(DiagramGeometry.nodeHeight)}));
      const edges = graph.edges.map(([a,b], i) =>
        ({id: 'e' + i, sources: ['n' + a], targets: ['n' + b]}));
      new ELK().layout({id:'root', children:nodes, edges, layoutOptions:{
        'elk.algorithm':'layered', 'elk.direction':'RIGHT', 'elk.edgeRouting':'ORTHOGONAL',
        'elk.spacing.nodeNode':'28', 'elk.layered.spacing.nodeNodeBetweenLayers':'56',
        'elk.layered.thoroughness':'2'
      }}).then(result => {
        const position = ({x, y}) => ({x, y});
        const sorted = (a,b) => Number(a.id.slice(1)) - Number(b.id.slice(1));
        complete(JSON.stringify({
          width: result.width, height: result.height,
          nodes: (result.children || []).sort(sorted).map(position),
          edges: (result.edges || []).sort(sorted).map(edge =>
            (edge.sections || []).map(section => [
              section.startPoint, ...(section.bendPoints || []), section.endPoint
            ].map(position)))
        }));
      }, () => complete(''));
      """)
    guard !failure, let reply, !reply.isEmpty, reply.utf8.count <= 600_000
    else {
      throw SevraError("diagram_layout", "Could not lay out this graph. Inspect its relationships.")
    }
    return try Value.parse(reply)
  }
}
