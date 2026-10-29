#!/usr/bin/env python3
"""Exercise exact condition change-input inspection through an installed CLI."""
import argparse
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
from pathlib import Path
import shutil
import sqlite3
import subprocess
import tempfile


def run(cli, worker, output):
    calls = []
    report = {"policy": "inventory-transition-inputs-v1", "ok": False,
              "cliSHA256": hashlib.sha256(cli.read_bytes()).hexdigest(),
              "workerSHA256": hashlib.sha256(worker.read_bytes()).hexdigest(),
              "actualModelInference": False, "automaticDispatch": False,
              "visibleOS": False, "concurrentReaders": 6, "calls": calls}
    try:
        with tempfile.TemporaryDirectory(prefix="sevra-condition-inputs-") as directory:
            folder = Path(directory)
            book = folder / "Inputs.sevra"
            fixture = subprocess.run([str(worker), "--condition-inputs-fixture", str(book)],
                                     capture_output=True, text=True, timeout=120, check=True)
            assert not fixture.stderr, fixture.stderr
            data = json.loads(fixture.stdout)
            observation = data["observationID"]

            def call(*arguments, error=None):
                result = subprocess.run([str(cli), *map(str, arguments)],
                                        capture_output=True, text=True, timeout=30)
                clean = lambda text: text.replace(str(folder), "<fixture>")
                calls.append({"arguments": [clean(str(a)) for a in arguments],
                              "returncode": result.returncode, "stdout": clean(result.stdout),
                              "stderr": clean(result.stderr)})
                assert (result.returncode == 0) == (error is None), result
                value = json.loads(result.stderr if error else result.stdout)
                assert value["ok"] == (error is None), value
                if error:
                    assert not result.stdout and value["error"]["code"] == error, value
                    return value
                assert not result.stderr, result.stderr
                return value["result"]

            def inspect(target, oid, *arguments):
                value = call("condition-inputs", target, oid, *arguments)
                assert value["execution"] == "none" and value["enabled"] is False
                summary = value["changeInputs"]
                assert summary["policy"] == report["policy"]
                assert summary["minimalCauseSet"] is False
                assert summary["automaticParents"] == "not-resolved"
                assert summary["dispatchEligibility"] == "not-evaluated"
                return value

            before = call("commits", book)
            first = inspect(book, observation, "-", 50)
            assert first["changeInputs"]["count"] == 205
            assert first["changeInputs"]["coverage"] == "complete"
            assert first["previousObservationID"] == data["baselineID"]
            assert first["previousCertainObservationID"] == data["baselineID"]
            page = first
            entries = []
            while True:
                entries += page["entries"]
                if not page["hasMore"]:
                    assert page["nextCursor"] is None
                    break
                page = inspect(book, observation, page["nextCursor"], 50)
            assert len(entries) == 205 == len({entry["id"] for entry in entries})
            assert [entry["id"] for entry in entries] == sorted(entry["id"] for entry in entries)
            assert all(entry["input"]["kind"] == "record-change" and
                       entry["input"]["beforeID"] is None and
                       entry["inputIDs"] == [entry["input"]["afterID"]] for entry in entries)
            baseline = inspect(book, data["baselineID"])
            assert baseline["changeInputs"]["coverage"] == "baseline" and not baseline["entries"]
            with ThreadPoolExecutor(max_workers=6) as pool:
                simultaneous = list(pool.map(lambda _: inspect(book, observation, "-", 50), range(6)))
            assert all(value == first for value in simultaneous)
            assert call("commits", book) == before
            restored = folder / "Restored.sevra"
            call("reconstruct", book, restored)
            assert inspect(restored, observation, "-", 50) == first
            assert call("verify", book)["ok"] and call("verify", restored)["ok"]
            call("condition-inputs", book, error="usage")
            call("condition-inputs", book, "", error="condition_input")
            call("condition-inputs", book, "missing", error="condition_observation")
            call("condition-inputs", book, observation, "foreign", error="condition_cursor")
            call("condition-inputs", book, data["baselineID"], entries[0]["id"], error="condition_cursor")
            call("condition-inputs", book, observation, "-", 51, error="condition_limit")
            call("condition-inputs", book, observation, "-", 0, error="condition_limit")
            for name, sql in [
                ("Missing", "DELETE FROM condition_observation_inputs WHERE observation_id=? AND id=(SELECT min(id) FROM condition_observation_inputs WHERE observation_id=?)"),
                ("Erased", "UPDATE condition_observation_inputs SET payload='{}' WHERE observation_id=? AND id=(SELECT min(id) FROM condition_observation_inputs WHERE observation_id=?)"),
            ]:
                damaged = folder / (name + ".sevra")
                shutil.copytree(book, damaged)
                with sqlite3.connect(str(damaged / "workbook.sqlite")) as db:
                    db.execute(sql, [observation, observation])
                call("condition-inputs", damaged, observation, "-", 50, error="condition_input_integrity")
                call("verify", damaged, error="condition_input_integrity")
            assert inspect(book, observation, "-", 50) == first
            report.update(ok=True, retainedInputs=len(entries), inertReconstruction=True,
                          readOnly=True, corruptedCopiesRefused=2)
    finally:
        report["callCount"] = len(calls)
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
    return report


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cli", type=Path, required=True)
    parser.add_argument("--worker", type=Path, required=True)
    parser.add_argument("--output", type=Path, default=Path(".build/condition-inputs-installed.json"))
    args = parser.parse_args()
    report = run(args.cli.resolve(strict=True), args.worker.resolve(strict=True), args.output)
    print(json.dumps({key: value for key, value in report.items() if key != "calls"}, sort_keys=True))
