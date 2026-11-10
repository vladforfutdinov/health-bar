# HealthBar

macOS menu bar app showing the status of the services you depend on (GitHub, OpenAI, Claude, Vercel, Supabase by default).

![HealthBar menu: each service with its status and a 30-day uptime strip](assets/screenshot.png)

## Install

```bash
brew install --cask vladforfutdinov/healthbar/healthbar
```

## Icon

The menu bar icon is a ring (donut) split into one sector per checked service, clockwise from 12 o'clock in the order of the list. With more than 10 services it has 10 sectors: each problem status takes a share proportional to how many services have it (at least one sector), worst first, and green fills the rest. A sector's colour:

| Colour | Status |
|---|---|
| green | `none` |
| orange | `minor` |
| red | `major` / `critical` |
| blue | maintenance |
| grey | not fetched (unreachable or still loading) |

In the menu each service carries its own glyph (`design/status-icons.svg`).

## Settings

Menu → Settings… (⌘,); Escape closes it. Menu → About HealthBar shows the version.

- **Services**: a built-in list of about 60 developer-service status pages in groups (Git, CI; AI; Hosting, cloud; Databases; Packages; Monitoring; Auth, secrets, network; Email, messaging, media; Work tools); GitHub, OpenAI, Claude, Vercel and Supabase are checked by default. Check the ones to show. Services can also sit outside any group, at the top.
  - New Service… / the pencil after a service's address: address, name (empty takes the page's own) and group. The address is checked when the field loses focus (a green check means its `status.json` answers) and again on save. Delete… is in the same sheet, with a confirmation.
  - New Group… / the pencil on a group: its name, and Delete…, which asks whether to keep the group's services (they move out of the group) or delete them too.
  - Drag services and groups by the dotted grip at the row's end; services can move between groups. Groups fold (Fold all / Unfold all). The menu and the icon's sectors follow the order of the checked services.
  - Deleted built-in pages stay deleted. The list is in `Core/Catalog.swift`.
- **Check status every**: 30 seconds to 15 minutes.
- **Launch at Login**.
- **Updates**: automatic checks and installs, Check Now.

Any Atlassian Statuspage or incident.io status page works; the platform is detected automatically. Changes apply at once. Settings live in the app's user defaults; a `~/Library/Application Support/HealthBar/services.json` from 0.2.x is imported once on first launch (its services checked, the rest of the list unchecked) and then ignored. Pages added to the built-in list in later versions appear unchecked.

## Menu

At most 8 services show at once; the rest scroll. Each service row shows its status and opens the status page; active incidents, or the fetch error, are in its tooltip. Under it a 30-day strip (one bar per day, worst component that day) and the uptime of its least available component. Hovering a bar lists that day's affected components with status and duration.

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
