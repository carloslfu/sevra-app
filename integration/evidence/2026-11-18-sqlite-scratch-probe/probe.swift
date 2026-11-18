// CPU probe of the system SQLite mechanics the general chat tools plan relies on.
// Run: swift probe.swift > results.json   (no model, no app code, in-memory databases only)
import Foundation
import SQLite3

let SQLITE_TRANSIENT_FN = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
var report: [String: Any] = ["sqliteVersion": String(cString: sqlite3_libversion())]

// ---------- helpers ----------
struct Row { var values: [String]; var types: [String] }
func typeName(_ t: Int32) -> String {
  switch t { case SQLITE_INTEGER: return "integer"; case SQLITE_FLOAT: return "real"
  case SQLITE_TEXT: return "text"; case SQLITE_BLOB: return "blob"; default: return "null" }
}
@discardableResult func run(_ db: OpaquePointer?, _ sql: String) -> (rc: Int32, rows: [Row], error: String) {
  var rows: [Row] = []
  var rest: UnsafePointer<CChar>? = nil
  var rc: Int32 = SQLITE_OK
  var err = ""
  sql.withCString { start in
    var cursor: UnsafePointer<CChar>? = start
    while let c = cursor, c.pointee != 0 {
      var stmt: OpaquePointer? = nil
      rc = sqlite3_prepare_v2(db, c, -1, &stmt, &rest)
      if rc != SQLITE_OK { err = String(cString: sqlite3_errmsg(db)); return }
      cursor = rest
      guard let stmt else { continue }
      while true {
        rc = sqlite3_step(stmt)
        if rc == SQLITE_ROW {
          var values: [String] = [], types: [String] = []
          for i in 0..<sqlite3_column_count(stmt) {
            let t = sqlite3_column_type(stmt, i)
            types.append(typeName(t))
            if t == SQLITE_FLOAT {
              values.append(String(sqlite3_column_double(stmt, i).bitPattern, radix: 16) + ":" + "\(sqlite3_column_double(stmt, i))")
            } else if t == SQLITE_NULL { values.append("NULL") } else {
              values.append(String(cString: sqlite3_column_text(stmt, i)))
            }
          }
          rows.append(Row(values: values, types: types))
        } else { break }
      }
      if rc != SQLITE_DONE { err = String(cString: sqlite3_errmsg(db)); sqlite3_finalize(stmt); return }
      rc = SQLITE_OK
      sqlite3_finalize(stmt)
    }
  }
  return (rc, rows, err)
}
func flat(_ r: (rc: Int32, rows: [Row], error: String)) -> [String: Any] {
  ["rc": Int(r.rc), "error": r.error, "rows": r.rows.map { $0.values }, "types": r.rows.first?.types ?? []]
}
func open() -> OpaquePointer? { var db: OpaquePointer? = nil; sqlite3_open(":memory:", &db); return db }

// ---------- decimal collation ----------
func decCompare(_ a: String, _ b: String) -> Int32 {
  guard let x = Decimal(string: a), let y = Decimal(string: b) else { return a < b ? -1 : (a > b ? 1 : 0) }
  return x < y ? -1 : (x > y ? 1 : 0)
}
func installCollation(_ db: OpaquePointer?) {
  sqlite3_create_collation(db, "DEC", SQLITE_UTF8, nil) { _, n1, p1, n2, p2 in
    let a = String(decoding: UnsafeRawBufferPointer(start: p1, count: Int(n1)), as: UTF8.self)
    let b = String(decoding: UnsafeRawBufferPointer(start: p2, count: Int(n2)), as: UTF8.self)
    return decCompare(a, b)
  }
}

