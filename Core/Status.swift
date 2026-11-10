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

public struct Incident: Equatable, Sendable {
    public var name: String
    public var stage: String
    public var level: Level
    public var lastUpdate: String?
    public var url: URL
}

/// The page-wide indicator from `/api/v2/status.json`.
public struct PageStatus: Equatable, Sendable {
    public var level: Level
    public var description: String
}

/// Time one component spent in one non-operational status during a day.
public struct Outage: Equatable, Sendable {
    /// Display name, `Group · Component` when the component is in a group.
    public var component: String
    /// Component status as the platform names it, e.g. `major_outage`, `partial_outage`, `degraded_performance`.
    public var status: String
    public var seconds: TimeInterval

    public var level: Level { Level(componentStatus: status) }
}

public struct UptimeDay: Equatable, Sendable {
    /// Start of the day.
    public var date: Date
    /// Most severe first.
    public var outages: [Outage]

    public init(date: Date, outages: [Outage]) {
        self.date = date
        self.outages = outages.sorted { ($0.level, $0.seconds) > ($1.level, $1.seconds) }
    }

    public var level: Level { outages.first?.level ?? .ok }
}

/// Per-day history for the uptime strip.
public struct Uptime: Equatable, Sendable {
    /// Oldest first.
    public var days: [UptimeDay]
    /// Uptime of the worst component over the same days, 0–100.
    public var percent: Double
}

/// What is read on the slow schedule: active incidents and the uptime strip.
public struct ServiceDetails: Equatable, Sendable {
    public var pageURL: URL
    public var incidents: [Incident]
    /// `nil` when the history endpoint failed; the strip is then left out.
    public var uptime: Uptime?
}

/// One service as the app last saw it.
public struct ServiceState: Sendable {
    public var status: Result<PageStatus, Error>?
    /// Last successfully read level, kept through failed reads so a change is still detected.
    public var known: Level?
    public var details: ServiceDetails?
    public var detailsAt: Date?

    public init() {}
}

/// Details are read on a level change, then hourly while the page is fine and every 15 min while it is not.
public func detailsDue(previous: Level?, current: Level, lastFetch: Date?, now: Date) -> Bool {
    guard let previous, let lastFetch, previous == current else { return true }
    return now.timeIntervalSince(lastFetch) >= (current == .ok ? 3600 : 900)
}

/// Sectors of the bar icon, clockwise from 12 o'clock. Up to `limit` services: one sector each, in order.
/// Beyond that, `limit` sectors: each status other than OK takes a share proportional to how many services have it
/// (at least one sector when any do), worst first; OK fills the rest. `nil` is not loaded or unreachable.
public func iconSectors(_ levels: [Level?], limit: Int = 10) -> [Level?] {
    guard levels.count > limit else { return levels }
    var sectors: [Level?] = []
    for kind in [Level.outage, .degraded, .maintenance, nil] as [Level?] {
        let count = levels.filter { $0 == kind }.count
        guard count > 0 else { continue }
        let share = max(1, Int((Double(count) / Double(levels.count) * Double(limit)).rounded()))
        sectors += Array(repeating: kind, count: min(share, limit - sectors.count))
    }
    return sectors + Array(repeating: .ok, count: limit - sectors.count)
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
