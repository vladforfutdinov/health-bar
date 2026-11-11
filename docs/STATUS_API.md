# Status page API

What a status page must serve for HealthBar to show it. This is the subset of the Atlassian Statuspage v2 public API that HealthBar reads (full reference: `/api` on any Statuspage page, e.g. <https://www.githubstatus.com/api>); incident.io pages serve the same JSON. Source of truth: [`Core/Parsing.swift`](../Core/Parsing.swift), [`Core/Fetcher.swift`](../Core/Fetcher.swift).

`<base>` is the service's address in Settings. JSON keys are snake_case; requests are plain `GET` with `Accept: application/json`, no auth; any non-2xx response is an error.

| Endpoint | Required | Drives |
|----------|----------|--------|
| `<base>/api/v2/status.json` | yes | service status, polled at the *Check status every* interval |
| `<base>/api/v2/summary.json` | yes | active incidents (the row's third line and tooltip), component list |
| `<base>/proxy/<host>/component_impacts` or `<base>/uptime_showcase` | no | 30-day strip and uptime % |

A page serving only the two required files shows status and incidents, without the strip.

## `status.json`

```json
{
  "page": { "url": "https://status.example.com" },
  "status": { "indicator": "none", "description": "All Systems Operational" }
}
```

- `page.url` — required.
- `page.name` — optional; names a service added without a name.
- `status.indicator` — `none` | `minor` | `major` | `critical` | `maintenance`.
- `status.description` — required, shown as the row's text.

## `summary.json`

`status.json` plus:

```json
{
  "page": { "url": "https://status.example.com" },
  "status": { "indicator": "minor", "description": "Partially Degraded Service" },
  "components": [
    { "id": "grp1", "name": "Backend", "group": true, "group_id": null },
    { "id": "api", "name": "API", "group": false, "group_id": "grp1" }
  ],
  "incidents": [
    { "name": "Elevated API errors", "status": "investigating" }
  ],
  "scheduled_maintenances": []
}
```

- `components`, `incidents`, `scheduled_maintenances` — optional arrays.
- Component: `id`, `name` required; `group` (bool) and `group_id` optional. Leaf components (`group` not `true`) are the ones asked for uptime; a leaf in a group is labelled `Group · Name`.
- Incident: `name` and `status` required, shown as `name — status`; other fields are ignored.
- `incidents` must list unresolved incidents only — every entry is shown as active.
- A scheduled maintenance is shown only while its `status` is `in_progress`.

## Uptime strip (optional)

HealthBar first tries the incident.io feed; a `404` there switches the page to the Statuspage feed for the rest of the session. Both feeds are undocumented internals of those platforms — the shapes below are what HealthBar reads, not a published contract.

### incident.io: `component_impacts`

`GET <base>/proxy/<host>/component_impacts?start_at=<ISO 8601>&end_at=<ISO 8601>`, where `<host>` is the host of `<base>`. The window starts at local midnight 29 days back.

```json
{
  "component_impacts": [
    {
      "component_id": "api",
      "start_at": "2026-11-01T10:00:00Z",
      "end_at": "2026-11-01T10:45:00Z",
      "status": "partial_outage"
    }
  ]
}
```

- `status` — `full_outage` | `partial_outage` | `degraded_performance`.
- `end_at` — `null` while ongoing.
- Uptime % = worst component over the window, counting `full_outage` in full, `partial_outage` at 30%, `degraded_performance` not at all.

Component names for the tooltip come from `GET <base>/proxy/<host>` (optional; ids are shown without it):

```json
{
  "summary": {
    "structure": {
      "items": [
        { "component": { "component_id": "api", "name": "API" } },
        { "group": { "name": "Backend", "components": [{ "component_id": "db", "name": "Database" }] } }
      ]
    }
  }
}
```

### Statuspage: `uptime_showcase`

`GET <base>/uptime_showcase?components=<id>,<id>,…` — leaf component ids from `summary.json`, at most 60 per request (HealthBar batches).

```json
{
  "values": [{ "component": "api", "thirty": 99.95 }],
  "timelines": {
    "api": {
      "component": { "name": "API" },
      "days": [{ "date": "2026-11-01", "outages": { "p": 2700, "m": 0 } }]
    }
  }
}
```

- `values[].thirty` — the component's 30-day uptime %; HealthBar shows the lowest.
- `days[].date` — local `yyyy-MM-dd`; `outages.p` / `outages.m` — seconds of partial / major outage that day. The last 30 dates are drawn.
