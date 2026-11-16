#!/usr/bin/env python3
"""Create signed-archive metadata and publish the appcast for GitHub releases."""

import argparse
import base64
from datetime import datetime
from email.utils import format_datetime
import html
import json
import os
from pathlib import Path
import plistlib
import re
import subprocess
import tempfile
import xml.etree.ElementTree as ET
import zipfile


REPOSITORY = "hypnodron/IPState"
BASE_URL = f"https://github.com/{REPOSITORY}"
SPARKLE = "http://www.andymatuschak.org/xml-namespaces/sparkle"
ET.register_namespace("sparkle", SPARKLE)
BRANCH = "updates"
COMMITTER = dict(name="github-actions[bot]", email="41898282+github-actions[bot]@users.noreply.github.com")


def validate_manifest(manifest):
    version = manifest["version"]
    if not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", version):
        raise ValueError("The update version must have the form X.Y.Z.")
    if not re.fullmatch(r"[1-9][0-9]*", manifest["build"]):
        raise ValueError("The update build must be a positive integer.")
    if not re.fullmatch(r"[0-9]+\.[0-9]+(?:\.[0-9]+)?", manifest["minimum_system_version"]):
        raise ValueError("The minimum macOS version is invalid.")
    if manifest["archive"] != f"IPState-{version}-universal-macos.zip":
        raise ValueError("The archive name does not match the update version.")
    if type(manifest["length"]) is not int or manifest["length"] <= 0:
        raise ValueError("The update archive size must be positive.")
    if len(base64.b64decode(manifest["signature"], validate=True)) != 64:
        raise ValueError("The update needs a valid Ed25519 signature.")
    return manifest


def manifest_from_archive(archive, signature_file):
    with zipfile.ZipFile(archive) as bundle:
        info = plistlib.loads(bundle.read("IP State.app/Contents/Info.plist"))
    if info["CFBundleIdentifier"] != "com.hypnodron.IPState":
        raise ValueError("The archive contains another application.")
    signature = re.fullmatch(r'\s*sparkle:edSignature="([A-Za-z0-9+/=]+)" length="([0-9]+)"\s*',
                             signature_file.read_text())
    if signature is None or int(signature[2]) != archive.stat().st_size:
        raise ValueError("The signature does not describe this archive's size.")
    return validate_manifest(dict(version=info["CFBundleShortVersionString"], build=info["CFBundleVersion"],
        minimum_system_version=info["LSMinimumSystemVersion"], archive=archive.name,
        length=archive.stat().st_size, signature=signature[1]))


def offered_releases(releases):
    return [release for release in releases if not release["draft"] and release.get("published_at")
            and any(asset["name"] == "update.json" for asset in release["assets"])]


def render_feed(releases, manifests):
    entries = []
    builds = set()
    for release in offered_releases(releases):
        tag = release["tag_name"]
        if not re.fullmatch(r"v[0-9]+\.[0-9]+\.[0-9]+", tag):
            raise ValueError("A signed release has an invalid version tag.")
        manifest = validate_manifest(json.loads((manifests / f"{tag}.json").read_text()))
        if tag != f'v{manifest["version"]}':
            raise ValueError("The release tag does not match the signed archive version.")
        matches = [a for a in release["assets"] if a["name"] == manifest["archive"]]
        expected_url = f'{BASE_URL}/releases/download/{tag}/{manifest["archive"]}'
        if len(matches) != 1 or matches[0]["browser_download_url"] != expected_url:
            raise ValueError("The update download must be this release's GitHub archive.")
        if matches[0]["size"] != manifest["length"]:
            raise ValueError("The published archive size does not match its signature metadata.")
        build = int(manifest["build"])
        if build in builds:
            raise ValueError("Published updates must have distinct build numbers.")
        builds.add(build)
        entries.append((build, release, manifest, expected_url))

    rss = ET.Element("rss", version="2.0")
    channel = ET.SubElement(rss, "channel")
    ET.SubElement(channel, "title").text = "IP State updates"
    ET.SubElement(channel, "link").text = f"{BASE_URL}/releases"
    ET.SubElement(channel, "description").text = "Published updates for IP State."
    for _, release, manifest, url in sorted(entries, key=lambda e: e[0], reverse=True):
        item = ET.SubElement(channel, "item")
        ET.SubElement(item, "title").text = f'IP State {manifest["version"]}'
        ET.SubElement(item, "link").text = f'{BASE_URL}/releases/tag/v{manifest["version"]}'
        date = datetime.fromisoformat(release["published_at"].replace("Z", "+00:00"))
        ET.SubElement(item, "pubDate").text = format_datetime(date)
        for name, value in [("version", manifest["build"]), ("shortVersionString", manifest["version"]),
                            ("minimumSystemVersion", manifest["minimum_system_version"])]:
            ET.SubElement(item, f"{{{SPARKLE}}}{name}").text = value
        if release["prerelease"]:
            ET.SubElement(item, f"{{{SPARKLE}}}channel").text = "preview"
        body = re.sub(r"[\x00-\x08\x0b\x0c\x0e-\x1f]", "", release.get("body") or "")
        ET.SubElement(item, "description").text = "<p>" + html.escape(body).replace("\n", "<br>") + "</p>"
        ET.SubElement(item, "enclosure", {"url": url, "length": str(manifest["length"]),
            "type": "application/octet-stream", f"{{{SPARKLE}}}edSignature": manifest["signature"]})
    ET.indent(rss)
    return ET.tostring(rss, encoding="utf-8", xml_declaration=True) + b"\n"


