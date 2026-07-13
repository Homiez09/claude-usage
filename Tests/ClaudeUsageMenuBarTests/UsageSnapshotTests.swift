import XCTest
@testable import ClaudeUsageMenuBar

final class UsageSnapshotTests: XCTestCase {
    func testBuildWithNoUsageProducesEmptyRows() {
        let snapshot = UsageSnapshotBuilder.build(
            hasSessionKey: false,
            usage: nil,
            errorMessage: "ยังไม่ได้ตั้งค่า Session Key",
            lastUpdated: nil
        )
        XCTAssertFalse(snapshot.hasSessionKey)
        XCTAssertTrue(snapshot.rows.isEmpty)
        XCTAssertNil(snapshot.lastUpdated)
    }

    func testBuildIncludesSessionAndWeeklyRowsInOrder() {
        let usage = UsageResponse(
            fiveHour: LimitWindow(utilization: 41, resetsAt: "2026-07-13T07:30:00+00:00"),
            sevenDay: LimitWindow(utilization: 43, resetsAt: "2026-07-15T16:00:00+00:00"),
            limits: [
                LimitEntry(group: "session", kind: "session", percent: 41, resetsAt: "2026-07-13T07:30:00+00:00", severity: "normal", scope: nil),
                LimitEntry(group: "weekly", kind: "weekly_all", percent: 43, resetsAt: "2026-07-15T16:00:00+00:00", severity: "normal", scope: nil),
                LimitEntry(group: "weekly", kind: "weekly_scoped", percent: 16, resetsAt: "2026-07-15T16:00:00+00:00", severity: "normal", scope: LimitScope(model: ModelInfo(displayName: "Fable")))
            ]
        )
        let now = Date(timeIntervalSince1970: 1_800_000_000)

        let snapshot = UsageSnapshotBuilder.build(hasSessionKey: true, usage: usage, errorMessage: nil, lastUpdated: now)

        XCTAssertEqual(snapshot.rows.count, 3)
        XCTAssertEqual(snapshot.rows[0].title, "Current session")
        XCTAssertEqual(snapshot.rows[0].percent, 41)
        XCTAssertEqual(snapshot.rows[1].title, "All models")
        XCTAssertEqual(snapshot.rows[1].percent, 43)
        XCTAssertEqual(snapshot.rows[2].title, "Fable")
        XCTAssertEqual(snapshot.rows[2].percent, 16)
        XCTAssertNotNil(snapshot.lastUpdated)
    }

    func testBuildExcludesSessionGroupFromWeeklyRows() {
        let usage = UsageResponse(
            fiveHour: nil,
            sevenDay: nil,
            limits: [
                LimitEntry(group: "session", kind: "session", percent: 90, resetsAt: nil, severity: "normal", scope: nil)
            ]
        )
        let snapshot = UsageSnapshotBuilder.build(hasSessionKey: true, usage: usage, errorMessage: nil, lastUpdated: nil)
        XCTAssertTrue(snapshot.rows.isEmpty)
    }

    func testEncodeJSONRoundTripsThroughDecoder() throws {
        let snapshot = UsageSnapshot(
            hasSessionKey: true,
            errorMessage: nil,
            lastUpdated: "2026-07-13T07:30:00Z",
            rows: [UsageSnapshot.Row(title: "Current session", percent: 41, resetsAt: "2026-07-13T07:30:00Z")],
            activeAgentSessions: ["Fix the login bug"]
        )
        let json = UsageSnapshotBuilder.encodeJSON(snapshot)
        let decoded = try JSONDecoder().decode(UsageSnapshot.self, from: Data(json.utf8))
        XCTAssertEqual(decoded, snapshot)
    }

    func testBuildIncludesActiveAgentSessions() {
        let snapshot = UsageSnapshotBuilder.build(
            hasSessionKey: true,
            usage: nil,
            errorMessage: nil,
            lastUpdated: nil,
            activeAgentSessions: ["Fix the login bug", "Refactor billing"]
        )
        XCTAssertEqual(snapshot.activeAgentSessions, ["Fix the login bug", "Refactor billing"])
    }

    func testBuildDefaultsToNoActiveAgentSessions() {
        let snapshot = UsageSnapshotBuilder.build(hasSessionKey: true, usage: nil, errorMessage: nil, lastUpdated: nil)
        XCTAssertTrue(snapshot.activeAgentSessions.isEmpty)
    }

    func testRouteReturnsJSONForApiUsagePath() {
        let result = LocalWebServer.route(path: "/api/usage", snapshotJSON: "{\"hasSessionKey\":true}")
        XCTAssertEqual(result.contentType, "application/json; charset=utf-8")
        XCTAssertEqual(result.body, "{\"hasSessionKey\":true}")
    }

    func testRouteReturnsHTMLForRootAndUnknownPaths() {
        let root = LocalWebServer.route(path: "/", snapshotJSON: "unused")
        XCTAssertEqual(root.contentType, "text/html; charset=utf-8")
        XCTAssertEqual(root.body, LocalWebServer.htmlPage)

        let unknown = LocalWebServer.route(path: "/whatever", snapshotJSON: "unused")
        XCTAssertEqual(unknown.contentType, "text/html; charset=utf-8")
    }
}
