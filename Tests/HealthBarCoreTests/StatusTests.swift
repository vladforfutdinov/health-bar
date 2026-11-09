import XCTest
@testable import HealthBarCore

final class StatusTests: XCTestCase {
    private func fixture(_ name: String) throws -> Data {
        let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
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

    func testHumanize() {
        XCTAssertEqual(humanize("partial_outage"), "Partial outage")
    }

    func testRealStatuspageSummaries() throws {
        let gh = try decodeStatuspage(fixture("github-summary")).serviceStatus()
        XCTAssertEqual(gh.level, .ok)
        XCTAssertEqual(gh.description, "All Systems Operational")
        XCTAssertFalse(gh.items.isEmpty)

        let vercel = try decodeStatuspage(fixture("vercel-summary")).serviceStatus()
        XCTAssertLessThan(vercel.items.count, 67, "group children must fold into their group row")
        XCTAssertTrue(vercel.items.allSatisfy { $0.level == .ok })

        let openai = try decodeStatuspage(fixture("openai-summary")).serviceStatus()
        XCTAssertEqual(openai.incidents.count, 1)
        XCTAssertEqual(openai.incidents[0].stage, "monitoring")
        XCTAssertNotNil(openai.incidents[0].lastUpdate)
        XCTAssertEqual(openai.incidents[0].level, .ok, "impact none")
    }

    func testScheduledMaintenanceIsNotAnIncident() throws {
        let sb = try decodeStatuspage(fixture("supabase-summary")).serviceStatus()
        XCTAssertTrue(sb.incidents.isEmpty)
    }

    func testRealIncidentIOProxy() throws {
        let items = try decodeIncidentIO(fixture("supabase-proxy")).items()
        XCTAssertEqual(items.count, 16)
        XCTAssertEqual(items.first?.name, "Branching")
        XCTAssertTrue(items.allSatisfy { $0.level == .ok && $0.affected.isEmpty })
    }

    func testStatuspageGroupAggregation() throws {
        let json = """
        {"page":{"url":"https://example.com"},
         "status":{"indicator":"minor","description":"Partial System Outage"},
         "components":[
           {"id":"g","name":"Edge","status":"partial_outage","position":1,"group_id":null},
           {"id":"a","name":"fra1","status":"operational","position":1,"group_id":"g"},
           {"id":"b","name":"iad1","status":"partial_outage","position":2,"group_id":"g"},
           {"id":"c","name":"cdg1","status":"degraded_performance","position":3,"group_id":"g"},
           {"id":"d","name":"API","status":"operational","position":0,"group_id":null},
           {"id":"e","name":"Hidden","status":"operational","position":2,"group_id":null,"only_show_if_degraded":true}
         ],
         "incidents":[{"id":"x1","name":"Edge errors","status":"investigating","impact":"minor","shortlink":null,
           "incident_updates":[{"body":"Newest"},{"body":"Older"}]}],
         "scheduled_maintenances":[{"id":"m1","name":"DB upgrade","status":"in_progress","impact":"maintenance","shortlink":"https://stspg.io/m1"}]}
        """
        let s = try decodeStatuspage(Data(json.utf8)).serviceStatus()
        XCTAssertEqual(s.level, .degraded)
        XCTAssertEqual(s.items, [
            Item(name: "API", level: .ok, status: "operational", affected: []),
            Item(name: "Edge", level: .degraded, status: "partial_outage", affected: ["iad1", "cdg1"]),
        ])
        XCTAssertEqual(s.incidents.map(\.name), ["Edge errors", "DB upgrade"])
        XCTAssertEqual(s.incidents[0].lastUpdate, "Newest")
        XCTAssertEqual(s.incidents[0].url.absoluteString, "https://example.com/incidents/x1")
        XCTAssertEqual(s.incidents[1].url.absoluteString, "https://stspg.io/m1")
        XCTAssertEqual(s.incidents[1].level, .maintenance)
    }

    func testIncidentIOAffectedComponents() throws {
        let json = """
        {"summary":{"structure":{"items":[
            {"group":{"name":"Postgres","hidden":false,"components":[
                {"component_id":"p1","name":"eu-west-1","hidden":false},
                {"component_id":"p2","name":"us-east-1","hidden":false},
                {"component_id":"p3","name":"secret","hidden":true}]}},
            {"component":{"component_id":"a1","name":"Auth","hidden":false}},
            {"component":{"component_id":"h1","name":"Hidden","hidden":true}}]},
          "affected_components":[
            {"component_id":"p2","status":"full_outage"},
            {"component_id":"p3","status":"full_outage"},
            {"component_id":"a1","status":"degraded_performance"}]}}
        """
        XCTAssertEqual(try decodeIncidentIO(Data(json.utf8)).items(), [
            Item(name: "Postgres", level: .outage, status: "full_outage", affected: ["us-east-1"]),
            Item(name: "Auth", level: .degraded, status: "degraded_performance", affected: []),
        ])
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
