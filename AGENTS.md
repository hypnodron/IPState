# IP State

- This directory is the project and Git repository root.
- Read `README.md`, `docs/usage.md`, and `docs/releasing.md` for behavior, builds, and releases.
- Native SwiftUI menu bar app; macOS 14+, Swift 6, no external packages.
- Use `bash Scripts/swift.sh test` and `bash Scripts/build-app.sh` from this directory.
- Build products and compiler caches remain in `.build/` and `build/`.
- The executable product is `IPState`; the app bundle is `build/IP State.app`.
- The modern icon source is `Support/AppIcon.icon`; compile it with Xcode's Icon Composer asset tools.
- Run `bash Scripts/package-release.sh` for a universal app archive and checksum.
- Use `com.hypnodron.IPState` as the bundle identifier and `IPStateSettings` for settings.
- Keep change detection and lookup behavior in `IPStateCore` with meaningful regression tests.
- Never change VPN, Wi-Fi, routing, or other network state during verification. Ask the user to perform transitions.
- The app has no development server or assigned TCP port range.
- Work on the existing default branch. Do not use a parent repository or create a worktree for routine changes.
- Keep design research, local agent state, credentials, and build products out of commits.
- Creating a public repository, pushing, and publishing releases require an explicit user request.
