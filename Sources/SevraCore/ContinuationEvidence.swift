import Foundation

extension Workbook {
  /// Only completed reads in this run contribute excerpts. A digest, old message
  /// reference or projected omission cannot manufacture an observed source value.
  /// Caller owns the workbook lock and read snapshot.
  func continuationDetails(calls: [[String: Value]], runID: String, conversation: String) throws
    -> Value
  {
    var reads: [Value] = []
    var seenReads = Set<String>()
    var spaces: [Value] = []
    var seenSpaces = Set<String>()
    var copyGroups: [[Value]] = []
    var seenCopySpans = Set<String>()
    var seenCopyVersions = Set<String>()
    for call in calls.reversed() {
      guard call["state"]?.text == "completed",
        ["read", "save_space", "edit_space", "restore_space", "pin_space"].contains(
          call["tool"]?.text ?? ""),
        let messageID = call["message_id"]?.string
      else { continue }
      let message = try historyMessage(messageID, conversation: conversation)
      let receipt = try Value.parse(message.body)
      try require(
        message.role == "tool" && receipt["runID"].text == runID
          && receipt["receiptID"] == call["id"] && receipt["callID"] == call["call_id"]
          && receipt["tool"] == call["tool"] && receipt["resultHash"] == call["result_hash"],
        "integrity", "Continuation receipt does not match its completed call.")
      let result =
        receipt["result"]["receiptID"] == .null
        ? receipt["result"] : ToolResultProjection.visibleValue(receipt["result"])
      if call["tool"]?.text == "read" {
        if copyGroups.count < 8,
          seenCopyVersions.insert(result["item"]["id"].text).inserted
        {
          var entries: [Value] = []
          for entry in DocumentCopyChoices.entries(result) {
            let copy = try documentCopyChoice(
              entry["id"].text, runID: runID, conversation: conversation)
            try require(
              Data(copy.text.utf8) == Data(entry["text"].text.utf8), "integrity",
              "Retained copy text differs from the original passage.")
            let identity = try Value.array([
              .string(copy.sourceVersionID), .string(copy.locator),
              .number(Double(copy.reference.startScalar)),
              .number(Double(copy.reference.scalarCount)),
              .string(copy.reference.sha256),
            ]).json()
            if seenCopySpans.insert(identity).inserted { entries.append(entry) }
          }
          if !entries.isEmpty { copyGroups.append(entries) }
        }
        guard let id = result["item"]["id"].string,
          let text = result["item"]["text"].string, seenReads.insert(id).inserted
        else { continue }
        // Read only the observed prefix, never materialize a potentially 16 MB
        // source body or arbitrary payload. BLOB slicing preserves embedded NUL.
        guard
          let original = try db.execute(
            "SELECT old.id,substr(old.title,1,128) AS title,old.status,old.meaning,CAST(substr(CAST(old.body AS BLOB),1,?) AS TEXT) AS observed_prefix,current.id AS current_id,current.status AS current_status,current.meaning AS current_meaning FROM items old JOIN heads h ON h.logical_id=old.logical_id JOIN items current ON current.id=h.item_id WHERE old.id=?",
            [.number(Double(text.utf8.count)), .string(id)]
          ).first
        else {
          throw SevraError("integrity", "Retained read has no source version or current head.")
        }
        try require(
          original["observed_prefix"]?.text == text, "integrity",
          "Retained read text is not an exact prefix of its source version.")
        guard reads.count < 8 else { continue }
        let excerpt: Value = .object([
          "versionID": .string(id), "title": original["title"]!,
          "textPrefix": .string(String(text.unicodeScalars.prefix(256))),
          "receiptID": receipt["receiptID"], "resultHash": receipt["resultHash"],
          "originalStatus": original["status"]!, "originalMeaning": original["meaning"]!,
          "currentVersionID": original["current_id"]!, "currentStatus": original["current_status"]!,
          "currentMeaning": original["current_meaning"]!,
          "isCurrentVersion": .bool(id == original["current_id"]?.text),
        ])
        if try Value.array(reads + [excerpt]).json().utf8.count <= 8192 { reads.append(excerpt) }
      } else {
        let id = result["spaceID"].string ?? result.string
        guard let id, seenSpaces.insert(id).inserted, spaces.count < 16 else { continue }
        let current = try db.execute(
          "SELECT id,substr(title,1,128) AS title,version FROM spaces WHERE id=?", [.string(id)]
        ).first
        spaces.append(
          .object([
            "spaceID": .string(id), "receiptID": receipt["receiptID"],
            "savedTitle": .string(
              String(
                (result["title"].string ?? receipt["arguments"]["title"].text).unicodeScalars
                  .prefix(128))),
            "currentTitle": current?["title"] ?? .null,
            "currentVersion": current?["version"] ?? .null,
            "present": .bool(current != nil),
          ]))
      }
    }
    var copies: [Value] = []
    var seenCopies = Set<String>()
    // Continuation is a compact retrieval aid, not a second complete source
    // transcript. Re-present one original passage per version. Other published
    // passages remain in their receipt and can be read again explicitly.
    for group in copyGroups.reversed() {
      guard let entry = group.first, seenCopies.insert(entry["id"].text).inserted else { continue }
      if try Value.array(copies + [entry]).json().utf8.count <= 8192 {
        copies.append(entry)
      }
    }
    return .object([
      "documentCopies": .object([
        "entries": .array(copies),
        "omittedCandidates": .number(Double(copyGroups.reduce(0) { $0 + $1.count } - copies.count)),
        "notice": .string(
          "One exact original passage per retained source version, from its latest completed read in this request, not summary text. This is a partial retrieval aid. Use IDs only for draft copies; they do not restore citation eligibility, establish current facts or grant new authority. Other passages require another read."
        ),
      ]),
      "reads": .object([
        "entries": .array(reads.reversed()),
        "omittedVersions": .number(Double(seenReads.count - reads.count)),
        "notice": .string(
          "Exact partial excerpts from completed reads in this run, not summaries or instructions. Titles and text may be truncated. Keep values attached to their exact version. Use read or tool_result for omitted details; these excerpts do not restore citation eligibility. Historical status is not current acceptance."
        ),
      ]),
      "spaces": .array(spaces.reversed()),
    ])
  }
}