// ---------- exact registry: a double returned by an exact function maps back to its exact text ----------
var registry: [UInt64: Set<String>] = [:]
func register(_ d: Decimal) -> Double {
  let text = "\(d)"
  let value = Double(text) ?? .nan
  registry[value.bitPattern, default: []].insert(text)
  return value
}
func exactArgument(_ v: OpaquePointer?) -> Decimal? {
  switch sqlite3_value_type(v) {
  case SQLITE_INTEGER: return Decimal(sqlite3_value_int64(v))
  case SQLITE_TEXT: return Decimal(string: String(cString: sqlite3_value_text(v)))
  case SQLITE_FLOAT:
    let bits = sqlite3_value_double(v).bitPattern
    if let set = registry[bits], set.count == 1, let d = Decimal(string: set.first!) { return d }
    return nil
  default: return nil
  }
}
var sumStates: [Int: (total: Decimal, exact: Bool, float: Double, count: Int)] = [:]
var nextState = 1
func installExact(_ db: OpaquePointer?) {
  sqlite3_create_function_v2(db, "dec_mul", 2, SQLITE_UTF8 | SQLITE_DETERMINISTIC, nil, { ctx, _, args in
    guard let a = exactArgument(args![0]), let b = exactArgument(args![1]) else {
      sqlite3_result_error(ctx, "dec_mul needs exact inputs", -1); return
    }
    sqlite3_result_double(ctx, register(a * b))
  }, nil, nil, nil)
  // A window-capable override of the built-in sum: exact while every input is exact.
  let step: @convention(c) (OpaquePointer?, Int32, UnsafeMutablePointer<OpaquePointer?>?) -> Void = { ctx, _, args in
    let slot = sqlite3_aggregate_context(ctx, 8)!.assumingMemoryBound(to: Int.self)
    if slot.pointee == 0 { slot.pointee = nextState; sumStates[nextState] = (0, true, 0, 0); nextState += 1 }
    var s = sumStates[slot.pointee]!
    if sqlite3_value_type(args![0]) != SQLITE_NULL {
      s.count += 1
      s.float += sqlite3_value_double(args![0])
      if let d = exactArgument(args![0]) { s.total += d } else { s.exact = false }
    }
    sumStates[slot.pointee] = s
  }
  let inverse: @convention(c) (OpaquePointer?, Int32, UnsafeMutablePointer<OpaquePointer?>?) -> Void = { ctx, _, args in
    let slot = sqlite3_aggregate_context(ctx, 8)!.assumingMemoryBound(to: Int.self)
    guard slot.pointee != 0, var s = sumStates[slot.pointee] else { return }
    if sqlite3_value_type(args![0]) != SQLITE_NULL {
      s.count -= 1
      s.float -= sqlite3_value_double(args![0])
      if let d = exactArgument(args![0]) { s.total -= d }
    }
    sumStates[slot.pointee] = s
  }
  let value: @convention(c) (OpaquePointer?) -> Void = { ctx in
    let slot = sqlite3_aggregate_context(ctx, 0)?.assumingMemoryBound(to: Int.self)
    guard let slot, slot.pointee != 0, let s = sumStates[slot.pointee], s.count > 0 else { sqlite3_result_null(ctx); return }
    if s.exact { sqlite3_result_double(ctx, register(s.total)) } else { sqlite3_result_double(ctx, s.float) }
  }
  sqlite3_create_window_function(db, "sum", 1, SQLITE_UTF8, nil, step, value, value, inverse, nil)
}
func exactText(_ cell: String) -> String {
  // cell is "bits:double" for a real result
  guard let bits = UInt64(cell.split(separator: ":").first ?? "", radix: 16) else { return cell }
  if let set = registry[bits], set.count == 1 { return "exact " + set.first! }
  return "approximate " + String(cell.split(separator: ":").last ?? "")
}

