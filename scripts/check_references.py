#!/usr/bin/env python3
"""Bounded, synthetic, model-free CLI/reference journey. Keeps no user workbook."""
import argparse
import json
from pathlib import Path
import subprocess
import tempfile
import time


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--cli", type=Path, default=Path("output/native/bin/sevra"))
    args = parser.parse_args()
    cli = args.cli.resolve()
    checks = []
    timings = []

    def run(*argv, error=None):
        started = time.perf_counter()
        process = subprocess.run([str(cli), *map(str, argv)], text=True, capture_output=True, timeout=30)
        timings.append(time.perf_counter() - started)
        result = json.loads(process.stdout if process.returncode == 0 else process.stderr)
        assert result["schemaVersion"] == 1
        if error:
            assert process.returncode != 0 and not result["ok"], result
            assert result["error"]["code"] == error, result
            return result["error"]
        assert process.returncode == 0 and result["ok"], result
        return result["result"]

    def checked(name, condition):
        assert condition, name
        checks.append(name)

    with tempfile.TemporaryDirectory(prefix="sevra-reference-cli-") as folder:
        root = Path(folder)
        book = root / "Synthetic.sevra"
        run("create", book, "Reference checks")

        def add(**fields):
            return run("add", book, json.dumps({"category": "source", "kind": "observation", **fields}))

        target = add(title="Quote", text="Exact synthetic quote Q-7.")
        body = (f"[live](sevra://logical/{target['logicalID']}) [pin](sevra://item/{target['id']}) "
                "[[Later]] [foreign](sevra://workbook/elsewhere/item/foreign) `[[example]]`")
        origin = add(title="Notes", text=body)
        snapshot = run("reference-snapshot", book, origin["id"])
        checked("body parser excludes code and preserves unresolved/foreign hints",
                snapshot["coverage"] == "ready" and len(snapshot["references"]) == 4)
        checked("outgoing targets are deduplicated", len(run("references", book, origin["id"])["hits"]) == 3)
        checked("incoming document is counted once", run("backlinks", book, target["id"])["hits"][0]["mentionCount"] == 2)

        revised = add(title="Renamed quote", text="Revised synthetic quote Q-8.", supersedes=target["id"])
        hits = run("references", book, origin["id"])["hits"]
        checked("live target follows a new head and pin stays historical",
                {hit["evidence"]["id"] for hit in hits if hit["evidence"]} == {target["id"], revised["id"]})
        options = json.dumps({"targetScope": "exact"})
        checked("historical exact target excludes live mentions", run("backlinks", book, target["id"], options)["hits"][0]["mentionCount"] == 1)
        checked("new exact target includes live mentions", run("backlinks", book, revised["id"], options)["hits"][0]["mentionCount"] == 1)

        # Correct one lookup explicitly. Original body and earlier snapshot stay exact.
        references = snapshot["references"]
        selections = []
        for reference in references:
            selected = {key: reference[key] for key in ["startScalar", "scalarCount", "lookup", "id"]}
            if reference["resolution"] == "bound":
                selected["target"] = {"mode": reference["targetMode"], "identity": reference.get("targetVersionID") or reference["targetLogicalID"]}
            elif reference["resolution"] == "external":
                selected["target"] = {"mode": "pinned", "identity": "foreign", "workbookID": "elsewhere"}
            else:
                selected["target"] = {"mode": "pinned", "identity": revised["id"]}
            selections.append(selected)
        correction = json.dumps({"selections": selections, "expectedSnapshotID": snapshot["id"], "token": "correct-links"})
        corrected = run("annotate-references", book, origin["id"], correction)
        checked("explicit correction preserves original body", run("read", book, origin["id"])["item"]["text"] == body)
        checked("annotation retry is idempotent", run("annotate-references", book, origin["id"], correction) == corrected)
        checked("original annotation remains inspectable", run("reference-snapshot", book, origin["id"], snapshot["id"]) == snapshot)
        checked("annotation history is paged", run("reference-history", book, origin["id"], '{"limit":1}')["nextBeforeVersion"] == 2)
        checked("foreign resolution performs no external read", run("reference-resolve", book, origin["id"], references[-1]["id"])["destination"] is None)
        run("annotate-references", book, origin["id"], json.dumps({"selections": [], "expectedSnapshotID": snapshot["id"]}), error="stale_reference")
        run("index-references", book, origin["id"])
        checked("repeat indexing preserves corrections", run("reference-snapshot", book, origin["id"]) == corrected)

        for index in range(4):
            add(title=f"Fanout {index}", text=f"[quote](sevra://item/{revised['id']})")
        cursor = None
        seen = set()
        while True:
            page = run("backlinks", book, revised["id"], json.dumps({"limit": 2, "cursor": cursor}))
            for hit in page["hits"]:
                assert hit["evidence"]["id"] not in seen
                seen.add(hit["evidence"]["id"])
            cursor = page["nextCursor"]
            if cursor is None:
                break
        checked("incoming continuation has no repeats or gaps", len(seen) == 5)
        page = run("backlinks", book, revised["id"], '{"limit":1}')
        add(title="Intervening mutation")
        run("backlinks", book, revised["id"], json.dumps({"limit": 1, "cursor": page["nextCursor"]}), error="stale_cursor")
        checked("changed workbook invalidates a discovery page", True)

        document = add(category="record", kind="document", title="Draft", text="Original", inputs=[target["id"]])
        text_file = root / "edit.txt"
        text_file.write_text("See quote", encoding="utf-8")
        json_file = root / "links.json"
        json_file.write_text(json.dumps([{"startScalar": 4, "scalarCount": 5, "target": {"mode": "pinned", "identity": revised["id"]}}]), encoding="utf-8")
        argv = ["edit-document", book, document["id"], text_file, "--token", "linked-edit", "--references", json_file]
        edited = run(*argv)
        checked("document edit and selected binding commit atomically", run("reference-snapshot", book, edited["id"])["references"][0]["targetVersionID"] == revised["id"])
        checked("linked document edit retries return the same version", run(*argv)["id"] == edited["id"])
        run("edit-document", book, document["id"], text_file, error="stale_revision")
        run("annotate-references", book, edited["id"], '{"expectedSnapshotID":null,"selections":[]}', error="reference_annotation")

        for options in ['{"limit":"2"}', '{"historicalOrigins":1}', '{"unknown":true}', '{"targetScope":"name"}']:
            run("backlinks", book, revised["id"], options, error="usage")
        checked("invalid query options refuse instead of silently changing scope", True)
        before = run("inspect", book)
        run("add", book, '{"title":"Bad selection","text":"one","references":[{"startScalar":0,"scalarCount":3,"target":{"mode":"pinned","identity":"missing"}}]}', error="reference_target")
        checked("failed authored binding has no partial write", run("inspect", book) == before)

        asset_file = root / "original.txt"
        asset_bytes = b"Original file [[not an item-body link]]\r\n"
        asset_file.write_bytes(asset_bytes)
        run("import", book, asset_file)
        checked("body coverage does not claim extracted file-link coverage", "extracted file contents" in run("backlinks", book, revised["id"])["notice"])
        run("rebuild-references", book)
        checked("rebuild preserves canonical annotation", run("reference-snapshot", book, origin["id"]) == corrected)
        checked("catch-up skips already indexed body versions", run("index-reference-bodies", book, '{"limit":1}')["processed"] == [])
        archive = root / "Portable.sevraz"
        reopened = root / "Reopened.sevra"
        run("export", book, archive)
        run("open-archive", archive, reopened)
        checked("portable reopen retains bindings", run("reference-snapshot", reopened, origin["id"]) == corrected)
        checked("original assets remain byte identical", any(path.is_file() and path.read_bytes() == asset_bytes for path in (reopened / "assets").rglob("*")))
        checked("reopened workbook integrity", run("verify", reopened)["ok"] is True)
    print(json.dumps({"ok": True, "checks": checks, "count": len(checks), "cliCalls": len(timings), "maxProcessSeconds": round(max(timings), 4)}, indent=2))


if __name__ == "__main__":
    main()
