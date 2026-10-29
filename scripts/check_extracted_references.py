#!/usr/bin/env python3
"""Model-free packaged CLI journey for immutable extracted mention annotations."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile
import time


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--cli", type=Path, default=Path("output/native/bin/sevra"))
    cli = parser.parse_args().cli.resolve()
    checks, timings = [], []

    def run(*argv, error=None):
        started = time.perf_counter()
        process = subprocess.run([str(cli), *map(str, argv)], text=True, capture_output=True, timeout=30)
        timings.append(time.perf_counter() - started)
        reply = json.loads(process.stdout if process.returncode == 0 else process.stderr)
        assert reply["schemaVersion"] == 1, reply
        if error:
            assert process.returncode != 0 and not reply["ok"] and reply["error"]["code"] == error, reply
            return reply["error"]
        assert process.returncode == 0 and reply["ok"], reply
        return reply["result"]

    def checked(name, condition):
        assert condition, name
        checks.append(name)

    def options(**fields):
        return json.dumps(fields, ensure_ascii=False)

    with tempfile.TemporaryDirectory(prefix="sevra-extracted-cli-") as folder:
        root = Path(folder)
        book = root / "Captured.sevra"
        run("create", book, "Synthetic extracted links")

        def add(**fields):
            return run("add", book, options(category="source", kind="observation", **fields))

        target = add(title="Target", text="Exact quote version one")
        text = (f"👩🏽‍💻 Cafe\u0301\r\n[live](sevra://logical/{target['logicalID']}) "
                f"[pin](sevra://item/{target['id']}) [[Chosen]] "
                "[foreign](sevra://workbook/elsewhere/item/remote) `[[example]]`\n")
        original = text.encode("utf-8")
        file = root / "references.md"
        file.write_bytes(original)
        origin = run("import", book, file, "--role", "reference")["source"]
        snapshot = run("file-reference-snapshot", book, origin["id"])
        refs = snapshot["references"]
        checked("import captures supported mentions and excludes code", snapshot["coverage"] == "ready" and len(refs) == 4)
        checked("capture binds the exact original asset hash", snapshot["input"]["asset_hash"] == hashlib.sha256(original).hexdigest())
        region = run("file-reference-region", book, origin["id"], options(snapshotID=snapshot["id"], region=0, limit=7))
        rebuilt = region["text"]
        while region["nextOffsetScalar"] is not None:
            region = run("file-reference-region", book, origin["id"], options(snapshotID=snapshot["id"], region=0, offset=region["nextOffsetScalar"], limit=7))
            rebuilt += region["text"]
        checked("retained Unicode and CRLF text has lossless bounded pages", rebuilt.encode("utf-8") == original)
        checked("file mentions do not appear as body bindings", run("reference-snapshot", book, origin["id"])["references"] == [])
        outgoing = run("references", book, origin["id"])
        checked("live and pinned mentions deduplicate the current target", len(outgoing["hits"]) == 3 and outgoing["hits"][0]["mentionCount"] == 2)
        checked("incoming file result exposes metadata and captured-text scope", run("backlinks", book, target["id"])["hits"][0]["discoveryScopes"] == ["extracted_text"])
        checked("body-only discovery excludes file mentions", run("backlinks", book, target["id"], options(contentScope="body"))["hits"] == [])
        checked("foreign resolution never opens another workbook", run("file-reference-resolve", book, origin["id"], refs[3]["reference"]["id"])["destination"] is None)

        selections = []
        for entry in refs:
            ref = entry["reference"]
            selection = {key: ref[key] for key in ("id", "startScalar", "scalarCount", "lookup")}
            if ref["resolution"] == "bound":
                selection["target"] = {"mode": ref["targetMode"], "identity": ref.get("targetVersionID") or ref["targetLogicalID"]}
            elif ref["resolution"] == "external":
                selection["target"] = {"mode": "pinned", "identity": "remote", "workbookID": "elsewhere"}
            else:
                selection["target"] = {"mode": "live", "identity": target["logicalID"]}
            selections.append({"region": entry["region"], "selection": selection})
        correction = options(expectedSnapshotID=snapshot["id"], selections=selections, token="explicit-file-choice")
        corrected = run("annotate-file-references", book, origin["id"], correction)
        checked("explicit file choice is versioned and reports partial coverage", corrected["version"] == 2 and corrected["coverage"] == "partial")
        checked("uncertain annotation retry returns the original result", run("annotate-file-references", book, origin["id"], correction) == corrected)
        checked("earlier unresolved choice stays inspectable", run("file-reference-snapshot", book, origin["id"], snapshot["id"]) == snapshot)
        history = run("file-reference-history", book, origin["id"], options(limit=1))
        checked("annotation history has a bounded continuation", len(history["versions"]) == 1 and history["nextBeforeVersion"] == 2)
        checked("history continuation reaches the original snapshot", run("file-reference-history", book, origin["id"], options(beforeVersion=2, limit=1))["versions"][0]["id"] == snapshot["id"])
        before = run("inspect", book)
        run("annotate-file-references", book, origin["id"], options(expectedSnapshotID=snapshot["id"], selections=[]), error="stale_reference")
        checked("stale annotation refuses without a partial write", run("inspect", book) == before)
        run("extract", book, origin["id"])
        checked("same extraction preserves explicit choices", run("file-reference-snapshot", book, origin["id"]) == corrected)
        run("rebuild-references", book)
        checked("projection rebuild preserves annotations", run("file-reference-snapshot", book, origin["id"]) == corrected)

        revised = add(title="Revised target", text="Exact quote version two", supersedes=target["id"])
        live = run("file-reference-resolve", book, origin["id"], refs[0]["reference"]["id"])
        pin = run("file-reference-resolve", book, origin["id"], refs[1]["reference"]["id"])
        checked("live file binding follows a new head while a pin keeps history", live["destination"]["id"] == revised["id"] and pin["destination"]["id"] == target["id"])
        checked("old exact target counts only its pin", run("backlinks", book, target["id"], options(targetScope="exact"))["hits"][0]["mentionCount"] == 1)

        for index in range(4):
            add(title=f"Body fanout {index}", text=f"[target](sevra://item/{revised['id']})")
        seen, cursor = set(), None
        while True:
            page = run("backlinks", book, revised["id"], options(limit=2, cursor=cursor))
            for hit in page["hits"]:
                assert hit["evidence"]["id"] not in seen
                assert "body" not in hit["evidence"] and "data" not in hit["evidence"]
                seen.add(hit["evidence"]["id"])
            cursor = page["nextCursor"]
            if cursor is None:
                break
        checked("mixed discovery has no repeated or missing exact versions", len(seen) == 5)
        page = run("backlinks", book, revised["id"], options(limit=1))
        run("backlinks", book, revised["id"], options(limit=1, cursor=page["nextCursor"], contentScope="body"), error="stale_cursor")
        checked("continuation refuses a changed content scope", True)

        before = run("inspect", book)
        for bad in [options(contentScope="files"), options(contentScope=1)]:
            run("references", book, origin["id"], bad, error="usage")
        for bad in [options(region=0), options(snapshotID=snapshot["id"], region=0.5), options(snapshotID=snapshot["id"], region=0, unknown=True)]:
            run("file-reference-region", book, origin["id"], bad, error="usage")
        for bad in [options(expectedSnapshotID=None, selections=[]), options(expectedSnapshotID=corrected["id"], selections=[{"region":0,"selection":{"startScalar":0,"scalarCount":1,"surprise":True}}]), options(expectedSnapshotID=corrected["id"], selections=[{"region":True,"selection":{}}])]:
            run("annotate-file-references", book, origin["id"], bad, error="usage")
        checked("strict options and invalid selection types have no writes", run("inspect", book) == before)
        run("file-reference-region", book, origin["id"], options(snapshotID=corrected["id"], region=511), error="reference_region")

        video = root / "video.unknown-format"
        video.write_bytes(b"Synthetic unsupported asset")
        unsupported = run("import", book, video, "--role", "reference")["source"]
        checked("unsupported extraction does not claim full link coverage", run("file-reference-snapshot", book, unsupported["id"])["coverage"] == "unsupported")
        checked("latest extraction and captured coverage are separately labeled", "latestExtraction" in run("references", book, unsupported["id"])["fileCoverage"])
        archive = root / "Portable.sevraz"
        reopened = root / "Reopened.sevra"
        run("export", book, archive)
        run("open-archive", archive, reopened)
        checked("portable reopen retains exact extracted annotation history", run("file-reference-snapshot", reopened, origin["id"]) == corrected and run("file-reference-snapshot", reopened, origin["id"], snapshot["id"]) == snapshot)
        checked("original asset bytes remain unchanged inside the workbook", any(path.is_file() and path.read_bytes() == original for path in (reopened / "assets").rglob("*")))
        checked("reopened workbook integrity includes file annotations", run("verify", reopened)["ok"] is True)
    print(json.dumps({"ok": True, "checks": checks, "count": len(checks), "cliCalls": len(timings), "maxProcessSeconds": round(max(timings), 4)}, indent=2))


if __name__ == "__main__":
    main()
