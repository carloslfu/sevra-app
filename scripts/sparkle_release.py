"""Fetch the pinned Sparkle tools and write a signed appcast for finalized DMGs."""
import argparse
from datetime import datetime, timezone
from email.utils import format_datetime
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
from urllib.parse import quote, urlsplit
from xml.etree import ElementTree as XML

ROOT = Path(__file__).resolve().parents[1]
VERSION = "2.10.1"
ARCHIVE_SHA256 = "1a856d2a9edb8e628de88121d7be04cf0e2167f8641650b78fca00b14244cf27"
SPARKLE = "http://www.andymatuschak.org/xml-namespaces/sparkle"
PRODUCTION_FEED = "https://www.sevrahq.com/updates/macos/appcast.xml"
RELEASE_ASSETS = "https://github.com/carloslfu/sevra-app/releases/download"
KEY_ACCOUNT = "sevra-distribution"
QA_KEY_ACCOUNT = "sevra-distribution-qa"


def digest(path):
    hasher = hashlib.sha256()
    with path.open("rb") as archive:
        for block in iter(lambda: archive.read(1024 * 1024), b""):
            hasher.update(block)
    return hasher.hexdigest()


def prepare():
    cache = ROOT / ".build/upstream"
    cache.mkdir(parents=True, exist_ok=True)
    archive_name = f"Sparkle-{VERSION}.tar.xz"
    archive = cache / archive_name
    directory = cache / f"sparkle-{VERSION}"
    with tempfile.TemporaryDirectory(dir=cache, prefix=".sparkle-") as temporary:
        stage = Path(temporary)
        if not archive.exists():
            download = stage / archive_name
            url = f"https://github.com/sparkle-project/Sparkle/releases/download/{VERSION}/{archive_name}"
            subprocess.run(["curl", "--fail", "--location", "--silent", "--show-error",
                            "--retry", "2", "--output", str(download), url], check=True)
            if digest(download) != ARCHIVE_SHA256:
                raise ValueError("Sparkle archive does not match the pinned SHA-256")
            download.replace(archive)
        if digest(archive) != ARCHIVE_SHA256:
            raise ValueError("Cached Sparkle archive does not match the pinned SHA-256")
        members = ["./Sparkle.framework", "./LICENSE", "./bin/sign_update", "./bin/generate_keys"]
        if not all((directory / name).exists() for name in members):
            product = stage / "distribution"
            product.mkdir()
            subprocess.run(["tar", "-xf", str(archive), "-C", str(product), *members], check=True)
            try:
                product.rename(directory)
            except OSError:
                if not all((directory / name).exists() for name in members):
                    raise RuntimeError(f"Incomplete Sparkle cache at {directory}")
    for name in ["Sparkle.framework", "bin/sign_update", "bin/generate_keys"]:
        subprocess.run(["codesign", "--verify", "--deep", "--strict", str(directory / name)], check=True)
    return directory


def public_key(directory, account):
    key = subprocess.check_output(
        [str(directory / "bin/generate_keys"), "--account", account, "-p"], text=True).strip()
    return key


def asset_url(info, local_root):
    if local_root:
        if info["stage"] != "qa":
            raise ValueError("Local asset URLs are reserved for QA packages")
        return f"{local_root.rstrip('/')}/{quote(info['asset'])}"
    return f"{RELEASE_ASSETS}/{quote(info['tag'], safe='')}/{quote(info['asset'])}"


def is_loopback_url(value):
    url = urlsplit(value)
    return url.scheme in ("http", "https") and url.hostname == "127.0.0.1" and not url.username


def write_feed(options):
    if options.asset_root and not is_loopback_url(options.asset_root):
        raise ValueError("A QA asset root must use a loopback URL")
    directory = prepare()
    key = public_key(directory, options.account)
    signer = [str(directory / "bin/sign_update"), "--account", options.account]
    if options.account == QA_KEY_ACCOUNT:
        # The disposable key can be exported by its creator. Keep the temp
        # file private so scripted rehearsals need no signer Keychain prompt.
        with tempfile.TemporaryDirectory(prefix="sevra-sparkle-qa-") as temporary:
            secret = Path(temporary) / "key"
            subprocess.run([str(directory / "bin/generate_keys"), "--account", options.account,
                            "-x", str(secret)], check=True, stdout=subprocess.DEVNULL)
            secret.chmod(0o600)
            sign_feed(options, [*signer, "--ed-key-file", str(secret)], key)
    else:
        sign_feed(options, signer, key)


