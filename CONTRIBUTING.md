# Contributing

Keep IP State a small native macOS menu bar utility. Discuss larger features in an issue before implementation.

## Development

Use macOS 14 or later and Xcode with Swift 6 and Icon Composer. There are no external package dependencies.

```sh
bash Scripts/swift.sh test
bash Scripts/build-app.sh
open "build/IP State.app"
```

The deterministic tests use controlled responses. Live lookup tests are opt-in; see [the release guide](docs/releasing.md).
Never change a contributor's VPN, Wi-Fi, DNS, or routing to verify a change. Ask the person to perform transitions.

Keep lookup and change-detection behavior in `Sources/IPStateCore`, with regression tests for meaningful behavior changes.
Use `com.hypnodron.IPState` as the bundle identifier and `IPStateSettings` for settings.

For interface changes, inspect the actual app at its minimum window size and in light and dark appearances.
For icon changes, inspect the compiled Icon Composer asset in Finder. A raw PNG preview alone is insufficient.

## Pull requests

Describe the user-visible change and the checks you ran. Include images for interface changes.
Use example addresses such as `203.0.113.10` and `2001:db8::10` instead of personal IPs.
Keep build products, credentials, signing identities, and local design research out of the repository.
