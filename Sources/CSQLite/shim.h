#include <sqlite3.h>

static inline int sevra_enable_triggers(sqlite3 *db, int enabled) {
  return sqlite3_db_config(db, SQLITE_DBCONFIG_ENABLE_TRIGGER, enabled, (int *)0);
}

static inline int sevra_trigger_state(sqlite3 *db) {
  int enabled = -1;
  return sqlite3_db_config(db, SQLITE_DBCONFIG_ENABLE_TRIGGER, -1, &enabled) == SQLITE_OK ? enabled : -1;
}
