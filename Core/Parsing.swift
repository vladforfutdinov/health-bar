import Foundation

/// Statuspage `/api/v2/status.json` and `/api/v2/summary.json`; incident.io serves compatible copies.
struct StatuspageSummary: Decodable {
    struct Page: Decodable { let url: URL }
    struct Status: Decodable { let indicator: String; let description: String }
    struct Component: Decodable { let id: String; let name: String; let group: Bool?; let groupId: String? }
    struct Update: Decodable { let body: String? }
    struct Event: Decodable {
        let id: String
        let name: String
        let status: String
        let impact: String?
        let shortlink: String?
        let incidentUpdates: [Update]?
    }

    let page: Page
    let status: Status
    let components: [Component]?
    let incidents: [Event]?
    let scheduledMaintenances: [Event]?
}

/// Statuspage `/uptime_showcase?components=<ids>`: the page's own uptime-bar feed, undocumented.
struct UptimeShowcase: Decodable {
    struct Value: Decodable { let component: String; let thirty: Double }
    /// `outages`: seconds of partial (`p`) and major (`m`) outage that day.
    struct Day: Decodable { let date: String; let outages: [String: Double] }
    struct Named: Decodable { let name: String? }
    struct Timeline: Decodable { let component: Named?; let days: [Day] }

    let values: [Value]
    let timelines: [String: Timeline]
}

/// incident.io `/proxy/<host>/component_impacts?start_at=&end_at=`: the page's own uptime-bar feed, undocumented.
struct ComponentImpacts: Decodable {
    struct Impact: Decodable {
        let componentId: String
        let startAt: Date
        let endAt: Date?
        let status: String
    }

    let componentImpacts: [Impact]
}

/// incident.io `/proxy/<host>`: the page's own feed; only the component names and groups are read.
struct IncidentIOPage: Decodable {
    struct Member: Decodable { let componentId: String; let name: String }
    struct Group: Decodable { let name: String; let components: [Member] }
    struct Item: Decodable { let group: Group?; let component: Member? }
    struct Structure: Decodable { let items: [Item] }
    struct Summary: Decodable { let structure: Structure }

    let summary: Summary

    /// Component id → `Group · Component`, or the bare name outside a group.
    var componentNames: [String: String] {
        var names: [String: String] = [:]
        for item in summary.structure.items {
            if let c = item.component { names[c.componentId] = c.name }
            if let g = item.group { for c in g.components { names[c.componentId] = "\(g.name) · \(c.name)" } }
        }
        return names
    }
}

private func decoder() -> JSONDecoder {
    let d = JSONDecoder()
    d.keyDecodingStrategy = .convertFromSnakeCase
    d.dateDecodingStrategy = .custom { dec in
        let s = try dec.singleValueContainer().decode(String.self)
        let frac = ISO8601DateFormatter()
        frac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = frac.date(from: s) ?? ISO8601DateFormatter().date(from: s) else {
            throw DecodingError.dataCorrupted(.init(codingPath: dec.codingPath, debugDescription: "bad date \(s)"))
        }
        return date
    }
    return d
}

func decodeStatuspage(_ data: Data) throws -> StatuspageSummary {
    try decoder().decode(StatuspageSummary.self, from: data)
}

func decodeShowcase(_ data: Data) throws -> UptimeShowcase {
    try decoder().decode(UptimeShowcase.self, from: data)
}

func decodeImpacts(_ data: Data) throws -> ComponentImpacts {
    try decoder().decode(ComponentImpacts.self, from: data)
}

func decodeIncidentIOPage(_ data: Data) throws -> IncidentIOPage {
    try decoder().decode(IncidentIOPage.self, from: data)
}

/// Midnight starting the oldest of `days` local days that end today.
func historyStart(days: Int, now: Date, calendar: Calendar = .current) -> Date {
    calendar.date(byAdding: .day, value: -(days - 1), to: calendar.startOfDay(for: now))!
}

extension StatuspageSummary {
    var pageStatus: PageStatus {
        PageStatus(level: Level(indicator: status.indicator), description: status.description)
    }

    /// Leaf component ids for `/uptime_showcase`; a group id would expand to its children again.
    var componentIDs: [String] { (components ?? []).filter { $0.group != true }.map(\.id) }

