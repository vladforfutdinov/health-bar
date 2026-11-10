# HealthBar

macOS menu bar app showing the status of the services you depend on (GitHub, OpenAI, Claude, Vercel, Supabase by default).

![HealthBar menu: each service with its status and a 30-day uptime strip](assets/screenshot.png)

## Install

```bash
brew install --cask vladforfutdinov/healthbar/healthbar
```

## Icon

The menu bar icon is a ring (donut) split into one sector per service, clockwise from 12 o'clock in config order. All green means every service is fine; a service's sector changes colour with its status:

| Colour | Status |
|---|---|
| green | `none` |
| orange | `minor` |
| red | `major` / `critical` |
| blue | maintenance |
| grey | not fetched (unreachable or still loading) |

In the menu each service carries its own glyph (`design/status-icons.svg`).

## Config

`~/Library/Application Support/HealthBar/services.json`, created on first launch (menu → Edit Config…, then Reload Config):

```json
{
  "refreshSeconds": 60,
  "services": [{ "name": "GitHub", "url": "https://www.githubstatus.com" }]
}
```

Any Atlassian Statuspage or incident.io status page works; the platform is detected automatically.

## Menu

Each service row shows its status and opens the status page; active incidents, or the fetch error, are in its tooltip. Under it a 30-day strip (one bar per day, worst component that day) and the uptime of its least available component. Hovering a bar lists that day's affected components with status and duration.

## Data sources

| What | Statuspage | incident.io | When |
|---|---|---|---|
| Status | `<url>/api/v2/status.json` | same | every `refreshSeconds` (60) |
| Incidents | `<url>/api/v2/summary.json` | same | with the strip |
| Strip | `<url>/uptime_showcase?components=<ids>` (ids and names from the summary) | `<url>/proxy/<host>/component_impacts`, names from `<url>/proxy/<host>` | at launch, on a status change, then hourly (every 15 min while not operational) |

The strip endpoints are the pages' own undocumented feeds; if one fails the strip is left out. The platform is detected by `component_impacts` answering 404 on Statuspage hosts.

## Develop

```bash
swift test
scripts/build.sh && open "dist/HealthBar (dev).app"
```

Releasing: `docs/RELEASING.md`.

## License

MIT, see `LICENSE`.
