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

    private let session: URLSession
    private var platforms: [URL: Platform] = [:]

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func fetch(_ service: ServiceConfig) async throws -> ServiceStatus {
        async let summaryData = get(service.url.appendingPathComponent("api/v2/summary.json"))
        let items = await incidentIOItems(service.url)
        return try decodeStatuspage(await summaryData).serviceStatus(items: items)
    }

    public func fetchAll(_ services: [ServiceConfig]) async -> [Result<ServiceStatus, Error>] {
        await withTaskGroup(of: (Int, Result<ServiceStatus, Error>).self) { group in
            for (i, s) in services.enumerated() {
                group.addTask { (i, await Result(catching: { try await self.fetch(s) })) }
            }
            var out = [Result<ServiceStatus, Error>?](repeating: nil, count: services.count)
            for await (i, r) in group { out[i] = r }
            return out.map { $0! }
        }
    }

    /// Detail rows from incident.io's proxy; `nil` for Statuspage hosts or when the proxy fails,
    /// so the caller falls back to the summary's own components.
    private func incidentIOItems(_ base: URL) async -> [Item]? {
        if platforms[base] == .statuspage { return nil }
        guard let host = base.host else { return nil }
        do {
            let items = try decodeIncidentIO(await get(base.appendingPathComponent("proxy/\(host)"))).items()
            platforms[base] = .incidentIO
            return items
        } catch FetchError.http(404) {
            platforms[base] = .statuspage
            return nil
        } catch {
            return nil
        }
    }

    private func get(_ url: URL) async throws -> Data {
        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
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
