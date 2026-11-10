import XCTest
@testable import HealthBarCore

final class StatusTests: XCTestCase {
    private func fixture(_ name: String) throws -> Data {
        let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }

    private func date(_ s: String) -> Date { ISO8601DateFormatter().date(from: s)! }

    private var utc: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    func testLevelMapping() {
        XCTAssertEqual(Level(indicator: "none"), .ok)
        XCTAssertEqual(Level(indicator: "minor"), .degraded)
        XCTAssertEqual(Level(indicator: "major"), .outage)
        XCTAssertEqual(Level(indicator: "critical"), .outage)
        XCTAssertEqual(Level(indicator: "maintenance"), .maintenance)
        XCTAssertEqual(Level(componentStatus: "operational"), .ok)
        XCTAssertEqual(Level(componentStatus: "degraded_performance"), .degraded)
        XCTAssertEqual(Level(componentStatus: "partial_outage"), .degraded)
        XCTAssertEqual(Level(componentStatus: "major_outage"), .outage)
        XCTAssertEqual(Level(componentStatus: "full_outage"), .outage)
        XCTAssertEqual(Level(componentStatus: "under_maintenance"), .maintenance)
    }

    func testIconState() {
        XCTAssertEqual(IconState(levels: [.ok, .ok]), .ok)
        XCTAssertEqual(IconState(levels: [.ok, .maintenance]), .ok)
        XCTAssertEqual(IconState(levels: [.ok, nil]), .ok)
        XCTAssertEqual(IconState(levels: [.degraded, .maintenance, nil]), .degraded)
        XCTAssertEqual(IconState(levels: [.degraded, .outage]), .outage)
        XCTAssertEqual(IconState(levels: [nil, nil]), .unknown)
        XCTAssertEqual(IconState(levels: []), .unknown)
    }

    func testStatusJSON() throws {
        let json = #"{"page":{"id":"x","name":"GitHub","url":"https://www.githubstatus.com"},"status":{"indicator":"major","description":"Partial System Outage"}}"#
        XCTAssertEqual(try decodeStatuspage(Data(json.utf8)).pageStatus, PageStatus(level: .outage, description: "Partial System Outage"))
        XCTAssertEqual(try decodeStatuspage(Data(json.utf8)).page.name, "GitHub")
    }

    func testRealStatuspageSummaries() throws {
        let gh = try decodeStatuspage(fixture("github-summary"))
        XCTAssertEqual(gh.pageStatus, PageStatus(level: .ok, description: "All Systems Operational"))
        XCTAssertEqual(gh.componentIDs.count, 12)

        let vercel = try decodeStatuspage(fixture("vercel-summary"))
        XCTAssertEqual(vercel.componentIDs.count, 59, "8 group ids left out: they expand to their children")
        XCTAssertEqual(vercel.componentNames.count, 59)
        XCTAssertEqual(vercel.componentNames["k8z1d2ll8hb3"], "CDN · ARN1 - Stockholm, Sweden")
        XCTAssertEqual(gh.componentNames.values.sorted().first, "API Requests", "no group: bare name")

        let openai = try decodeStatuspage(fixture("openai-summary")).details(uptime: nil)
        XCTAssertEqual(openai.incidents.count, 1)
        XCTAssertEqual(openai.incidents[0].stage, "monitoring")
        XCTAssertNotNil(openai.incidents[0].lastUpdate)
        XCTAssertEqual(openai.incidents[0].level, .ok, "impact none")
    }

    func testScheduledMaintenanceIsNotAnIncident() throws {
        XCTAssertTrue(try decodeStatuspage(fixture("supabase-summary")).details(uptime: nil).incidents.isEmpty)
    }

