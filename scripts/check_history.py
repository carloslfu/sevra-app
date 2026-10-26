#!/usr/bin/env python3
"""Packaged CLI migration, full history paging/search and offline export/reopen."""
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor
import json
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
CLI = ROOT / "output/bin/sevra"

with tempfile.TemporaryDirectory(prefix="sevra-history-cli-") as folder:
    root = Path(folder)
    workbook = root / "Legacy.sevra"
    workbook.mkdir()
    (workbook / "assets").mkdir()
    (workbook / "staging").mkdir()
    (workbook / "manifest.json").write_text(json.dumps({
        "format": "sevra", "version": 1, "id": "synthetic-legacy", "title": "Legacy history"
    }))
    schema = (ROOT / "Tests/Fixtures/schema-v1.sql").read_text()
    schema += """
    WITH RECURSIVE seq(n) AS (SELECT 1 UNION ALL SELECT n+1 FROM seq WHERE n<700)
    INSERT INTO messages SELECT 'legacy-'||n,'main',
      CASE WHEN n%2=1 THEN 'user' ELSE 'assistant' END,
      'Supplier archive entry '||n,'complete','2026-10-25T10:00:00Z' FROM seq;
    UPDATE meta SET value='700' WHERE key='revision';
    """
    subprocess.run(["/usr/bin/sqlite3", str(workbook / "workbook.sqlite")],
                   input=schema, text=True, check=True, capture_output=True)

    def run(*args):
        result = subprocess.run([str(CLI), *map(str, args)], cwd=root,
                                text=True, capture_output=True, check=True)
        value = json.loads(result.stdout)
        assert value["ok"], value
        return value["result"]

    with ThreadPoolExecutor(max_workers=8) as workers:
        list(workers.map(lambda _: run("inspect", workbook), range(8)))
    migrations = subprocess.run(["/usr/bin/sqlite3", str(workbook / "workbook.sqlite"),
                                  "SELECT count(*) FROM operations WHERE kind='schema_migration';"],
                                 text=True, capture_output=True, check=True)
    assert migrations.stdout.strip() == "1"
    ids = []
    after = None
    while True:
        page = run("history", workbook, "main", *([after] if after else []))
        assert page["revision"] == 701
        assert page["messages"], "History pagination did not progress"
        ids.extend(message["id"] for message in page["messages"])
        after = ids[-1]
        if not page["hasMore"]:
            break
    assert ids == [f"legacy-{n}" for n in range(1, 701)]
    query = run("history-search", workbook, "main", "Supplier archive")
    assert len(query["hits"]) == 30 and query["nextCursor"]
    next_page = run("history-search", workbook, "main", "Supplier archive", query["nextCursor"])
    assert not ({hit["id"] for hit in query["hits"]} & {hit["id"] for hit in next_page["hits"]})
    original = run("history-read", workbook, "main", "legacy-17")
    assert original["message"]["body"] == "Supplier archive entry 17"
    assert original["payload"] is None  # Never invent receipts for old messages.
    assert run("checkpoints", workbook) == []  # Storage is not automatic compaction.
    archive = root / "Portable.sevraz"
    restored = root / "Restored.sevra"
    run("export", workbook, archive)
    run("open-archive", archive, restored)
    assert run("history-read", restored, "main", "legacy-17") == original
    assert run("history", restored)["digest"] == run("history", workbook)["digest"]
    assert run("verify", restored)["ok"]
    print(json.dumps({"migration": True, "concurrentOpeners": 8, "messagesPaged": len(ids), "searchAndCursor": True,
                      "exactOlderMessage": True, "offlineExportReopen": True,
                      "automaticCompaction": False}))
