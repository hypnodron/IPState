import os
import json
from pathlib import Path
import plistlib
import re
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "Scripts/package-dmg.sh"


@unittest.skipUnless(sys.platform == "darwin", "DMG integration checks require macOS")
class DiskImageTests(unittest.TestCase):
    def setUp(self):
        (ROOT / "build").mkdir(exist_ok=True)
        self.temporary = tempfile.TemporaryDirectory(prefix="dmg-test-", dir=ROOT / "build")
        self.addCleanup(self.temporary.cleanup)
        self.directory = Path(self.temporary.name)

    def test_image_contains_the_app_and_applications_shortcut_with_permissions_and_links(self):
        app = self.directory / "IP State.app"
        executable = app / "Contents/MacOS/IPState"
        executable.parent.mkdir(parents=True)
        executable.write_text("#!/bin/sh\nexit 0\n")
        executable.chmod(0o755)
        resources = app / "Contents/Resources"
        resources.mkdir()
        (resources / "payload.txt").write_text("App resources survive packaging.")
        (app / "Contents/Info.plist").write_bytes(plistlib.dumps(dict(
            CFBundleIdentifier="com.example.DMGTest", CFBundleExecutable="IPState",
            CFBundlePackageType="APPL")))
        versions = app / "Contents/Frameworks/Example.framework/Versions"
        (versions / "A").mkdir(parents=True)
        (versions / "A/Example").write_bytes(b"framework fixture")
        (versions / "Current").symlink_to("A")
        image = self.directory / "output folder/Test.dmg"
        result = subprocess.run(["bash", str(SCRIPT), str(app), str(image)],
                                capture_output=True, text=True, timeout=120)
        self.assertEqual(result.returncode, 0, result.stderr)
        mount = self.directory / "mounted"
        mount.mkdir()

        def detach():
            if os.path.ismount(mount):
                subprocess.run(["hdiutil", "detach", str(mount)],
                               check=True, capture_output=True, timeout=30)

        self.addCleanup(detach)
        subprocess.run(["hdiutil", "attach", "-readonly", "-nobrowse", "-noautoopen",
                        "-mountpoint", str(mount), str(image)],
                       check=True, capture_output=True, timeout=30)
        self.assertEqual({p.name for p in mount.iterdir() if not p.name.startswith(".")},
                         {"IP State.app", "Applications"})
        self.assertEqual(os.readlink(mount / "Applications"), "/Applications")
        packaged = mount / "IP State.app"
        self.assertEqual((packaged / "Contents/Resources/payload.txt").read_text(),
                         "App resources survive packaging.")
        self.assertEqual((packaged / "Contents/MacOS/IPState").stat().st_mode & 0o777, 0o755)
        self.assertEqual(os.readlink(packaged / "Contents/Frameworks/Example.framework/Versions/Current"), "A")
        self.assertEqual((packaged / "Contents/Frameworks/Example.framework/Versions/Current/Example").read_bytes(),
                         b"framework fixture")
        attributes = subprocess.check_output(["/usr/bin/xattr", str(packaged)], text=True).splitlines()
        self.assertNotIn("com.apple.FinderInfo", attributes)
        self.assertNotIn("com.apple.ResourceFork", attributes)
        self.assertTrue((mount / ".DS_Store").is_file())
        layout = subprocess.run([str(ROOT / ".build/dmg-venv/bin/python3"), "-c", """
import json
from ds_store import DSStore
import sys
with DSStore.open(sys.argv[1], 'r') as store:
    print(json.dumps(dict(app=store['IP State.app']['Iloc'], applications=store['Applications']['Iloc'],
                         background=store['.']['icvp']['backgroundType'],
                         bounds=store['.']['bwsp']['WindowBounds'])))
""", str(mount / ".DS_Store")], check=True, capture_output=True, text=True, timeout=10)
        layout = json.loads(layout.stdout)
        self.assertLess(layout["app"][0], layout["applications"][0])
        self.assertEqual(layout["app"][1], layout["applications"][1])
        self.assertEqual(layout["background"], 2)
        background_properties = subprocess.check_output([
            "sips", "-g", "pixelWidth", "-g", "pixelHeight", "-g", "dpiWidth", "-g", "dpiHeight",
            str(mount / ".background.tiff")], text=True, timeout=10)
        properties = dict(re.findall(r"(pixelWidth|pixelHeight|dpiWidth|dpiHeight): ([\d.]+)",
                                     background_properties))
        artwork_width = float(properties["pixelWidth"]) * 72 / float(properties["dpiWidth"])
        artwork_height = float(properties["pixelHeight"]) * 72 / float(properties["dpiHeight"])
        _, _, window_width, window_height = map(int, re.findall(r"\d+", layout["bounds"]))
        self.assertEqual(window_width, artwork_width)
        # Finder's title, tab, path, and status bars can remain visible despite the saved flags.
        self.assertGreaterEqual(window_height - 132, artwork_height,
                                "Finder chrome must not crop the installation instructions")

    def test_invalid_input_does_not_replace_an_existing_image(self):
        image = self.directory / "Existing.dmg"
        image.write_bytes(b"previous image")
        result = subprocess.run(["bash", str(SCRIPT), str(self.directory / "Missing.app"), str(image)],
                                capture_output=True, text=True, timeout=10)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(image.read_bytes(), b"previous image")


if __name__ == "__main__":
    unittest.main()