    func testIncidentsAndActiveMaintenance() throws {
        let json = """
        {"page":{"url":"https://example.com"},
         "status":{"indicator":"minor","description":"Partial System Outage"},
         "incidents":[{"id":"x1","name":"Edge errors","status":"investigating","impact":"minor","shortlink":null,
           "incident_updates":[{"body":"Newest"},{"body":"Older"}]}],
         "scheduled_maintenances":[
           {"id":"m1","name":"DB upgrade","status":"in_progress","impact":"maintenance","shortlink":"https://stspg.io/m1"},
           {"id":"m2","name":"Later","status":"scheduled","impact":"maintenance","shortlink":null}]}
        """
        let s = try decodeStatuspage(Data(json.utf8)).details(uptime: nil)
        XCTAssertEqual(s.incidents.map(\.name), ["Edge errors", "DB upgrade"])
        XCTAssertEqual(s.incidents[0].lastUpdate, "Newest")
        XCTAssertEqual(s.incidents[0].url.absoluteString, "https://example.com/incidents/x1")
        XCTAssertEqual(s.incidents[1].url.absoluteString, "https://stspg.io/m1")
        XCTAssertEqual(s.incidents[1].level, .maintenance)
    }

    func testShowcaseUptimeTakesWorstComponentPerDay() throws {
        let a = """
        {"components":{"a":"<svg/>"},"values":[{"component":"a","ninety":99.9,"sixty":99.9,"thirty":99.95}],
         "timelines":{"a":{"component":{},"days":[
           {"date":"2026-11-08","outages":{},"related_events":[]},
           {"date":"2026-11-09","outages":{"p":600},"related_events":[]},
           {"date":"2026-11-10","outages":{},"related_events":[]}]}}}
        """
        let b = """
        {"components":{},"values":[{"component":"b","ninety":100,"sixty":100,"thirty":99.5}],
         "timelines":{"b":{"component":{"code":"b","name":"Pages"},"days":[
           {"date":"2026-11-08","outages":{"m":411},"related_events":[]},
           {"date":"2026-11-09","outages":{},"related_events":[]},
           {"date":"2026-11-10","outages":{"p":5,"m":0},"related_events":[]}]}}}
        """
        let batches = try [a, b].map { try decodeShowcase(Data($0.utf8)) }
        let u = try XCTUnwrap(showcaseUptime(batches, days: 3, names: ["a": "Git · Push"], calendar: utc))
        XCTAssertEqual(u.days.map(\.level), [.outage, .degraded, .degraded])
        XCTAssertEqual(u.percent, 99.5)
        XCTAssertEqual(u.days[0].date, date("2026-11-08T00:00:00Z"))
        XCTAssertEqual(u.days[0].outages, [Outage(component: "Pages", status: "major_outage", seconds: 411)], "showcase name when not in names")
        XCTAssertEqual(u.days[1].outages, [Outage(component: "Git · Push", status: "partial_outage", seconds: 600)])
        XCTAssertEqual(u.days[2].outages.map(\.seconds), [5], "zero-second outages are dropped")
        XCTAssertEqual(showcaseUptime(batches, days: 2)?.days.map(\.level), [.degraded, .degraded], "keeps the newest days")
        XCTAssertNil(showcaseUptime([], days: 3))
    }

    func testIncidentIOImpactsUptime() throws {
        let json = """
        {"component_impacts":[
          {"id":"1","component_id":"c1","start_at":"2026-11-08T23:00:00.5Z","end_at":"2026-11-09T01:00:00.5Z","status":"full_outage","status_page_incident_id":"i1"},
          {"id":"2","component_id":"c2","start_at":"2026-11-10T10:00:00.03Z","end_at":null,"status":"partial_outage","status_page_incident_id":"i2"},
          {"id":"3","component_id":"c3","start_at":"2026-11-07T10:00:00Z","end_at":"2026-11-07T11:00:00Z","status":"full_outage","status_page_incident_id":"i3"}],
         "component_uptimes":[],"incident_links":[]}
        """
        let u = try decodeImpacts(Data(json.utf8)).uptime(days: 3, now: date("2026-11-10T12:00:00Z"), names: ["c1": "APIs · Chat"], calendar: utc)
        XCTAssertEqual(u.days.map(\.level), [.outage, .outage, .degraded], "c3 ended before the window")
        XCTAssertEqual(u.days.map(\.date), [date("2026-11-08T00:00:00Z"), date("2026-11-09T00:00:00Z"), date("2026-11-10T00:00:00Z")])
        XCTAssertEqual(u.days[0].outages.map(\.component), ["APIs · Chat"])
        XCTAssertEqual(u.days[0].outages[0].seconds, 3599.5, accuracy: 0.01, "split at midnight")
        XCTAssertEqual(u.days[1].outages[0].seconds, 3600.5, accuracy: 0.01)
        XCTAssertEqual(u.days[2].outages.map(\.component), ["c2"], "id when the name is unknown")
        XCTAssertEqual(u.days[2].outages[0].status, "partial_outage")
        XCTAssertEqual(u.days[2].outages[0].seconds, 7199.97, accuracy: 0.01, "ongoing: counted up to now")
        // window 60 h; worst component c1 down 2 h (c2: 2 h × 0.3)
        XCTAssertEqual(u.percent, 100 * (1 - 2.0 / 60), accuracy: 0.001)
    }

