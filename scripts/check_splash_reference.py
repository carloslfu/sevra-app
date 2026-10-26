#!/usr/bin/env python3
"""Development reference only. Never installed in Sevra.app.

Run with the pinned Splash install/requirements.txt in an isolated environment.
This checks assembly bytes and native transport, not full frontend or speed parity.
"""
import argparse
import json
import os
from pathlib import Path
import signal
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("target", type=Path)
    parser.add_argument("draft", type=Path)
    parser.add_argument("--output", type=Path, required=True, help="new evidence directory")
    parser.add_argument("--run-engine", action="store_true")
    parser.add_argument("--memory-bytes", type=int, default=22 * 1024**3)
    args = parser.parse_args()
    pin = json.loads((ROOT / "integration/splash.json").read_text())
    upstream = ROOT / ".build/upstream" / ("splash-" + pin["release"])
    engine = ROOT / ".build/upstream" / ("splash-native-" + pin["release"]) / "engine/splash"
    checks = ROOT / ".build/debug/sevra-splash-checks"
    revision = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=upstream, text=True).strip()
    if revision != pin["commit"]:
        raise RuntimeError("Reference source does not match the integration pin")
    if subprocess.check_output(["git", "status", "--porcelain"], cwd=upstream):
        raise RuntimeError("Reference source has local changes")
    args.output.mkdir(parents=True, exist_ok=False)
    target, draft = args.target.resolve(), args.draft.resolve()
    prepared = subprocess.check_output([
        str(checks), "--prepare", str(target), str(draft), str(args.output / "native-models")
    ], text=True)
    native = json.loads(prepared)
    (args.output / "preparation.json").write_text(prepared)
    # Use the unchanged Python preparation API with the pinned native executable.
    sys.path.insert(0, str(upstream))
    from install import paths
    paths.BINARY = engine
    from install.local import prepare_local_model
    reference = prepare_local_model(target, draft, language_only=True,
                                    models_dir=args.output / "reference-models")
    native_assembly = Path(native["assembly"])
    native_record = (native_assembly / "model.json").read_bytes()
    reference_record = (reference / "model.json").read_bytes()
    if native_record != reference_record:
        raise RuntimeError("Native and upstream model.json differ; evidence preserved")
    result = {"preparationByteIdentical": True, "recordBytes": len(native_record),
              "release": pin["release"], "commit": revision, "python": sys.version,
              "nativePreparationSeconds": native["seconds"]}

    from transformers import AutoTokenizer
    tokenizer = AutoTokenizer.from_pretrained(str(target), local_files_only=True)
    messages = [
        {"role": "system", "content": "You are a concise assistant."},
        {"role": "user", "content": "Reply with exactly these four words: The workbook is ready."},
    ]
    full = tokenizer.apply_chat_template(messages, tokenize=False,
                                        add_generation_prompt=True, enable_thinking=False)
    base = tokenizer.apply_chat_template(messages, tokenize=False,
                                        add_generation_prompt=False, enable_thinking=False)
    if not full.startswith(base):
        raise RuntimeError("Selected template generation prefix changed")
    tokens = tokenizer(full, add_special_tokens=False)["input_ids"]
    prefix = tokenizer(full[len(base):], add_special_tokens=False)["input_ids"]
    if not prefix or tokens[-len(prefix):] != prefix:
        raise RuntimeError("Generation prefix tokenization changed")
    prompt = args.output / "prompt.json"
    prompt.write_text(json.dumps({"prompt": tokens, "maxOutput": 48, "generationTokens": len(prefix)}))
    (args.output / "request.json").write_text(json.dumps({"messages": messages, "enable_thinking": False}))
    if args.run_engine:
        environment = dict(os.environ, SEVRA_SPLASH_PROBE_MEMORY_BYTES=str(args.memory_bytes))
        job = subprocess.Popen([str(checks), "--run-engine", str(engine), str(native_assembly), str(prompt)],
                               stdout=subprocess.PIPE, stderr=subprocess.PIPE, start_new_session=True, env=environment)
        try:
            stdout, stderr = job.communicate(timeout=600)
        except BaseException:
            os.killpg(job.pid, signal.SIGKILL)
            job.wait()
            raise
        (args.output / "native-results.jsonl").write_bytes(stdout)
        (args.output / "native-errors.log").write_bytes(stderr)
        if job.returncode:
            raise RuntimeError("Native engine probe failed; evidence preserved")
        rows = [json.loads(line) for line in stdout.splitlines()]
        responses = [row for row in rows if "request" in row]
        if [row["request"] for row in responses] != [1, 2, 3, 4, 6]:
            raise RuntimeError("Missing native request results")
        for row in responses:
            if row["request"] == 3:
                if row["finish"] != 2:
                    raise RuntimeError("Cancellation did not complete")
            elif tokenizer.decode(row["tokens"], skip_special_tokens=True).strip() != "The workbook is ready.":
                raise RuntimeError("Unexpected real-model answer")
        status = rows[-1]["status"]
        if not status["weights"]["released"] or not status["metal"]["healthy"]:
            raise RuntimeError("Native release or Metal health check failed")
        result.update({"nativeRequestsPassed": True, "memoryBudgetBytes": args.memory_bytes,
                       "requests": status["requests"], "memoryActual": status["memory_actual"],
                       "streamedExperts": status["streamed_experts"],
                       "limit": "Short transport/recovery smoke test; not frontend or performance qualification."})
    (args.output / "summary.json").write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps(result))


if __name__ == "__main__":
    main()
