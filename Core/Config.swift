import Foundation

public struct ServiceConfig: Codable, Equatable, Sendable {
    public var name: String
    public var url: URL
    public var enabled: Bool

    public init(name: String, url: URL, enabled: Bool = true) {
        self.name = name
        self.url = url
        self.enabled = enabled
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        url = try c.decode(URL.self, forKey: .url)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
    }

    /// A status page base URL from what a user typed: adds `https://` when no scheme is given and drops trailing
    /// slashes, so `status.example.com/` becomes `https://status.example.com`. `nil` unless http(s) with a host.
    public static func pageURL(from text: String) -> URL? {
        var s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !s.contains("://") { s = "https://" + s }
        while s.hasSuffix("/") { s.removeLast() }
        guard let url = URL(string: s), ["http", "https"].contains(url.scheme?.lowercased()), url.host?.isEmpty == false else { return nil }
        return url
    }
}

public struct ServiceGroup: Codable, Equatable, Sendable, Identifiable {
    /// Catalog groups use their name, so a stored config can be matched to the catalog; the user's get a UUID.
    public var id: String
    public var name: String
    public var services: [ServiceConfig]

    public init(id: String? = nil, name: String, services: [ServiceConfig]) {
        self.id = id ?? name
        self.name = name
        self.services = services
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? name
        services = try c.decode([ServiceConfig].self, forKey: .services)
    }

}

public struct Config: Codable, Equatable, Sendable {
    public var refreshSeconds: Int
    /// Services outside any group; listed and shown before the groups.
    public var ungrouped: [ServiceConfig]
    public var groups: [ServiceGroup]
    /// Catalog pages the user deleted, so `addingMissing` doesn't bring them back.
    public var removed: [URL]

    public init(refreshSeconds: Int = 60, ungrouped: [ServiceConfig] = [], groups: [ServiceGroup], removed: [URL] = []) {
        self.refreshSeconds = refreshSeconds
        self.ungrouped = ungrouped
        self.groups = groups
        self.removed = removed
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        refreshSeconds = try c.decode(Int.self, forKey: .refreshSeconds)
        ungrouped = try c.decodeIfPresent([ServiceConfig].self, forKey: .ungrouped) ?? []
        groups = try c.decode([ServiceGroup].self, forKey: .groups)
        removed = try c.decodeIfPresent([URL].self, forKey: .removed) ?? []
    }

    /// Enabled services, ungrouped first, then in group order: what the menu shows and polls.
    public var services: [ServiceConfig] { (ungrouped + groups.flatMap(\.services)).filter(\.enabled) }

    public static let `default` = Config(groups: catalog)

    /// Stands for "outside any group" where a group id is expected.
    public static let noGroup = ""

    /// Poll intervals offered in Settings, in seconds.
    public static let refreshChoices = [30, 60, 120, 300, 900]

    static let defaultsKey = "config"
    static let unreadableKey = "config.unreadable"

