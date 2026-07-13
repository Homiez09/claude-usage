import XCTest
@testable import ClaudeUsageMenuBar

final class DateParsingTests: XCTestCase {
    func testParsesFractionalSeconds() {
        let date = FlexibleISO8601.date(from: "2026-07-13T07:30:00.473904+00:00")
        XCTAssertNotNil(date)
    }

    func testParsesWithoutFractionalSeconds() {
        let date = FlexibleISO8601.date(from: "2026-07-13T07:30:00+00:00")
        XCTAssertNotNil(date)
    }

    func testReturnsNilForGarbageInput() {
        XCTAssertNil(FlexibleISO8601.date(from: "not-a-date"))
        XCTAssertNil(FlexibleISO8601.date(from: nil))
    }

    func testDescribeMinutesOnly() {
        let now = Date(timeIntervalSince1970: 0)
        let resetsAt = now.addingTimeInterval(45 * 60)
        XCTAssertEqual(ResetDescriber.describe(resetsAt, now: now), "Resets in 45 min")
    }

    func testDescribeHoursAndMinutes() {
        let now = Date(timeIntervalSince1970: 0)
        let resetsAt = now.addingTimeInterval(2 * 3600 + 17 * 60)
        XCTAssertEqual(ResetDescriber.describe(resetsAt, now: now), "Resets in 2 hr 17 min")
    }

    func testDescribeFarFutureUsesWeekdayFormat() {
        let now = Date(timeIntervalSince1970: 0)
        let resetsAt = now.addingTimeInterval(3 * 24 * 3600)
        XCTAssertTrue(ResetDescriber.describe(resetsAt, now: now).hasPrefix("Resets "))
        XCTAssertFalse(ResetDescriber.describe(resetsAt, now: now).contains("hr"))
    }

    func testDescribePastDate() {
        let now = Date(timeIntervalSince1970: 1000)
        let resetsAt = Date(timeIntervalSince1970: 0)
        XCTAssertEqual(ResetDescriber.describe(resetsAt, now: now), "Resetting now")
    }

    func testDescribeNilDate() {
        XCTAssertEqual(ResetDescriber.describe(nil), "")
    }

    func testShortCountdownMinutesOnly() {
        let now = Date(timeIntervalSince1970: 0)
        let resetsAt = now.addingTimeInterval(45 * 60)
        XCTAssertEqual(ResetDescriber.shortCountdown(resetsAt, now: now), "45m")
    }

    func testShortCountdownHoursAndMinutes() {
        let now = Date(timeIntervalSince1970: 0)
        let resetsAt = now.addingTimeInterval(2 * 3600 + 17 * 60)
        XCTAssertEqual(ResetDescriber.shortCountdown(resetsAt, now: now), "2h17m")
    }

    func testShortCountdownDaysForFarFuture()  {
        let now = Date(timeIntervalSince1970: 0)
        let resetsAt = now.addingTimeInterval(3 * 24 * 3600 + 3600)
        XCTAssertEqual(ResetDescriber.shortCountdown(resetsAt, now: now), "3d")
    }

    func testShortCountdownPastDate() {
        let now = Date(timeIntervalSince1970: 1000)
        let resetsAt = Date(timeIntervalSince1970: 0)
        XCTAssertEqual(ResetDescriber.shortCountdown(resetsAt, now: now), "0m")
    }

    func testShortCountdownNilDate() {
        XCTAssertNil(ResetDescriber.shortCountdown(nil))
    }
}