    func testIncidentIOComponentNames() throws {
        let json = """
        {"summary":{"name":"Supabase","structure":{"items":[
          {"group":{"id":"g1","name":"Branching","hidden":false,"components":[{"component_id":"c1","name":"ap-east-1","hidden":false}]}},
          {"component":{"component_id":"c2","name":"Auth","hidden":false}}]}}}
        """
        XCTAssertEqual(try decodeIncidentIOPage(Data(json.utf8)).componentNames, ["c1": "Branching · ap-east-1", "c2": "Auth"])
    }

    func testDayOrdersOutagesBySeverityThenDuration() {
        let day = UptimeDay(date: Date(), outages: [
            Outage(component: "a", status: "partial_outage", seconds: 900),
            Outage(component: "b", status: "major_outage", seconds: 60),
            Outage(component: "c", status: "partial_outage", seconds: 1800),
        ])
        XCTAssertEqual(day.outages.map(\.component), ["b", "c", "a"])
        XCTAssertEqual(day.level, .outage)
        XCTAssertEqual(UptimeDay(date: Date(), outages: []).level, .ok)
    }

    func testDetailsSchedule() {
        let t0 = date("2026-11-10T12:00:00Z")
        func due(_ prev: Level?, _ cur: Level, after minutes: Double?) -> Bool {
            detailsDue(previous: prev, current: cur, lastFetch: minutes.map { _ in t0 }, now: t0.addingTimeInterval((minutes ?? 0) * 60))
        }
        XCTAssertTrue(due(nil, .ok, after: 1), "first status read")
        XCTAssertTrue(due(.ok, .ok, after: nil), "never fetched")
        XCTAssertTrue(due(.ok, .degraded, after: 1), "status changed")
        XCTAssertTrue(due(.degraded, .ok, after: 1), "recovered")
        XCTAssertFalse(due(.ok, .ok, after: 59))
        XCTAssertTrue(due(.ok, .ok, after: 60))
        XCTAssertFalse(due(.degraded, .degraded, after: 14))
        XCTAssertTrue(due(.degraded, .degraded, after: 15))
    }

    private func scratchDefaults() -> UserDefaults {
        let name = "HealthBarTests-\(UUID().uuidString)"
        addTeardownBlock { UserDefaults.standard.removePersistentDomain(forName: name) }
        return UserDefaults(suiteName: name)!
    }

