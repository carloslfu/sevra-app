#include <sqlite3.h>

static inline int sevra_enable_triggers(sqlite3 *db, int enabled) {
  return sqlite3_db_config(db, SQLITE_DBCONFIG_ENABLE_TRIGGER, enabled, (int *)0);
}

static inline int sevra_trigger_state(sqlite3 *db) {
  int enabled = -1;
  return sqlite3_db_config(db, SQLITE_DBCONFIG_ENABLE_TRIGGER, -1, &enabled) == SQLITE_OK ? enabled : -1;
}

/// Double-quoted text that names no column is an error, never a silent string.
static inline int sevra_strict_quotes(sqlite3 *db) {
  int dml = sqlite3_db_config(db, SQLITE_DBCONFIG_DQS_DML, 0, (int *)0);
  int ddl = sqlite3_db_config(db, SQLITE_DBCONFIG_DQS_DDL, 0, (int *)0);
  return dml == SQLITE_OK ? ddl : dml;
}
