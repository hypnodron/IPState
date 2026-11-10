# Using IP State

IP State lives in the menu bar. Click its item to view addresses, refresh, copy an address, or open **Settings…**.

There is no Dock icon or main app window.

## Refresh behavior

Network events trigger an immediate lookup. Periodic checks catch public IP changes that produce no local network event.
Detection takes up to the selected interval plus request time under normal conditions.
Changes that occur entirely between checks cannot be observed.

Off disables periodic checks and timer retries. Launch, wake, network events, and manual refresh still work.
The app pauses checks while offline or asleep. Failed IP lookups use capped backoff for each address family.
Unavailable IPv6 does not delay IPv4 checks. Each family keeps its own address, location, update time, and stale state.

The first successful lookup after launch sets a separate baseline for each family, without a notification.
Later IP changes produce one notification each, even when the country stays the same.
The menu bar and history update as soon as an IP change is detected.
The notification waits for that IP's location lookup, then includes its location or an explicit unavailable message.
Failed, cancelled, or superseded location lookups still produce one alert for a detected change without reusing another IP's location.
Equivalent IPv6 address spellings do not produce false change notifications.
macOS notification permission and Focus settings control visible banners.

## Remembered locations

The app remembers locations for up to 100 IP addresses across restarts, independently of optional history.
Returning to a known IP displays its cached country and city immediately.
Results stay fresh for 24 hours. Older results remain visible while a background lookup checks for location changes.
Entries older than seven days expire and require a new lookup. Failed updates keep any unexpired cached location.

## States

| Menu bar | Meaning |
|---|---|
| Connection-check icon | Connection check in progress |
| `—` | No successful lookup yet |
| `NL`, `🇳🇱`, or an IP | Current result in the selected format |
| A result with a small corner dot | Last successful result is stale; open the menu for its update time |
| `??` or `🌐` | IP is available; country is unavailable |
| `???` | IP is available; city code is unavailable |
| Wi-Fi slash icon | No network connection |
| Wi-Fi warning icon | Internet check failed |
| Question-mark icon | Internet is reachable; IP lookup services are unavailable |

The menu shows the last successful IP and update time. A failed lookup never replaces that IP with an error or empty value.

## Menu bar layout and name limits

In the **Menu bar** section of Settings, check the items to show. Drag their rows or use the arrow buttons to choose their order.
Rows keep the same height when their inline fields appear or disappear.
The preview reflects the current data and layout. Old display modes migrate to the equivalent checkbox selection.
If all items are unchecked, the app shows a globe so its menu stays accessible.

Check **City name** or **Country name** to reveal a **Max** field beside that item.
Zero means no limit. Longer names end in an ellipsis that counts toward the limit.
These limits affect full names; country codes and custom city codes remain separate items.
Press Return or leave the field to apply a number.

## City codes

Check **City code** in Settings. Its field appears beside that item.
The default uses three letters from the city name, with Latin transliteration when available.
Enter a city code in the field to override the default. Codes support up to eight characters.
The app saves each code for that city and country. Clear the field to use the default again.

These codes are editable labels derived from the city name.

## Connection status

The system network monitor detects a disconnected path immediately.
If the network remains connected but all IP lookups fail, a short HTTPS probe helps distinguish a service outage from an unreachable Internet.
While the Internet remains unreachable, a recovery probe runs three seconds after the previous check finishes.
This probe bypasses IP lookup backoff and refreshes both addresses as soon as connectivity returns.
Recovery probes pause during sleep and stop when periodic checks are Off or no network path is available.
If the Internet is reachable but IP services fail, probes remain limited to once per 30 seconds.
A successful IP lookup clears the outage status immediately, without waiting for city or country data.

Connection icons replace the label within the space reserved by its last known text.
The stale indicator also uses an overlay, so it does not expand the item.
Normal IP or location changes, layout edits, and name-limit edits can change the label width.

## Notifications and history

Use **Test Notification** in Settings to check permission and banner presentation without changing the IP.
The test works independently of both automatic notification switches.
It shows a snapshot of the current flag, full country and city names, and public IP.
Notification names use their full text, regardless of menu-bar selections, name limits, or custom city codes.
The menu's address sections share this format: `🇳🇱 Netherlands · Amsterdam`, followed by the full IP on the next line.
Both show explicit unavailable location details and mark stale addresses as **Last known**.
IP-change alerts put the new IP first and keep the previous address below it.
Connection alerts include the available snapshot; disconnected or stale addresses say **Last known**.
If no IP is available yet, the test says so instead of showing example data.

Enable **Notify when connection is lost or restored** for connection alerts.
The first confirmed connection state sets a silent baseline. Later loss and recovery each produce one alert.
A disconnected path or failed Internet probe counts as lost. A successful IP lookup or Internet probe confirms recovery.
IP lookup service failures alone do not count as connection loss. Missing IPv6 does not count while IPv4 works.
Sleep and wake reset the connection baseline so those transitions do not produce alerts.
Connection checks follow the refresh behavior above; Off still allows checks on network changes, wake, launch, and manual refresh.

Manage notification banners and sounds in **System Settings → Notifications → IP State**.

Enable **Keep recent IP changes** in Settings to record changes for both families, with timestamps.
Set the **Keep** count beside it to any number from 1 to 200. Lowering it removes older entries after you commit the number.
The count appears while history is enabled.
The menu then offers **Recent IP Changes**. Each entry shows its previous address and lets you copy its new address.
Use **Clear History** to remove entries. Turning history off also removes all saved entries.
