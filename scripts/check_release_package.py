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


def check(record, install_dir, full_runtime):
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
            results[name] = value
    print(json.dumps({"bundle": str(app), "build": receipt["build"], "sha256": receipt["sha256"],
                      "uuid": uuid[1], "buildTreeDenied": True, "resources": results}, indent=2))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("receipt", type=Path)
    parser.add_argument("install_dir", type=Path)
    parser.add_argument("--full-runtime", action="store_true", help="Also validate Metal on a supported Mac")
    options = parser.parse_args()
    check(options.receipt.resolve(), options.install_dir.resolve(), options.full_runtime)


if __name__ == "__main__":
    main()
