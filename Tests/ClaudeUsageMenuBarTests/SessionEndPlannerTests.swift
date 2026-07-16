import XCTest
@testable import ClaudeUsageMenuBar

final class SessionEndPlannerTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func session(
        id: String,
        name: String? = nil,
        isActive: Bool,
        isSubagent: Bool = false
    ) -> ClaudeCodeSessionStatus {
        ClaudeCodeSessionStatus(
            id: id,
            displayName: name ?? id,
            isActive: isActive,
            lastActivity: now,
            model: nil,
            isSubagent: isSubagent,
            subagentType: isSubagent ? "general-purpose" : nil
        )
    }

    func testNewlyActiveSessionGetsTrackedWithCurrentTime() {
        let (ended, state) = SessionEndPlanner.plan(
            activeSince: [:],
            sessions: [session(id: "a", isActive: true)],
            now: now
        )
        XCTAssertTrue(ended.isEmpty)
        XCTAssertEqual(state["a"], now)
    }

    func testStillActiveSessionKeepsOriginalStartTime() {
        let started = now.addingTimeInterval(-300)
        let (ended, state) = SessionEndPlanner.plan(
            activeSince: ["a": started],
            sessions: [session(id: "a", isActive: true)],
            now: now
        )
        XCTAssertTrue(ended.isEmpty)
        XCTAssertEqual(state["a"], started)
    }

    func testSessionEndingAfterLongRunFiresWithDuration() {
        let started = now.addingTimeInterval(-600)
        let (ended, state) = SessionEndPlanner.plan(
            activeSince: ["a": started],
            sessions: [session(id: "a", name: "Fix login bug", isActive: false)],
            now: now
        )
        XCTAssertEqual(ended, [
            SessionEndPlanner.EndedSession(id: "a", displayName: "Fix login bug", activeDuration: 600)
        ])
        XCTAssertNil(state["a"])
    }

    func testShortBurstDoesNotFire() {
        // ถาม-ตอบสั้นๆ: active แค่ ~1 นาทีแล้วเงียบ — ไม่ควรเด้งแจ้งเตือน
        let started = now.addingTimeInterval(-60)
        let (ended, state) = SessionEndPlanner.plan(
            activeSince: ["a": started],
            sessions: [session(id: "a", isActive: false)],
            now: now
        )
        XCTAssertTrue(ended.isEmpty)
        XCTAssertNil(state["a"])
    }

    func testSubagentsAreNeverTrackedOrReported() {
        let started = now.addingTimeInterval(-600)
        let (ended, state) = SessionEndPlanner.plan(
            activeSince: ["parent/agent-1": started],
            sessions: [
                session(id: "parent/agent-1", isActive: false, isSubagent: true),
                session(id: "sub-active", isActive: true, isSubagent: true),
            ],
            now: now
        )
        XCTAssertTrue(ended.isEmpty)
        XCTAssertTrue(state.isEmpty)
    }

    func testIdleSessionNeverSeenActiveDoesNotFireOnFirstPoll() {
        // poll แรกหลังเปิดแอป: ทุก session เป็น idle อยู่แล้ว — ห้ามเด้ง
        let (ended, state) = SessionEndPlanner.plan(
            activeSince: [:],
            sessions: [session(id: "a", isActive: false)],
            now: now
        )
        XCTAssertTrue(ended.isEmpty)
        XCTAssertTrue(state.isEmpty)
    }

    func testDisappearedSessionIsDroppedFromStateWithoutFiring() {
        let started = now.addingTimeInterval(-600)
        let (ended, state) = SessionEndPlanner.plan(
            activeSince: ["gone": started],
            sessions: [],
            now: now
        )
        XCTAssertTrue(ended.isEmpty)
        XCTAssertTrue(state.isEmpty)
    }

    func testMultipleSessionsTrackedIndependently() {
        let longStarted = now.addingTimeInterval(-600)
        let (ended, state) = SessionEndPlanner.plan(
            activeSince: ["done": longStarted, "busy": longStarted],
            sessions: [
                session(id: "done", isActive: false),
                session(id: "busy", isActive: true),
                session(id: "fresh", isActive: true),
            ],
            now: now
        )
        XCTAssertEqual(ended.map(\.id), ["done"])
        XCTAssertEqual(state["busy"], longStarted)
        XCTAssertEqual(state["fresh"], now)
        XCTAssertNil(state["done"])
    }
}
