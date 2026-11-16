"""Bounded old/new native diagnostic using frozen corrected-host workers.

One warmup and one measured attempt per job. Retain failures and include repair
time. This pilot cannot qualify timing or clear the separate repeatability gate.
"""
import argparse
import json
from pathlib import Path

from compare_splash_performance import ROOT, save, sha
from compare_workflow_performance import worker
from probe_workflow_prefix import resource_files


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("old-workers", "new-workers", "old-models", "new-models", "output"):
        parser.add_argument("--" + name, type=Path, required=True)
    args = parser.parse_args()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    guidance = json.loads((ROOT / ".build/llguidance-receipt.json").read_text())
    protocol = json.loads((ROOT / "integration/performance/inference-upgrade-protocol.json").read_text())
    jobs = protocol["upgradeComparison"]["workloads"]
    arms = []
    frozen = {}
    for label, workers, models, pin_file in [
        ("control", args.old_workers, args.old_models, "splash-1.4.1-preserved.json"),
        ("candidate", args.new_workers, args.new_models, "splash.json"),
    ]:
        pin = json.loads((ROOT / "integration" / pin_file).read_text())
        binary = workers.resolve() / "sevra-workflow-performance"
        engine_root = ROOT / ".build/upstream" / ("splash-native-" + pin["release"])
        for name, expected in pin["runtime"]["files"].items():
            if sha(engine_root / name) != expected:
                raise RuntimeError("Runtime differs from preserved pin")
        manifest = json.loads((workers / "manifest.json").read_text())
        expected = manifest.get("binarySHA256", manifest.get("files", {}))[binary.name]
        if sha(binary) != expected:
            raise RuntimeError("Frozen worker differs from its manifest")
        config = dict(protocol["control"], engine=str(engine_root / "engine/splash"),
                      engineFiles={Path(k).name: v for k, v in pin["runtime"]["files"].items()
                                   if k.startswith("engine/")},
                      grammarLibrary=str(ROOT / guidance["library"]),
                      grammarSHA256=guidance["librarySHA256"],
                      modelsRoot=str(models.resolve()), workflowQualification=True)
        paths = [binary, workers / "manifest.json", ROOT / "integration" / pin_file,
                 ROOT / guidance["library"], *resource_files(binary)]
        paths += [engine_root / name for name in pin["runtime"]["files"]]
        frozen.update({str(p.resolve()): sha(p) for p in paths})
        arms.append((label, binary, config, pin["release"]))
    frozen[str(Path(__file__).resolve())] = sha(Path(__file__))
    save(output / "identity.json", {
        "scope": "Frozen P1-corrected 1.4.1 versus P2 1.6.1 native pilot",
        "order": [arm[0] for arm in arms], "jobs": jobs, "frozenFiles": frozen,
        "performanceQualification": False, "productionAdoption": False,
        "limits": "Sequential one-pair pilot; no speedup or tail-latency claim. Later history/navigation changes are outside these frozen workers.",
    })
    results = []
    for label, binary, config, release in arms:
        if any(sha(Path(path)) != digest for path, digest in frozen.items()):
            raise RuntimeError("Frozen pilot input changed")
        folder = output / label
        folder.mkdir()
        config_path = folder / "config.json"
        save(config_path, config)
        result = worker("native", 9, jobs, 1, config_path, folder, binary)
        results.append({"arm": label, "release": release, "result": result})
        save(output / "summary.json", {
            "performanceQualification": False, "productionAdoption": False,
            "arms": [{"arm": r["arm"], "release": r["release"],
                      "failure": r["result"]["failure"],
                      "jobs": [{k: row.get(k) for k in
                                ("id", "seed", "warmup", "completeSeconds", "errors", "validationFailures", "memory")}
                               for row in r["result"]["rows"]]} for r in results],
        })
        if result.get("failure"):
            raise RuntimeError("Pilot worker failed; retain evidence before investigating")
    if any(sha(Path(path)) != digest for path, digest in frozen.items()):
        raise RuntimeError("Frozen pilot input changed during execution")


if __name__ == "__main__":
    main()