// ---------- A. authorizer: table discovery and schema statements ----------
var events: [String] = []
var denyNames: Set<String> = []
var denyCodes: Set<Int32> = []
func installAuthorizer(_ db: OpaquePointer?) {
  sqlite3_set_authorizer(db, { _, code, a, b, c, d in
    let s = { (p: UnsafePointer<CChar>?) in p.map { String(cString: $0) } ?? "" }
    events.append("\(code)|\(s(a))|\(s(b))|\(s(c))|\(s(d))")
    if denyCodes.contains(code) { return SQLITE_DENY }
    // Deny direct access to host tables; allow it from inside a host trigger (d names the trigger).
    if denyNames.contains(s(a)) && d == nil && [SQLITE_READ, SQLITE_INSERT, SQLITE_UPDATE, SQLITE_DELETE, SQLITE_DROP_TABLE, SQLITE_ALTER_TABLE].contains(code) { return SQLITE_DENY }
    if code == SQLITE_ALTER_TABLE && denyNames.contains(s(b)) { return SQLITE_DENY }
    if code == SQLITE_DROP_TRIGGER && s(a).hasPrefix("host_") { return SQLITE_DENY }
    return SQLITE_OK
  }, nil)
}
func prepareOnly(_ db: OpaquePointer?, _ sql: String) -> [String: Any] {
  events = []
  var stmt: OpaquePointer? = nil
  let rc = sqlite3_prepare_v2(db, sql, -1, &stmt, nil)
  let err = rc == SQLITE_OK ? "" : String(cString: sqlite3_errmsg(db))
  sqlite3_finalize(stmt)
  return ["sql": sql, "rc": Int(rc), "error": err, "events": events]
}
do {
  let db = open(); installAuthorizer(db)
  run(db, "CREATE TABLE t1(id, x); CREATE TABLE t2(id, y); CREATE TABLE t3(z); CREATE VIEW v1 AS SELECT id, y FROM t2;")
  var a: [[String: Any]] = []
  for sql in [
    "SELECT a.x, b.y FROM t1 a JOIN t2 b ON a.id = b.id WHERE a.x > (SELECT max(z) FROM t3)",
    "SELECT count(*) FROM t1",
    "SELECT * FROM v1",
    "WITH c AS (SELECT z FROM t3) SELECT * FROM c, t1",
    "INSERT INTO t1 SELECT id, y FROM t2",
    "UPDATE t1 SET x = 1 WHERE id IN (SELECT id FROM t2)",
    "DELETE FROM t3",
    "INSERT INTO t1(id, x) VALUES (1, 2) ON CONFLICT DO NOTHING",
    "CREATE TABLE n1(a INTEGER PRIMARY KEY, b TEXT NOT NULL)",
    "ALTER TABLE t1 RENAME COLUMN x TO xx",
    "ALTER TABLE t1 ADD COLUMN w TEXT",
    "ALTER TABLE t1 DROP COLUMN x",
    "ALTER TABLE t1 RENAME TO t9",
    "DROP TABLE t3",
    "CREATE INDEX i1 ON t1(x)",
    "CREATE TEMP TABLE tmp1(a)",
    "CREATE VIEW v2 AS SELECT * FROM t1",
    "CREATE TRIGGER tr1 AFTER INSERT ON t1 BEGIN SELECT 1; END",
    "ATTACH DATABASE '/tmp/should-not-exist.db' AS other",
    "PRAGMA writable_schema = 1",
    "PRAGMA table_xinfo(t1)",
    "SELECT load_extension('x')",
    "VACUUM INTO '/tmp/should-not-exist-2.db'",
    "SELECT * FROM sqlite_master",
  ] { a.append(prepareOnly(db, sql)) }
  report["A_authorizer_events"] = a
  report["A_codes"] = ["SQLITE_CREATE_INDEX": 1, "SQLITE_CREATE_TABLE": 2, "SQLITE_CREATE_TEMP_TABLE": 4, "SQLITE_CREATE_TRIGGER": 7, "SQLITE_CREATE_VIEW": 8, "SQLITE_DELETE": 9, "SQLITE_DROP_TABLE": 11, "SQLITE_DROP_TRIGGER": 16, "SQLITE_INSERT": 18, "SQLITE_PRAGMA": 19, "SQLITE_READ": 20, "SQLITE_SELECT": 21, "SQLITE_TRANSACTION": 22, "SQLITE_UPDATE": 23, "SQLITE_ATTACH": 24, "SQLITE_DETACH": 25, "SQLITE_ALTER_TABLE": 26, "SQLITE_FUNCTION": 31]
  // Denying ATTACH, PRAGMA and load_extension through the authorizer.
  denyCodes = [SQLITE_ATTACH, SQLITE_DETACH, SQLITE_PRAGMA]
  report["A_deny_attach"] = flat(run(db, "ATTACH DATABASE ':memory:' AS other"))
  report["A_deny_pragma"] = flat(run(db, "PRAGMA writable_schema = 1"))
  denyCodes = []
  report["A_load_extension_default"] = flat(run(db, "SELECT load_extension('nothing')"))
  sqlite3_close(db)
}

