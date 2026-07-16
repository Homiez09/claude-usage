import XCTest
@testable import ClaudeUsageMenuBar

final class BurnRateEstimatorTests: XCTestCase {
    func testReturnsNilWithFewerThanTwoSamples() {
        XCTAssertNil(BurnRateEstimator.ratePerHour(samples: []))
        XCTAssertNil(BurnRateEstimator.ratePerHour(samples: [BurnRateSample(time: Date(), percent: 10)]))
    }

    func testReturnsNilWhenSpanTooShort() {
        let now = Date()
        let samples = [
            BurnRateSample(time: now, percent: 10),
            BurnRateSample(time: now.addingTimeInterval(60), percent: 12),
        ]
        XCTAssertNil(BurnRateEstimator.ratePerHour(samples: samples))
    }

    func testReturnsNilWhenPercentDidNotClimb() {
        let now = Date()
        let samples = [
            BurnRateSample(time: now, percent: 20),
            BurnRateSample(time: now.addingTimeInterval(600), percent: 20),
        ]
        XCTAssertNil(BurnRateEstimator.ratePerHour(samples: samples))
    }

    func testComputesRatePerHourFromFirstAndLastSample() throws {
        let now = Date()
        let samples = [
            BurnRateSample(time: now, percent: 10),
            BurnRateSample(time: now.addingTimeInterval(1800), percent: 20), // 30 min, +10%
        ]
        let rate = try XCTUnwrap(BurnRateEstimator.ratePerHour(samples: samples))
        XCTAssertEqual(rate, 20.0, accuracy: 0.01) // 10% per 30min => 20%/hr
    }

    func testProjectedFullDateExtrapolatesToHundredPercent() throws {
        let now = Date()
        let samples = [
            BurnRateSample(time: now, percent: 0),
            BurnRateSample(time: now.addingTimeInterval(3600), percent: 50), // 50%/hr
        ]
        let projected = try XCTUnwrap(BurnRateEstimator.projectedFullDate(samples: samples))
        // Remaining 50% at 50%/hr => 1 more hour from last sample
        XCTAssertEqual(projected.timeIntervalSince(now.addingTimeInterval(3600)), 3600, accuracy: 1)
    }

    func testProjectedFullDateReturnsLastTimeWhenAlreadyAtHundred() throws {
        let now = Date()
        let samples = [
            BurnRateSample(time: now, percent: 50),
            BurnRateSample(time: now.addingTimeInterval(1800), percent: 100),
        ]
        let projected = try XCTUnwrap(BurnRateEstimator.projectedFullDate(samples: samples))
        XCTAssertEqual(projected, samples.last?.time)
    }

    func testProjectedFullDateNilWhenRateUnavailable() {
        XCTAssertNil(BurnRateEstimator.projectedFullDate(samples: []))
    }
}