def sign_feed(options, signer, key):
    XML.register_namespace("sparkle", SPARKLE)
    rss = XML.Element("rss", version="2.0")
    channel = XML.SubElement(rss, "channel")
    XML.SubElement(channel, "title").text = "Sevra for Mac"
    XML.SubElement(channel, "link").text = "https://www.sevrahq.com/"
    XML.SubElement(channel, "description").text = "Sevra for Mac software updates"
    records = []
    for record, notes in options.item:
        info = json.loads(record.read_text())
        if info["sparklePublicKey"] != key:
            raise ValueError(f"{record.name} uses a different Sparkle key")
        if (info["stage"] == "qa") != (options.account == QA_KEY_ACCOUNT):
            raise ValueError("QA and public feed items must use separate keys")
        dmg = record.parent / info["asset"]
        if dmg.parent != record.parent or dmg.stat().st_size != info["size"] or digest(dmg) != info["sha256"]:
            raise ValueError(f"The DMG bytes differ from {record.name}")
        records.append((info, dmg, notes.read_text()))
    builds = [info["build"] for info, _, _ in records]
    if len(set(builds)) != len(builds):
        raise ValueError("An appcast cannot list the same build twice")
    for info, dmg, notes in sorted(records, key=lambda row: int(row[0]["build"]), reverse=True):
        sig = subprocess.check_output([*signer, "-p", str(dmg)], text=True).strip()
        item = XML.SubElement(channel, "item")
        XML.SubElement(item, "title").text = f"Sevra {info['releaseVersion']}"
        XML.SubElement(item, "description").text = notes
        XML.SubElement(item, "pubDate").text = format_datetime(
            datetime.fromisoformat(info["created"]).astimezone(timezone.utc), usegmt=True)
        for name, value in [("version", info["build"]), ("shortVersionString", info["version"]),
                            ("minimumSystemVersion", info["minimumSystemVersion"]),
                            ("hardwareRequirements", "arm64")]:
            XML.SubElement(item, f"{{{SPARKLE}}}{name}").text = value
        if info["stage"] == "early-access":
            XML.SubElement(item, f"{{{SPARKLE}}}channel").text = "early-access"
        XML.SubElement(item, "enclosure", {
            "url": asset_url(info, options.asset_root),
            "length": str(info["size"]),
            "type": "application/octet-stream",
            f"{{{SPARKLE}}}edSignature": sig,
        })
    output = options.output.resolve()
    if output.suffix != ".xml":
        raise ValueError("The appcast output must end in .xml for Sparkle to sign it")
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=output.parent, prefix=".appcast-") as temporary:
        stage = Path(temporary) / "appcast.xml"
        XML.indent(rss)
        XML.ElementTree(rss).write(stage, encoding="UTF-8", xml_declaration=True)
        subprocess.run([*signer, str(stage)], check=True)
        subprocess.run([*signer, "--verify", str(stage)], check=True)
        stage.replace(output)
    print(output)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("prepare", help="Print the path to the verified Sparkle distribution")
    key = commands.add_parser("key", help="Create or display a Keychain-backed Sparkle key")
    key.add_argument("--qa", action="store_true", help="Select the rehearsal key")
    feed = commands.add_parser("feed", help="Sign a feed containing the given release receipts")
    feed.add_argument("--account", choices=[KEY_ACCOUNT, QA_KEY_ACCOUNT], default=KEY_ACCOUNT)
    feed.add_argument("--output", type=Path, required=True)
    feed.add_argument("--item", nargs=2, type=Path, action="append", default=[],
                      metavar=("RECEIPT", "NOTES_HTML"))
    feed.add_argument("--asset-root", help="Override the GitHub asset root for loopback-only QA")
    options = parser.parse_args()
    if options.command == "prepare":
        print(prepare())
    elif options.command == "key":
        account = QA_KEY_ACCOUNT if options.qa else KEY_ACCOUNT
        subprocess.run([str(prepare() / "bin/generate_keys"), "--account", account], check=True)
    else:
        write_feed(options)


if __name__ == "__main__":
    main()