// ---------- B. trigger log: order, REPLACE, upsert, rowid reuse, protection ----------
do {
  let db = open(); installAuthorizer(db)
  run(db, """
    PRAGMA recursive_triggers = ON;
    CREATE TABLE t(k UNIQUE, v);
    CREATE TABLE host_log(seq INTEGER PRIMARY KEY AUTOINCREMENT, op, old_rowid, new_rowid);
    CREATE TRIGGER host_ai AFTER INSERT ON t BEGIN INSERT INTO host_log(op, new_rowid) VALUES ('insert', NEW.rowid); END;
    CREATE TRIGGER host_au AFTER UPDATE ON t BEGIN INSERT INTO host_log(op, old_rowid, new_rowid) VALUES ('update', OLD.rowid, NEW.rowid); END;
    CREATE TRIGGER host_ad AFTER DELETE ON t BEGIN INSERT INTO host_log(op, old_rowid) VALUES ('delete', OLD.rowid); END;
    """)
  denyNames = ["host_log"]
  var b: [String: Any] = [:]
  b["insert_two"] = flat(run(db, "INSERT INTO t VALUES ('a', 1), ('b', 2)"))
  b["replace_existing"] = flat(run(db, "INSERT OR REPLACE INTO t VALUES ('a', 10)"))
  b["upsert"] = flat(run(db, "INSERT INTO t VALUES ('b', 20) ON CONFLICT(k) DO UPDATE SET v = excluded.v"))
  b["delete_last_then_insert"] = flat(run(db, "DELETE FROM t WHERE rowid = (SELECT max(rowid) FROM t); INSERT INTO t VALUES ('c', 3)"))
  b["update_rowid"] = flat(run(db, "UPDATE t SET rowid = 99 WHERE k = 'c'"))
  b["direct_read_of_log_denied"] = flat(run(db, "SELECT * FROM host_log"))
  b["direct_write_of_log_denied"] = flat(run(db, "DELETE FROM host_log"))
  b["drop_host_trigger_denied"] = flat(run(db, "DROP TRIGGER host_ai"))
  b["drop_log_table_denied"] = flat(run(db, "DROP TABLE host_log"))
  b["rows_after"] = flat(run(db, "SELECT rowid, k, v FROM t ORDER BY rowid"))
  denyNames = []
  b["log"] = flat(run(db, "SELECT seq, op, old_rowid, new_rowid FROM host_log ORDER BY seq"))
  report["B_trigger_log"] = b
  sqlite3_close(db)
}

// ---------- C. what a BEFORE trigger sees for a value written to a text-affinity decimal column ----------
do {
  let db = open()
  installCollation(db); installExact(db)
  run(db, """
    CREATE TABLE t(name TEXT, price TEXT COLLATE DEC, qty TEXT COLLATE DEC);
    CREATE TABLE seen(seq INTEGER PRIMARY KEY AUTOINCREMENT, phase, kind, raw);
    CREATE TRIGGER bi BEFORE INSERT ON t BEGIN INSERT INTO seen(phase, kind, raw) VALUES ('before insert', typeof(NEW.price), NEW.price); END;
    CREATE TRIGGER ai AFTER INSERT ON t BEGIN INSERT INTO seen(phase, kind, raw) VALUES ('after insert', typeof(NEW.price), NEW.price); END;
    CREATE TRIGGER bu BEFORE UPDATE ON t BEGIN INSERT INTO seen(phase, kind, raw) VALUES ('before update', typeof(NEW.price), NEW.price); END;
    CREATE TRIGGER au AFTER UPDATE ON t BEGIN INSERT INTO seen(phase, kind, raw) VALUES ('after update', typeof(NEW.price), NEW.price); END;
    """)
  var c: [String: Any] = [:]
  c["insert_text"] = flat(run(db, "INSERT INTO t VALUES ('text', '12.50', '2')"))
  c["insert_real_literal"] = flat(run(db, "INSERT INTO t VALUES ('real literal', 12.5, 2)"))
  c["insert_integer_literal"] = flat(run(db, "INSERT INTO t VALUES ('integer literal', 3, 2)"))
  c["insert_float_arithmetic"] = flat(run(db, "INSERT INTO t VALUES ('float arithmetic', 0.1 + 0.2, 2)"))
  c["insert_exact_function"] = flat(run(db, "INSERT INTO t VALUES ('exact function', dec_mul('1.10', '3'), 2)"))
  c["update_float"] = flat(run(db, "UPDATE t SET price = price * 1.1 WHERE name = 'text'"))
  c["update_exact"] = flat(run(db, "UPDATE t SET price = dec_mul(price, '1.1') WHERE name = 'integer literal'"))
  c["seen"] = flat(run(db, "SELECT seq, phase, kind, typeof(raw), raw FROM seen ORDER BY seq"))
  c["stored"] = flat(run(db, "SELECT name, typeof(price), price FROM t ORDER BY rowid"))
  report["C_before_trigger_typeof"] = c
  sqlite3_close(db)
}

