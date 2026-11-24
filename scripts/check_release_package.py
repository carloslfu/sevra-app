"""Copy a release DMG to an empty test location and verify the installed app."""
import argparse
import json
from pathlib import Path
import plistlib
import subprocess
import tempfile

from package_native import ROOT
from package_release import CLI_EXECUTABLE
from sparkle_release import digest


def output(*args):
    return subprocess.check_output(args, text=True).strip()


def first_chat(cli, profile, install_dir, models, header):
    """With the build tree denied and the app's cache folder empty, the copy installed from the
    disk image answers its first chat from the header it carries, resumed and not computed."""
    if subprocess.run(["pgrep", "-x", "splash"], capture_output=True).returncode == 0:
        raise ValueError("Another engine is running; the first-chat check loads the model")
    cache = Path.home() / "Library/Caches/Sevra/PromptCache"
    if cache.exists():
        subprocess.run(["rm", "-rf", str(cache)], check=True)
    workbook = install_dir / "First chat.sevra"
    def cli_run(*args, timeout=60):
        data = json.loads(subprocess.check_output(
            ["sandbox-exec", "-p", profile, str(cli), *args], cwd=install_dir, text=True, timeout=timeout))
        return data["result"]
    cli_run("demo", str(workbook))
    cli_run("ask", str(workbook), "Hi", str(models), timeout=600)
    metrics = [m for run in cli_run("runs", str(workbook)) for m in json.loads(run["metrics"] or "[]")
               if isinstance(m, dict) and "promptTokens" in m]
    first = metrics[-1] if metrics else {}
    if first.get("headerInputs") != header["inputs"] or first.get("headerResumed") is not True:
        raise ValueError("The installed copy did not resume its own header in its first chat")
    return {"headerResumed": True, "matchedPromptTokens": first.get("matchedPromptTokens"),
            "headTokens": first.get("headTokens")}


def check(record, install_dir, full_runtime, models=None):
    receipt = json.loads(record.read_text())
    dmg = record.parent / receipt["asset"]
    if digest(dmg) != receipt["sha256"] or dmg.stat().st_size != receipt["size"]:
        raise ValueError("The downloaded DMG does not match its release receipt")
    install_dir.mkdir(parents=True, exist_ok=True)
    app = install_dir / "Sevra.app"
    if app.exists() or app.is_symlink():
        raise ValueError("Use an empty test installation path")
    binary = app / "Contents/MacOS/Sevra"
    with tempfile.TemporaryDirectory(prefix="sevra-install-volume-") as temporary:
        mount = Path(temporary)
        subprocess.run(["hdiutil", "attach", "-readonly", "-nobrowse", "-mountpoint", str(mount), str(dmg)],
                       check=True)
        try:
            if (mount / "Applications").readlink() != Path("/Applications"):
                raise ValueError("The DMG is missing a valid Applications shortcut")
            source = mount / "Sevra.app"
            uuid = output("dwarfdump", "--uuid", str(source / binary.relative_to(app))).split()[:3]
            subprocess.run(["ditto", str(source), str(app)], check=True)
        finally:
            subprocess.run(["hdiutil", "detach", str(mount)], check=True)
    subprocess.run(["codesign", "--verify", "--deep", "--strict", str(app)], check=True)
    info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
    expected = {
        "CFBundleIdentifier": receipt["bundleIdentifier"], "CFBundleShortVersionString": receipt["version"],
        "CFBundleVersion": receipt["build"], "LSMinimumSystemVersion": receipt["minimumSystemVersion"],
        "SUFeedURL": receipt["feed"], "SUPublicEDKey": receipt["sparklePublicKey"],
        "SURequireSignedFeed": True, "SUVerifyUpdateBeforeExtraction": True,
    }
    if any(info.get(field) != value for field, value in expected.items()):
        raise ValueError("The installed bundle metadata differs from its release receipt")
    if uuid != output("dwarfdump", "--uuid", str(binary)).split()[:3] or output("lipo", "-archs", str(binary)) != "arm64":
        raise ValueError("The installed executable differs from the Apple Silicon executable on the DMG")
    if "@rpath/Sparkle.framework/" not in output("otool", "-L", str(binary)):
        raise ValueError("The installed app is missing its Sparkle runtime link")

    # The prompt header sealed in the app is the one the receipt names. Early access and stable
    # releases carry one; a QA build may not.
    header = receipt.get("promptHeader")
    folder = app / "Contents/Resources/PromptHeader"
    installed = sorted(folder.glob("*/manifest.json")) if folder.exists() else []
    if header:
        expected = {k: v for k, v in header.items() if k != "madeOn"}
        if [m.parent.name for m in installed] != [header["inputs"]] or json.loads(installed[0].read_text()) != expected:
            raise ValueError("The installed prompt header differs from the release receipt")
    elif receipt["stage"] != "qa" or installed:
        raise ValueError("The release has no prompt header in its receipt")

    profile = "(version 1) (allow default) (deny file-read* (subpath " + json.dumps(str(ROOT / ".build")) + "))"
    results = {}
    with tempfile.TemporaryDirectory(prefix="sevra-cli-link-") as temporary:
        link = Path(temporary) / "sevra"
        link.symlink_to(app / CLI_EXECUTABLE)
        for name, executable, command in [
            ("app", binary, "--check-resources"),
            ("cli", app / CLI_EXECUTABLE, "check-resources"),
            ("cliLink", link, "check-resources"),
        ]:
            args = [] if full_runtime else ["--paths-only"]
            # Run outside the checkout, with explicit denial of the build cache.
            data = json.loads(subprocess.check_output(
                ["sandbox-exec", "-p", profile, str(executable), command, *args], cwd=install_dir, text=True,
                timeout=90))
            value = data.get("result", data)
            if not all(value.get(key) for key in ("runtimeDigests", "grammarLibrary", "extractionWorker")):
                raise ValueError(f"The installed {name} could not verify its runtime files")
            if full_runtime and not value.get("kernelCount", 0):
                raise ValueError(f"The installed {name} could not load its Metal kernels")
            if header and (value.get("promptHeader") or {}).get("state") != "present":
                raise ValueError(f"The installed {name} does not find its prompt header")
            results[name] = value
        if header and models:
            results["fromDiskImageAlone"] = first_chat(app / CLI_EXECUTABLE, profile, install_dir, models, header)
    print(json.dumps({"bundle": str(app), "build": receipt["build"], "sha256": receipt["sha256"],
                      "uuid": uuid[1], "buildTreeDenied": True, "resources": results}, indent=2))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("receipt", type=Path)
    parser.add_argument("install_dir", type=Path)
    parser.add_argument("--full-runtime", action="store_true", help="Also validate Metal on a supported Mac")
    parser.add_argument("--models", type=Path,
                        help="With the model installed here, also answer a first chat from the installed copy")
    options = parser.parse_args()
    check(options.receipt.resolve(), options.install_dir.resolve(), options.full_runtime,
          options.models and options.models.resolve())


if __name__ == "__main__":
    main()
