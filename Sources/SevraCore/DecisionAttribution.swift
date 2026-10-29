import Foundation

extension Workbook {
  /// Attribution never grants execution authority. For a caller that already has
  /// authority to make an AI decision, retain its exact accepted rule Source.
  func validateDecisionActor(_ actor: ChangeActor) throws {
    try actor.validate()
    if actor.kind == "ai" {
      guard let identity = actor.policy, let rule = try? item(identity) else {
        throw SevraError("decision_policy", "An AI decision needs an exact saved rule Source.")
      }
      try require(
        rule.id == identity && rule.category == "source" && rule.kind == "rule"
          && rule.meaning == "rule" && rule.status == "accepted", "decision_policy",
        "An AI decision needs an exact accepted rule Source, not a current-head alias or a policy label."
      )
      try require(
        try item(rule.logicalID).id == rule.id, "decision_policy",
        "This rule has a newer version. Review the current rule before another AI decision.")
    }
  }
  func decisionInputs() -> [String] {
    guard let actor = db.changes?.actor, actor.kind == "ai", let policy = actor.policy else {
      return []
    }
    return [policy]
  }
  func decisionData(_ record: String?, additional: [String: Value] = [:]) throws -> Value {
    let actor = db.changes?.actor ?? .programmatic("SevraCore")
    var data = additional
    if let record { data["record"] = .string(record) }
    data["attribution"] = try encoded(actor)
    data["transformation"] = .string("decision-evidence-v2")
    return .object(data)
  }
}