def write_atomic(path, content):
    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(dir=path.parent, delete=False) as temporary:
        temporary.write(content)
        staging = Path(temporary.name)
    try:
        staging.replace(path)
    finally:
        staging.unlink(missing_ok=True)


def gh_api(endpoint, payload=None):
    arguments = ["gh", "api", endpoint]
    if payload is not None:
        arguments += ["--method", "POST", "--input", "-"]
    result = subprocess.run(arguments, input=json.dumps(payload) if payload is not None else None,
                            text=True, capture_output=True, check=True)
    return json.loads(result.stdout)


def collect_feed(directory):
    response = subprocess.check_output(["gh", "api", f"repos/{REPOSITORY}/releases?per_page=100",
                                        "--paginate", "--slurp"], text=True)
    releases = [release for page in json.loads(response) for release in page]
    for release in offered_releases(releases):
        tag = release["tag_name"]
        if not re.fullmatch(r"v[0-9]+\.[0-9]+\.[0-9]+", tag):
            raise ValueError("A signed release has an invalid version tag.")
        subprocess.run(["gh", "release", "download", tag, "--repo", REPOSITORY, "--pattern", "update.json",
                        "--output", str(directory / f"{tag}.json")], check=True)
    return render_feed(releases, directory)


def publish_feed(content):
    prefix = f"repos/{REPOSITORY}"
    refs = gh_api(f"{prefix}/git/matching-refs/heads/{BRANCH}")
    message = "🔄 chore(updates): refresh the published appcast"
    if any(ref["ref"] == f"refs/heads/{BRANCH}" for ref in refs):
        previous = gh_api(f"{prefix}/contents/appcast.xml?ref={BRANCH}")
        if base64.b64decode(previous["content"]) == content:
            print("The update feed is already current.")
            return
        payload = dict(branch=BRANCH, sha=previous["sha"], message=message, committer=COMMITTER,
                       content=base64.b64encode(content).decode())
        subprocess.run(["gh", "api", f"{prefix}/contents/appcast.xml", "--method", "PUT", "--input", "-"],
                       input=json.dumps(payload), text=True, capture_output=True, check=True)
    else:
        tree = gh_api(f"{prefix}/git/trees", {"tree": [dict(path="appcast.xml", mode="100644", type="blob", content=content.decode())]})
        commit = gh_api(f"{prefix}/git/commits", dict(message=message, tree=tree["sha"], parents=[], author=COMMITTER))
        gh_api(f"{prefix}/git/refs", dict(ref=f"refs/heads/{BRANCH}", sha=commit["sha"]))
    print("Published appcast.xml on the updates branch.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    manifest = commands.add_parser("manifest")
    manifest.add_argument("--archive", type=Path, required=True)
    manifest.add_argument("--signature-file", type=Path, required=True)
    manifest.add_argument("--output", type=Path, required=True)
    render = commands.add_parser("render")
    render.add_argument("--releases", type=Path, required=True)
    render.add_argument("--manifests", type=Path, required=True)
    render.add_argument("--output", type=Path, required=True)
    publish = commands.add_parser("publish")
    publish.add_argument("--dry-run", action="store_true")
    publish.add_argument("--output", type=Path, default=Path("build/updates/appcast.xml"))
    args = parser.parse_args()
    try:
        if args.command == "manifest":
            metadata = manifest_from_archive(args.archive, args.signature_file)
            write_atomic(args.output, (json.dumps(metadata, indent=2) + "\n").encode())
        elif args.command == "render":
            write_atomic(args.output, render_feed(json.loads(args.releases.read_text()), args.manifests))
        else:
            if not args.dry_run and os.environ.get("GITHUB_ACTIONS") != "true":
                raise ValueError("Publish from GitHub Actions; use --dry-run for local checks.")
            with tempfile.TemporaryDirectory() as directory:
                content = collect_feed(Path(directory))
            write_atomic(args.output, content)
            if not args.dry_run:
                publish_feed(content)
    except (KeyError, ValueError, OSError, zipfile.BadZipFile, subprocess.CalledProcessError) as error:
        detail = error.stderr.strip() if isinstance(error, subprocess.CalledProcessError) and error.stderr else str(error)
        parser.exit(1, f"Update feed failed: {detail}\n")


if __name__ == "__main__":
    main()
