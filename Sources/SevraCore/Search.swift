import Foundation

extension Workbook {
  static func searchTerms(_ query: String) throws -> String {
    try require(query.utf8.count <= 2048, "query_limit", "Search is limited to 2048 bytes.")
    return query.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
      .prefix(24).map { "\"" + $0 + "\"*" }.joined(separator: " AND ")
  }
  func insertChunks(_ item: String, title: String, chunks: [Chunk]) throws {
    let metadata = try self.item(item)
    let current =
      try db.scalar("SELECT count(*) FROM heads WHERE item_id=?", [.string(item)]).int == 1
    var inserted = 0
    for chunk in chunks {
      let characters = Array(chunk.text)
      let total = max(1, characters.count)
      for start in stride(from: 0, to: total, by: 2400) {
        let end = min(characters.count, start + 2800)
        let body = start < end ? String(characters[start..<end]) : ""
        inserted += 1
        try db.execute(
          "INSERT INTO chunks(item_id,title,body,locator,is_current,kind,meaning,status,scenario) VALUES(?,?,?,?,?,?,?,?,?)",
          [
            .string(item), .string(title), .string(body),
            .string(chunk.locator + "; offset=\(start)"), .bool(current), .string(metadata.kind),
            .string(metadata.meaning), .string(metadata.status), .string(metadata.scenario),
          ])
      }
    }
    if inserted > 1 {
      try db.execute(
        "INSERT INTO meta VALUES('has_multichunk','1') ON CONFLICT(key) DO UPDATE SET value='1'")
    }
  }
}
extension Workbook {
  public func index(
    _ id: String, chunks: [Chunk], state: String = "ready", detail: String = "",
    parser: String = "native-v1"
  ) throws {
    _ = try mutation("index", request: .string(id)) {
      let record = try item(id)
      try db.execute("DELETE FROM chunks WHERE item_id=?", [.string(id)])
      try insertChunks(id, title: record.title, chunks: chunks.isEmpty ? [Chunk("")] : chunks)
      try db.execute(
        "INSERT INTO extraction VALUES(?,?,?,?,?) ON CONFLICT(item_id) DO UPDATE SET state=excluded.state,detail=excluded.detail,parser=excluded.parser,updated=excluded.updated",
        [.string(id), .string(state), .string(detail), .string(parser), .string(timestamp())])
      return .string(id)
    }
  }
  public func extractionStatus(_ id: String) throws -> Value {
    try synchronized {
      .object(
        try db.execute("SELECT * FROM extraction WHERE item_id=?", [.string(id)]).first ?? [:])
    }
  }
  public func search(
    _ query: String, kind: String? = nil, meaning: String? = nil, historical: Bool = false,
    limit: Int = 30, offset: Int = 0, cursor: String? = nil, status: String? = nil,
    scenario: String? = nil, cancellation: Cancellation = .init(), deadlineSeconds: TimeInterval = 3
  ) throws -> SearchPage {
    try synchronized {
      try db.budget(cancellation: cancellation, seconds: deadlineSeconds) {
        try db.readTransaction {
          let terms = try Self.searchTerms(query)
          let count = min(max(limit, 1), 100)
          let skip = min(max(offset, 0), 10_000)
          let rev = try revision()
          let identity = try Value.object([
            "q": .string(query), "kind": kind.map(Value.string) ?? .null,
            "meaning": meaning.map(Value.string) ?? .null, "historical": .bool(historical),
            "status": status.map(Value.string) ?? .null,
            "scenario": scenario.map(Value.string) ?? .null,
          ]).json()
          var afterRank: Value = .null
          var afterID: Value = .number(0)
          if let cursor {
            guard cursor.utf8.count <= 8192, let data = Data(base64Encoded: cursor),
              let token = try? Value.parse(String(decoding: data, as: UTF8.self))
            else { throw SevraError("cursor", "Invalid search cursor.") }
            try require(
              token["revision"].int == rev && token["query"].text == identity, "stale_cursor",
              "The workbook or query changed. Start a fresh search.")
            guard case .number(let rank) = token["rank"], rank.isFinite, let id = token["id"].int
            else {
              throw SevraError("cursor", "Invalid cursor position.")
            }
            afterRank = .number(rank)
            afterID = .number(Double(id))
          }
          let incomplete =
            try db.scalar(
              "SELECT count(*) FROM extraction e JOIN heads h ON h.item_id=e.item_id WHERE state!='ready'"
            ).int ?? 0
          if terms.isEmpty {
            return SearchPage(hits: [], incomplete: incomplete, nextOffset: nil, nextCursor: nil)
          }
          let current = historical ? "" : " AND c.is_current=1 "
          var filters = ""
          var filtersArgs: [Value] = []
          for (column, value) in [
            ("kind", kind), ("meaning", meaning), ("status", status), ("scenario", scenario),
          ] {
            if let value {
              filters += " AND c.\(column)=?"
              filtersArgs.append(.string(value))
            }
          }
          let lexical =
            "SELECT c.id,c.item_id,bm25(search_fts,8,1) AS score FROM search_fts JOIN chunks c ON c.id=search_fts.rowid WHERE search_fts MATCH ? \(current) \(filters)"
          var args: [Value] = [.string(terms)] + filtersArgs
          var filename = ""
          if query.count >= 3 {
            filename =
              " SELECT c.id,c.item_id,-0.5 AS score FROM names_fts JOIN chunks c ON c.id=names_fts.rowid WHERE names_fts MATCH ? \(current) \(filters)"
            args +=
              [.string("\"" + query.replacingOccurrences(of: "\"", with: "\"\"") + "\"")]
              + filtersArgs
          }
          // The minimum aggregate keeps the matching passage associated with its best score.
          // Keyset pagination is revision-bound so edits cannot silently skip/repeat evidence.
          let multi = try db.scalar("SELECT value FROM meta WHERE key='has_multichunk'").text == "1"
          let merged =
            filename.isEmpty
            ? "SELECT * FROM lexical"
            : "SELECT * FROM lexical UNION ALL SELECT * FROM (\(filename)) named WHERE NOT EXISTS(SELECT 1 FROM lexical l WHERE l.id=named.id)"
          let evidence =
            multi
            ? "SELECT id,item_id,min(score) AS score FROM candidates GROUP BY item_id"
            : "SELECT * FROM candidates"
          let sql =
            "WITH lexical AS MATERIALIZED (\(lexical)), candidates AS (\(merged)), evidence AS (\(evidence)), selected AS (SELECT * FROM evidence WHERE (? IS NULL OR score>? OR (score=? AND id>?)) ORDER BY score,id LIMIT ? OFFSET ?) SELECT selected.*,c.title,substr(c.body,1,240) AS snippet,c.locator FROM selected JOIN chunks c ON c.id=selected.id ORDER BY selected.score,selected.id"
          args += [
            afterRank, afterRank, afterRank, afterID, .number(Double(count + 1)),
            .number(Double(cursor == nil ? skip : 0)),
          ]
          let rows = try db.execute(sql, args)
          let hits = try rows.prefix(count).map { r -> SearchHit in
            guard let id = r["id"]?.int, let rank = Double(r["score"]?.text ?? ""), rank.isFinite
            else {
              throw SevraError("integrity", "Invalid search index row.")
            }
            let snippet =
              try db.scalar(
                "SELECT snippet(search_fts,1,\'\',\'\',\' … \',36) FROM search_fts WHERE rowid=? AND search_fts MATCH ?",
                [.number(Double(id)), .string(terms)]
              ).string ?? r["snippet"]!.text
            return SearchHit(
              id: id, itemID: r["item_id"]!.text, title: r["title"]!.text, snippet: snippet,
              locator: r["locator"]!.text, rank: rank)
          }
          var next: String?
          if rows.count > count, let last = hits.last {
            next = Data(
              try Value.object([
                "query": .string(identity), "revision": .number(Double(rev)),
                "rank": .number(last.rank), "id": .number(Double(last.id)),
              ]).json().utf8
            ).base64EncodedString()
          }
          return SearchPage(
            hits: hits, incomplete: incomplete, nextOffset: next == nil ? nil : skip + count,
            nextCursor: next)
        }
      }
    }
  }
  public func readChunks(_ id: String, offset: Int = 0, limit: Int = 8) throws -> [Value] {
    try synchronized {
      try db.execute(
        "SELECT id,body,locator FROM chunks WHERE item_id=? ORDER BY id LIMIT ? OFFSET ?",
        [.string(id), .number(Double(min(max(limit, 1), 12))), .number(Double(max(offset, 0)))]
      ).map(Value.object)
    }
  }
  public func rebuildSearch() throws {
    _ = try mutation("rebuild_search") {
      try db.execute(
        "UPDATE chunks SET is_current=EXISTS(SELECT 1 FROM heads h WHERE h.item_id=chunks.item_id)")
      try db.execute("INSERT INTO search_fts(search_fts) VALUES('rebuild')")
      try db.execute("INSERT INTO names_fts(names_fts) VALUES('rebuild')")
      return .bool(true)
    }
  }
}

extension Workbook {
  public func searchFacets() throws -> Value {
    try synchronized {
      var result: [String: Value] = [:]
      for key in ["kind", "meaning", "status", "scenario"] {
        result[key] = .array(
          try db.execute("SELECT DISTINCT \(key) AS value FROM items ORDER BY \(key) LIMIT 100").map
          { $0["value"] ?? .null })
      }
      return .object(result)
    }
  }
}
