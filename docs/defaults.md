# Default settings

IP State serves Mac users who switch VPN connections and need to notice changes in their public IP or exit location.
These defaults favor quick detection, a compact menu bar, and limited notification noise.

## New installations

| Setting | Default | Reason |
|---|---|---|
| Menu bar | Country flag, then country code, such as `🇳🇱 NL` | A compact exit-location indicator with a readable code. |
| IP address and full location names | Hidden in the menu bar | Full addresses and locations remain available in the menu and IP-change alerts. |
| City code | Hidden; automatic suggestion when enabled | City abbreviations are ambiguous, and users can edit them. |
| City name limit | 16 characters, including ellipsis | Bounds long names when the user enables this component. |
| Country name limit | 20 characters, including ellipsis | Keeps most names readable without excessive menu bar width. |
| Periodic IP check | Every 5 seconds | Catches VPN exit changes that produce no local network event. |
| Network changes and wake | Immediate checks | Covers normal VPN switches without waiting for a timer. |
| Address family | Automatic; prefer fresh IPv4, otherwise fresh IPv6 | Tracks both families without requiring users to choose one. |
| IP-change notifications | On, subject to macOS permission | Reports exact address changes even when the exit country stays the same. |
| Connection loss/restoration notifications | Off | Avoids extra banners during ordinary VPN reconnects; the menu bar still shows outages. |
| Start at login | Opt-in | Users control background startup through the app and macOS. |
| IP history | Off; retain 20 changes when enabled | Avoids a saved change timeline until the user requests one. |
| Location cache | Up to 100 IPs; fresh for 24 hours; expire after 7 days | Reuses known locations immediately while allowing reassignment and data corrections. |
| Appearance and notification presentation | macOS settings | Respects system theme, Focus, banners, and sound preferences. |

The first successful address establishes a silent baseline. Later changes generate alerts.
Location lookup does not delay the connection status. Recovery probes retry three seconds after the previous check finishes.
Periodic checks Off also disables recovery timers; launch, wake, network events, and manual refresh remain available.

## Refresh tradeoff

Five seconds favors quick detection for VPN users. It is a product choice, not a measured optimum for battery use.
Users who prefer fewer background requests can select a longer interval without disabling checks on network changes.
[Apple recommends minimizing background network activity](https://developer.apple.com/documentation/xcode/reducing-networking-and-bluetooth-power-usage).
[ipify documents unrestricted address requests](https://www.ipify.org/); fallback providers can have different availability and limits.

## Saved settings

Saved layouts, notification switches, refresh intervals, and explicit name limits are restored across launches, including zero for unlimited names.
Missing name limits use the current defaults. Initial limits are saved so they remain consistent across subsequent launches.
The current app identity starts with fresh settings and does not import settings from earlier identities.
Notification permission and Start at login may need to be enabled again after installing this build.
