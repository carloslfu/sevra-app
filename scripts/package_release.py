"""Package a standalone Sevra DMG and record the exact archive bytes."""
import argparse
from datetime import datetime, timezone
import json
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import tempfile

from package_native import ROOT, copy, stage, write_manifest
import prompt_header
from sparkle_release import KEY_ACCOUNT, PRODUCTION_FEED, QA_KEY_ACCOUNT, digest, is_loopback_url, prepare, public_key

MINIMUM_OS = "26.4"
CLI_BUNDLE = Path("Contents/Helpers/Sevra CLI.app")
CLI_EXECUTABLE = CLI_BUNDLE / "Contents/MacOS/sevra"


def run(*args):
    subprocess.run(args, check=True)


def chip():
    """The Apple chip this release's header was made and tested on (P7)."""
    return output("sysctl", "-n", "machdep.cpu.brand_string")


def output(*args):
    return subprocess.check_output(args, text=True, cwd=ROOT).strip()


def sign(path, identity, entitlements=None, disk_image=False):
    command = ["codesign", "--force", "--sign", identity]
    if identity != "-":
        command += ["--timestamp"]
        if not disk_image:
            command += ["--options", "runtime"]
    if entitlements:
        command += ["--entitlements", str(entitlements)]
    run(*command, str(path))


def verify_team(path, team):
    verification = subprocess.run(["codesign", "--display", "--verbose=4", str(path)],
                                  capture_output=True, text=True, check=True).stderr.splitlines()
    if (f"TeamIdentifier={team}" not in verification
            or not any(line.startswith("Authority=Developer ID Application:") for line in verification)):
        raise ValueError(f"Wrong Apple signing identity for {path.name}")


def stage_sparkle(directory, contents, identity):
    framework = contents / "Frameworks/Sparkle.framework"
    shutil.copytree(directory / "Sparkle.framework", framework, symlinks=True)
    # The main app is outside the App Sandbox. The separate Sevra worker XPC
    # service stays sandboxed. Sparkle does not need its sandbox bridge here.
    (framework / "XPCServices").unlink()
    current = framework / "Versions/Current"
    shutil.rmtree(current / "XPCServices")
    sign(current / "Autoupdate", identity)
    sign(current / "Updater.app", identity)
    sign(framework, identity)
    copy(directory / "LICENSE", contents / "Resources/Licenses/Sparkle/LICENSE")


def stage_cli(binary, app, info):
    contents = app / "Contents"
    cli = app / CLI_BUNDLE / "Contents"
    copy(binary / "sevra", cli / "MacOS/sevra")
    for path in ["Resources", "MacOS/sevra-extract", "Frameworks/libllguidance.dylib"]:
        copy(contents / path, cli / path)
    shutil.copytree(contents / "Helpers/Splash", cli / "Helpers/Splash", symlinks=True)
    (cli / "Info.plist").write_bytes(plistlib.dumps({
        "CFBundleIdentifier": info["CFBundleIdentifier"] + ".cli",
        "CFBundleName": "Sevra CLI", "CFBundleExecutable": "sevra",
        "CFBundlePackageType": "APPL", "LSBackgroundOnly": True,
        "CFBundleShortVersionString": info["CFBundleShortVersionString"],
        "CFBundleVersion": info["CFBundleVersion"], "LSMinimumSystemVersion": MINIMUM_OS,
    }))


def notarize(dmg, profile):
    response = json.loads(output(
        "xcrun", "notarytool", "submit", str(dmg), "--keychain-profile", profile,
        "--wait", "--output-format", "json",
    ))
    log = output("xcrun", "notarytool", "log", response["id"], "--keychain-profile", profile)
    print(log)
    if response.get("status") != "Accepted" or json.loads(log).get("status") != "Accepted":
        raise ValueError(f"Apple notarization did not accept {response['id']}")
    run("xcrun", "stapler", "staple", str(dmg))
    run("xcrun", "stapler", "validate", str(dmg))
    return response["id"]


