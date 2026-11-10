import Foundation

public enum FetchError: Error, LocalizedError {
    case http(Int)

    public var errorDescription: String? {
        switch self {
        case .http(let code): return "HTTP \(code)"
        }
    }
}

/// Fetches status pages, detecting per host whether it is Statuspage or incident.io.
public actor StatusFetcher {
    private enum Platform { case statuspage, incidentIO }

    /// Length of the uptime strip.
    public static let historyDays = 30
    /// `/uptime_showcase` refuses more components per request.
    private static let showcaseBatch = 60

    private let session: URLSession
    private var platforms: [URL: Platform] = [:]

    public init(session: URLSession = .shared) {
        self.session = session
    }

    /// Reads the status, then the details if `force` or `detailsDue` says so.
    /// A failed details read keeps the previous details and is retried on the next poll.
    public func poll(_ service: ServiceConfig, _ state: ServiceState, force: Bool, now: Date = Date()) async -> ServiceState {
        var s = state
        s.status = await Result { try await status(service.url) }
        guard case .success(let page) = s.status else { return s }
        let due = force || detailsDue(previous: s.known, current: page.level, lastFetch: s.detailsAt, now: now)
        s.known = page.level
        if due, let details = try? await details(service.url, now: now) {
            s.details = details
            s.detailsAt = now
        }
        return s
    }

    public func status(_ base: URL) async throws -> PageStatus {
        try decodeStatuspage(await get(base.appendingPathComponent("api/v2/status.json"))).pageStatus
    }

    /// Checks that `base` serves a status page and returns the page's own name, if it has one.
    /// - Throws: network errors, `FetchError.http`, or `DecodingError` when it is not a status page.
    public func pageName(_ base: URL) async throws -> String? {
        try decodeStatuspage(await get(base.appendingPathComponent("api/v2/status.json"))).page.name
    }

    /// Incidents from `summary.json` plus the uptime strip; a failed strip leaves `uptime` nil.
    public func details(_ base: URL, now: Date = Date()) async throws -> ServiceDetails {
        let summary = try decodeStatuspage(await get(base.appendingPathComponent("api/v2/summary.json")))
        return summary.details(uptime: try? await uptime(base, summary: summary, now: now))
    }

    private func uptime(_ base: URL, summary: StatuspageSummary, now: Date) async throws -> Uptime? {
        if platforms[base] != .statuspage, let host = base.host {
            let start = historyStart(days: Self.historyDays, now: now)
            let iso = ISO8601DateFormatter()
            do {
                let data = try await get(base.appendingPathComponent("proxy/\(host)/component_impacts"), query: [
                    "start_at": iso.string(from: start), "end_at": iso.string(from: now),
                ])
                platforms[base] = .incidentIO
                // Names only label the tooltip; the strip is drawn without them.
                let page = try? decodeIncidentIOPage(await get(base.appendingPathComponent("proxy/\(host)")))
                return try decodeImpacts(data).uptime(days: Self.historyDays, now: now, names: page?.componentNames ?? [:])
            } catch FetchError.http(404) {
                platforms[base] = .statuspage
            }
        }
        let componentIDs = summary.componentIDs
        var batches: [UptimeShowcase] = []
        for i in stride(from: 0, to: componentIDs.count, by: Self.showcaseBatch) {
            let ids = componentIDs[i..<min(i + Self.showcaseBatch, componentIDs.count)]
            let data = try await get(base.appendingPathComponent("uptime_showcase"), query: ["components": ids.joined(separator: ",")])
            batches.append(try decodeShowcase(data))
        }
        return showcaseUptime(batches, days: Self.historyDays, names: summary.componentNames)
    }

    /// Whether `base` looks like a status page: a HEAD of its `status.json` answers 200. Cheap enough to run while typing.
    public func answers(_ base: URL) async -> Bool {
        var req = URLRequest(url: base.appendingPathComponent("api/v2/status.json"), cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
        req.httpMethod = "HEAD"
        return ((try? await session.data(for: req))?.1 as? HTTPURLResponse)?.statusCode == 200
    }

    private func get(_ url: URL, query: [String: String] = [:]) async throws -> Data {
        var parts = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        if !query.isEmpty { parts.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) } }
        var req = URLRequest(url: parts.url!, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, resp) = try await session.data(for: req)
        if let code = (resp as? HTTPURLResponse)?.statusCode, !(200..<300).contains(code) {
            throw FetchError.http(code)
        }
        return data
    }
}

extension Result where Failure == Error {
    init(catching body: () async throws -> Success) async {
        do { self = .success(try await body()) } catch { self = .failure(error) }
    }
}
