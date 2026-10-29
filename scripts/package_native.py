"""Assemble the isolated native candidate from verified build inputs."""
import hashlib
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def copy(source, target):
    target.parent.mkdir(parents=True, exist_ok=True)
    if source.is_dir():
        shutil.copytree(source, target)
    else:
        shutil.copy2(source, target)


def notices(destination, scratch, splash, grammar):
    copy(ROOT / "LICENSE", destination / "Sevra.txt")
    copy(ROOT / "Resources/Brand/Poppins-OFL.txt", destination / "Poppins-OFL.txt")
    copy(ROOT / "Package.resolved", destination / "Package.resolved")
    # SwiftPM resolves baseline packages too. Include their notices conservatively;
    # this list is licensing evidence, not a claim they are linked in the candidate.
    for package in (scratch / "checkouts").iterdir():
        for source in package.rglob("*"):
            if source.is_file() and ".git" not in source.parts and source.name.lower().split(".")[0] in {
                "license", "copying", "notice", "copyright", "licence"
            }:
                copy(source, destination / "Swift" / package.name / source.relative_to(package))
    for name in ("LICENSE", "THIRD_PARTY_NOTICES"):
        copy(splash / name, destination / "Splash" / name)
    toolchain = json.loads((ROOT / "integration/llguidance.json").read_text())["rustToolchain"]
    # Query only the built normal-dependency tree. Full workspace metadata also
    # resolves unrelated development crates that are neither built nor shipped.
    metadata = json.loads(subprocess.check_output([
        "cargo", "+" + toolchain, "metadata", "--no-deps", "--locked", "--offline", "--format-version", "1"
    ], cwd=grammar))
    workspace = {(p["name"], p["version"]): Path(p["manifest_path"]).parent for p in metadata["packages"]}
    tree = subprocess.check_output([
        "cargo", "+" + toolchain, "tree", "--locked", "--offline", "-p", "llguidance",
        "--edges", "normal", "--target", "aarch64-apple-darwin", "--prefix", "none", "--format", "{p}|{l}|{r}"
    ], cwd=grammar, text=True)
    cargo_home = Path(os.environ.get("CARGO_HOME", Path.home() / ".cargo"))
    packages = {}
    for line in tree.splitlines():
        identity, license, repository = line.removesuffix(" (*)").split("|", 2)
        name, version = identity.split()[:2]
        version = version.removeprefix("v")
        packages[(name, version)] = {"name": name, "version": version, "license": license, "repository": repository}
    receipt = []
    for key, package in sorted(packages.items()):
        label = package["name"] + "-" + package["version"]
        folder = workspace.get(key)
        if folder is None:
            candidates = list((cargo_home / "registry/src").glob("*/" + label))
            if len(candidates) != 1:
                raise RuntimeError("Cannot identify the built license source for " + label)
            folder = candidates[0]
        paths = [p for p in folder.rglob("*") if p.is_file() and "target" not in p.relative_to(folder).parts
                 and p.name.upper().startswith(("LICENSE", "LICENCE", "COPYING", "NOTICE", "COPYRIGHT"))]
        # Workspace crates share the repository license.
        if not paths and folder.is_relative_to(grammar):
            paths = [grammar / "LICENSE"]
        if not paths:
            raise RuntimeError("Missing license notice for " + label)
        for p in set(paths):
            relative = p.relative_to(folder) if p.is_relative_to(folder) else Path(p.name)
            copy(p, destination / "Rust" / label / relative)
        receipt.append({k: package[k] for k in ("name", "version", "license", "repository")})
    (destination / "Rust/packages.json").write_text(json.dumps(receipt, indent=2) + "\n")


