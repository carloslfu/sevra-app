#!/usr/bin/env python3
"""Current-format history, concurrent opens, portable copies and old-format refusal."""
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor
import argparse
import hashlib
import json
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--cli", type=Path, default=ROOT / "output/bin/sevra")
parser.add_argument("--checks", type=Path, default=ROOT / ".build/debug/sevra-checks")
args = parser.parse_args()
CLI = args.cli.resolve()

with tempfile.TemporaryDirectory(prefix="sevra-history-cli-") as folder:
    root = Path(folder)
    workbook = root / "History.sevra"
    fixture = subprocess.run([str(args.checks.resolve()), "--history-fixture", str(workbook)],
                             text=True, capture_output=True)
    assert fixture.returncode == 0, fixture.stdout + fixture.stderr
    expected = json.loads(fixture.stdout)
    assert expected["integrity"]["ok"] and len(expected["ids"]) == 700

    old = root / "Unsupported.sevra"
    old.mkdir()
    (old / "assets").mkdir()
    (old / "staging").mkdir()
    (old / "manifest.json").write_text(json.dumps({
        "format": "sevra", "version": 1, "id": "synthetic-legacy", "title": "Legacy history"
    }))
    schema = (ROOT / "Tests/Fixtures/schema-v1.sql").read_text()
    subprocess.run(["/usr/bin/sqlite3", str(old / "workbook.sqlite")],
                   input=schema, text=True, check=True, capture_output=True)

    def hashes(path):
        return {str(p.relative_to(path)): hashlib.sha256(p.read_bytes()).hexdigest()
                for p in path.rglob("*") if p.is_file()}

    before = hashes(old)
    refused = subprocess.run([str(CLI), "inspect", str(old)], text=True, capture_output=True)
    assert refused.returncode != 0, refused.stdout
    assert json.loads(refused.stderr)["error"]["code"] == "schema", refused.stderr
    assert hashes(old) == before, "Unsupported workbook was changed"

    def run(*args):
        result = subprocess.run([str(CLI), *map(str, args)], cwd=root,
                                text=True, capture_output=True)
        assert result.returncode == 0, result.stdout + result.stderr
        value = json.loads(result.stdout)
        assert value["ok"], value
        return value["result"]

    with ThreadPoolExecutor(max_workers=8) as workers:
        list(workers.map(lambda _: run("inspect", workbook), range(8)))
    assert run("inspect", workbook)["revision"] == expected["revision"]
    ids = []
    after = None
    while True:
        page = run("history", workbook, "main", *([after] if after else []))
        assert page["revision"] == expected["revision"]
        assert page["messages"], "History pagination did not progress"
        ids.extend(message["id"] for message in page["messages"])
        after = ids[-1]
        if not page["hasMore"]:
            break
    assert ids == expected["ids"]
    query = run("history-search", workbook, "main", "Supplier archive")
    assert len(query["hits"]) == 30 and query["nextCursor"]
    next_page = run("history-search", workbook, "main", "Supplier archive", query["nextCursor"])
    assert not ({hit["id"] for hit in query["hits"]} & {hit["id"] for hit in next_page["hits"]})
    original = run("history-read", workbook, "main", ids[16])
    assert original["message"]["body"] == "Supplier archive entry 17"
    assert original["payload"] is None  # Never invent receipts for ordinary messages.
    assert run("checkpoints", workbook) == []  # Storage is not automatic compaction.
    archive = root / "Portable.sevraz"
    restored = root / "Restored.sevra"
    run("export", workbook, archive)
    run("open-archive", archive, restored)
    assert run("history-read", restored, "main", ids[16]) == original
    assert run("history", restored)["digest"] == run("history", workbook)["digest"]
    assert run("verify", restored)["ok"]
    print(json.dumps({"unsupportedFormatRefusedUnchanged": True, "concurrentOpeners": 8, "messagesPaged": len(ids), "searchAndCursor": True,
                      "exactOlderMessage": True, "offlineExportReopen": True,
                      "automaticCompaction": False}))
