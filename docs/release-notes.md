IP State shows your public IP and location in the macOS menu bar and alerts you when the address changes.

This preview includes automatic IPv4/IPv6 selection, configurable checks, connection alerts, and optional local history.

Version 0.10.5 starts with a compact country flag and country code, with bounded optional names for new installations.
Existing layouts, name limits, notification choices, and refresh intervals remain unchanged.
Connection recovery clears the outage icon before location lookups finish and bypasses IP lookup backoff.
Public IP checks now continue independently of location lookup, and VPN changes reset old retry delays.
Manual refreshes share connectivity checks safely, including when periodic checks are Off.
Re-enabling IP alerts keeps earlier muted or canceled changes silent, even when their location lookup finishes later.
It also remembers recent IP locations across restarts, with automatic revalidation and expiry.

Download the universal macOS ZIP for Apple silicon or Intel, extract it, and move **IP State.app** into Applications.
Requires macOS 14 or later.

This preview is ad-hoc signed and **not notarized by Apple**. macOS may block its first launch.
See [Apple's instructions for opening an unidentified developer's app](https://support.apple.com/guide/mac-help/mh40617/mac).
The source is available if you prefer to build it yourself.

The `.sha256` file records the ZIP's SHA-256 checksum.
