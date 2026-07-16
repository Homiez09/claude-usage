import XCTest
@testable import ClaudeUsageMenuBar

final class UsageAlertPlannerTests: XCTestCase {
    func testFiresAlertWhenCrossing80PercentFirstTime() {
        let (alerts, state) = UsageAlertPlanner.plan(
            current: [(key: "session", title: "Current session", percent: 82)],
            firedThresholds: [:]
        )
        XCTAssertEqual(alerts.count, 1)
        XCTAssertEqual(alerts[0].threshold, 80)
        XCTAssertEqual(alerts[0].percent, 82)
        XCTAssertEqual(state["session"], 80)
    }

    func testDoesNotRefireSameThresholdOnSubsequentPoll() {
        let (alerts, _) = UsageAlertPlanner.plan(
            current: [(key: "session", title: "Current session", percent: 85)],
            firedThresholds: ["session": 80]
        )
        XCTAssertTrue(alerts.isEmpty)
    }

    func testFiresAgainWhenCrossingHigherThreshold() {
        let (alerts, state) = UsageAlertPlanner.plan(
            current: [(key: "session", title: "Current session", percent: 96)],
            firedThresholds: ["session": 80]
        )
        XCTAssertEqual(alerts.count, 1)
        XCTAssertEqual(alerts[0].threshold, 95)
        XCTAssertEqual(state["session"], 95)
    }

    func testJumpingStraightTo95OnlyFiresOnce() {
        let (alerts, state) = UsageAlertPlanner.plan(
            current: [(key: "session", title: "Current session", percent: 97)],
            firedThresholds: [:]
        )
        XCTAssertEqual(alerts.count, 1)
        XCTAssertEqual(alerts[0].threshold, 95)
        XCTAssertEqual(state["session"], 95)
    }

    func testDroppingBelowThresholdRearmsForNextCrossing() {
        let (_, resetState) = UsageAlertPlanner.plan(
            current: [(key: "session", title: "Current session", percent: 10)],
            firedThresholds: ["session": 95]
        )
        XCTAssertNil(resetState["session"])

        let (alerts, _) = UsageAlertPlanner.plan(
            current: [(key: "session", title: "Current session", percent: 81)],
            firedThresholds: resetState
        )
        XCTAssertEqual(alerts.count, 1)
        XCTAssertEqual(alerts[0].threshold, 80)
    }

    func testTracksMultipleKeysIndependently() {
        let (alerts, state) = UsageAlertPlanner.plan(
            current: [
                (key: "session", title: "Current session", percent: 82),
                (key: "weekly_all-All models", title: "All models", percent: 40),
            ],
            firedThresholds: [:]
        )
        XCTAssertEqual(alerts.count, 1)
        XCTAssertEqual(alerts[0].key, "session")
        XCTAssertNil(state["weekly_all-All models"])
    }

    func testBelow80NeverFires() {
        let (alerts, state) = UsageAlertPlanner.plan(
            current: [(key: "session", title: "Current session", percent: 79)],
            firedThresholds: [:]
        )
        XCTAssertTrue(alerts.isEmpty)
        XCTAssertNil(state["session"])
    }

    // MARK: - shouldNotifyReset

    func testResetNotifiedWhenDroppingFromNearFullToNearZero() {
        XCTAssertTrue(UsageAlertPlanner.shouldNotifyReset(previousPercent: 85, currentPercent: 0))
        XCTAssertTrue(UsageAlertPlanner.shouldNotifyReset(previousPercent: 97, currentPercent: 12))
    }

    func testResetNotNotifiedOnFirstPoll() {
        XCTAssertFalse(UsageAlertPlanner.shouldNotifyReset(previousPercent: nil, currentPercent: 0))
    }

    func testResetNotNotifiedWhenPreviousUsageWasLow() {
        // รีเซ็ตปกติที่ผู้ใช้ไม่ได้รออะไร (ใช้ไปแค่ 40%) — ไม่ต้องเด้ง
        XCTAssertFalse(UsageAlertPlanner.shouldNotifyReset(previousPercent: 40, currentPercent: 0))
    }

    func testResetNotNotifiedWhilePercentStillHigh() {
        XCTAssertFalse(UsageAlertPlanner.shouldNotifyReset(previousPercent: 85, currentPercent: 84))
    }
}