def main():
    binary, scratch = map(Path, sys.argv[1:])
    pin = json.loads((ROOT / "integration/splash.json").read_text())
    guidance = json.loads((ROOT / "integration/llguidance.json").read_text())
    receipt = json.loads((ROOT / ".build/llguidance-receipt.json").read_text())
    if receipt["commit"] != guidance["commit"] or receipt["cargoLockSHA256"] != guidance["cargoLockSHA256"]:
        raise RuntimeError("Grammar build does not match its pin")
    splash = ROOT / ".build/upstream" / ("splash-native-" + pin["release"])
    grammar = ROOT / ".build/upstream" / ("llguidance-" + guidance["version"])
    library = ROOT / receipt["library"]
    if sha(library) != receipt["librarySHA256"]:
        raise RuntimeError("Grammar artifact changed after its verified build")
    for relative, expected in pin["runtime"]["files"].items():
        if sha(splash / relative) != expected:
            raise RuntimeError("Native artifact differs from pin: " + relative)
    out = ROOT / "output/native"
    if out.exists():
        shutil.rmtree(out)
    app = out / "Sevra Native Preview.app"
    resources = app / "Contents/Resources"
    cli = out / "bin"
    copy(binary / "SevraDesktop", app / "Contents/MacOS/Sevra")
    copy(binary / "sevra", cli / "sevra")
    copy(binary / "sevra-extract", app / "Contents/MacOS/sevra-extract")
    copy(binary / "sevra-extract", cli / "sevra-extract")
    info = plistlib.loads((ROOT / "Resources/Info.plist").read_bytes())
    info.update(CFBundleIdentifier="com.sevra.workbooks.native-preview",
                CFBundleName="Sevra Native Preview", CFBundleDisplayName="Sevra Native Preview",
                LSMinimumSystemVersion="26.4")
    # Qualification must not steal Finder associations from the installed app.
    info.pop("CFBundleDocumentTypes", None)
    info.pop("UTExportedTypeDeclarations", None)
    (app / "Contents/Info.plist").write_bytes(plistlib.dumps(info))
    copy(ROOT / "Resources/Sevra.icns", resources / "Sevra.icns")
    bundles = ["swift-transformers_Hub", "ZIPFoundation_ZIPFoundation", "swift-crypto_Crypto",
               "Sevra_SevraSplash", "Sevra_SevraSplashText", "Sevra_SevraSplashGrammar"]
    for name in bundles:
        copy(binary / (name + ".bundle"), resources / (name + ".bundle"))
        copy(binary / (name + ".bundle"), cli / (name + ".bundle"))
    manifest = {"schemaVersion": 1, "release": pin["release"], "commit": pin["commit"],
                "engineFiles": {Path(k).name: v for k, v in pin["runtime"]["files"].items() if k.startswith("engine/")},
                "grammarSHA256": receipt["librarySHA256"]}
    for name in manifest["engineFiles"]:
        installed = app / "Contents/Helpers/Splash" / name
        if name.endswith(".metallib"):
            # Keep resources in the sealed resource directory. The unchanged
            # helper expects its libraries beside itself, so use bundle-local
            # links instead of signing or modifying upstream Metal bytes.
            copy(splash / "engine" / name, resources / "Splash" / name)
            installed.parent.mkdir(parents=True, exist_ok=True)
            installed.symlink_to("../../Resources/Splash/" + name)
        else:
            copy(splash / "engine" / name, installed)
        copy(splash / "engine" / name, cli / "NativeRuntime/engine" / name)
    copy(library, app / "Contents/Frameworks/libllguidance.dylib")
    copy(library, cli / "NativeRuntime/libllguidance.dylib")
    for folder in [resources, cli]:
        (folder / "native-runtime.json").write_text(json.dumps(manifest, indent=2) + "\n")
    notices(resources / "Licenses", scratch, splash, grammar)
    copy(resources / "Licenses", cli / "Licenses")
    # Upstream engine and native grammar are already linker-signed. Preserve
    # their bytes and sign the containing app without --deep rewriting helpers.
    subprocess.run(["codesign", "--force", "--sign", "-", str(app)], check=True)
    subprocess.run(["codesign", "--verify", "--deep", "--strict", str(app)], check=True)
    for name, expected in manifest["engineFiles"].items():
        assert sha(app / "Contents/Helpers/Splash" / name) == expected
    assert sha(app / "Contents/Frameworks/libllguidance.dylib") == receipt["librarySHA256"]
    print(json.dumps({"app": str(app.relative_to(ROOT)), "cli": str((cli / "sevra").relative_to(ROOT)),
                      "candidate": True, "unchangedEngine": True}))


if __name__ == "__main__":
    main()