    /// Leaf component id → `Group · Component`, or the bare name outside a group.
    var componentNames: [String: String] {
        let all = components ?? []
        let groups = Dictionary(all.filter { $0.group == true }.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
        return Dictionary(all.filter { $0.group != true }.map { c in
            (c.id, c.groupId.flatMap { groups[$0] }.map { "\($0) · \(c.name)" } ?? c.name)
        }, uniquingKeysWith: { a, _ in a })
    }

    func details(uptime: Uptime?) -> ServiceDetails {
        let active = (incidents ?? []) + (scheduledMaintenances ?? []).filter { $0.status == "in_progress" }
        return ServiceDetails(
            pageURL: page.url,
            incidents: active.map { inc in
                Incident(
                    name: inc.name,
                    stage: inc.status,
                    level: Level(indicator: inc.impact ?? "minor"),
                    lastUpdate: inc.incidentUpdates?.first?.body,
                    url: inc.shortlink.flatMap { $0.isEmpty ? nil : URL(string: $0) }
                        ?? page.url.appendingPathComponent("incidents/\(inc.id)")
                )
            },
            uptime: uptime
        )
    }
}

/// Merges showcase batches into one strip: each day lists every component's partial and major outage time;
/// the percentage is the page's own 30-day figure for the worst component.
/// - Parameter names: component id → display name; falls back to the showcase's own name, then the id.
func showcaseUptime(_ batches: [UptimeShowcase], days: Int, names: [String: String] = [:], calendar: Calendar = .current) -> Uptime? {
    var byDate: [String: [Outage]] = [:]
    for batch in batches {
        for (id, timeline) in batch.timelines {
            let name = names[id] ?? timeline.component?.name ?? id
            for day in timeline.days {
                byDate[day.date, default: []] += [("m", "major_outage"), ("p", "partial_outage")].compactMap { key, status in
                    (day.outages[key] ?? 0) > 0 ? Outage(component: name, status: status, seconds: day.outages[key]!) : nil
                }
            }
        }
    }
    guard !byDate.isEmpty, let percent = batches.flatMap(\.values).map(\.thirty).min() else { return nil }
    let parse = DateFormatter()
    parse.calendar = calendar
    parse.timeZone = calendar.timeZone
    parse.locale = Locale(identifier: "en_US_POSIX")
    parse.dateFormat = "yyyy-MM-dd"
    let list = byDate.keys.sorted().suffix(days).compactMap { key in parse.date(from: key).map { UptimeDay(date: $0, outages: byDate[key]!) } }
    return Uptime(days: list, percent: percent)
}

extension ComponentImpacts {
    /// Each day lists the time every component spent in each status. The percentage follows Statuspage's formula
    /// (major outage counts in full, partial 30%, degraded performance not at all) for the worst component.
    /// - Parameter names: component id → display name; the id is shown when missing.
    func uptime(days: Int, now: Date, names: [String: String] = [:], calendar: Calendar = .current) -> Uptime {
        let start = historyStart(days: days, now: now, calendar: calendar)
        // shortcut: overlapping impacts of one component are summed, not merged; merge if a page double-reports.
        func spent(from: Date, to: Date) -> [String: [String: TimeInterval]] {
            var spans: [String: [String: TimeInterval]] = [:]
            for impact in componentImpacts {
                let span = min(impact.endAt ?? now, to, now).timeIntervalSince(max(impact.startAt, from))
                if span > 0 { spans[impact.componentId, default: [:]][impact.status, default: 0] += span }
            }
            return spans
        }
        let list = (0..<days).map { i -> UptimeDay in
            let from = calendar.date(byAdding: .day, value: i, to: start)!
            let to = calendar.date(byAdding: .day, value: 1, to: from)!
            return UptimeDay(date: from, outages: spent(from: from, to: to).flatMap { id, statuses in
                statuses.map { Outage(component: names[id] ?? id, status: $0.key, seconds: $0.value) }
            })
        }
        let weight = ["full_outage": 1.0, "partial_outage": 0.3]
        let down = spent(from: start, to: now).values.map { $0.reduce(0) { $0 + (weight[$1.key] ?? 0) * $1.value } }
        let window = now.timeIntervalSince(start)
        return Uptime(days: list, percent: 100 * (1 - min(down.max() ?? 0, window) / window))
    }
}
