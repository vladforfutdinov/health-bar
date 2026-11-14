# HealthBar

macOS menu bar app showing the status of the services you depend on (GitHub, OpenAI, Claude, Vercel, Supabase by default).

<img src="assets/screenshot.png" width="314" alt="HealthBar menu: each service with its status and a 30-day uptime strip">

## Install

```bash
brew install --cask vladforfutdinov/healthbar/healthbar
```

## Features

- **One ring for everything.** One sector per checked service (at most 10), problems first, worst first; green fills the rest.

  <img src="assets/ring.png" width="88" alt="Four menu bar rings: all green; one degraded of 6; outage, maintenance and unreachable among 8; 20 services with problems scaled to 10 sectors">

- **A row per service**: its status, the current incident, and a 30-day uptime strip; a click opens the status page.
- **About 120 built-in status pages** in groups, plus any Atlassian Statuspage or incident.io page, or your own that serves the same JSON ([docs/STATUS_API.md](docs/STATUS_API.md)).
- **Keyboard and VoiceOver** reach every service in the menu; Settings works from the keyboard too.
- **Automatic updates.**

<img src="assets/settings.png" width="480" alt="HealthBar Settings: services in groups with checkboxes, the poll interval and Launch at Login">

Colours, menu, Settings and where the data comes from: [docs/USAGE.md](docs/USAGE.md). The built-in pages: [docs/SERVICES.md](docs/SERVICES.md).

## Develop

```bash
swift test
scripts/build.sh && open "dist/HealthBar (dev).app"
```

Releasing: `docs/RELEASING.md`.

## License

MIT, see `LICENSE`.
