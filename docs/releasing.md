# Build and release guide

## Local checks

Use macOS, Python 3.11+, and a full Xcode installation with Swift 6 and Icon Composer.
The app's runtime minimum remains macOS 14.

```sh
bash Scripts/swift.sh test
python3 -m unittest discover -s Tests/ReleaseTools -v
bash Scripts/package-release.sh
```

Tests run serially because native window rendering shares the main thread with bounded async checks.

Packaging builds a universal `arm64`/`x86_64` executable, compiles the modern icon and legacy fallback, and signs the app locally.
It includes both app and Sparkle licenses and embeds Sparkle's framework and helpers.
It creates a ZIP, a DMG, and a separate `.sha256` file for each download in `build/release/`.
The DMG contains the app and an `/Applications` shortcut. App updates continue to use the signed ZIP.
Its background and Finder layout come from `Support/DMG/`.
Packaging installs hash-pinned build tools from `Scripts/requirements-dmg.txt` into `.build/dmg-venv/`.
Download names contain the version from `Support/Info.plist`.

Verify an archive's checksum from its directory:

```sh
shasum -a 256 -c IPState-1.0.1-universal-macos.zip.sha256
shasum -a 256 -c IPState-1.0.1-universal-macos.dmg.sha256
```

Before distributing a new build, extract it and check the signature, launch, settings, and icon in Finder.
Mount the DMG read-only. Check its app signature and Applications shortcut, then eject it.
Check notifications with **Test Notification**. Real network transitions remain user-controlled.
Cross-compiling both architectures does not replace a check on a real Intel Mac.

## Signing status

The current scripts use an ad-hoc signature. The archive is not Developer ID signed or notarized.
The checksum verifies bytes against a trusted checksum; it does not establish the publisher's identity.

To distribute without the unidentified-developer first-launch exception, obtain a Developer ID Application identity and notarize the build.
That requires an Apple Developer account and separately configured signing credentials.
Do not commit certificates, passwords, provisioning files, or private keys.
Follow [Apple's notarization documentation](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution).

## Update signing key

Sparkle archive signatures are separate from Apple code signing and notarization.
The app verifies updates against `SUPublicEDKey` in `Support/Info.plist` before extraction.
The corresponding private key stays in macOS Keychain under the account `com.hypnodron.IPState`.
Keep a secure backup of this key. Do not regenerate it for each release or commit an exported private key.

After resolving the Swift package, export the key directly into the repository secret:

```sh
umask 077
key_file=$(mktemp)
trap 'rm -f "$key_file"' EXIT
.build/artifacts/sparkle/Sparkle/bin/generate_keys --account com.hypnodron.IPState -x "$key_file"
gh secret set SPARKLE_PRIVATE_KEY --repo hypnodron/IPState < "$key_file"
```

For a local signed update, use the existing Keychain key:

```sh
bash Scripts/package-release.sh
bash Scripts/sign-update.sh build/release/IPState-1.0.1-universal-macos.zip
```

The signing command verifies the archive against the app's public key and creates `build/release/update.json`.
This public metadata records the archive signature, byte count, version, build number, and minimum macOS version.
CI reads the private key through `SPARKLE_PRIVATE_KEY`; it does not store the private key in an artifact.
See [Sparkle's signing documentation](https://sparkle-project.org/documentation/publishing/).

## GitHub workflows

`ci.yml` runs deterministic tests and a universal app build for relevant changes pushed to `master` or included in pull requests.
It watches `Sources/`, `Tests/`, `Scripts/`, `Support/`, the package manifest and lockfile, `LICENSE`, and workflow files.
Documentation and social preview changes do not trigger CI.
It uses the `macos-26` hosted image and its selected Xcode. Action revisions are pinned by commit.

Normal CI runs do not create or upload downloadable archives.
For an on-demand archive, select **Actions → Build and test → Run workflow**.
Enable **Create and upload a downloadable app archive** before starting the run.
The resulting `IPState-universal-macos` artifact contains both downloads and their checksums and remains available for 14 days.
Manual runs without this option only test and build the app.

You can also request an archive with the GitHub CLI:

```sh
gh workflow run ci.yml --ref master -f create_archive=true
```

`release.yml` runs after a `v*` tag push. It rejects a tag that does not match `CFBundleShortVersionString`.
After tests, packaging, and update signing, it creates a **draft** GitHub release with both downloads, their checksums, and `update.json`.
The `SPARKLE_PRIVATE_KEY` repository secret is required; a missing or mismatched key stops the release job.
It runs only for newly created tags and skips versions that already have a draft or published release.
It does not publish the draft automatically. Review the notes and artifacts before publishing.
To retry a version with an incomplete draft, delete that draft before rerunning its release job.
The workflow requires `contents: write` only for its release job.

For each release:

1. Update `CFBundleShortVersionString` and increment `CFBundleVersion` in `Support/Info.plist`.
2. Update `CHANGELOG.md` and `docs/release-notes.md`.
3. Run the local checks and review the extracted app.
4. Commit the release changes.
5. Create and push the matching tag, such as `v1.0.1`.
6. Review the workflow result and draft release.
7. Publish the draft when its notes, signing status, and assets are correct.

For the first publication, create the GitHub repository and push `master` only after reviewing the initial commit and license.
Enable private vulnerability reporting in repository settings if you want the private security-reporting channel.

## Update feed publication

`update-feed.yml` regenerates the appcast after publication or changes to releases.
It reads current published releases, so delayed workflow events cannot restore an obsolete feed snapshot.
Drafts and legacy releases without `update.json` are omitted.
Releases marked as prereleases use Sparkle's `preview` channel; stable releases use the default channel.
Promoting or withdrawing a release refreshes this channel selection.
Every offered archive must have a signature, a matching tag and byte count, and a download URL in this repository.
Build numbers must be unique and increase across releases.

The workflow creates or updates only `appcast.xml` on a separate `updates` branch, using `contents: write`.
It leaves `master` unchanged. GitHub serves the feed at:

```text
https://raw.githubusercontent.com/hypnodron/IPState/updates/appcast.xml
```

After the workflow is first pushed to `master`, initialize the feed before distributing an updater-enabled build:

```sh
gh workflow run update-feed.yml --ref master --repo hypnodron/IPState
```

An empty feed is valid until the first signed release is published.
To inspect the generated feed locally without publishing:

```sh
python3 Scripts/update-feed.py publish --dry-run
```

After publishing, check that the feed workflow passes and the public feed contains the expected release and channel.
Versions before 0.11.0 have no updater, so their users must install an updater-enabled version manually once.

## Opt-in live checks

The normal test suite uses controlled responses. These commands make real provider requests:

```sh
IPSTATE_LIVE_LOOKUP=1 bash Scripts/swift.sh test --filter liveLookupReturnsIPv4AndCountry
IPSTATE_LIVE_LOCATION_FALLBACKS=1 bash Scripts/swift.sh test --filter liveLocationFallbacks
```

The native IPv6 check requires a working IPv6 connection:

```sh
IPSTATE_LIVE_IPV6=1 bash Scripts/swift.sh test --filter liveIPv6Lookup
```

The location-fallback check passes IPv6 lookup arguments over the available connection; it does not require native IPv6 connectivity.
No check changes VPN, Wi-Fi, DNS, or routing.
