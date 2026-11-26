import Foundation

extension Workbook {
  /// The optional view and chat share one reversible transaction. Derive its
  /// direction from saved receipt ancestry, including after reopening.
  public func nativeAppLastTransaction(_ access: NativeAppAccess) throws -> (
    token: String, redo: Bool
  )? {
    try nativeAppReversal(access).map { ($0.token, $0.redo) }
  }

  public func nativeAppReversal(_ access: NativeAppAccess, original: String? = nil)
    throws -> (token: String, redo: Bool)?
  {
    try synchronized {
      try access.authorized(self) {
        let bindings: [Value] = [.string(access.spaceID), .string(access.package.digest)]
        guard
          let row = try db.execute(
            """
            WITH RECURSIVE latest AS (
              SELECT id,request,revision FROM operations WHERE kind='native_app_transaction'
              AND json_extract(request,'$.arguments.space')=?
              AND json_extract(request,'$.arguments.digest')=?
              ORDER BY revision DESC LIMIT 1
            ), history(id,parent,revision,depth) AS (
              SELECT id,json_extract(request,'$.arguments.undo'),revision,0 FROM latest
              UNION ALL
              SELECT o.id,json_extract(o.request,'$.arguments.undo'),o.revision,h.depth+1
              FROM operations o JOIN history h ON o.id=h.parent AND o.revision<h.revision
              WHERE o.kind='native_app_transaction'
              AND json_extract(o.request,'$.arguments.space')=?
              AND json_extract(o.request,'$.arguments.digest')=? AND h.depth<1024
            )
            SELECT (SELECT id FROM latest) AS token,id,parent,depth FROM history ORDER BY depth DESC LIMIT 1
            """, bindings + bindings
          ).first, row["parent"] == .null, let token = row["token"]?.string,
          let depth = row["depth"]?.int, original == nil || row["id"]?.string == original
        else { return nil }
        return (token, depth % 2 == 1)
      }
    }
  }
  @discardableResult public func chatTableTransaction(
    _ id: String, expectedDefinitionID: String, operations: [Value], undo: String? = nil,
    token: String = identifier(), requestSourceID: String? = nil, limit: Int = 64,
    cancellation: Cancellation = .init()
  ) throws -> Value {
    try synchronized(cancellation: cancellation) {
      let table = try dataset(id)
      try require(
        table.definitionID == expectedDefinitionID && !table.archived, "stale_revision",
        "Inspect the current table schema before changing rows.")
      let scoped = try operations.map { operation -> Value in
        try require(
          ["insert", "update", "delete"].contains(operation["op"].text)
            && Set(operation.object.keys).isSubset(of: ["op", "id", "values"]), "table_operation",
          "Use insert/update/delete with exact row IDs and changed values only.")
        return .object(operation.object.merging(["table": .string("table")]) { _, new in new })
      }
      let access = try NativeAppAccess(
        workbook: self, table: table, requestSourceID: requestSourceID, cancellation: cancellation)
      defer { access.revoke() }
      let saved = try db.scalar(
        "SELECT request FROM operations WHERE id=? AND kind='native_app_transaction'",
        [.string(token)]
      ).string
      let base =
        try saved.map { try Value.parse($0)["arguments"]["expectedRevision"].int ?? revision() }
        ?? revision()
      return try nativeAppTransaction(
        access, operations: scoped, expectedRevision: base, token: token, undo: undo,
        limit: limit, deadlineSeconds: SQLScratch.applySeconds)
    }
  }
  public func nativeAppConversationRow(
    _ access: NativeAppAccess, alias: String, id: String, columnLabels: Value? = nil
  ) throws -> Value {
    try synchronized {
      try db.readTransaction {
        try access.authorized(self) {
          let table = try nativeAppBoundTable(access.binding(alias))
          let row = try item(id)
          try require(
            row.id == id && item(row.logicalID).id == id && row.status == "accepted"
              && row.logicalID
                != nativeAppWorksheetPresentation(
                  table, columnLabels: columnLabels
                ).heading
              && db.scalar(
                "SELECT count(*) FROM dataset_rows WHERE dataset_id=? AND logical_id=?",
                [.string(table.id), .string(row.logicalID)]
              ).int == 1,
            "app_row", "Choose a current row from this app's table.")
          return .object([
            "id": .string(row.id), "key": .string(row.logicalID),
            "values": .object(calculatedValues(row, columns: table.columns)),
          ])
        }
      }
    }
  }
  /// Approval covers these exact columns, not future additions to the same table.
  private func nativeAppBoundTable(_ binding: NativeAppDataset) throws -> Dataset {
    guard let id = binding.datasetID else {
      throw SevraError("app_permission", "This app has an unbound table.")
    }
    let table = try dataset(id)
    try require(
      !table.archived && table.columns == binding.columns, "app_schema",
      "The table schema changed; update this app binding and review access again.")
    return table
  }
  /// A native view can use original worksheet labels without changing its raw rows.
  /// Passing nil keeps JS reads and saved-row assertions in worksheet coordinates.
  private func nativeAppWorksheetPresentation(_ table: Dataset, columnLabels: Value?) throws
    -> (labels: Value, heading: String?)
  {
    guard let columnLabels else { return (.null, nil) }
    guard table.columns.count >= 2,
      let original = try db.execute(
        """
        SELECT min(r.logical_id) AS row, json_extract(s.data,'$.columnLabels') AS labels
        FROM datasets d JOIN items s ON s.id=d.source_id AND s.kind='worksheet'
        JOIN dataset_rows r ON r.dataset_id=d.id AND r.ordinal=0 WHERE d.id=?
        GROUP BY s.id HAVING count(*)=1
        """, [.string(table.id)]
      ).first, let row = original["row"]?.string
    else { return (columnLabels, nil) }
    let item = try item(row)
    guard item.status == "accepted" else { return (columnLabels, nil) }
    func matches(_ labels: Value) -> Bool {
      labels.object.count == table.columns.count
        && table.columns.allSatisfy { column in
          guard let label = labels[column.id].string, !label.isEmpty else { return false }
          return item.data[column.id] == .string(label)
        }
    }
    if let stored = original["labels"]?.string,
      let labels = try? Value.parse(stored), matches(labels)
    {
      return (.object(labels.object.merging(columnLabels.object) { _, label in label }), row)
    }
    return (columnLabels, matches(columnLabels) ? row : nil)
  }
  /// Page data stays in native memory when used by a native table. JS queries use the same scope.
  public func nativeAppPage(
    _ access: NativeAppAccess, request: Value, columnLabels: Value? = nil
  ) throws -> Value {
    try synchronized {
      try db.readTransaction {
        try access.authorized(self) {
          let binding = try access.binding(request["table"].text)
          let table = try nativeAppBoundTable(binding)
          let offset = request["offset"].int ?? 0
          let limit = request["limit"].int ?? 100
          try require(
            (0...100_000).contains(offset) && (1...200).contains(limit), "app_query",
            "Invalid page bounds.")
          let presentation = try nativeAppWorksheetPresentation(table, columnLabels: columnLabels)
          let page = try tablePage(
            table.id, offset: offset, limit: limit,
            query: request["search"].string ?? "", sort: request["sort"].string,
            descending: request["descending"] == .bool(true),
            omittingRow: presentation.heading)
          var fields: [String: Value] = [
            "revision": .number(Double(page.revision)),
            "columns": try encoded(page.dataset.columns),
            "total": .number(Double(page.total)), "offset": .number(Double(offset)),
            "rows": .array(
              zip(page.rows, page.values).map { row, values in
                .object([
                  "id": .string(row.id), "key": .string(row.logicalID), "values": .object(values),
                ])
              }),
          ]
          if presentation.labels != .null { fields["columnLabels"] = presentation.labels }
          let result = Value.object(fields)
          try require(
            result.json().utf8.count <= 1_048_576, "app_query",
            "Page exceeds 1 MiB; select fewer rows.")
          return result
        }
      }
    }
  }

