# Build and release guide

## Local checks

Use macOS and a full Xcode installation with Swift 6 and Icon Composer.
The app's runtime minimum remains macOS 14.

```sh
bash Scripts/swift.sh test
bash Scripts/package-release.sh
```

Tests run serially because native window rendering shares the main thread with bounded async checks.

Packaging builds a universal `arm64`/`x86_64` executable, compiles the modern icon and legacy fallback, and signs the app locally.
It includes the MIT license in the app and creates a ZIP with a matching `.sha256` file in `build/release/`.
The archive name contains the version from `Support/Info.plist`.

Verify an archive's checksum from its directory:

```sh
shasum -a 256 -c IPState-0.10.6-universal-macos.zip.sha256
```

Before distributing a new build, extract it and check the signature, launch, settings, and icon in Finder.
Check notifications with **Test Notification**. Real network transitions remain user-controlled.
Cross-compiling both architectures does not replace a check on a real Intel Mac.

## Signing status

The current scripts use an ad-hoc signature. The archive is not Developer ID signed or notarized.
The checksum verifies bytes against a trusted checksum; it does not establish the publisher's identity.

To distribute without the unidentified-developer first-launch exception, obtain a Developer ID Application identity and notarize the build.
That requires an Apple Developer account and separately configured signing credentials.
Do not commit certificates, passwords, provisioning files, or private keys.
Follow [Apple's notarization documentation](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution).

## GitHub workflows

`ci.yml` runs deterministic tests and a universal app build for relevant changes pushed to `master` or included in pull requests.
It watches `Sources/`, `Tests/`, `Scripts/`, `Support/`, the package manifest and lockfile, `LICENSE`, and workflow files.
Documentation and social preview changes do not trigger CI.
It uses the `macos-26` hosted image and its selected Xcode. Action revisions are pinned by commit.

Normal CI runs do not create or upload downloadable archives.
For an on-demand archive, select **Actions → Build and test → Run workflow**.
Enable **Create and upload a downloadable app archive** before starting the run.
The resulting `IPState-universal-macos` artifact contains the ZIP and checksum and remains available for 14 days.
Manual runs without this option only test and build the app.

You can also request an archive with the GitHub CLI:

```sh
gh workflow run ci.yml --ref master -f create_archive=true
```

`release.yml` runs after a `v*` tag push. It rejects a tag that does not match `CFBundleShortVersionString`.
After tests and packaging, it creates a **draft** GitHub release with the ZIP and checksum.
It runs only for newly created tags and skips versions that already have a draft or published release.
It does not publish the draft automatically. Review the notes and artifacts before publishing.
To retry a version with an incomplete draft, delete that draft before rerunning its release job.
The workflow requires `contents: write` only for its release job.

For each release:

1. Update `CFBundleShortVersionString` and increment `CFBundleVersion` in `Support/Info.plist`.
2. Update `CHANGELOG.md` and `docs/release-notes.md`.
3. Run the local checks and review the extracted app.
4. Commit the release changes.
5. Create and push the matching tag, such as `v0.10.6`.
6. Review the workflow result and draft release.
7. Publish the draft when its notes, signing status, and assets are correct.

For the first publication, create the GitHub repository and push `master` only after reviewing the initial commit and license.
Enable private vulnerability reporting in repository settings if you want the private security-reporting channel.

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
