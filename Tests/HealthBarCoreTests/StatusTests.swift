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

    func testConfigCreatesDefaultAndClampsInterval() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("services.json")

        XCTAssertEqual(try Config.loadOrCreate(at: file), .default)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))

        try Data(#"{"refreshSeconds":1,"services":[]}"#.utf8).write(to: file)
        XCTAssertEqual(try Config.loadOrCreate(at: file).refreshSeconds, Config.minRefreshSeconds)

        try Data("{".utf8).write(to: file)
        XCTAssertThrowsError(try Config.loadOrCreate(at: file))
    }
}
