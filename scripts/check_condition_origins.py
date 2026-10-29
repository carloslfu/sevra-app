#!/usr/bin/env python3
"""Qualify exact condition-window business origins through an installed CLI."""
import argparse
import concurrent.futures
import hashlib
import json
from pathlib import Path
import shutil
import sqlite3
import subprocess
import tempfile


def run(cli, worker, output):
    calls = []
    with tempfile.TemporaryDirectory(prefix="sevra-condition-origins-") as directory:
        folder = Path(directory)

        def fixture(name, flag):
            book = folder / (name + ".sevra")
            result = subprocess.run([str(worker), flag, str(book)],
                                    capture_output=True, text=True, timeout=60, check=True)
            assert not result.stderr, result.stderr
            return book, json.loads(result.stdout)

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

        def inspect(book, observation):
            value = call("condition-origins", book, observation)
            assert value["policy"] == "condition-business-origins-v1"
            assert value["observationID"] == observation
            assert value["coverage"] == "complete-retained-window-to-automatic-producers"
            assert value["minimalCauseSet"] is False
            assert value["independentBusinessRoots"] == "not-established"
            assert value["dispatchEligibility"] == "not-evaluated"
            assert value["execution"] == "none" and value["enabled"] is False
            assert value["inputInspection"] == {"command": "condition-inputs", "observationID": observation}
            with sqlite3.connect(book / "workbook.sqlite") as db:
                pairs = [[identity, json.loads(raw)] for identity, raw in db.execute(
                    "SELECT id,payload FROM condition_observation_inputs WHERE observation_id=? ORDER BY id", [observation])]
            digest = hashlib.sha256(json.dumps(pairs, ensure_ascii=False, sort_keys=True,
                                              separators=(",", ":")).encode()).hexdigest()
            assert value["inputSetHash"] == digest and value["inputCount"] == len(pairs)
            starts = sorted({entry[key] for _, entry in pairs for key in ["beforeID", "afterID"] if entry[key] is not None})
            assert value["origins"]["inputs"] == starts
            assert value["automaticProducerRunIDs"] == [p["runID"] for p in value["origins"]["automaticProducers"]]
            return value

        book, data = fixture("Automatic", "--condition-origin-fixture")
        before = call("commits", book)
        state = call("condition-state", book, data["consumerID"])
        value = inspect(book, data["observationID"])
        assert value["inputCount"] == 1 and value["automaticProducerRunIDs"] == [data["runID"]]
        assert value["previousCertainObservationID"] == data["baselineID"]
        assert value["origins"]["inputs"] == sorted([data["acceptedID"], data["correctionID"]])
        assert value == inspect(book, data["observationID"])
        assert call("commits", book) == before and call("condition-state", book, data["consumerID"]) == state
        rebuilt = folder / "Rebuilt.sevra"
        call("reconstruct", book, rebuilt)
        assert inspect(rebuilt, data["observationID"]) == value
        assert call("verify", book)["ok"] and call("verify", rebuilt)["ok"]
        call("condition-origins", book, error="usage")
        call("condition-origins", book, data["observationID"], "extra", error="usage")
        call("condition-origins", book, "", error="condition_input")
        call("condition-origins", book, "x" * 257, error="condition_input")
        call("condition-origins", book, "missing", error="condition_observation")
        call("condition-origins", book, data["baselineID"], error="condition_origin_coverage")

        paged, page_data = fixture("Paged", "--condition-inputs-fixture")
        paged_before = call("commits", paged)
        page_value = inspect(paged, page_data["observationID"])
        assert page_value["inputCount"] == 205
        assert len(page_value["origins"]["inputs"]) == 205 and page_value["origins"]["itemCount"] == 206
        assert page_value["automaticProducerRunIDs"] == []
        members = []
        cursor = "-"
        while True:
            page = call("condition-inputs", paged, page_data["observationID"], cursor, 50)
            members += page["entries"]
            if not page["hasMore"]:
                break
            cursor = page["nextCursor"]
        assert len(members) == 205
        with concurrent.futures.ThreadPoolExecutor(max_workers=6) as pool:
            readers = list(pool.map(lambda _: inspect(paged, page_data["observationID"]), range(6)))
        assert all(result == page_value for result in readers)
        assert call("commits", paged) == paged_before
        assert call("verify", paged)["ok"]

        for case in ["missing", "foreign", "event", "previous", "seal", "oversize", "admission"]:
            damaged = folder / (case + ".sevra")
            shutil.copytree(book, damaged)
            error = "condition_input_integrity"
            with sqlite3.connect(damaged / "workbook.sqlite") as db:
                observation = data["observationID"]
                if case == "missing":
                    db.execute("DELETE FROM condition_observation_inputs WHERE observation_id=?", [observation])
                elif case == "foreign":
                    db.execute("UPDATE condition_observation_inputs SET id='foreign' WHERE observation_id=?", [observation])
                elif case == "event":
                    db.execute("UPDATE condition_observation_inputs SET payload=json_set(payload,'$.eventID','foreign') WHERE observation_id=?", [observation])
                elif case == "previous":
                    db.execute("UPDATE condition_observations SET payload=json_set(payload,'$.previousObservationID','foreign') WHERE id=?", [observation])
                elif case == "seal":
                    db.execute("UPDATE items SET derivation='{}' WHERE id=?", [data["correctionID"]])
                    error = "derivation_integrity"
                elif case == "oversize":
                    db.execute("UPDATE condition_observation_inputs SET payload=? WHERE observation_id=?", ["x" * 16385, observation])
                    error = "condition_origin_limit"
                else:
                    db.execute("DELETE FROM automatic_root_members WHERE run_id=?", [data["runID"]])
                    error = "causal_integrity"
            call("condition-origins", damaged, data["observationID"], error=error)
        assert inspect(book, data["observationID"]) == value
        assert call("commits", book) == before
    report = {"version": 1, "scope": "read-only exact complete condition-window business origins; no independent-root or dispatch claim",
              "cliSHA256": hashlib.sha256(cli.read_bytes()).hexdigest(),
              "workerSHA256": hashlib.sha256(worker.read_bytes()).hexdigest(),
              "callCount": len(calls), "independentReaders": 6, "independentInputHash": True,
              "pagedInputs": 205, "actualModel": False, "automaticDispatch": False,
              "visibleOS": False, "calls": calls}
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(report, sort_keys=True, indent=2) + "\n")
    return report


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cli", type=Path, required=True)
    parser.add_argument("--worker", type=Path, required=True)
    parser.add_argument("--output", type=Path, default=Path(".build/condition-origins-cli.json"))
    args = parser.parse_args()
    report = run(args.cli.resolve(strict=True), args.worker.resolve(strict=True), args.output)
    print(json.dumps({key: value for key, value in report.items() if key != "calls"}, sort_keys=True))