  /// Typed query sources name aliases, never raw SQL or an ungranted workbook/table.
  public func nativeAppQuery(_ access: NativeAppAccess, request: Value) throws -> Value {
    try nativeAppQuerySet(access, requests: [request], byteLimit: 1_048_576)[0]
  }

  func nativeAppQuerySet(
    _ access: NativeAppAccess, requests: [Value], byteLimit: Int = 8_388_608,
    captureLineage: Bool = false, cursor: String? = nil, cancellation: Cancellation = .init()
  ) throws -> [Value] {
    try synchronized(cancellation: cancellation) {
      try db.readTransaction {
        try access.authorized(self) {
          let normalized = try requests.map { request -> Value in
            var object = request.object
            object["sources"] = .array(
              try request["sources"].array.map { source in
                var source = try queryObject(source, keys: ["table", "scope", "excelRows"])
                let binding = try access.binding(source.removeValue(forKey: "table")?.text ?? "")
                let table = try nativeAppBoundTable(binding)
                source["datasetID"] = .string(table.id)
                source["definitionID"] = .string(table.definitionID)
                return .object(source)
              })
            return .object(object)
          }
          let result = try queryDatasetSet(
            normalized, cursor: cursor, captureLineage: captureLineage,
            cancellation: cancellation)
          try require(
            try result.reduce(0) { total, value in total + (try value.json().utf8.count) }
              <= byteLimit,
            "app_query", "Narrow this view’s results to fit the app’s query limit.")
          return result
        }
      }
    }
  }