    private func scratchFile(_ contents: String?) throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("services.json")
        if let contents { try Data(contents.utf8).write(to: file) }
        return file
    }

    func testConfigDefaultsWhenNothingStoredOrImported() throws {
        let defaults = scratchDefaults()
        XCTAssertEqual(Config.load(from: defaults, legacyFile: try scratchFile(nil)), .default)
        XCTAssertNotNil(defaults.data(forKey: Config.defaultsKey), "stored on first load")
    }

    func testDefaultShowsTheOriginalFive() {
        XCTAssertEqual(Config.default.services.map(\.name), ["GitHub", "OpenAI", "Claude", "Vercel", "Supabase"])
        let urls = Config.catalog.flatMap(\.services).map(\.url)
        XCTAssertEqual(Set(urls).count, urls.count, "no page listed twice")
    }

    func testConfigImportsLegacyFileOnce() throws {
        let defaults = scratchDefaults()
        let file = try scratchFile(#"{"refreshSeconds":50,"services":[{"name":"Mine","url":"https://status.npmjs.org"},{"name":"X","url":"https://x.example"}]}"#)
        let imported = Config.load(from: defaults, legacyFile: file)
        XCTAssertEqual(imported.refreshSeconds, 60)
        XCTAssertEqual(imported.services.map(\.name), ["X", "npm"], "exactly the legacy pages; catalog names win")
        XCTAssertEqual(imported.ungrouped.map(\.name), ["X"], "pages outside the catalog go outside the groups")

        try Data(#"{"refreshSeconds":900,"services":[]}"#.utf8).write(to: file)
        XCTAssertEqual(Config.load(from: defaults, legacyFile: file), imported, "the file is not read again")
    }

    func testConfigMalformedLegacyFileFallsBackToDefault() throws {
        XCTAssertEqual(Config.load(from: scratchDefaults(), legacyFile: try scratchFile("{")), .default)
    }

    func testConfigSaveRoundTrip() throws {
        let defaults = scratchDefaults()
        var config = Config.default
        config.refreshSeconds = 300
        config.groups.swapAt(0, 1)
        config.groups[0].services[0].enabled = false
        let mine = config.addGroup(named: "Mine")
        config.add(ServiceConfig(name: "Y", url: URL(string: "https://y.example")!), toGroup: mine)
        config.save(to: defaults)
        XCTAssertEqual(Config.load(from: defaults, legacyFile: try scratchFile(nil)), config)
    }

    func testStoredConfigGainsNewCatalogPagesDisabled() {
        let new = ServiceConfig(name: "New", url: URL(string: "https://new.example")!, enabled: true)
        let catalog = Config.catalog + [ServiceGroup(name: "Fresh", services: [new])]
        var trimmed = Config.default
        trimmed.groups[0].services.removeLast()
        let merged = trimmed.addingMissing(from: catalog)
        XCTAssertEqual(merged.groups.last, ServiceGroup(name: "Fresh", services: [ServiceConfig(name: "New", url: new.url, enabled: false)]))
        var renamed = Config.default
        renamed.groups[0].name = "Renamed"
        XCTAssertEqual(renamed.addingMissing(from: Config.catalog).groups.count, Config.catalog.count, "matched by id, not name")
        XCTAssertEqual(merged.groups[0].services.last?.url, Config.catalog[0].services.last?.url, "re-added to its group")
        XCTAssertEqual(merged.services, Config.default.services, "nothing new is shown")
    }

    func testUserGroups() throws {
        var config = Config.default
        let id = config.addGroup(named: "Mine")
        let page = ServiceConfig(name: "Z", url: URL(string: "https://z.example")!)
        config.add(page, toGroup: id)
        XCTAssertEqual(config.groups.last?.services, [page])
        XCTAssertEqual(config.groups.last?.isCustom, true)
        XCTAssertEqual(config.groups.first?.isCustom, false)
        XCTAssertTrue(Config.isCustom(page.url))
        XCTAssertFalse(Config.isCustom(URL(string: "https://www.githubstatus.com")!))
        XCTAssertEqual(config.services.last, page)

        let old = try JSONDecoder().decode(ServiceGroup.self, from: Data(#"{"name":"AI","services":[]}"#.utf8))
        XCTAssertEqual(old.id, "AI", "stored before ids: the name")
    }

    func testMovingServicesAndGroups() {
        func names(_ c: Config, _ g: Int) -> [String] { c.groups[g].services.map(\.name) }
        let url = { (name: String) in Config.catalog.flatMap(\.services).first { $0.name == name }!.url }
        var c = Config.default

        c.move(url("GitHub"), to: url("CircleCI"), after: true)
        XCTAssertEqual(Array(names(c, 0).prefix(3)), ["Bitbucket", "CircleCI", "GitHub"])
        c.move(url("GitHub"), to: url("Bitbucket"), after: false)
        XCTAssertEqual(Array(names(c, 0).prefix(3)), ["GitHub", "Bitbucket", "CircleCI"])
        c.move(url("GitHub"), to: url("GitHub"), after: true)
        XCTAssertEqual(names(c, 0).first, "GitHub", "onto itself: no change")

        c.move(url("Claude"), to: url("GitHub"), after: true)
        XCTAssertEqual(Array(names(c, 0).prefix(3)), ["GitHub", "Claude", "Bitbucket"], "across groups")
        XCTAssertFalse(names(c, 1).contains("Claude"))

        c.move(url("Claude"), intoGroup: "Databases")
        XCTAssertEqual(c.groups[3].services.first?.name, "Claude", "dropped on a header: top of that group")
        XCTAssertEqual(c.services.map(\.name), ["GitHub", "OpenAI", "Vercel", "Claude", "Supabase"])

        c.moveGroup("Databases", to: "Git, CI", after: false)
        XCTAssertEqual(c.groups.prefix(3).map(\.name), ["Databases", "Git, CI", "AI"])
        c.moveGroup("Databases", to: "AI", after: true)
        XCTAssertEqual(c.groups.prefix(3).map(\.name), ["Git, CI", "AI", "Databases"])
        c.moveGroup("Git, CI", to: c.groups.last!.id, after: true)
        XCTAssertEqual(c.groups.last?.name, "Git, CI", "after the last group")
        XCTAssertEqual(c.addingMissing(from: Config.catalog), c, "moved catalog pages are not re-added")
    }

    func testReplacingAService() {
        var c = Config.default
        let gh = c.groups[0].services[0]
        var renamed = gh
        renamed.name = "GH"
        c.replace(gh.url, with: renamed, inGroup: "Git, CI")
        XCTAssertEqual(c.groups[0].services[0], renamed, "same group: in place")

        let mine = c.addGroup(named: "Mine")
        c.replace(gh.url, with: renamed, inGroup: mine)
        XCTAssertEqual(c.groups.last?.services, [renamed], "other group: moved to its end")
        XCTAssertEqual(c.group(of: gh.url), mine)
        XCTAssertFalse(c.groups[0].services.contains(renamed))
    }

    func testUngroupedServices() throws {
        let url = { (name: String) in Config.catalog.flatMap(\.services).first { $0.name == name }!.url }
        var c = Config.default
        let solo = ServiceConfig(name: "Solo", url: URL(string: "https://solo.example")!)
        c.add(solo, toGroup: Config.noGroup)
        XCTAssertEqual(c.services.first, solo, "ungrouped come first")
        XCTAssertEqual(c.group(of: solo.url), Config.noGroup)

        c.move(url("GitHub"), to: solo.url, after: true)
        XCTAssertEqual(c.ungrouped.map(\.name), ["Solo", "GitHub"], "dragged out of a group")
        c.move(solo.url, intoGroup: "AI")
        XCTAssertEqual(c.groups[1].services.first, solo)

        let mine = c.addGroup(named: "Mine")
        c.move(solo.url, intoGroup: mine)
        c.removeGroup(mine, keepingServices: true)
        XCTAssertEqual(c.ungrouped.last, solo, "kept: moved outside the groups")
        let other = c.addGroup(named: "Other")
        c.move(solo.url, intoGroup: other)
        c.removeGroup(other, keepingServices: false)
        XCTAssertFalse(c.contains(solo.url))

        c.remove(url("GitHub"))
        XCTAssertFalse(c.contains(url("GitHub")))
        XCTAssertFalse(c.addingMissing(from: Config.catalog).contains(url("GitHub")), "a deleted catalog page stays deleted")
        c.removeGroup("AI", keepingServices: false)
        XCTAssertFalse(c.addingMissing(from: Config.catalog).groups.contains { $0.id == "AI" }, "nor does a deleted catalog group")

        let stored = try JSONDecoder().decode(Config.self, from: Data(#"{"refreshSeconds":60,"groups":[]}"#.utf8))
        XCTAssertEqual(stored.ungrouped, [], "stored before ungrouped existed")
    }

    func testPageURLFromTypedText() {
        XCTAssertEqual(ServiceConfig.pageURL(from: " status.example.com/ ")?.absoluteString, "https://status.example.com")
        XCTAssertEqual(ServiceConfig.pageURL(from: "http://x.example//")?.absoluteString, "http://x.example")
        XCTAssertEqual(ServiceConfig.pageURL(from: "https://example.com/status")?.absoluteString, "https://example.com/status")
        XCTAssertNil(ServiceConfig.pageURL(from: ""))
        XCTAssertNil(ServiceConfig.pageURL(from: "ftp://x.example"))
        XCTAssertNil(ServiceConfig.pageURL(from: "not a url"))
    }

    func testRefreshIntervalSnapsToChoices() {
        XCTAssertEqual(Config.snapped(1), 30)
        XCTAssertEqual(Config.snapped(60), 60)
        XCTAssertEqual(Config.snapped(90), 120, "tie goes to the longer interval")
        XCTAssertEqual(Config.snapped(100_000), 900)
    }
}
