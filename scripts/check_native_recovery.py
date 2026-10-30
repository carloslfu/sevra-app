"""Opt-in actual native CLI crash, lease refusal and request-history recovery.

Requires the built native preview, installed selected weights and an idle model.
Only temporary synthetic workbooks and the spawned CLI/helper are affected.
"""
import argparse
import fcntl
import json
import os
from pathlib import Path
import selectors
import signal
import subprocess
import tempfile
import time


def require(condition, message):
    if not condition:
        raise AssertionError(message)


def emit(**value):
    print(json.dumps(value, ensure_ascii=False), flush=True)


def command_for(pid):
    result = subprocess.run(["ps", "-ww", "-p", str(pid), "-o", "command="], capture_output=True, text=True)
    return result.stdout.strip() if result.returncode == 0 else ""


def helpers_for(pid):
    result = subprocess.run(["ps", "-ww", "-axo", "pid=,ppid=,command="], capture_output=True, text=True, check=True)
    found = {}
    for line in result.stdout.splitlines():
        fields = line.split(None, 2)
        if len(fields) == 3 and fields[1] == str(pid) and "/splash serve-native " in fields[2]:
            found[int(fields[0])] = fields[2]
    return found


def await_helpers_exit(helpers, seconds=15):
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        if all(command_for(pid) != command for pid, command in helpers.items()):
            return True
        time.sleep(0.1)
    return False


def main():
    root = Path(__file__).resolve().parent.parent
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cli", type=Path, default=root / "output/native/bin/sevra")
    parser.add_argument("--models", type=Path, required=True)
    args = parser.parse_args()
    cli = args.cli.resolve()
    models = args.models.resolve()
    lease_path = Path.home() / "Library/Application Support/Sevra/inference.lock"
    lease_path.parent.mkdir(parents=True, exist_ok=True)
    lease = os.open(lease_path, os.O_RDWR | os.O_CREAT | os.O_NOFOLLOW | os.O_CLOEXEC, 0o600)
    fcntl.flock(lease, fcntl.LOCK_EX | fcntl.LOCK_NB)
    fcntl.flock(lease, fcntl.LOCK_UN)
    process = None
    helpers = {}
    try:
        with tempfile.TemporaryDirectory(prefix="sevra-crash-recovery-") as folder:
            book = Path(folder) / "Recovery.sevra"

            def invoke(*arguments):
                command = [str(cli), *map(str, arguments)]
                if arguments[0] == "ask":
                    command.append(str(models))
                result = subprocess.run(command, capture_output=True, text=True, timeout=180)
                if arguments[0] == "ask":
                    emit(stage="request", prompt=arguments[2], exitCode=result.returncode,
                         stdout=result.stdout, stderr=result.stderr)
                require(result.returncode == 0, result.stderr)
                reply = json.loads(result.stdout)
                require(reply["ok"], reply)
                return reply["result"]

            invoke("demo", book)
            original_items = invoke("records", book)
            original_spaces = invoke("spaces", book)
            prompt = "What is the current stock of brass bolts? Use the balance tool and cite the evidence. Do not change the workbook."
            process = subprocess.Popen([str(cli), "ask", str(book), prompt, str(models)],
                                       stdout=subprocess.PIPE, stderr=subprocess.PIPE, bufsize=0)
            deadline = time.monotonic() + 120
            progress = bytearray()
            ready = False
            with selectors.DefaultSelector() as selector:
                selector.register(process.stderr, selectors.EVENT_READ)
                while time.monotonic() < deadline and process.poll() is None:
                    if not selector.select(timeout=1):
                        continue
                    chunk = os.read(process.stderr.fileno(), 65536)
                    progress.extend(chunk)
                    if b"Processing context" in progress or b"Thinking locally" in progress:
                        ready = True
                        break
            require(ready, "Native inference did not start before crash injection: " + progress.decode(errors="replace"))
            helpers = helpers_for(process.pid)
            require(helpers, "No child native helper observed")
            process.kill()
            out, error = process.communicate(timeout=15)
            require(process.returncode == -signal.SIGKILL, "CLI did not terminate by injected SIGKILL")
            exited = await_helpers_exit(helpers)
            emit(stage="owner_death", exitCode=process.returncode, helperPIDs=list(helpers),
                 helpersExited=exited, stdout=out.decode(errors="replace"),
                 stderr=progress.decode(errors="replace") + error.decode(errors="replace"))
            require(exited, "Native helper survived owner death; cleanup will be attempted")
            fcntl.flock(lease, fcntl.LOCK_EX | fcntl.LOCK_NB)
            try:
                old_run = invoke("runs", book)[0]
                require(old_run["status"] == "running", "Crash fixture did not leave an unfinished run")
                original_message = old_run["request_message_id"]
                busy = subprocess.run([str(cli), "ask", str(book), "Reply Rejected. Do not change the workbook.", str(models)],
                                      capture_output=True, text=True, timeout=30)
                runs = invoke("runs", book)
                history = invoke("conversation", book)
                emit(stage="lease_refusal", exitCode=busy.returncode, stderr=busy.stderr, runs=runs, messages=history)
                require(busy.returncode == 1 and json.loads(busy.stderr)["error"]["code"] == "model_busy",
                        "Held lease did not refuse the new request")
                require(runs[0]["status"] == "failed" and runs[0]["request_message_id"], "Rejected request has no linked outcome")
                require(next(run for run in runs if run["id"] == old_run["id"])["status"] == "running",
                        "Rejected request interrupted another run")
                require(history[-1]["state"] == "failed", "Rejected request has no assistant diagnostic")
            finally:
                fcntl.flock(lease, fcntl.LOCK_UN)
            response = invoke("ask", book, "Reply with the word Ready. Do not change the workbook.")
            runs = invoke("runs", book)
            history = invoke("conversation", book)
            emit(stage="recovered", result=response, runs=runs, messages=history)
            require(next(run for run in runs if run["id"] == old_run["id"])["status"] == "interrupted",
                    "Fresh request did not recover abandoned run")
            require(next(message for message in history if message["id"] == original_message)["body"] == prompt,
                    "Crash recovery changed original request")
            require(response["state"] == "complete" and response["answer"] == "Ready",
                    "Recovered model did not follow the new request")
            require([item for item in invoke("records", book) if item["kind"] != "request"] == original_items,
                    "Read-only recovery changed business items")
            require(invoke("spaces", book) == original_spaces, "Read-only recovery changed spaces")
            require(invoke("verify", book)["ok"], "Recovered workbook failed integrity")
            fcntl.flock(lease, fcntl.LOCK_EX | fcntl.LOCK_NB)
            fcntl.flock(lease, fcntl.LOCK_UN)
            emit(check="native_crash_and_request_recovery", passed=True,
                 originalRequestPreserved=True, businessDataUnchanged=True, leaseFree=True)
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