def package(options):
    qa = options.stage == "qa"
    stable = options.stage == "stable"
    signing = (options.identity, options.team_id, options.notary_profile)
    if stable and (not all(signing) or options.identity == "-"):
        raise ValueError("A stable release needs a Developer ID Application identity, Team ID and notary profile")
    if not stable and any(signing):
        raise ValueError("Apple signing options apply to stable builds")
    if bool(options.qa_feed) != qa or (qa and not is_loopback_url(options.qa_feed)):
        raise ValueError("QA needs an explicit loopback feed URL. Public builds use the fixed HTTPS feed.")
    if not re.fullmatch(r"(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)", options.version):
        raise ValueError("Specify a three-part version, for example 0.9.0")
    if not re.fullmatch(r"[1-9][0-9]*", options.build):
        raise ValueError("The build must be a positive integer")

    commit = output("git", "rev-parse", "HEAD")
    dirty = bool(output("git", "status", "--porcelain"))
    if dirty and not qa:
        raise ValueError("Build public releases from a clean checkout")
    suffix = {"qa": f"-qa.{options.build}", "early-access": f"-preview.{options.build}", "stable": ""}
    release_version = options.version + suffix[options.stage]
    tag = "v" + release_version
    out = ROOT / "output/releases"
    out.mkdir(parents=True, exist_ok=True)
    destination = out / release_version
    if destination.exists():
        raise ValueError(f"Release output already exists at {destination}; use a new build")

    sparkle = prepare()
    account = QA_KEY_ACCOUNT if qa else KEY_ACCOUNT
    key = public_key(sparkle, account)
    if len(key) != 44:
        raise ValueError("Create the release Sparkle key before packaging")
    identity = options.identity or "-"
    info = {
        "CFBundleIdentifier": "com.sevrahq.sevra.qa" if qa else "com.sevrahq.sevra",
        "CFBundleShortVersionString": options.version,
        "CFBundleVersion": options.build,
        "LSMinimumSystemVersion": MINIMUM_OS,
        "SevraDistributionStage": options.stage,
        "SUFeedURL": options.qa_feed if qa else PRODUCTION_FEED,
        "SUPublicEDKey": key,
        "SUEnableSystemProfiling": False,
        "SUAllowsAutomaticUpdates": False,
        "SUVerifyUpdateBeforeExtraction": True,
        "SURequireSignedFeed": True,
        "SUSignedFeedFailureExpirationInterval": 0,
    }
    if qa:
        info.update(CFBundleDisplayName="Sevra QA", CFBundleDocumentTypes=[], UTExportedTypeDeclarations=[])
    with tempfile.TemporaryDirectory(dir=out, prefix=".package-") as temporary:
        work = Path(temporary)
        image = work / "image"
        app = image / "Sevra.app"
        contents = app / "Contents"
        cli = app / CLI_BUNDLE / "Contents"
        manifest = stage(options.binary, options.scratch, app, release_info=info)
        stage_sparkle(sparkle, contents, identity)
        stage_cli(options.binary, app, info)
        for folder in (contents, cli):
            engine = folder / "Helpers/Splash"
            grammar = folder / "Frameworks/libllguidance.dylib"
            for binary in (folder / "MacOS/sevra-extract", engine / "splash", grammar):
                sign(binary, identity)
            write_manifest(folder / "Resources", {
                **manifest,
                "engineFiles": {name: digest(engine / name) for name in manifest["engineFiles"]},
                "grammarSHA256": digest(grammar),
            })
        sign(app / CLI_BUNDLE, identity)
        # After the command line helper app is staged, so it gets no second copy, and before
        # the app is signed, so the header is sealed with it. Early access and stable need one.
        header = prompt_header.place(app / CLI_EXECUTABLE, app, required=not qa)
        for service in (contents / "XPCServices").glob("*.xpc"):
            sign(service, identity, ROOT / "Resources/AppWorker.entitlements")
        sign(app, identity, ROOT / "Resources/Distribution.entitlements" if stable else None)
        run("codesign", "--verify", "--deep", "--strict", str(app))
        (image / "Applications").symlink_to("/Applications")

        result = work / "release"
        result.mkdir()
        dmg = result / f"Sevra-{release_version}-macOS-arm64.dmg"
        run("hdiutil", "create", "-fs", "APFS", "-format", "ULFO", "-volname",
            "Sevra QA" if qa else "Sevra", "-srcfolder", str(image), str(dmg))
        notary_id = None
        if stable:
            verify_team(app, options.team_id)
            sign(dmg, identity, disk_image=True)
            verify_team(dmg, options.team_id)
            notary_id = notarize(dmg, options.notary_profile)
            run("codesign", "--verify", str(dmg))
        run("hdiutil", "verify", str(dmg))
        if dmg.stat().st_size >= 2 * 1024**3:
            raise ValueError("The DMG exceeds GitHub's per-asset size limit")
        release = {
            "stage": options.stage, "releaseVersion": release_version, "tag": tag,
            "version": options.version, "build": options.build, "minimumSystemVersion": MINIMUM_OS,
            "architecture": "arm64", "bundleIdentifier": info["CFBundleIdentifier"],
            "feed": info["SUFeedURL"], "sparklePublicKey": key,
            "sourceCommit": commit, "sourceDirty": dirty,
            "teamID": options.team_id, "notarySubmission": notary_id,
            "created": datetime.now(timezone.utc).isoformat(),
            "asset": dmg.name, "size": dmg.stat().st_size, "sha256": digest(dmg),
            "promptHeader": header and {**header, "madeOn": chip()},
        }
        (result / "release.json").write_text(json.dumps(release, indent=2) + "\n")
        result.rename(destination)
    print(destination / dmg.name)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("binary", type=Path)
    parser.add_argument("scratch", type=Path)
    parser.add_argument("--version", required=True)
    parser.add_argument("--build", required=True)
    parser.add_argument("--stage", choices=["qa", "early-access", "stable"], default="qa")
    parser.add_argument("--qa-feed")
    parser.add_argument("--identity")
    parser.add_argument("--team-id")
    parser.add_argument("--notary-profile")
    package(parser.parse_args())


if __name__ == "__main__":
    main()
