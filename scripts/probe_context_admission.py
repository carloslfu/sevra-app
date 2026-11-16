"""Bounded startup-only context/memory checks, independent of job qualification."""
import argparse
import json
import os
from pathlib import Path
import re
import signal
import subprocess

from compare_splash_performance import ROOT, Sampler, environment, line, save, sha
from compare_workflow_performance import assert_available
from probe_workflow_prefix import resource_files


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--models-root", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    protocol_path = ROOT / "integration/performance/context-admission-protocol.json"
    protocol = json.loads(protocol_path.read_text())
    pin = json.loads((ROOT / "integration/splash.json").read_text())
    runtime = ROOT / ".build/upstream" / ("splash-native-" + pin["release"])
    for name, digest in pin["runtime"]["files"].items():
        if sha(runtime / name) != digest:
            raise RuntimeError("Engine differs from candidate pin")
    binary = ROOT / ".build/debug/sevra-splash-checks"
    assembly = args.models_root.resolve() / "qwen36-35b-a3b-4bit"
    files = [binary, Path(__file__), protocol_path, assembly / "model.json",
             ROOT / "integration/splash.json", *resource_files(binary)]
    files += [runtime / name for name in pin["runtime"]["files"]]
    files += list((ROOT / "Sources").rglob("*.swift"))
    files += list((ROOT / "IntegrationTests/Splash").glob("*.swift"))
    frozen = {str(p.resolve()): sha(p) for p in files}
    save(output / "identity.json", {"protocol": protocol, "frozenFiles": frozen,
                                   "head": subprocess.check_output(
                                       ["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip()})
    physical = int(subprocess.check_output(["sysctl", "-n", "hw.memsize"], text=True))
    results = []
    for context, memory in protocol["cells"]:
        assert_available()
        if any(sha(Path(p)) != digest for p, digest in frozen.items()):
            raise RuntimeError("Frozen admission input changed")
        folder = output / f"{context // 1024}k-{memory}g"
        folder.mkdir()
        before = environment()
        result = {"contextTokens": context, "memoryGiB": memory, "before": before,
                  "events": [], "failure": None}
        free = re.search(r"free percentage: (\d+)%", before.get("pressure", ""))
        if not free or physical * int(free[1]) // 100 < (memory + 8) * 1024**3:
            result["preflightRefusal"] = "Unknown or insufficient available-headroom estimate"
        elif before.get("thermalState", 99) >= 2:
            result["preflightRefusal"] = "Serious or unknown thermal state"
        else:
            stderr = (folder / "stderr.log").open("w")
            process = subprocess.Popen([
                str(binary), "--admit-engine", str(runtime / "engine/splash"),
                str(assembly), str(context), str(memory * 1024**3),
            ], stdout=subprocess.PIPE, stderr=stderr, stdin=subprocess.DEVNULL, start_new_session=True)
            sampler = None
            try:
                while True:
                    row = line(process, timeout=240)
                    result["events"].append(row)
                    if row.get("event") == "launched":
                        sampler = Sampler([row["hostPID"], row["helperPID"]])
                        sampler.thread.start()
                    if row.get("event") == "complete":
                        if not row.get("closed"):
                            raise RuntimeError("Admission helper was not reaped")
                        break
                process.wait(timeout=15)
                result["returncode"] = process.returncode
                if process.returncode:
                    raise RuntimeError("Admission worker failed")
            except Exception as error:
                result["failure"] = str(error)
            finally:
                if sampler:
                    result["memory"] = sampler.stop()
                    save(folder / "memory.json", sampler.samples)
                if process.poll() is None:
                    os.killpg(process.pid, signal.SIGTERM)
                    try:
                        process.wait(timeout=5)
                    except subprocess.TimeoutExpired:
                        os.killpg(process.pid, signal.SIGKILL)
                        process.wait()
                stderr.close()
            result["after"] = environment()
            assert_available()
        results.append(result)
        save(folder / "result.json", result)
        save(output / "summary.json", {"results": results, "generatedRequests": 0,
                                       "taskQualification": False, "productionAdoption": False})
        print(json.dumps({k: result.get(k) for k in
                          ("contextTokens", "memoryGiB", "preflightRefusal", "failure")}
                         | {"admission": next((e for e in result["events"]
                                               if e.get("event") == "admission"), None)}), flush=True)
        if result["failure"] or any(e.get("event") == "failure" for e in result["events"]):
            raise RuntimeError("Admission worker failed; stop before any further helper launch")
        if any(e.get("criticalPressureStop") or e.get("thermalState", 0) >= 2
               for e in result["events"]) or result.get("memory", {}).get("maximumThermalState", 0) >= 2:
            raise RuntimeError("Safety stop: remaining admission cells are untested")
    if any(sha(Path(p)) != digest for p, digest in frozen.items()):
        raise RuntimeError("Frozen admission input changed during execution")


if __name__ == "__main__":
    main()