// ---------- D. decimal columns as text with a decimal collation ----------
do {
  let db = open(); installCollation(db); installExact(db)
  run(db, """
    CREATE TABLE p(item TEXT, price TEXT COLLATE DEC, qty TEXT COLLATE DEC);
    INSERT INTO p VALUES ('a', '9', '2'), ('b', '10', '1'), ('c', '2.50', '4'), ('d', '-1', '1'), ('e', '2.5', '3'), ('f', '100.10', '1');
    CREATE TABLE q(item TEXT, price TEXT COLLATE DEC);
    INSERT INTO q VALUES ('x', '2.5'), ('y', '10.0');
    """)
  var d: [String: Any] = [:]
  for (name, sql) in [
    ("order_by", "SELECT price FROM p ORDER BY price"),
    ("min_max", "SELECT min(price), max(price) FROM p"),
    ("bare_column_with_min", "SELECT item, min(price) FROM p"),
    ("gt_integer_literal", "SELECT item FROM p WHERE price > 9 ORDER BY item"),
    ("gt_real_literal", "SELECT item FROM p WHERE price > 9.5 ORDER BY item"),
    ("gt_text_literal", "SELECT item FROM p WHERE price > '9' ORDER BY item"),
    ("eq_integer_literal", "SELECT item FROM p WHERE price = 10"),
    ("eq_real_literal", "SELECT item FROM p WHERE price = 2.5 ORDER BY item"),
    ("between", "SELECT item FROM p WHERE price BETWEEN 2 AND 9.5 ORDER BY item"),
    ("in_list", "SELECT item FROM p WHERE price IN (2.5, 10) ORDER BY item"),
    ("group_by", "SELECT price, count(*) FROM p GROUP BY price ORDER BY price"),
    ("distinct", "SELECT DISTINCT price FROM p ORDER BY price"),
    ("join_on_decimal", "SELECT p.item, q.item FROM p JOIN q ON p.price = q.price ORDER BY 1, 2"),
    ("builtin_arithmetic", "SELECT item, price * qty FROM p ORDER BY item"),
    ("expression_compare", "SELECT item FROM p WHERE price * qty > 9.5 ORDER BY item"),
    ("sum_override_exact", "SELECT sum(price) FROM p"),
    ("sum_override_of_products", "SELECT sum(price * qty) FROM p"),
    ("sum_of_exact_products", "SELECT sum(dec_mul(price, qty)) FROM p"),
    ("group_sum_having_order", "SELECT qty, sum(price) AS total FROM p GROUP BY qty HAVING sum(price) > 9.5 ORDER BY total DESC"),
    ("sum_window", "SELECT item, sum(price) OVER (ORDER BY item ROWS BETWEEN 1 PRECEDING AND CURRENT ROW) FROM p ORDER BY item"),
    ("sum_in_subquery_and_cte", "WITH s AS (SELECT sum(price) AS total FROM p) SELECT total, total > 100 FROM s"),
    ("sum_all_integers", "SELECT sum(x) FROM (SELECT 1 AS x UNION ALL SELECT 2)"),
    ("sum_empty", "SELECT sum(price) FROM p WHERE 0"),
    ("avg_builtin", "SELECT avg(price) FROM p"),
    ("total_builtin", "SELECT total(price) FROM p"),
  ] {
    var r = flat(run(db, sql))
    if let rows = r["rows"] as? [[String]] { r["rendered"] = rows.map { $0.map(exactText) } }
    d[name] = r
  }
  report["D_decimal_collation_and_exact"] = d
  sqlite3_close(db)
}

