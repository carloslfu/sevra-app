"""Opt-in actual native CLI death during context maintenance, then an ordinary follow-up.

Requires the built native preview, installed selected weights, an idle model and the output
folder of one --active-context-maintained run, which supplies the synthetic fixture and request.
Only a new copy of that workbook and the spawned CLI and helper are affected.
"""
import argparse
import fcntl
import json
import os
from pathlib import Path
import re
import selectors
import signal
import subprocess
import time

from check_native_recovery import await_helpers_exit, command_for, emit, helpers_for, require

FOLLOW_UP = "Please continue and finish the request you were working on."
MAINTENANCE = b"Keeping conversation context"


def main():
    root = Path(__file__).resolve().parent.parent
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cli", type=Path, default=root / "output/native/bin/sevra")
    parser.add_argument("--models", type=Path, required=True)
    parser.add_argument("--fixture", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--stop-at", type=int, default=2, help="Which maintenance pass to die in.")
    args = parser.parse_args()
    cli = args.cli.resolve()
    models = args.models.resolve()
    args.output.mkdir(parents=False, exist_ok=False)
    book = args.output.resolve() / "Recovery.sevra"
    prompt = (args.fixture / "request.txt").read_text()
    lease_path = Path.home() / "Library/Application Support/Sevra/inference.lock"
    lease = os.open(lease_path, os.O_RDWR | os.O_CREAT | os.O_NOFOLLOW | os.O_CLOEXEC, 0o600)
    fcntl.flock(lease, fcntl.LOCK_EX | fcntl.LOCK_NB)
    fcntl.flock(lease, fcntl.LOCK_UN)
    process = None
    helpers = {}

    def invoke(*arguments, timeout=180):
        command = [str(cli), *map(str, arguments)]
        if arguments[0] == "ask":
            command.append(str(models))
        result = subprocess.run(command, capture_output=True, text=True, timeout=timeout)
        require(result.returncode == 0, result.stderr)
        reply = json.loads(result.stdout)
        require(reply["ok"], reply)
        return reply["result"]

    def drafts():
        return [item for item in invoke("records", book)
                if item["kind"] == "document" and item["category"] == "record"]

    def spaces():
        return [space for space in invoke("spaces", book) if space["title"] == "Receiving review"]

    try:
        invoke("open-archive", (args.fixture / "Fixture.sevraz").resolve(), book)
        started = time.monotonic()
        process = subprocess.Popen([str(cli), "ask", str(book), prompt, str(models)],
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE, bufsize=0)
        progress = bytearray()
        reached = False
        with selectors.DefaultSelector() as selector:
            selector.register(process.stderr, selectors.EVENT_READ)
            while time.monotonic() < started + 420 and process.poll() is None:
                if not selector.select(timeout=1):
                    continue
                progress.extend(os.read(process.stderr.fileno(), 65536))
                if progress.count(MAINTENANCE) >= args.stop_at:
                    reached = True
                    break
        require(reached, "Maintenance did not start: " + progress.decode(errors="replace")[-800:])
        helpers = helpers_for(process.pid)
        require(helpers, "No child native helper observed")
        process.kill()
        process.communicate(timeout=15)
        require(process.returncode == -signal.SIGKILL, "CLI did not terminate by injected SIGKILL")
        exited = await_helpers_exit(helpers)
        require(exited, "Native helper survived owner death; cleanup will be attempted")
        fcntl.flock(lease, fcntl.LOCK_EX | fcntl.LOCK_NB)
        fcntl.flock(lease, fcntl.LOCK_UN)
        stopped = invoke("runs", book)[0]
        require(stopped["status"] == "running", "The death did not leave an unfinished run")
        require(invoke("verify", book)["ok"], "The workbook failed integrity after the death")
        require(len(spaces()) == 1 and not drafts(), "The death left the wrong saved work")
        emit(stage="owner_death", seconds=round(time.monotonic() - started, 1), helpersExited=exited,
             maintenancePasses=progress.count(MAINTENANCE))

        started = time.monotonic()
        response = invoke("ask", book, FOLLOW_UP, timeout=600)
        seconds = round(time.monotonic() - started, 1)
        runs = invoke("runs", book)
        emit(stage="follow_up", seconds=seconds, result=response)
        require(response["state"] == "complete", "The follow-up did not finish")
        require(next(run for run in runs if run["id"] == stopped["id"])["status"] == "interrupted",
                "The follow-up did not close the abandoned run")
        saved = drafts()
        require(len(saved) == 1 and len(spaces()) == 1, "The follow-up duplicated saved work")
        memo = saved[0]["text"].replace("*", "")
        for words in ["MAPLE-27", "0.10 kg", "0.25 kg", "nspecified"]:
            require(words in memo, "The memo lost " + words)
        reports = re.findall(r"^Inspection (\w+): ", prompt, re.M)
        require(len(reports) == 8, "The fixture request changed")
        for index, word in enumerate(reports):
            lines = [line for line in memo.split("\n") if word + "-CHECK" in line]
            require(len(lines) == 1 and f"0.{index + 31} mm" in lines[0] and "HOLD" in lines[0].upper(),
                    "The memo's line for " + word + " is wrong")
        require(invoke("verify", book)["ok"], "The recovered workbook failed integrity")
        fcntl.flock(lease, fcntl.LOCK_EX | fcntl.LOCK_NB)
        fcntl.flock(lease, fcntl.LOCK_UN)
        summary = {"check": "native_death_during_context_maintenance", "passed": True,
                   "followUpSeconds": seconds, "steps": response["steps"], "memo": saved[0]["text"]}
        (args.output / "result.json").write_text(json.dumps(summary, indent=1))
        emit(**summary)
    finally:
        if process is not None and process.poll() is None:
            process.kill()
            process.communicate(timeout=15)
        # Only clean up a helper observed as this spawned CLI's child, if its
        # exact command still identifies the same test process.
        for pid, command in helpers.items():
            if command_for(pid) == command:
                os.kill(pid, signal.SIGTERM)
                if not await_helpers_exit({pid: command}, seconds=5):
                    os.kill(pid, signal.SIGKILL)
        os.close(lease)


if __name__ == "__main__":
    main()
