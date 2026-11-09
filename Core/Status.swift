import Foundation

/// Ordered by severity, so `max()` is the worst.
public enum Level: Int, Comparable, Sendable {
    case ok, maintenance, degraded, outage

    public static func < (a: Level, b: Level) -> Bool { a.rawValue < b.rawValue }

    /// Statuspage `status.indicator` / incident `impact`.
    public init(indicator: String) {
        switch indicator {
        case "none": self = .ok
        case "maintenance": self = .maintenance
        case "minor": self = .degraded
        case "major", "critical": self = .outage
        default: self = .degraded
        }
    }

    /// Component status from Statuspage or incident.io.
    public init(componentStatus: String) {
        switch componentStatus {
        case "operational": self = .ok
        case "under_maintenance": self = .maintenance
        case "major_outage", "full_outage": self = .outage
        default: self = .degraded
        }
    }
}

/// "partial_outage" → "Partial outage".
public func humanize(_ status: String) -> String {
    let s = status.replacingOccurrences(of: "_", with: " ")
    return s.prefix(1).uppercased() + s.dropFirst()
}

public struct Incident: Equatable, Sendable {
    public var name: String
    public var stage: String
    public var level: Level
    public var lastUpdate: String?
    public var url: URL
}

/// One row of the second-level menu: a standalone component, or a group summarised by its worst child.
public struct Item: Equatable, Sendable {
    public var name: String
    public var level: Level
    public var status: String
    /// Names of non-operational children; empty for standalone components.
    public var affected: [String]
}

public struct ServiceStatus: Equatable, Sendable {
    public var level: Level
    public var description: String
    public var pageURL: URL
    public var incidents: [Incident]
    public var items: [Item]
}

public enum IconState: Equatable, Sendable {
    case ok, degraded, outage, unknown

    /// Maintenance and failed fetches don't colour the icon; it goes grey only when nothing loaded.
    public init(levels: [Level?]) {
        let loaded = levels.compactMap { $0 }
        if loaded.isEmpty { self = .unknown; return }
        switch loaded.max()! {
        case .outage: self = .outage
        case .degraded: self = .degraded
        case .ok, .maintenance: self = .ok
        }
    }
}

/// Builds a group row from its children.
func groupItem(name: String, children: [(name: String, status: String)]) -> Item {
    let rated = children.map { (name: $0.name, status: $0.status, level: Level(componentStatus: $0.status)) }
    let worst = rated.max { $0.level < $1.level }
    return Item(
        name: name,
        level: worst?.level ?? .ok,
        status: worst?.status ?? "operational",
        affected: rated.filter { $0.level != .ok }.map(\.name)
    )
}
