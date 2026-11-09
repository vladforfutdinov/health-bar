import Foundation

/// Statuspage `/api/v2/summary.json`; incident.io serves a compatible copy.
struct StatuspageSummary: Decodable {
    struct Page: Decodable { let url: URL }
    struct Status: Decodable { let indicator: String; let description: String }
    struct Component: Decodable {
        let id: String
        let name: String
        let status: String
        let position: Int?
        let groupId: String?
        let onlyShowIfDegraded: Bool?
    }
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

/// incident.io `/proxy/<host>`: the page's own data feed, undocumented.
struct IncidentIOProxy: Decodable {
    struct Component: Decodable { let componentId: String; let name: String; let hidden: Bool? }
    struct Group: Decodable { let name: String; let hidden: Bool?; let components: [Component] }
    struct Entry: Decodable { let group: Group?; let component: Component? }
    struct Structure: Decodable { let items: [Entry] }
    struct Affected: Decodable { let componentId: String; let status: String }
    struct Summary: Decodable { let structure: Structure; let affectedComponents: [Affected]? }

    let summary: Summary
}

private func decoder() -> JSONDecoder {
    let d = JSONDecoder()
    d.keyDecodingStrategy = .convertFromSnakeCase
    return d
}

func decodeStatuspage(_ data: Data) throws -> StatuspageSummary {
    try decoder().decode(StatuspageSummary.self, from: data)
}

func decodeIncidentIO(_ data: Data) throws -> IncidentIOProxy {
    try decoder().decode(IncidentIOProxy.self, from: data)
}

extension StatuspageSummary {
    /// - Parameter items: replaces the component rows (incident.io detail); `nil` uses this summary's components.
    func serviceStatus(items: [Item]? = nil) -> ServiceStatus {
        let active = (incidents ?? []) + (scheduledMaintenances ?? []).filter { $0.status == "in_progress" }
        return ServiceStatus(
            level: Level(indicator: status.indicator),
            description: status.description,
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
            items: items ?? componentItems()
        )
    }

    func componentItems() -> [Item] {
        let all = (components ?? []).sorted { ($0.position ?? 0) < ($1.position ?? 0) }
        let children = Dictionary(grouping: all.filter { $0.groupId != nil }, by: { $0.groupId! })
        return all.compactMap { c in
            guard c.groupId == nil else { return nil }
            if let kids = children[c.id] {
                return groupItem(name: c.name, children: kids.map { ($0.name, $0.status) })
            }
            if c.onlyShowIfDegraded == true && c.status == "operational" { return nil }
            return Item(name: c.name, level: Level(componentStatus: c.status), status: c.status, affected: [])
        }
    }
}

extension IncidentIOProxy {
    func items() -> [Item] {
        let status = Dictionary(
            (summary.affectedComponents ?? []).map { ($0.componentId, $0.status) },
            uniquingKeysWith: { a, b in Level(componentStatus: a) >= Level(componentStatus: b) ? a : b })
        func st(_ c: Component) -> String { status[c.componentId] ?? "operational" }
        return summary.structure.items.compactMap { e in
            if let g = e.group, g.hidden != true {
                let visible = g.components.filter { $0.hidden != true }
                return groupItem(name: g.name, children: visible.map { ($0.name, st($0)) })
            }
            if let c = e.component, c.hidden != true {
                return Item(name: c.name, level: Level(componentStatus: st(c)), status: st(c), affected: [])
            }
            return nil
        }
    }
}
