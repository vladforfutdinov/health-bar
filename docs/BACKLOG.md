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
