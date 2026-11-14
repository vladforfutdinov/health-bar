# Backlog

## Hund.io status pages

Example: `https://status.bitwarden.com` (Bitwarden). Not Statuspage or incident.io, so it can't be added today: `/api/v2/status.json` and `/api/v2/summary.json` answer 404.

What the page exposes without a key:
- Atom feed `/state_feed/feed`: issues and maintenance windows — title with state in brackets (`[Cancelled]`, …), affected components, times, link to `/issues/<id>`.
- HTML page: current component states, only in markup.
- `/api/v1/…` is JSON but needs an API key (`401 not_authenticated`).

Possible support, via the feed:
- status: not OK while the newest issue is open; the issue title as the menu row's third line;
- platform detection: `/api/v2/status.json` 404 and the feed answering;
- no 30-day strip or uptime percentage: the feed has no per-component history.

## Gaps against Downbar

[Downbar](https://github.com/Ntarasiuk/downbar) is the closest app (MIT source, $2.99 in the App Store, Swift menu bar, 110+ status pages). What it has and HealthBar does not, in the order users will ask:

- Notifications on going down and on recovery, with de-flapping so a single unreachable poll doesn't fire.
- Webhooks (Slack, Discord, any URL) on status change.
- Per-component watch: on a Statuspage page follow only chosen components, ignore the rest.
- More sources: Instatus (`summary.json`, Statuspage-like), plain HTTPS reachability of any site, first-party feeds for AWS, Apple, Google Cloud, Azure.

HealthBar's own edges to keep: uptime history from the page itself (30-day strip, worst component per day), the ring icon with a sector per service, incident.io, macOS 13 and Intel, keyboard and VoiceOver.
