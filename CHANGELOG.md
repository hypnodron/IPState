# Changelog

## 0.10.5 — VPN defaults and responsive IP checks

- Show the country flag and country code by default on new installations.
- Limit optional city names to 16 characters and country names to 20 on new installations.
- Preserve existing layouts, unlimited names, and saved preferences across upgrades.
- Document the complete default configuration and its rationale.
- Poll public addresses independently of location enrichment, preserving pending location results and one alert per change.
- Reset retry backoff after network changes and wake so a new VPN path receives prompt checks.
- Share connectivity probes across refreshes without losing results when a waiter cancels.
- Cancel queued IP alerts when their switch is disabled, and avoid permission requests from canceled test alerts.
- Keep muted or canceled IP changes silent when alerts are re-enabled before location lookup finishes.

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
