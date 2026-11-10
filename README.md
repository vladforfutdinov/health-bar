# HealthBar

macOS menu bar app showing the status of the services you depend on (GitHub, OpenAI, Claude, Vercel, Supabase by default).

## Install

```bash
brew tap vladforfutdinov/healthbar
brew install --cask healthbar
```

## Icon

| Icon | Meaning |
|---|---|
| green filled circle | every service reports `none` |
| orange circle, right half filled | at least one reports `minor` |
| red ring | at least one reports `major` / `critical` |
| grey dashed ring | no service could be fetched |

Maintenance and fetch errors show in the menu only. Source glyphs: `design/status-icons.svg`.

## Config

`~/Library/Application Support/HealthBar/services.json`, created on first launch (menu → Edit Config…, then Reload Config):

```json
{
  "refreshSeconds": 60,
  "services": [{ "name": "GitHub", "url": "https://www.githubstatus.com" }]
}
```

Any Atlassian Statuspage or incident.io status page works; the platform is detected automatically.

## Data sources

- Statuspage: `<url>/api/v2/summary.json`.
- incident.io: `<url>/api/v2/summary.json` for status and incidents, `<url>/proxy/<host>` for groups and components (undocumented; falls back to the summary's components).

## Develop

```bash
swift test
scripts/build.sh && open "dist/HealthBar (dev).app"
```

Releasing: `docs/RELEASING.md`.
