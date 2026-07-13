import XCTest
@testable import ClaudeUsageMenuBar

final class UsageHistoryGranularityQueryKeyTests: XCTestCase {
    func testQueryKeyRoundTrip() {
        for granularity in UsageHistoryGranularity.allCases {
            XCTAssertEqual(UsageHistoryGranularity(queryKey: granularity.queryKey), granularity)
        }
    }

    func testUnknownQueryKeyReturnsNil() {
        XCTAssertNil(UsageHistoryGranularity(queryKey: "bogus"))
    }
}

final class UsageHistorySnapshotTests: XCTestCase {
    func testBuildAndEncodeRoundTrips() throws {
        let buckets = [
            UsageHistoryBucket(periodStart: Date(timeIntervalSince1970: 0), label: "13 Jul 2026", totalCostUSD: 1.23, totalTokens: 456),
        ]
        let snapshot = UsageHistorySnapshotBuilder.build(buckets: buckets, granularity: .day)

        XCTAssertEqual(snapshot.granularity, "day")
        XCTAssertEqual(snapshot.periods.count, 1)
        XCTAssertEqual(snapshot.periods[0].label, "13 Jul 2026")
        XCTAssertEqual(snapshot.periods[0].costUSD, 1.23)
        XCTAssertEqual(snapshot.periods[0].tokens, 456)

        let json = UsageHistorySnapshotBuilder.encodeJSON(snapshot)
        let decoded = try JSONDecoder().decode(UsageHistorySnapshot.self, from: Data(json.utf8))
        XCTAssertEqual(decoded, snapshot)
    }

    func testBuildWithNoBucketsProducesEmptyPeriods() {
        let snapshot = UsageHistorySnapshotBuilder.build(buckets: [], granularity: .month)
        XCTAssertEqual(snapshot.granularity, "month")
        XCTAssertTrue(snapshot.periods.isEmpty)
    }
}

final class LocalWebServerHistoryRouteTests: XCTestCase {
    func testRouteReturnsHistoryJSONWithGranularityFromQuery() {
        var capturedKey: String?
        let result = LocalWebServer.route(
            path: "/api/history?granularity=month",
            snapshotJSON: "unused",
            historyJSON: { key in
                capturedKey = key
                return "{\"granularity\":\"month\"}"
            }
        )
        XCTAssertEqual(capturedKey, "month")
        XCTAssertEqual(result.contentType, "application/json; charset=utf-8")
        XCTAssertEqual(result.body, "{\"granularity\":\"month\"}")
    }

    func testRouteDefaultsHistoryGranularityToDayWithoutQuery() {
        var capturedKey: String?
        _ = LocalWebServer.route(
            path: "/api/history",
            snapshotJSON: "unused",
            historyJSON: { key in
                capturedKey = key
                return "{}"
            }
        )
        XCTAssertEqual(capturedKey, "day")
    }

    func testRouteStillReturnsUsageJSONUnaffected() {
        let result = LocalWebServer.route(path: "/api/usage", snapshotJSON: "{\"hasSessionKey\":true}")
        XCTAssertEqual(result.contentType, "application/json; charset=utf-8")
        XCTAssertEqual(result.body, "{\"hasSessionKey\":true}")
    }
}