    /// Where versions up to 0.2.x kept the config; read once by `load` and left in place.
    public static var legacyFileURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("HealthBar/services.json")
    }

    /// The 0.2.x file: a flat list, every entry shown.
    struct Legacy: Decodable {
        let refreshSeconds: Int
        let services: [ServiceConfig]
    }

    /// The stored config, with catalog pages it doesn't know yet added (disabled). With nothing stored it imports
    /// `legacyFile` (or takes `default` when that is missing or malformed) and stores the result, so the file is
    /// read at most once.
    /// Stored data it can't read (say, written by a newer version) is kept under `unreadableKey` before being replaced.
    public static func load(from defaults: UserDefaults = .standard, legacyFile: URL = legacyFileURL) -> Config {
        if let data = defaults.data(forKey: defaultsKey) {
            if let stored = try? JSONDecoder().decode(Config.self, from: data) { return stored.addingMissing(from: catalog) }
            defaults.set(data, forKey: unreadableKey)
        }
        let config = (try? JSONDecoder().decode(Legacy.self, from: Data(contentsOf: legacyFile))).map(imported) ?? .default
        config.save(to: defaults)
        return config
    }

    /// A config from an exported file, or from a 0.2.x `services.json`; catalog pages it lacks are added unchecked,
    /// and an address listed twice is kept once.
    /// - Throws: `DecodingError` when the data is neither.
    public static func importing(_ data: Data) throws -> Config {
        if var config = try? JSONDecoder().decode(Config.self, from: data) {
            var seen = Set<URL>()
            config.ungrouped = config.ungrouped.filter { seen.insert($0.url).inserted }
            for g in config.groups.indices { config.groups[g].services = config.groups[g].services.filter { seen.insert($0.url).inserted } }
            var c = config.addingMissing(from: catalog)
            c.refreshSeconds = snapped(c.refreshSeconds)
            return c
        }
        let legacy = try JSONDecoder().decode(Legacy.self, from: data)
        var seen = Set<URL>()
        return imported(Legacy(refreshSeconds: legacy.refreshSeconds, services: legacy.services.filter { seen.insert($0.url).inserted }))
    }

    /// Readable JSON for Export; `importing` reads it back.
    public func exported() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }

    public func save(to defaults: UserDefaults = .standard) {
        defaults.set(try? JSONEncoder().encode(self), forKey: Self.defaultsKey)
    }

    /// The catalog with exactly the legacy services enabled; ones not in the catalog go outside the groups.
    static func imported(_ legacy: Legacy) -> Config {
        var config = Config(refreshSeconds: snapped(legacy.refreshSeconds), groups: catalog)
        for g in config.groups.indices {
            for s in config.groups[g].services.indices {
                config.groups[g].services[s].enabled = legacy.services.contains { $0.url == config.groups[g].services[s].url }
            }
        }
        config.ungrouped = legacy.services.filter { !config.contains($0.url) }.map { ServiceConfig(name: $0.name, url: $0.url) }
        return config
    }

    /// Adds `catalog` pages missing here and not deleted by the user, disabled, to their group (appended when the group is new).
    func addingMissing(from catalog: [ServiceGroup]) -> Config {
        var config = self
        for group in catalog {
            for service in group.services where !config.contains(service.url) && !config.removed.contains(service.url) {
                var off = service
                off.enabled = false
                if let g = config.groups.firstIndex(where: { $0.id == group.id }) {
                    config.groups[g].services.append(off)
                } else {
                    config.groups.append(ServiceGroup(id: group.id, name: group.name, services: [off]))
                }
            }
        }
        return config
    }

    public func contains(_ url: URL) -> Bool { locate(url) != nil }

    /// Not one of the catalog's pages.
    public static func isCustom(_ url: URL) -> Bool {
        !catalog.contains { $0.services.contains { $0.url == url } }
    }

    /// Appends an empty user group.
    /// - Returns: its id.
    @discardableResult
    public mutating func addGroup(named name: String) -> String {
        let group = ServiceGroup(id: UUID().uuidString, name: name, services: [])
        groups.append(group)
        return group.id
    }

    /// Removes the group `id`; its services move outside the groups when `keepingServices`, else go with it.
    public mutating func removeGroup(_ id: String, keepingServices: Bool) {
        guard let g = groups.firstIndex(where: { $0.id == id }) else { return }
        let group = groups.remove(at: g)
        if keepingServices {
            ungrouped += group.services
        } else {
            removed += group.services.map(\.url).filter { !Self.isCustom($0) }
        }
    }

    /// Removes the page `url` wherever it is; a catalog page stays removed.
    public mutating func remove(_ url: URL) {
        guard let at = locate(url) else { return }
        edit(at.group) { $0.remove(at: at.index) }
        if !Self.isCustom(url) { removed.append(url) }
    }

    /// Appends `service` to the group `id` (`noGroup`: outside the groups); does nothing if there is no such group.
    public mutating func add(_ service: ServiceConfig, toGroup id: String) {
        guard let g = slot(id) else { return }
        edit(g) { $0.append(service) }
    }

    /// Replaces the page `url` with `service`: in place when `group` is where it is, else at the end of `group`.
    public mutating func replace(_ url: URL, with service: ServiceConfig, inGroup group: String) {
        guard let from = locate(url), let to = slot(group) else { return }
        if from.group == to {
            edit(to) { $0[from.index] = service }
        } else {
            edit(from.group) { $0.remove(at: from.index) }
            edit(to) { $0.append(service) }
        }
    }

    /// The id of the group holding the page `url`; `noGroup` outside the groups.
    public func group(of url: URL) -> String? {
        locate(url).map { $0.group.map { groups[$0].id } ?? Self.noGroup }
    }

    /// Moves the page `url` up (negative) or down within its own list; stops at the ends.
    public mutating func shift(_ url: URL, by offset: Int) {
        guard let at = locate(url) else { return }
        edit(at.group) { list in
            let to = min(max(at.index + offset, 0), list.count - 1)
            list.insert(list.remove(at: at.index), at: to)
        }
    }

    /// Moves the group `id` up (negative) or down; stops at the ends.
    public mutating func shiftGroup(_ id: String, by offset: Int) {
        guard let from = groups.firstIndex(where: { $0.id == id }) else { return }
        let to = min(max(from + offset, 0), groups.count - 1)
        groups.insert(groups.remove(at: from), at: to)
    }

    /// Where the page `url` sits in its own list, and that list's length.
    public func position(of url: URL) -> (index: Int, count: Int)? {
        guard let at = locate(url) else { return nil }
        return (at.index, at.group.map { groups[$0].services.count } ?? ungrouped.count)
    }

    /// `group` is a group index, `nil` outside the groups.
    private func locate(_ url: URL) -> (group: Int?, index: Int)? {
        if let i = ungrouped.firstIndex(where: { $0.url == url }) { return (nil, i) }
        for (g, group) in groups.enumerated() {
            if let i = group.services.firstIndex(where: { $0.url == url }) { return (g, i) }
        }
        return nil
    }

    /// `.some(nil)` for `noGroup`, `nil` for an unknown id.
    private func slot(_ id: String) -> Int?? {
        if id == Self.noGroup { return .some(nil) }
        return groups.firstIndex { $0.id == id }.map { .some($0) }
    }

    @discardableResult
    private mutating func edit<R>(_ group: Int?, _ body: (inout [ServiceConfig]) -> R) -> R {
        if let group { return body(&groups[group].services) }
        return body(&ungrouped)
    }

    /// The nearest of `refreshChoices`; on a tie the longer one.
    static func snapped(_ seconds: Int) -> Int {
        refreshChoices.min { (abs($0 - seconds), -$0) < (abs($1 - seconds), -$1) }!
    }
}
