import Foundation

extension Workbook {
  /// Declining a draft records a decision without ever applying its proposed effect.
  @discardableResult public func withdrawDraft(
    _ id: String, token: String = identifier(),
    actor: ChangeActor = .programmatic("SevraCore.withdraw")
  ) throws
    -> Item
  {
    return try mutation(
      "withdraw_draft", token: token, request: .string(id), actor: actor,
      reading: { try item($0.text) }
    ) {
      try validateDecisionActor(actor)
      let old = try item(id)
      try require(
        try db.scalar("SELECT item_id FROM heads WHERE logical_id=?", [.string(old.logicalID)]).text
          == id,
        "stale_revision",
        "This draft has a newer version. Review the current version before withdrawing.")
      try require(
        old.status == "draft", "not_draft",
        "Only a current draft can be withdrawn. Use Undo for an accepted change.")
      let settled = try settledVersion(old.logicalID, before: old.version)
      // Declining a correction or an edit leaves the previously accepted version in force.
      // Preserve it as the new head, so it stays current and inventory agrees.
      let content = settled?.status == "accepted" ? settled! : old
      let decision = try insertItem(
        category: "source", kind: "decision", title: "Withdraw \(old.title)",
        text: actor.label + " withdrew this draft without applying it.",
        data: try decisionData(id),
        meaning: "actual", status: "accepted", scenario: "actual", inputs: [old.id],
        transformation: "decision-withdraw-v2", controlInputs: decisionInputs())
      let next = try insertItem(
        category: old.category, kind: old.kind, title: content.title, text: content.text,
        data: content.data, meaning: content.meaning,
        status: content.id == old.id ? "rejected" : "accepted", scenario: content.scenario,
        inputs: [old.id, content.id, decision], transformation: "withdraw-draft-v1",
        assetID: content.assetID,
        supersedes: old.id, referenceOrigin: content.id)
      try db.execute(
        "INSERT INTO effects SELECT occurrence,subject,kind,?,quantity,effective FROM effects WHERE item_id=?",
        [.string(next), .string(content.id)])
      return .string(next)
    }
  }
}
