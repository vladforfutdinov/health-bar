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

## xAI status page

`https://status.x.ai` (Grok, xAI API, and the Cursor products hosted on the same page). A custom Next.js page: `/api/v2/status.json` and `/summary.json` answer 403, and the HTML is behind a Cloudflare challenge for non-browser clients, so it can't be added today.

What the page exposes without a key (plain `curl`, no User-Agent needed):
- `/api/status`: `{ updated_at, overall: { status }, products: [ { id, name, status, components: [ { id, name, status } ] } ] }`; 7 products, 26 components. Only `available` observed so far; the degraded and outage vocabulary is unknown.
- `/api/incidents`: `{ incidents: [] }` while quiet; the item shape is unknown.
- `/feed.xml`: RSS 2.0 incident history, `Status: <STATE>` and `Severity: <level>` inside the description CDATA, resolved items stay in it (what Downbar reads).

Possible support, via `/api/status`:
- status: map `overall.status`, the per-component statuses give the row's third line and the tooltip;
- platform detection: `/api/v2/status.json` 403 and `/api/status` answering with `products`;
- no 30-day strip or uptime percentage: no per-component history endpoint; `/feed.xml` gives incidents only.

## Gaps against Downbar

[Downbar](https://github.com/Ntarasiuk/downbar) is the closest app (free, MIT, Swift menu bar, 110+ status pages; direct DMG, Homebrew cask and App Store). What it has and HealthBar does not, in the order users will ask:

- Notifications on going down and on recovery, with de-flapping so a single unreachable poll doesn't fire.
- Webhooks (Slack, Discord, any URL) on status change.
- Per-component watch: on a Statuspage page follow only chosen components, ignore the rest.
- More sources: Instatus (`summary.json`, Statuspage-like), plain HTTPS reachability of any site, first-party feeds for AWS, Apple, Google Cloud, Azure.

HealthBar's own edges to keep: uptime history from the page itself (30-day strip, worst component per day), the ring icon with a sector per service, incident.io, macOS 13 and Intel, keyboard and VoiceOver.
