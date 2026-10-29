import Foundation

extension Workbook {
  /// An admitted producer accounts for its output's existing inputs. A later
  /// correction can also introduce new independent inputs outside that boundary.
  func businessCauseFrontier(_ graph: Value, cancellation: Cancellation) throws
    -> (originals: [String], automatic: [Value], unclassified: [Value])
  {
    let producers = Dictionary(
      uniqueKeysWithValues: graph["automaticProducers"].array.map {
        ($0["invocationSourceID"].text, $0)
      })
    let originals = Set(graph["originalInputCandidates"].array.map(\.text))
    let unclassified = Dictionary(
      uniqueKeysWithValues: graph["unclassifiedOrigins"].array.map {
        ($0["itemID"].text, $0)
      })
    let edges = Dictionary(grouping: graph["edges"].array.filter { $0["traversed"] == .bool(true) })
    {
      $0["child"].text
    }
    var production: [String: Bool] = [:]
    func automaticProduction(_ id: String) -> Bool {
      if let known = production[id] { return known }
      let result =
        producers[id] != nil
        || (edges[id] ?? []).contains {
          $0["roles"].array.contains(.string("producer")) && automaticProduction($0["parent"].text)
        }
      production[id] = result
      return result
    }
    var queue = graph["inputs"].array.map(\.text)
    var visited = Set<String>()
    var leaves = Set<String>()
    var runs: [String: Value] = [:]
    var unknown: [Value] = []
    var index = 0
    while index < queue.count {
      try cancellation.check()
      let id = queue[index]
      index += 1
      guard visited.insert(id).inserted else { continue }
      let inputs = edges[id] ?? []
      if let producer = producers[id] {
        runs[producer["runID"].text] = producer
        continue
      }
      if automaticProduction(id) {
        queue += inputs.filter { $0["roles"].array.contains(.string("producer")) }
          .map { $0["parent"].text }
        continue
      }
      if originals.contains(id) { leaves.insert(id) }
      if let missing = unclassified[id] { unknown.append(missing) }
      queue += inputs.map { $0["parent"].text }
    }
    return (
      leaves.sorted(), runs.values.sorted { $0["runID"].text < $1["runID"].text },
      unknown.sorted { $0["itemID"].text < $1["itemID"].text }
    )
  }
}