  /// All operations either commit together with existing captured history, or none do.
  public func nativeAppTransaction(
    _ access: NativeAppAccess, operations: [Value], expectedRevision: Int, token: String,
    undo: String? = nil, reverseRedo: Bool? = nil, limit: Int = 64,
    deadlineSeconds: TimeInterval = 3
  ) throws -> Value {
    try require(
      token.utf8.count <= 256 && !token.isEmpty && expectedRevision >= 0,
      "app_command", "A command needs an operation token and base revision.")
    try require(
      operations.count <= limit && (undo == nil ? !operations.isEmpty : operations.isEmpty),
      "app_command", "Use 1 to \(limit) operations, or undo one receipt.")
    let request: Value = .object(
      [
        "space": .string(access.spaceID), "digest": .string(access.package.digest),
        "operations": .array(operations), "expectedRevision": .number(Double(expectedRevision)),
        "undo": undo.map(Value.string) ?? .null,
      ].merging(reverseRedo.map { ["reverseRedo": .bool($0)] } ?? [:]) { _, new in new })
    // The guard also executes for idempotent replays: a cached receipt never bypasses revocation.
    return try synchronized {
      try access.authorized(self) {
        try mutation(
          "native_app_transaction", token: token, request: request, expected: expectedRevision,
          actor: access.tableOperation
            ? ChangeAttribution.actor ?? .programmatic("Sevra.chat-table")
            : .programmatic("native-app:" + access.package.digest),
          deadlineSeconds: deadlineSeconds, commitGuard: { try access.authorized(self) {} }
        ) {
          var requested = operations
          var behaviorCommand = false
          if let undo {
            if let reverseRedo {
              let current = try nativeAppLastTransaction(access)
              try require(
                current?.token == undo && current?.redo == reverseRedo, "app_undo",
                "A different transaction is now available. Inspect the latest saved change.")
            }
            guard
              let original = try db.execute(
                "SELECT request,result FROM operations WHERE id=? AND kind='native_app_transaction'",
                [.string(undo)]
              ).first
            else {
              throw SevraError("app_undo", "That app command receipt is unavailable.")
            }
            let priorRequest = try Value.parse(original["request"]!.text)["arguments"]
            try require(
              priorRequest["space"] == .string(access.spaceID)
                && priorRequest["digest"] == .string(access.package.digest),
              "app_undo", "This receipt belongs to another app version.")
            let priorResult = try Value.parse(original["result"]!.text)
            requested = priorResult["inverse"].array
            behaviorCommand = priorResult["excelAction"] == .bool(true)
          } else if operations.contains(where: { $0["op"] == .string("excel_action") }) {
            try require(
              operations.count == 1
                && Set(operations[0].object.keys).isSubset(of: ["op", "action", "arguments"]),
              "excel_action",
              "Submit one excel_action operation with only op, action and arguments. Remove writes, table, id and values; write permissions come from the saved action declaration."
            )
            requested = try excelActionOperations(
              access, action: operations[0]["action"].text,
              arguments: operations[0]["arguments"] == .null
                ? .object([:]) : operations[0]["arguments"])
            behaviorCommand = true
          }
          let evidence = try insertItem(
            category: "source", kind: "observation", title: access.package.name + " update",
            text: access.tableOperation
              ? "A conversation operation submitted these values."
              : "An authorized native app submitted these values.", data: request,
            meaning: "actual", status: "accepted", scenario: "actual",
            inputs: access.requestSourceID.map { [$0] } ?? [],
            transformation: "native-app-command-v1")
          var output: [Value] = []
          var inverse: [Value] = []
          // A large change saves its updates as one edit, with one correction Source,
          // where the loop below would write one for every row.
          var together: Set<Int> = []
          if requested.count > 64 {
            let updates = requested.enumerated().filter { $0.element["op"].text == "update" }
            if let alias = updates.first?.element["table"].text,
              updates.allSatisfy({ $0.element["table"].text == alias })
            {
              let table = try nativeAppBoundTable(try access.binding(alias, write: true))
              let recalculating = try recalculatingColumns(table.id)
              let formulas = Set(table.columns.filter { $0.formula != nil }.map(\.id))
              let olds = try updates.map { update -> Item in
                let old = try item(update.element["id"].text)
                try require(
                  old.id == update.element["id"].text && item(old.logicalID).id == old.id,
                  "stale_revision", "This row changed. Refresh before editing.")
                return old
              }
              let saved = try applyRows(
                table.id,
                edits: zip(olds, updates).map { old, update in
                  RowEdit(
                    id: old.id,
                    values: Self.current(old, table).merging(update.element["values"].object) {
                      _, new in new
                    })
                },
                request: .object([
                  "token": .string(token), "rows": .number(Double(updates.count)),
                ]), deferSheetCalculation: true)["items"].array
              for (index, update) in updates.enumerated() {
                output.append(.object(["id": saved[index]]))
                let computed = formulas.union(recalculating[olds[index].logicalID] ?? [])
                let previous = update.element["values"].object.keys
                  .filter { !computed.contains($0) }
                  .reduce(into: [String: Value]()) { $0[$1] = olds[index].data[$1] }
                inverse.insert(
                  .object([
                    "op": .string("update"), "table": .string(alias), "id": saved[index],
                    "values": .object(previous),
                  ]), at: 0)
                together.insert(update.offset)
              }
            }
          }
          for (offset, operation) in requested.enumerated() where !together.contains(offset) {
            let alias = operation["table"].text
            let binding = try access.binding(alias, write: true)
            let table = try nativeAppBoundTable(binding)
            let kind = operation["op"].text
            switch kind {
            case "insert":
              let values = try newRowValues(operation["values"].object, table: table)
              try validateValues(values, columns: table.columns)
              let id = try insertItem(
                category: "record", kind: "row", title: table.title + " entry",
                text: values.sorted { $0.key < $1.key }.map { "\($0.key): \($0.value.text)" }
                  .joined(separator: "\n"),
                data: .object(values), meaning: "actual", status: "accepted", scenario: "actual",
                inputs: [evidence], transformation: "native-app-insert-v1")
              let ordinal =
                (try db.scalar(
                  "SELECT MAX(ordinal) FROM dataset_rows WHERE dataset_id=?", [.string(table.id)]
                ).int ?? -1) + 1
              try insertDatasetMember(table.id, ordinal: ordinal, logicalID: item(id).logicalID)
              output.append(.object(["id": .string(id)]))
              inverse.insert(
                .object(["op": .string("delete"), "table": .string(alias), "id": .string(id)]),
                at: 0)
            case "update", "delete", "restore":
              try require(
                kind != "restore" || undo != nil, "app_command",
                "Restore is available only through a saved undo receipt.")
              let old = try item(operation["id"].text)
              try require(
                (behaviorCommand && undo == nil || old.id == operation["id"].text)
                  && item(old.logicalID).id == old.id,
                "stale_revision", "This row changed. Refresh before editing.")
              let member = try db.execute(
                "SELECT ordinal FROM dataset_rows WHERE dataset_id=? AND logical_id=?",
                [.string(table.id), .string(old.logicalID)]
              ).first
              try require(
                kind == "restore" ? member == nil : member != nil, "app_permission",
                "This row is not in the expected table state.")
              if kind == "update" {
                let values = Self.current(old, table).merging(operation["values"].object) {
                  _, new in new
                }
                let result = try applyRows(
                  table.id, edits: [.init(id: old.id, values: values)], request: request,
                  deferSheetCalculation: true)
                let id = result["items"].array[0]
                output.append(.object(["id": id]))
                // Undo the edited inputs, then let the same formula engine recalculate.
                // Restoring a full old row would try to overwrite protected formula outputs.
                let computed = Set(table.columns.filter { $0.formula != nil }.map(\.id))
                  .union(try recalculatingColumns(table.id)[old.logicalID] ?? [])
                let previous = operation["values"].object.keys.filter { !computed.contains($0) }
                  .reduce(into: [String: Value]()) { $0[$1] = old.data[$1] }
                inverse.insert(
                  .object([
                    "op": .string("update"), "table": .string(alias), "id": id,
                    "values": .object(previous),
                  ]), at: 0)
              } else {
                let restore = kind == "restore"
                let id = try insertItem(
                  category: old.category, kind: old.kind, title: old.title, text: old.text,
                  data: old.data, meaning: old.meaning, status: restore ? "accepted" : "rejected",
                  scenario: old.scenario,
                  inputs: [old.id, evidence], transformation: "native-app-" + kind + "-v1",
                  supersedes: old.id)
                if restore {
                  let ordinal = operation["ordinal"].int ?? 0
                  try insertDatasetMember(table.id, ordinal: ordinal, logicalID: old.logicalID)
                  inverse.insert(
                    .object(["op": .string("delete"), "table": .string(alias), "id": .string(id)]),
                    at: 0)
                } else {
                  let schema = try db.managedSchema(table.id)
                  try db.execute(
                    "DELETE FROM " + ChangeFormat.quote(schema.table) + " WHERE _sevra_logical=?",
                    [.string(old.logicalID)])
                  try db.execute(
                    "DELETE FROM dataset_rows WHERE dataset_id=? AND logical_id=?",
                    [.string(table.id), .string(old.logicalID)])
                  inverse.insert(
                    .object([
                      "op": .string("restore"), "table": .string(alias), "id": .string(id),
                      "ordinal": member!["ordinal"]!,
                    ]), at: 0)
                }
                output.append(.object(["id": .string(id)]))
              }
            default: throw SevraError("app_command", "Unknown app command: " + kind)
            }
          }
          // Every native transaction is atomic, including ordinary multi-table edits and Undo.
          // Calculate only the final input state, then return its final immutable row versions.
          try recalculateChangedSheets()
          if !inverse.isEmpty {
            // Derived writes may supersede an edited row. Undo must target its final head.
            inverse = try inverse.map { operation in
              var fields = operation.object
              fields["id"] = .string(try item(operation["id"].text).logicalID)
              fields["id"] = .string(try item(fields["id"]!.text).id)
              return .object(fields)
            }
            output = try output.map { result in
              .object(["id": .string(try item(item(result["id"].text).logicalID).id)])
            }
          }
          return .object([
            "token": .string(token), "revision": .number(Double(expectedRevision + 1)),
            "results": .array(output), "inverse": .array(inverse),
            "excelAction": .bool(behaviorCommand),
          ])
        }
      }
    }
  }
}

