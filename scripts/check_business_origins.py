#!/usr/bin/env python3
"""Qualify bounded business origins and excluded configuration in an installed CLI."""
import argparse
import copy
import hashlib
import json
from pathlib import Path
import shutil
import sqlite3
import subprocess
import tempfile
import uuid


def run(cli, worker, output):
    calls = []
    with tempfile.TemporaryDirectory(prefix="sevra-business-origins-") as directory:
        folder = Path(directory)
        book = folder / "Origins.sevra"
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
            value = call("business-origins", target, *ids)
            assert value["policy"] == "business-origins-v1"
            assert value["execution"] == "none" and value["enabled"] is False
            assert value["minimalCauseSet"] is False
            assert value["independentBusinessRoots"] == "not-established"
            assert value["dispatchEligibility"] == "not-evaluated"
            assert value["coverage"] == "retained-business-dependencies-to-automatic-producers"
            assert value["itemCount"] == len(value["items"])
            assert value["edgeCount"] == len(value["edges"])
            assert all(set(edge["roles"]) <= {"data", "control", "producer", "revision"}
                       for edge in value["edges"])
            return value

        def save(content, token, inputs=()):
            return call("definition-save", book, uuid.uuid4(), json.dumps(content),
                        "new", token, json.dumps(inputs))

        # An automatically authored definition is configuration. Its origin
        # remains inspectable in the broad graph but cannot taint unrelated data.
        template = call("receiving-template", book)
        action = save(template, "automatic-config", [data["acceptedID"]])
        saved_workflow = call("definition-read", book, data["workflowID"])
        workflow_content = {key: saved_workflow[key] for key in
                            ["kind", "title", "description", "parameters", "payload"]}
        workflow_content["payload"]["steps"][0]["binding"]["versionID"] = action["id"]
        workflow = save(workflow_content, "manual-workflow")
        arguments = copy.deepcopy(data["arguments"])
        arguments["delivery"] = "independent-manual-delivery"
        manual = call("workflow-start", book, workflow["id"], json.dumps(arguments), "manual")
        waiting = call("workflow-continue", book, manual["id"], folder / "absent-model")
        manual_id = waiting["steps"][0]["output"]["value"]["proposals"][0]
        assert len(call("automation-ancestry", book, manual_id)["automaticRuns"]) == 1

        # A later human Source that explicitly uses automatic business data
        # remains derived from that producer, regardless of its category.
        derived = call("add", book, json.dumps({
            "category": "source", "kind": "observation", "title": "Human explanation",
            "inputs": [data["acceptedID"]], "token": "derived-human"}))
        constant = call("add", book, json.dumps({
            "category": "source", "kind": "annotation", "title": "Unclassified technical metadata",
            "token": "constant"}))
        function = save({
            "kind": "function", "title": "Double", "description": "Synthetic",
            "parameters": [{"id": "x", "label": "Count", "type": "decimal", "required": True}],
            "payload": {"expression": "x*2"}}, "function")
        evaluation = call("definition-evaluate", book, function["id"], '{"x":"3"}')
        published = call("definition-publish", book, json.dumps({
            "id": function["id"], "arguments": {"x": "3"}, "evaluation": evaluation,
            "title": "Expected count", "meaning": "estimate", "inputs": [data["sourceID"]]}), "publish")
        before = call("commits", book)
        draft = inspect(book, data["proposalID"])
        accepted = inspect(book, data["acceptedID"])
        human = inspect(book, derived["id"])
        for value in [draft, accepted, human]:
            assert len(value["automaticProducers"]) == 1
            producer = value["automaticProducers"][0]
            assert producer["runID"] == data["runID"]
            assert producer["invocationSourceID"] == data["invocationID"]
            assert producer["admission"]["depth"] == 1
            boundary = producer["invocationSourceID"]
            assert all(not edge["traversed"] for edge in value["edges"] if edge["child"] == boundary)
        assert accepted == inspect(book, data["acceptedID"], data["acceptedID"])
        manual_trace = inspect(book, manual_id)
        assert manual_trace["automaticProducers"] == []
        assert manual_trace["originalInputCandidates"] == [data["sourceID"]]
        assert any(link["parent"] == action["sourceID"] for link in manual_trace["controlLinks"])
        assert not any(item["id"] == data["acceptedID"] for item in manual_trace["items"])
        assert inspect(book, data["sourceID"])["originalInputCandidates"] == [data["sourceID"]]
        unknown = inspect(book, constant["id"])
        assert unknown["originalInputCandidates"] == [] and len(unknown["unclassifiedOrigins"]) == 1
        assert inspect(book, published["id"])["originalInputCandidates"] == [data["sourceID"]]
        assert call("commits", book) == before
        rebuilt = folder / "Rebuilt.sevra"
        call("reconstruct", book, rebuilt)
        assert inspect(rebuilt, data["acceptedID"]) == accepted
        assert inspect(rebuilt, manual_id) == manual_trace
        assert call("verify", book)["ok"] and call("verify", rebuilt)["ok"]
        call("business-origins", book, error="usage")
        call("business-origins", book, *([data["sourceID"]] * 17), error="usage")
        call("business-origins", book, "", error="origin_input")
        call("business-origins", book, "x" * 257, error="origin_input")
        call("business-origins", book, "missing", error="origin_item")

        # Corrupt only disposable copies. Missing/changed retained edges must
        # refuse, never silently reclassify an incomplete graph as independent.
        for case in ["missing-edge", "changed-role", "erased-seal", "foreign-seal",
                     "missing-admission", "erased-producer", "changed-kind", "unsupported-direct"]:
            damaged = folder / (case + ".sevra")
            shutil.copytree(book, damaged)
            target = data["acceptedID"]
            error = "derivation_integrity"
            with sqlite3.connect(damaged / "workbook.sqlite") as db:
                if case == "missing-edge":
                    db.execute("DELETE FROM lineage WHERE child=?", [target])
                elif case == "changed-role":
                    db.execute("UPDATE lineage SET roles=2 WHERE child=?", [data["proposalID"]])
                elif case == "erased-seal":
                    db.execute("UPDATE items SET derivation='{}' WHERE id=?", [target])
                elif case == "foreign-seal":
                    db.execute("UPDATE items SET derivation=json_set(derivation,'$.itemID','foreign') WHERE id=?", [target])
                elif case == "missing-admission":
                    db.execute("DELETE FROM automatic_root_members WHERE run_id=?", [data["runID"]])
                    error = "causal_integrity"
                elif case == "erased-producer":
                    db.execute("UPDATE items SET data='{}' WHERE id=?", [data["invocationID"]])
                    error = "ancestry_integrity"
                elif case == "changed-kind":
                    db.execute("UPDATE items SET kind='observation' WHERE id=?", [data["invocationID"]])
                    error = "origin_producer"
                else:
                    target = published["id"]
                    producer = db.execute("SELECT parent FROM lineage WHERE child=? AND roles=4", [target]).fetchone()[0]
                    db.execute("UPDATE items SET data=json_set(data,'$.producerPolicy','unsupported') WHERE id=?", [producer])
                    error = "origin_producer"
            call("business-origins", damaged, target, error=error)
        assert inspect(book, data["acceptedID"]) == accepted
        assert call("commits", book) == before
    report = {"version": 1, "scope": "bounded historical business dependencies; configuration separate; no dispatch or independence claim",
              "cliSHA256": hashlib.sha256(cli.read_bytes()).hexdigest(),
              "workerSHA256": hashlib.sha256(worker.read_bytes()).hexdigest(),
              "callCount": len(calls), "actualModel": False, "automaticDispatch": False,
              "independentBusinessRoots": False, "visibleOS": False, "calls": calls}
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(report, sort_keys=True, indent=2) + "\n")
    return report


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cli", type=Path, required=True)
    parser.add_argument("--worker", type=Path, required=True)
    parser.add_argument("--output", type=Path, default=Path(".build/business-origins-cli.json"))
    args = parser.parse_args()
    report = run(args.cli.resolve(strict=True), args.worker.resolve(strict=True), args.output)
    print(json.dumps({key: value for key, value in report.items() if key != "calls"}, sort_keys=True))
