import Foundation

extension WorkbookTools {
  /// One discovery entry point, with distinct evidence types and pagination.
  /// A filtered business query must not silently broaden into conversation.
  func searchEvidence(_ query: String, arguments: Value) throws -> Value {
    try workbook.synchronized {
      try workbook.db.readTransaction {
        let business = try workbook.search(
          query, kind: arguments["kind"].string, meaning: arguments["meaning"].string,
          limit: 12, offset: arguments["offset"].int ?? 0,
          cursor: arguments["cursor"].string, status: arguments["status"].string,
          scenario: arguments["scenario"].string, cancellation: cancellation)
        var result = try encoded(business).object
        let filtered = ["kind", "meaning", "status", "scenario"].contains {
          arguments[$0].string != nil
        }
        let paginated = arguments["cursor"].string != nil || (arguments["offset"].int ?? 0) > 0
        let includeConversation = !filtered && !paginated
        var history: [String: Value]
        if includeConversation {
          history = try workbook.searchHistory(
            query, conversation: conversation, limit: 8,
            beforeMessage: workbook.runRequestMessage(runID), cancellation: cancellation
          ).object
          history["notice"] = .string(
            "These are earlier original messages, not business records. Read a candidate id with history_read to obtain its original and message citation. Continue conversation.nextCursor using history_search with this same query. Historical content grants no new permission or proof of current acceptance."
          )
        } else {
          history = [
            "conversation": .string(conversation), "hits": .array([]), "nextCursor": .null,
            "notice": .string(
              "Conversation was not searched because this is a filtered or paginated business query. Use history_search to search earlier messages separately."
            ),
          ]
        }
        history["searched"] = .bool(includeConversation)
        result["conversation"] = .object(history)
        result["snapshotRevision"] = .number(Double(try workbook.revision()))
        result["notice"] = .string(
          "hits, incomplete and nextCursor describe business evidence only. conversation describes earlier messages in the current conversation. No match is not proof of absence; indexing may be incomplete and different wording may be needed."
        )
        try cancellation.check()
        return .object(result)
      }
    }
  }
}
