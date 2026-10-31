import SevraCore

/// Bounded exploration is not proof of coverage. A stalled answer should retain
/// time to calculate and explain what its inspected originals actually support.
package struct DiscoveryBudget {
  package init() {}
  private var candidates = Set<String>()
  private(set) var unchangedSearches = 0
  package var stalled: Bool { unchangedSearches >= 3 }
  package mutating func observe(tool: String, result: Value, inspected: Set<String>) {
    guard ["search", "history_search"].contains(tool) else { return }
    candidates.formUnion(inspected)
    let found: Set<String>
    if tool == "search" {
      found = Set(result["hits"].array.compactMap { $0["itemID"].string })
        .union(
          result["conversation"]["hits"].array.compactMap {
            $0["id"].string.map { "message:" + $0 }
          })
    } else {
      found = Set(result["hits"].array.compactMap { $0["id"].string.map { "message:" + $0 } })
    }
    unchangedSearches = found.subtracting(candidates).isEmpty ? unchangedSearches + 1 : 0
    candidates.formUnion(found)
  }
}