extension Workbook {
  /// A saved row's values for the table's columns today. An older row version can still
  /// carry a column the table has since dropped, which an edit must not write back.
  static func current(_ row: Item, _ table: Dataset) -> [String: Value] {
    let known = Set(table.columns.map(\.id))
    return row.data.object.filter { known.contains($0.key) }
  }
}

extension Workbook {
  /// Read after a workbook revision changes. Row identity is immutable, so a new head changes
  /// max(rowid); removals change count. Schema versions cover calculated-column changes.
  public func nativeAppFingerprints(_ access: NativeAppAccess) throws -> [String: String] {
    try synchronized {
      try db.readTransaction {
        try access.authorized(self) {
          var result: [String: String] = [:]
          for (alias, binding) in access.package.datasets {
            let table = try nativeAppBoundTable(binding)
            let row = try db.execute(
              "SELECT COUNT(*) AS n,MAX(i.rowid) AS last FROM dataset_rows d JOIN heads h ON h.logical_id=d.logical_id JOIN items i ON i.id=h.item_id WHERE d.dataset_id=?",
              [.string(table.id)]
            ).first!
            result[alias] = "\(table.definitionID):\(row["n"]!.text):\(row["last"]?.text ?? "")"
          }
          return result
        }
      }
    }
  }
}
