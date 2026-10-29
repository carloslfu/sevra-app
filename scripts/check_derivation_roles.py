#!/usr/bin/env python3
"""Qualify named lineage roles and complete seals through an installed CLI."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import sqlite3
import subprocess
import tempfile


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def snapshot(book):
    with sqlite3.connect(book / "workbook.sqlite") as db:
        assert db.execute("PRAGMA user_version").fetchone()[0] == 29
        items = db.execute("SELECT id,supersedes,derivation FROM items ORDER BY id").fetchall()
        result = []
        for identity, supersedes, raw in items:
            edges = db.execute(
                "SELECT parent,relation,transformation,roles FROM lineage WHERE child=? ORDER BY parent,relation",
                [identity]).fetchall()
            business = False
            revisions = []
            for parent, relation, transformation, roles in edges:
                assert ((relation == "derives-from" and 1 <= roles <= 7)
                        or (relation == "definition-input" and roles == 2)
                        or (relation == "supersedes" and roles == 8))
                assert db.execute("SELECT 1 FROM items WHERE id=?", [parent]).fetchone()
                business |= bool(roles & 13)
                if relation == "supersedes":
                    revisions.append(parent)
            assert revisions == ([] if supersedes is None else [supersedes])
            digest = hashlib.sha256(json.dumps(
                edges, ensure_ascii=False, separators=(",", ":")).encode()).hexdigest()
            seal = json.loads(raw)
            assert seal == {"policy": "item-derivation-v1", "itemID": identity,
                            "edgeCount": len(edges), "edgeHash": digest,
                            "classification": "retained-derivation" if business else "unclassified-original"}
            result.append([identity, supersedes, seal, edges])
        return result


def run(cli, worker, output):
    calls = []
    with tempfile.TemporaryDirectory(prefix="sevra-derivation-roles-") as directory:
        folder = Path(directory)
        book = folder / "Roles.sevra"
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

        generic = call("add", book, json.dumps({
            "category": "record", "kind": "document", "title": "Generic conservative input",
            "inputs": [data["sourceID"]], "token": "generic-role-check"}))
        generic_id = generic["id"]
        before = call("commits", book)
        retained = snapshot(book)
        for identity in [data["proposalID"], data["acceptedID"], data["invocationID"]]:
            edges = call("lineage", book, identity)
            assert edges and all(isinstance(edge["roles"], list) and edge["roles"] for edge in edges)
            assert all(set(edge["roles"]) <= {"data", "control", "producer", "revision"} for edge in edges)
        trace = call("automation-ancestry", book, data["acceptedID"])
        assert all(isinstance(edge["roles"], list) for edge in trace["edges"])
        assert trace["enabled"] is False and trace["execution"] == "none"
        assert trace["dispatchEligibility"] == "not-evaluated"
        assert call("commits", book) == before and snapshot(book) == retained
        restored = folder / "Rebuilt.sevra"
        call("reconstruct", book, restored)
        assert snapshot(restored) == retained
        assert call("lineage", book, data["acceptedID"]) == call("lineage", restored, data["acceptedID"])
        assert call("verify", book)["ok"] and call("verify", restored)["ok"]
        # Damage disposable copies, never a user's workbook. Use a generic data
        # edge so an earlier workflow-specific integrity check cannot mask this gate.
        spare = next(row[0] for row in retained if row[0] != data["sourceID"])
        for case in ["missing", "changed", "erased", "foreign", "extra", "unsupported"]:
            damaged = folder / (case + ".sevra")
            shutil.copytree(book, damaged)
            with sqlite3.connect(damaged / "workbook.sqlite") as db:
                if case == "missing":
                    db.execute("DELETE FROM lineage WHERE child=? AND relation='derives-from'", [generic_id])
                elif case == "changed":
                    db.execute("UPDATE lineage SET roles=2 WHERE child=? AND relation='derives-from'", [generic_id])
                elif case == "erased":
                    db.execute("UPDATE items SET derivation='{}' WHERE id=?", [data["sourceID"]])
                elif case == "foreign":
                    db.execute("UPDATE items SET derivation=json_set(derivation,'$.itemID','other') WHERE id=?", [data["sourceID"]])
                elif case == "extra":
                    db.execute("INSERT INTO lineage VALUES(?,?,'derives-from','synthetic',1)", [data["sourceID"], spare])
                else:
                    db.execute("UPDATE items SET derivation=json_set(derivation,'$.policy','unsupported') WHERE id=?", [data["sourceID"]])
            call("verify", damaged, error="derivation_integrity")
        assert call("commits", book) == before and snapshot(book) == retained
    report = {"version": 1, "scope": "schema29 role capture and named lineage; no business-origin resolution or condition dispatch",
              "cliSHA256": sha(cli), "workerSHA256": sha(worker), "callCount": len(calls),
              "verifiedItems": len(retained), "independentSealHashes": True,
              "actualModel": False, "automaticDispatch": False, "visibleOS": False, "calls": calls}
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(report, sort_keys=True, indent=2) + "\n")
    return report


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cli", type=Path, required=True)
    parser.add_argument("--worker", type=Path, required=True)
    parser.add_argument("--output", type=Path, default=Path(".build/derivation-roles-cli.json"))
    args = parser.parse_args()
    report = run(args.cli.resolve(strict=True), args.worker.resolve(strict=True), args.output)
    print(json.dumps({key: value for key, value in report.items() if key != "calls"}, sort_keys=True))
