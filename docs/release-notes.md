## 💿 IP State 1.0.1

**Your public IP, at a glance.** This release adds a DMG download for drag-and-drop installation.

### ✨ What's new

- Add a styled universal DMG with an installation arrow, **IP State.app**, and an **Applications** shortcut.
- Offer SHA-256 checksums for both downloads.
- Keep the signed ZIP for automatic app updates.

### ⬇️ Install or update

Download **IPState-1.0.1-universal-macos.dmg**. Open it and drag **IP State.app** onto **Applications**.
Eject the disk image, then open **IP State** from Applications.
You can also download the ZIP, extract it, and move the app into Applications.
Both downloads support Apple silicon and Intel and require macOS 14 or later.

Already on 0.11.0 or later? Choose **Check for Updates…** in the app menu.
Earlier versions need one manual installation to enable app updates.
Your existing IP State settings remain intact.

### ℹ️ First launch

This release is ad-hoc signed and **not notarized by Apple**. macOS may block its first launch.
See [Apple's instructions for opening an unidentified developer's app](https://support.apple.com/guide/mac-help/mh40617/mac).
The source is available if you prefer to build it yourself.

Each `.sha256` file records the checksum of its corresponding download.
Sparkle verifies the ZIP update archive's signature before installation.
