#!/usr/bin/env python3
"""Check read-only automatic derivation ancestry in an installed CLI."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import sqlite3
import subprocess
import tempfile


def run(cli, worker, output):
    calls = []
    with tempfile.TemporaryDirectory(prefix="sevra-automatic-ancestry-") as directory:
        folder = Path(directory)
        book = folder / "Ancestry.sevra"
        fixture = subprocess.run(
            [str(worker), "--automatic-ancestry-fixture", str(book)],
            capture_output=True, text=True, timeout=60, check=True)
        assert not fixture.stderr, fixture.stderr
        data = json.loads(fixture.stdout)

        def call(*arguments, error=None):
            result = subprocess.run([str(cli), *map(str, arguments)],
                                    capture_output=True, text=True, timeout=30)
            clean = lambda text: text.replace(str(folder), "<fixture>")
            calls.append({"arguments": [clean(str(a)) for a in arguments],
                          "returncode": result.returncode, "stdout": clean(result.stdout),
                          "stderr": clean(result.stderr)})
            assert (result.returncode == 0) == (error is None), result
            value = json.loads(result.stdout if error is None else result.stderr)
            assert value["ok"] == (error is None), value
            if error:
                assert not result.stdout and value["error"]["code"] == error, value
                return value
            assert not result.stderr, result.stderr
            return value["result"]

        def inspect(target, *ids):
            value = call("automation-ancestry", target, *ids)
            assert value["execution"] == "none" and value["enabled"] is False
            assert value["minimalCausalSlice"] is False
            assert value["dispatchEligibility"] == "not-evaluated"
            assert value["coverage"] == "retained-derivation-graph"
            return value

        before = call("commits", book)
        draft = inspect(book, data["proposalID"])
        accepted = inspect(book, data["acceptedID"])
        assert len(draft["automaticRuns"]) == 1 and len(accepted["automaticRuns"]) == 1
        for value in [draft, accepted]:
            binding = value["automaticRuns"][0]
            assert binding["runID"] == data["runID"]
            assert binding["invocationSourceID"] == data["invocationID"]
            assert binding["automationDefinitionID"] == data["automationID"]
            assert value["automationLogicalIDs"] == [data["automationLogicalID"]]
        assert accepted == inspect(book, data["acceptedID"], data["acceptedID"])
        combined = inspect(book, data["proposalID"], data["acceptedID"])
        assert len(combined["automaticRuns"]) == 1
        assert inspect(book, data["sourceID"])["automaticRuns"] == []
        assert call("commits", book) == before
        restored = folder / "Rebuilt.sevra"
        call("reconstruct", book, restored)
        assert inspect(restored, data["acceptedID"]) == accepted
        assert call("verify", book)["ok"] and call("verify", restored)["ok"]
        call("automation-ancestry", book, error="usage")
        call("automation-ancestry", book, *([data["sourceID"]] * 17), error="usage")
        call("automation-ancestry", book, "", error="ancestry_input")
        call("automation-ancestry", book, "x" * 257, error="ancestry_input")
        call("automation-ancestry", book, "missing", error="ancestry_item")

        # Corrupt isolated copies only. No fixture defect is applied to a user file.
        missing = folder / "MissingBinding.sevra"
        shutil.copytree(book, missing)
        with sqlite3.connect(str(missing / "workbook.sqlite")) as db:
            db.execute("DELETE FROM automation_runs WHERE run_id=?", [data["runID"]])
        call("automation-ancestry", missing, data["acceptedID"], error="ancestry_integrity")
        damaged = folder / "DamagedOrigin.sevra"
        shutil.copytree(book, damaged)
        with sqlite3.connect(str(damaged / "workbook.sqlite")) as db:
            raw = json.loads(db.execute("SELECT data FROM items WHERE id=?",
                                       [data["invocationID"]]).fetchone()[0])
            raw["origin"]["generation"] += 1
            db.execute("UPDATE items SET data=? WHERE id=?", [json.dumps(raw), data["invocationID"]])
        call("automation-ancestry", damaged, data["acceptedID"], error="ancestry_integrity")
        erased = folder / "ErasedMetadata.sevra"
        shutil.copytree(book, erased)
        with sqlite3.connect(str(erased / "workbook.sqlite")) as db:
            db.execute("UPDATE items SET data='{}' WHERE id=?", [data["invocationID"]])
        call("automation-ancestry", erased, data["acceptedID"], error="ancestry_integrity")
        with sqlite3.connect(str(erased / "workbook.sqlite")) as db:
            db.execute("UPDATE items SET kind='observation' WHERE id=?", [data["invocationID"]])
        call("automation-ancestry", erased, data["acceptedID"], error="ancestry_integrity")
        cycle = folder / "Cycle.sevra"
        shutil.copytree(book, cycle)
        with sqlite3.connect(str(cycle / "workbook.sqlite")) as db:
            db.execute("INSERT INTO lineage VALUES(?,?,'derives-from','synthetic-corruption')",
                       [data["sourceID"], data["acceptedID"]])
        call("automation-ancestry", cycle, data["acceptedID"], error="ancestry_cycle")
        assert inspect(book, data["acceptedID"]) == accepted
    report = {"version": 1, "scope": "installed read-only automatic derivation ancestry",
              "cliSHA256": hashlib.sha256(cli.read_bytes()).hexdigest(),
              "workerSHA256": hashlib.sha256(worker.read_bytes()).hexdigest(),
              "callCount": len(calls), "actualModel": False, "automaticDispatch": False,
              "minimalCausalSlice": False, "visibleOS": False, "calls": calls}
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(report, sort_keys=True, indent=2) + "\n")
    return report


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cli", type=Path, required=True)
    parser.add_argument("--worker", type=Path, required=True)
    parser.add_argument("--output", type=Path, default=Path(".build/automatic-ancestry-cli.json"))
    args = parser.parse_args()
    report = run(args.cli.resolve(strict=True), args.worker.resolve(strict=True), args.output)
    print(json.dumps({key: value for key, value in report.items() if key != "calls"}, sort_keys=True))