// ---------- E. a page cap on an in-memory database, and on temporary tables ----------
do {
  let db = open()
  var e: [String: Any] = [:]
  e["page_size"] = flat(run(db, "PRAGMA page_size"))
  e["set_cap"] = flat(run(db, "PRAGMA max_page_count = 64"))
  run(db, "CREATE TABLE big(x)")
  var inserted = 0; var last = (rc: Int32(0), rows: [Row](), error: "")
  for _ in 0..<2000 { last = run(db, "INSERT INTO big VALUES (randomblob(1000))"); if last.rc != SQLITE_OK { break }; inserted += 1 }
  e["main_rows_before_full"] = inserted; e["main_error"] = last.error; e["main_rc"] = Int(last.rc)
  e["temp_store"] = flat(run(db, "PRAGMA temp_store = MEMORY; PRAGMA temp.max_page_count = 64; CREATE TEMP TABLE tbig(x)"))
  inserted = 0
  for _ in 0..<2000 { last = run(db, "INSERT INTO tbig VALUES (randomblob(1000))"); if last.rc != SQLITE_OK { break }; inserted += 1 }
  e["temp_rows_before_full"] = inserted; e["temp_error"] = last.error
  e["soft_heap_limit_available"] = sqlite3_soft_heap_limit64(-1) >= 0
  report["E_page_cap"] = e
  sqlite3_close(db)
}

// ---------- F. redefinition idiom and column lists ----------
do {
  let db = open(); installAuthorizer(db)
  run(db, "CREATE TABLE s(a TEXT, b TEXT); INSERT INTO s VALUES ('1', 'x'), ('2', 'y');")
  var f: [String: Any] = [:]
  f["before"] = flat(run(db, "PRAGMA table_xinfo(s)"))
  events = []
  f["rebuild"] = flat(run(db, "CREATE TABLE s_new(a INTEGER, b TEXT, c TEXT); INSERT INTO s_new(a, b) SELECT a, b FROM s; DROP TABLE s; ALTER TABLE s_new RENAME TO s;"))
  f["rebuild_events"] = events.filter { $0.hasPrefix("2|") || $0.hasPrefix("11|") || $0.hasPrefix("26|") }
  f["after"] = flat(run(db, "PRAGMA table_xinfo(s)"))
  f["rowids_after"] = flat(run(db, "SELECT rowid, a, b FROM s"))
  report["F_schema_changes"] = f
  sqlite3_close(db)
}


