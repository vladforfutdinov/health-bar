import Foundation

public struct ServiceConfig: Codable, Equatable, Sendable {
    public var name: String
    public var url: URL

    public init(name: String, url: URL) {
        self.name = name
        self.url = url
    }
}

public struct Config: Codable, Equatable, Sendable {
    public var refreshSeconds: Int
    public var services: [ServiceConfig]

    public init(refreshSeconds: Int = 60, services: [ServiceConfig]) {
        self.refreshSeconds = refreshSeconds
        self.services = services
    }

    public static let `default` = Config(services: [
        ServiceConfig(name: "GitHub", url: URL(string: "https://www.githubstatus.com")!),
        ServiceConfig(name: "OpenAI", url: URL(string: "https://status.openai.com")!),
        ServiceConfig(name: "Claude", url: URL(string: "https://status.claude.com")!),
        ServiceConfig(name: "Vercel", url: URL(string: "https://www.vercel-status.com")!),
        ServiceConfig(name: "Supabase", url: URL(string: "https://status.supabase.com")!),
    ])

    /// Below this the status pages would be hammered for no gain.
    public static let minRefreshSeconds = 15

    public static var fileURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("HealthBar/services.json")
    }

    /// Reads the config at `url`, writing `Config.default` there first if the file is missing.
    /// - Throws: file-system errors, or `DecodingError` for a malformed file.
    public static func loadOrCreate(at url: URL = fileURL) throws -> Config {
        if !FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            try encoder.encode(Config.default).write(to: url)
        }
        var config = try JSONDecoder().decode(Config.self, from: Data(contentsOf: url))
        config.refreshSeconds = max(config.refreshSeconds, minRefreshSeconds)
        return config
    }
}
