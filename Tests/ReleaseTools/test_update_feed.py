import base64
import json
import os
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile
import unittest
import xml.etree.ElementTree as ET
import zipfile


ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "Scripts/update-feed.py"
SPARKLE = "{http://www.andymatuschak.org/xml-namespaces/sparkle}"
SIGNATURE = base64.b64encode(bytes(range(64))).decode()
REPOSITORY = "https://github.com/hypnodron/IPState"


class UpdateFeedTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.directory = Path(self.temporary.name)

    def run_tool(self, *arguments):
        return subprocess.run([sys.executable, str(SCRIPT), *map(str, arguments)],
                              capture_output=True, text=True)

    def release(self, version="0.11.0", build="22", preview=False, draft=False):
        tag = f"v{version}"
        archive = f"IPState-{version}-universal-macos.zip"
        manifest = dict(version=version, build=build, minimum_system_version="14.0",
                        archive=archive, length=123, signature=SIGNATURE)
        (self.directory / f"{tag}.json").write_text(json.dumps(manifest))
        release = dict(tag_name=tag, name=f"IP State {version}", draft=draft,
                       prerelease=preview, published_at="2026-11-16T12:00:00Z",
                       html_url=f"{REPOSITORY}/releases/tag/{tag}", body="A useful update.",
                       assets=[dict(name="update.json", size=500),
                               dict(name=archive, size=123,
                                    browser_download_url=f"{REPOSITORY}/releases/download/{tag}/{archive}")])
        return release, manifest

    def render(self, releases):
        source = self.directory / "releases.json"
        source.write_text(json.dumps(releases))
        output = self.directory / "appcast.xml"
        result = self.run_tool("render", "--releases", source, "--manifests", self.directory, "--output", output)
        return result, output

    def test_manifest_uses_the_packaged_app_identity_and_archive_bytes(self):
        archive = self.directory / "IPState-0.11.0-universal-macos.zip"
        with zipfile.ZipFile(archive, "w") as bundle:
            bundle.writestr("IP State.app/Contents/Info.plist", plistlib.dumps(dict(
                CFBundleIdentifier="com.hypnodron.IPState", CFBundleShortVersionString="0.11.0",
                CFBundleVersion="22", LSMinimumSystemVersion="14.0")))
        signature = self.directory / "signature.txt"
        signature.write_text(f'sparkle:edSignature="{SIGNATURE}" length="{archive.stat().st_size}"\n')
        output = self.directory / "update.json"
        result = self.run_tool("manifest", "--archive", archive, "--signature-file", signature, "--output", output)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(output.read_text()), dict(version="0.11.0", build="22",
            minimum_system_version="14.0", archive=archive.name, length=archive.stat().st_size, signature=SIGNATURE))

    def test_stable_and_preview_entries_preserve_signed_downloads_and_build_order(self):
        stable, _ = self.release()
        preview, _ = self.release("0.12.0", "23", preview=True)
        result, output = self.render([stable, preview])
        self.assertEqual(result.returncode, 0, result.stderr)
        entries = ET.parse(output).findall("./channel/item")
        self.assertEqual([e.findtext(f"{SPARKLE}version") for e in entries], ["23", "22"])
        self.assertEqual(entries[0].findtext(f"{SPARKLE}channel"), "preview")
        self.assertIsNone(entries[1].find(f"{SPARKLE}channel"))
        enclosure = entries[1].find("enclosure")
        self.assertEqual(enclosure.attrib, dict(url=f"{REPOSITORY}/releases/download/v0.11.0/IPState-0.11.0-universal-macos.zip",
            length="123", type="application/octet-stream", **{f"{SPARKLE}edSignature": SIGNATURE}))
        self.assertEqual(entries[1].findtext(f"{SPARKLE}minimumSystemVersion"), "14.0")

    def test_drafts_and_legacy_releases_without_signed_metadata_are_not_offered(self):
        draft, _ = self.release(draft=True)
        legacy, _ = self.release("0.10.6", "21")
        legacy["assets"] = []
        result, output = self.render([draft, legacy])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(ET.parse(output).findall("./channel/item"), [])

    def test_invalid_release_metadata_fails_without_replacing_the_feed(self):
        for mutation in ["external_download", "size", "signature", "version", "missing_manifest"]:
            with self.subTest(mutation=mutation):
                release, manifest = self.release()
                if mutation == "external_download":
                    release["assets"][1]["browser_download_url"] = "https://example.com/untrusted.zip"
                elif mutation == "size":
                    release["assets"][1]["size"] = 124
                elif mutation == "signature":
                    manifest["signature"] = "invalid"
                elif mutation == "version":
                    manifest["version"] = "0.12.0"
                metadata = self.directory / "v0.11.0.json"
                metadata.write_text(json.dumps(manifest))
                if mutation == "missing_manifest":
                    metadata.unlink()
                output = self.directory / "appcast.xml"
                output.write_text("previous valid feed")
                result, _ = self.render([release])
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(output.read_text(), "previous valid feed")

    def test_duplicate_build_numbers_fail_instead_of_choosing_an_ambiguous_update(self):
        first, _ = self.release()
        second, _ = self.release("0.12.0", "22", preview=True)
        result, output = self.render([first, second])
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(output.exists())

    def test_publication_reports_the_github_permission_error(self):
        transport = self.directory / "gh"
        transport.write_text(f"#!{sys.executable}\n" + """
import sys
endpoint = sys.argv[2]
if '/releases?' in endpoint:
    print('[[]]')
elif '/matching-refs/' in endpoint:
    print('[]')
else:
    print('Resource not accessible by integration (HTTP 403)', file=sys.stderr)
    sys.exit(1)
""")
        transport.chmod(0o700)
        environment = dict(os.environ, PATH=f"{self.directory}:{os.environ['PATH']}", GITHUB_ACTIONS="true")
        result = subprocess.run([sys.executable, str(SCRIPT), "publish", "--output", str(self.directory / "appcast.xml")],
                                env=environment, capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Resource not accessible by integration (HTTP 403)", result.stderr)


if __name__ == "__main__":
    unittest.main()
