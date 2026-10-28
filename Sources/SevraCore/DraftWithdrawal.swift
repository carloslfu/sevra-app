import Foundation

extension Workbook {
  /// Declining a draft records a decision without ever applying its proposed effect.
  @discardableResult public func withdrawDraft(_ id: String, token: String = identifier()) throws
    -> Item
  {
    let result = try mutation("withdraw_draft", token: token, request: .string(id)) {
      let old = try item(id)
      try require(
        try db.scalar("SELECT item_id FROM heads WHERE logical_id=?", [.string(old.logicalID)]).text
          == id,
        "stale_revision",
        "This draft has a newer version. Review the current version before withdrawing.")
      try require(
        old.status == "draft", "not_draft",
        "Only a current draft can be withdrawn. Use Undo for an accepted change.")
      let decision = try insertItem(
        category: "source", kind: "decision", title: "Withdraw \(old.title)",
        text: "The user withdrew this draft without applying it.",
        data: .object(["record": .string(id)]),
        meaning: "actual", status: "accepted", scenario: "actual", inputs: [],
        transformation: "human-withdraw-v1")
      let next = try insertItem(
        category: old.category, kind: old.kind, title: old.title, text: old.text,
        data: old.data, meaning: old.meaning, status: "rejected", scenario: old.scenario,
        inputs: [old.id, decision], transformation: "withdraw-draft-v1", assetID: old.assetID,
        supersedes: old.id)
      try db.execute(
        "INSERT INTO effects SELECT occurrence,subject,kind,?,quantity,effective FROM effects WHERE item_id=?",
        [.string(next), .string(old.id)])
      return .string(next)
    }
    return try item(result.text)
  }
}
