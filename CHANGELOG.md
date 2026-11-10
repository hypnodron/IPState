# Changelog

## 0.10.4 — Faster recovery and remembered locations

- Clear the outage icon as soon as either IP address resolves, before location lookup finishes.
- Check for Internet recovery independently of IP lookup backoff during confirmed outages.
- Refresh both address families when the recovery probe succeeds. Off still disables timer retries.
- Remember locations for up to 100 IPs across restarts. Refresh day-old results and expire them after seven days.

## 0.10.3 — Initial public preview

- Show public IP, country, city, and editable city codes in the macOS menu bar.
- Choose and reorder visible components, with character limits for names.
- Track IPv4 and IPv6 independently and select the available family automatically.
- Check on a configurable interval, network changes, wake, launch, and manual refresh.
- Notify about IP changes and optional connection loss or recovery.
- Use four location providers with response validation and fallback behavior.
- Keep optional local history with a configurable retention count.
- Include a native Icon Composer icon and a fallback for older macOS versions.
