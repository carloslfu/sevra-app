#!/usr/bin/env python3
"""Qualify explicit original input declarations, their integrity and publication boundaries."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import select
import sqlite3
import subprocess
import tempfile


def run(cli, worker, output):
    calls = []
    with tempfile.TemporaryDirectory(prefix="sevra-business-inputs-") as directory:
        folder = Path(directory)

        def call(*args, error=None):
            result = subprocess.run([str(cli), *map(str, args)], capture_output=True,
                                    text=True, timeout=40)
            clean = lambda s: s.replace(str(folder), "<fixture>")
            calls.append({"arguments": [clean(str(a)) for a in args], "returncode": result.returncode,
                          "stdout": clean(result.stdout), "stderr": clean(result.stderr)})
            assert (result.returncode == 0) == (error is None), result
            value = json.loads(result.stderr if error else result.stdout)
            assert value["ok"] == (error is None), value
            if error:
                assert value["error"]["code"] == error and not result.stdout, value
                return value
            assert not result.stderr, result.stderr
            return value["result"]

        book = folder / "Shared.sevra"
        call("create", book)
        data = {"sourceID": call("observe", book, json.dumps(
            {"title": "Counted opening input", "text": "Synthetic count", "token": "opening"}))["id"]}
        with sqlite3.connect(book / "workbook.sqlite") as db:
            assert db.execute("PRAGMA user_version").fetchone()[0] == 36
            declaration = db.execute("SELECT commit_id,kind,policy FROM business_inputs WHERE source_id=?",
                                     [data["sourceID"]]).fetchone()
        assert declaration[1:] == ("observation", "business-input-v1"), declaration
        assert call("verify", book)["ok"]
        rebuilt = folder / "Rebuilt.sevra"
        call("reconstruct", book, rebuilt)
        assert call("verify", rebuilt)["ok"]

        observation_json = json.dumps({"title": "Fresh independent event", "text": "Counted on site", "token": "fresh"})
        observed = call("observe", book, observation_json)
        retry_before = call("commits", book)
        assert call("observe", book, observation_json) == observed
        assert call("commits", book) == retry_before
        call("observe", book, json.dumps({"title": "Copy", "inputs": [data["sourceID"]]}), error="business_input")
        call("observe", book, error="usage")

        # Source capture itself is a qualified external input; parser completion is independent.
        document = folder / "Supplier.txt"
        document.write_text("Independent supplier invoice: synthetic only.\n")
        imported = call("import", book, document, "--role", "reference", "--token", "file")
        with sqlite3.connect(book / "workbook.sqlite") as db:
            assert db.execute("SELECT kind FROM business_inputs WHERE source_id=?",
                              [imported["source"]["id"]]).fetchone() == ("external-file",)

        # Missing or altered declarations, and altered creating changes, fail verification.
        for damage in ["missing", "ordinal", "commit", "hash", "large"]:
            bad = folder / (damage + ".sevra")
            shutil.copytree(book, bad)
            with sqlite3.connect(bad / "workbook.sqlite") as db:
                if damage == "missing":
                    db.execute("DELETE FROM business_inputs WHERE source_id=?", [data["sourceID"]])
                elif damage == "ordinal":
                    db.execute("UPDATE business_inputs SET item_index=1 WHERE source_id=?", [data["sourceID"]])
                elif damage == "commit":
                    db.execute("UPDATE business_inputs SET commit_id=(SELECT id FROM committed_changes ORDER BY rowid LIMIT 1) WHERE source_id=?", [data["sourceID"]])
                elif damage == "hash":
                    db.execute("UPDATE committed_changes SET hash='altered' WHERE id=?", [declaration[0]])
                else:
                    db.execute("UPDATE committed_changes SET payload=? WHERE id=?", ["x" * 16_777_217, declaration[0]])
            # Verification refuses every altered declaration or its creating change.
            call("verify", bad,
                 error="change_hash" if damage in ("hash", "large") else "business_input_integrity")

        death = []
        for stage in ["prepared", "committed"]:
            path = folder / ("Publication-" + stage + ".sevra")
            process = subprocess.Popen([str(worker), "--business-input-death-worker", str(path), stage],
                                       stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                       stderr=subprocess.PIPE, text=True)
            try:
                assert select.select([process.stdout], [], [], 20)[0], "Input publication barrier timed out"
                line = process.stdout.readline()
                barrier = json.loads(line)
                assert barrier["stage"] == stage
                process.kill()
                stdout, stderr = process.communicate(timeout=20)
                assert process.returncode == -9 and not stdout and not stderr, (stdout, stderr)
            finally:
                if process.poll() is None:
                    process.kill()
                    process.communicate(timeout=20)
            with sqlite3.connect(path / "workbook.sqlite") as db:
                counts = [db.execute("SELECT count(*) FROM " + table).fetchone()[0]
                          for table in ["items", "business_inputs", "committed_changes", "operations"]]
            # A new workbook records one change, its first chat; the publication adds one of each or nothing.
            assert counts == ([0, 0, 1, 1] if stage == "prepared" else [1, 1, 2, 2]), counts
            assert call("verify", path)["ok"]
            copied = folder / ("Recovered-" + stage + ".sevra")
            call("reconstruct", path, copied)
            assert call("verify", copied)["ok"]
            death.append({"stage": stage, "sentSIGKILL": True, "returncode": process.returncode,
                          "sourceID": barrier["sourceID"], "counts": counts})

        assert call("verify", book)["ok"]
        output.parent.mkdir(parents=True, exist_ok=True)
        report = {"version": 1, "scope": "explicit original input capture, declaration integrity and publication boundaries",
                  "cliSHA256": hashlib.sha256(cli.read_bytes()).hexdigest(),
                  "workerSHA256": hashlib.sha256(worker.read_bytes()).hexdigest(),
                  "damagedCopies": 5,
                  "publicationBoundaries": death,
                  "callCount": len(calls), "calls": calls}
        output.write_text(json.dumps(report, sort_keys=True, indent=2) + "\n")
        print(json.dumps({"passed": True, "calls": len(calls), "output": str(output)}))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cli", type=Path, required=True)
    parser.add_argument("--worker", type=Path, required=True)
    parser.add_argument("--output", type=Path, default=Path(".build/business-inputs-installed.json"))
    arguments = parser.parse_args()
    run(arguments.cli.resolve(), arguments.worker.resolve(), arguments.output)