// ---------- G. decimal cells held as doubles with an exact side table ----------
func registerLiteral(_ text: String) { if let d = Decimal(string: text) { _ = register(d) } }
do {
  let db = open(); installExact(db); installAuthorizer(db)
  registry = [:]
  run(db, "CREATE TABLE p(item TEXT, price REAL, qty REAL); CREATE TABLE q(item TEXT, price REAL);")
  // Fill as the host would: bind doubles and register their exact text.
  for (item, price, qty) in [("a", "9", "2"), ("b", "10", "1"), ("c", "2.50", "4"), ("d", "-1", "1"), ("e", "2.5", "3"), ("f", "100.10", "1"), ("g", "0.1", "3")] {
    let pd = register(Decimal(string: price)!), qd = register(Decimal(string: qty)!)
    run(db, "INSERT INTO p VALUES ('\(item)', \(String(format: "%.17g", pd)), \(String(format: "%.17g", qd)))")
  }
  run(db, "INSERT INTO q VALUES ('x', 2.5), ('y', 10.0)")
  var g: [String: Any] = [:]
  // Literals a statement types are registered by a lexer in the real design; simulate that here.
  for lit in ["9", "9.5", "10", "2.5", "2", "1.1", "12.5", "7.25", "0", "100"] { registerLiteral(lit) }
  for (name, sql) in [
    ("stored_types", "SELECT item, typeof(price), price FROM p ORDER BY rowid"),
    ("order_by", "SELECT price FROM p ORDER BY price"),
    ("min_max", "SELECT min(price), max(price) FROM p"),
    ("gt_integer_literal", "SELECT item FROM p WHERE price > 9 ORDER BY item"),
    ("gt_text_literal", "SELECT item FROM p WHERE price > '9' ORDER BY item"),
    ("eq_text_literal", "SELECT item FROM p WHERE price = '2.50' ORDER BY item"),
    ("eq_real_literal", "SELECT item FROM p WHERE price = 2.5 ORDER BY item"),
    ("between_in", "SELECT item FROM p WHERE price BETWEEN 2 AND 9.5 OR price IN (10) ORDER BY item"),
    ("group_by", "SELECT price, count(*) FROM p GROUP BY price ORDER BY price"),
    ("join", "SELECT p.item, q.item FROM p JOIN q ON p.price = q.price ORDER BY 1, 2"),
    ("sum_exact", "SELECT sum(price) FROM p"),
    ("sum_tenths", "SELECT sum(price) FROM p WHERE item = 'g' OR item = 'd' OR item = 'e'"),
    ("float_product", "SELECT item, price * qty FROM p WHERE item IN ('g', 'c') ORDER BY item"),
    ("exact_product", "SELECT item, dec_mul(price, qty) FROM p WHERE item IN ('g', 'c') ORDER BY item"),
    ("coalesce_case", "SELECT coalesce(price, 0), CASE WHEN qty > 1 THEN price ELSE 0 END FROM p WHERE item IN ('a', 'b') ORDER BY item"),
    ("division", "SELECT price / qty FROM p WHERE item = 'b' OR item = 'a' ORDER BY item"),
    ("having_order", "SELECT qty, sum(price) AS total FROM p GROUP BY qty HAVING sum(price) > 9.5 ORDER BY total DESC"),
  ] {
    var r = flat(run(db, sql))
    if let rows = r["rows"] as? [[String]], let types = r["types"] as? [String] {
      r["rendered"] = rows.map { row in zip(row, types).map { $1 == "real" ? exactText($0) : $0 } }
    }
    g[name] = r
  }
  // Writes: what storage class does each kind of written value arrive with?
  run(db, "CREATE TABLE w(label TEXT, price REAL)")
  for (label, expr) in [("real literal", "12.5"), ("integer literal", "3"), ("text numeral", "'7.25'"), ("text word", "'abc'"), ("float arithmetic", "0.1 + 0.2"), ("float product", "12.5 * 1.1"), ("exact product", "dec_mul(12.5, 1.1)"), ("copied cell", "(SELECT price FROM p WHERE item = 'c')"), ("null", "NULL")] {
    run(db, "INSERT INTO w VALUES ('\(label)', \(expr))")
  }
  var w = flat(run(db, "SELECT label, typeof(price), price FROM w ORDER BY rowid"))
  if let rows = w["rows"] as? [[String]] { w["rendered"] = rows.map { [$0[0], $0[1], $0[1] == "real" ? exactText($0[2]) : $0[2]] } }
  g["written_values"] = w
  // Statements that could reach a file or leave the call's transaction.
  denyCodes = [SQLITE_ATTACH, SQLITE_DETACH, SQLITE_PRAGMA, SQLITE_TRANSACTION, SQLITE_SAVEPOINT]
  g["vacuum_into_denied"] = flat(run(db, "VACUUM INTO '/tmp/sevra-probe-should-not-exist.db'"))
  g["vacuum_into_file_exists"] = FileManager.default.fileExists(atPath: "/tmp/sevra-probe-should-not-exist.db")
  g["vacuum_plain"] = flat(run(db, "VACUUM"))
  g["begin_denied"] = flat(run(db, "BEGIN"))
  g["savepoint_denied"] = flat(run(db, "SAVEPOINT s1"))
  denyCodes = []
  report["G_real_with_exact_side_table"] = g
  sqlite3_close(db)
}

let data = try! JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
print(String(data: data, encoding: .utf8)!)
