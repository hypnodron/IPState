# Privacy and network requests

IP State has no account, analytics, advertising, or application server.
It does not request macOS Location Services access.

## Data on your Mac

Preferences, custom city labels, cached locations, and optional IP history use local macOS preferences storage.
History is off by default. When enabled, it keeps the selected number of changes, from 1 to 200.
Turning history off or choosing **Clear History** removes the saved entries.
The location cache stores up to 100 IP addresses with their country, city, and lookup time in the `IPStateSettings` preferences domain.
It works independently of history, including when history is off. **Clear History** does not clear the location cache.
Results stay fresh for 24 hours. Older results appear immediately while a new lookup runs in the background.
Entries older than seven days are ignored and removed on cache access or app launch.

The app does not encrypt this preferences storage. Other software with access to your user account may read it.

## Public IP checks

The app uses HTTPS to ask these services for its public address:

| Family | Primary | Fallback |
|---|---|---|
| IPv4 | `api.ipify.org` | `v4.api.ipinfo.io` |
| IPv6 | `api6.ipify.org` | `v6.api.ipinfo.io` |

These services receive the source public IP and normal HTTPS request metadata.
Checks follow the selected refresh interval, plus launch, wake, network events, and manual refresh.
The default interval is five seconds. **Off** disables periodic checks, but permits event-triggered and manual checks.

## Country and city lookups

Location requests include the exact public IP in the HTTPS URL path.
The app tries these providers in order, stopping when it receives a valid country and city:

1. [Country.is](https://country.is/) — `api.country.is`.
2. [IPWHOIS](https://ipwhois.io/documentation) — `ipwho.is`.
3. [GeoJS](https://www.geojs.io/docs/v1/endpoints/geo/) — `get.geojs.io`.
4. [FreeIPAPI](https://freeipapi.com/docs/api-reference/get-ip-info) — `free.freeipapi.com`.

A missing city may trigger the next provider. Valid responses enter the local cache described above.
Later providers must agree with the first valid country result before their city is accepted.
Providers receive the queried IP, the request's source public IP, and normal HTTPS request metadata.
Their own privacy policies and terms apply to those requests.

Country and city describe an IP's reported location, not the Mac's physical location.
Results can be approximate, outdated, or unavailable. IPv4 and IPv6 may use different routes and locations.

## Connection checks and notifications

When address checks fail, the app may request [Apple's connectivity-test page](https://www.apple.com/library/test/success.html).
Apple receives the source public IP and normal HTTPS request metadata.
During a confirmed Internet outage, the probe repeats three seconds after each check finishes, unless periodic checks are Off.
It pauses during sleep or when no network path is available. Recovery triggers fresh IP lookups.
For IP-service failures with reachable Internet, probes remain limited to once per 30 seconds.

IP State submits notifications to macOS, including the available public IP and location.
macOS notification settings control permission, banners, sounds, and lock-screen presentation.
Notifications do not pass through an IP State server.
