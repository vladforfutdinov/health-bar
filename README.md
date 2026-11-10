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

Any Atlassian Statuspage or incident.io status page works; the platform is detected automatically. A page of your own works too if it serves the same JSON: [docs/STATUS_API.md](docs/STATUS_API.md).

Pages that serve `/api/v2/summary.json` (checked 2026-11-10), ready to paste as `url`:

| Area | Services |
|------|----------|
| Git, CI | `https://bitbucket.status.atlassian.com`, `https://status.circleci.com`, `https://www.buildkitestatus.com`, `https://www.traviscistatus.com`, `https://status.codecov.com`, `https://status.snyk.io` |
| Packages | `https://status.npmjs.org`, `https://status.python.org` (PyPI), `https://status.rubygems.org`, `https://www.dockerstatus.com`, `https://status.jfrog.io` |
| Hosting, cloud | `https://www.cloudflarestatus.com`, `https://www.netlifystatus.com`, `https://status.render.com`, `https://status.flyio.net`, `https://status.digitalocean.com`, `https://status.linode.com`, `https://status.hashicorp.com` |
| Databases | `https://www.planetscalestatus.com`, `https://status.mongodb.com`, `https://status.upstash.com`, `https://status.convex.dev`, `https://status.pinecone.io` |
| AI | `https://status.mistral.ai`, `https://groqstatus.com`, `https://status.cohere.com`, `https://status.deepgram.com`, `https://status.elevenlabs.io`, `https://status.perplexity.com`, `https://status.windsurf.com`, `https://status.replit.com`, `https://status.lovable.dev`, `https://status.bolt.new` |
| Monitoring | `https://status.sentry.io`, `https://status.grafana.com`, `https://status.newrelic.com` |
| Auth, secrets, network | `https://status.clerk.com`, `https://status.1password.com`, `https://www.dopplerstatus.com`, `https://status.tailscale.com`, `https://status.ngrok.com` |
| Email, messaging, media | `https://status.twilio.com` (incl. SendGrid), `https://status.mailgun.com`, `https://resend-status.com`, `https://status.cloudinary.com`, `https://status.mapbox.com` |
| Work tools | `https://linearstatus.com`, `https://jira-software.status.atlassian.com`, `https://status.figma.com`, `https://status.postman.com`, `https://status.expo.dev`, `https://discordstatus.com`, `https://www.zoomstatus.com`, `https://status.dropbox.com` |

No such API (custom pages, not supported): GitLab, Stripe, Heroku, Slack, PagerDuty, Datadog, Fastly, Neon, Notion, Railway, Hugging Face, Auth0, Firebase, Apple Developer, JetBrains.

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
