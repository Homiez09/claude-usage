import XCTest
@testable import ClaudeUsageMenuBar

final class ClaudeCodePricingTests: XCTestCase {
    func testExactModelMatch() {
        let pricing = PricingCatalog.pricing(for: "claude-sonnet-5")
        XCTAssertEqual(pricing?.inputPerMTok, 3.00)
        XCTAssertEqual(pricing?.outputPerMTok, 15.00)
    }

    func testDatedSnapshotFallsBackToAlias() {
        let pricing = PricingCatalog.pricing(for: "claude-sonnet-4-5-20250929")
        XCTAssertEqual(pricing?.inputPerMTok, 3.00)
        XCTAssertEqual(pricing?.outputPerMTok, 15.00)
    }

    func testUnknownModelReturnsNil() {
        XCTAssertNil(PricingCatalog.pricing(for: "gpt-4"))
    }

    func testCacheRatesDeriveFromInputRate() {
        let pricing = PricingCatalog.byModel["claude-opus-4-8"]!
        XCTAssertEqual(pricing.cacheWritePerMTok, 6.25, accuracy: 0.0001)
        XCTAssertEqual(pricing.cacheReadPerMTok, 0.5, accuracy: 0.0001)
    }
}

final class ClaudeCodeUsageRecordTests: XCTestCase {
    func testEstimatedCostCombinesAllTokenTypes() {
        let record = ClaudeCodeUsageRecord(
            date: Date(),
            model: "claude-sonnet-5",
            inputTokens: 1_000_000,
            outputTokens: 1_000_000,
            cacheCreationTokens: 1_000_000,
            cacheReadTokens: 1_000_000
        )
        // input: $3, output: $15, cache write: $3.75, cache read: $0.30
        XCTAssertEqual(record.estimatedCostUSD, 22.05, accuracy: 0.001)
    }

    func testUnknownModelCostsZero() {
        let record = ClaudeCodeUsageRecord(
            date: Date(),
            model: "unknown-model",
            inputTokens: 1_000_000,
            outputTokens: 1_000_000,
            cacheCreationTokens: 0,
            cacheReadTokens: 0
        )
        XCTAssertEqual(record.estimatedCostUSD, 0)
    }

    func testTotalTokensSumsAllFields() {
        let record = ClaudeCodeUsageRecord(
            date: Date(),
            model: "claude-haiku-4-5",
            inputTokens: 10,
            outputTokens: 20,
            cacheCreationTokens: 30,
            cacheReadTokens: 40
        )
        XCTAssertEqual(record.totalTokens, 100)
    }
}

final class ClaudeCodeTranscriptScannerTests: XCTestCase {
    func testParsesValidAssistantLine() throws {
        let line = """
        {"type":"assistant","timestamp":"2026-07-13T05:32:42.298Z","message":{"id":"msg_abc123","model":"claude-sonnet-5","usage":{"input_tokens":100,"output_tokens":50,"cache_creation_input_tokens":10,"cache_read_input_tokens":5}}}
        """
        let parsed = ClaudeCodeTranscriptScanner.parseLine(line)
        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed?.id, "msg_abc123")
        XCTAssertEqual(parsed?.record.model, "claude-sonnet-5")
        XCTAssertEqual(parsed?.record.inputTokens, 100)
        XCTAssertEqual(parsed?.record.outputTokens, 50)
        XCTAssertEqual(parsed?.record.cacheCreationTokens, 10)
        XCTAssertEqual(parsed?.record.cacheReadTokens, 5)
    }

    func testIgnoresNonAssistantLines() {
        let line = """
        {"type":"user","timestamp":"2026-07-13T05:32:42.298Z","message":{"id":"msg_abc123"}}
        """
        XCTAssertNil(ClaudeCodeTranscriptScanner.parseLine(line))
    }

    func testIgnoresSyntheticModel() {
        let line = """
        {"type":"assistant","timestamp":"2026-07-13T05:32:42.298Z","message":{"id":"msg_abc123","model":"<synthetic>","usage":{"input_tokens":1,"output_tokens":1}}}
        """
        XCTAssertNil(ClaudeCodeTranscriptScanner.parseLine(line))
    }

    func testIgnoresMalformedJSON() {
        XCTAssertNil(ClaudeCodeTranscriptScanner.parseLine("not json"))
    }

    func testIgnoresLineMissingUsage() {
        let line = """
        {"type":"assistant","timestamp":"2026-07-13T05:32:42.298Z","message":{"id":"msg_abc123","model":"claude-sonnet-5"}}
        """
        XCTAssertNil(ClaudeCodeTranscriptScanner.parseLine(line))
    }

    func testDeduplicatesByMessageIDAcrossFiles() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("claude-code-scanner-test-\(UUID().uuidString)")
        let projectDir = tempDir.appendingPathComponent("project-a")
        try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let line = """
        {"type":"assistant","timestamp":"2026-07-13T05:32:42.298Z","message":{"id":"msg_dup","model":"claude-sonnet-5","usage":{"input_tokens":100,"output_tokens":50}}}
        """
        try line.write(to: projectDir.appendingPathComponent("session-1.jsonl"), atomically: true, encoding: .utf8)
        try line.write(to: projectDir.appendingPathComponent("session-2.jsonl"), atomically: true, encoding: .utf8)

        let records = ClaudeCodeTranscriptScanner.scan(directory: tempDir)
        XCTAssertEqual(records.count, 1)
    }

    func testScanEmptyDirectoryReturnsEmpty() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("claude-code-scanner-empty-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        XCTAssertTrue(ClaudeCodeTranscriptScanner.scan(directory: tempDir).isEmpty)
    }
}

final class ClaudeCodeUsageAggregatorTests: XCTestCase {
    func testAggregatesByDay() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!

        let day1 = calendar.date(from: DateComponents(year: 2026, month: 7, day: 13, hour: 9))!
        let day1Later = calendar.date(from: DateComponents(year: 2026, month: 7, day: 13, hour: 18))!
        let day2 = calendar.date(from: DateComponents(year: 2026, month: 7, day: 14, hour: 9))!

        let records = [
            ClaudeCodeUsageRecord(date: day1, model: "claude-haiku-4-5", inputTokens: 1_000_000, outputTokens: 0, cacheCreationTokens: 0, cacheReadTokens: 0),
            ClaudeCodeUsageRecord(date: day1Later, model: "claude-haiku-4-5", inputTokens: 1_000_000, outputTokens: 0, cacheCreationTokens: 0, cacheReadTokens: 0),
            ClaudeCodeUsageRecord(date: day2, model: "claude-haiku-4-5", inputTokens: 1_000_000, outputTokens: 0, cacheCreationTokens: 0, cacheReadTokens: 0),
        ]

        let buckets = ClaudeCodeUsageAggregator.aggregate(records, by: .day, calendar: calendar)

        XCTAssertEqual(buckets.count, 2)
        XCTAssertEqual(buckets[0].periodStart, calendar.startOfDay(for: day2))
        XCTAssertEqual(buckets[0].totalCostUSD, 1.00, accuracy: 0.0001)
        XCTAssertEqual(buckets[1].periodStart, calendar.startOfDay(for: day1))
        XCTAssertEqual(buckets[1].totalCostUSD, 2.00, accuracy: 0.0001)
    }

    func testAggregatesByMonthAndYear() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!

        let januaryDate = calendar.date(from: DateComponents(year: 2026, month: 1, day: 5))!
        let julyDate = calendar.date(from: DateComponents(year: 2026, month: 7, day: 5))!

        let records = [
            ClaudeCodeUsageRecord(date: januaryDate, model: "claude-haiku-4-5", inputTokens: 0, outputTokens: 1_000_000, cacheCreationTokens: 0, cacheReadTokens: 0),
            ClaudeCodeUsageRecord(date: julyDate, model: "claude-haiku-4-5", inputTokens: 0, outputTokens: 1_000_000, cacheCreationTokens: 0, cacheReadTokens: 0),
        ]

        let monthlyBuckets = ClaudeCodeUsageAggregator.aggregate(records, by: .month, calendar: calendar)
        XCTAssertEqual(monthlyBuckets.count, 2)

        let yearlyBuckets = ClaudeCodeUsageAggregator.aggregate(records, by: .year, calendar: calendar)
        XCTAssertEqual(yearlyBuckets.count, 1)
        XCTAssertEqual(yearlyBuckets[0].totalCostUSD, 10.00, accuracy: 0.0001)
    }

    func testEmptyRecordsProducesNoBuckets() {
        XCTAssertTrue(ClaudeCodeUsageAggregator.aggregate([], by: .day).isEmpty)
    }
}

@MainActor
final class ClaudeCodeHistoryStoreTests: XCTestCase {
    func testRefreshPopulatesRecordsFromIsolatedDirectory() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("claude-code-store-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let line = """
        {"type":"assistant","timestamp":"2026-07-13T05:32:42.298Z","message":{"id":"msg_store_test","model":"claude-sonnet-5","usage":{"input_tokens":1000000,"output_tokens":0}}}
        """
        try line.write(to: tempDir.appendingPathComponent("session.jsonl"), atomically: true, encoding: .utf8)

        let store = ClaudeCodeHistoryStore(directory: tempDir)
        XCTAssertNil(store.lastScanned)

        await store.refresh()

        XCTAssertNotNil(store.lastScanned)
        XCTAssertNil(store.errorMessage)
        XCTAssertEqual(store.buckets(for: .day).count, 1)
        XCTAssertEqual(store.buckets(for: .day)[0].totalCostUSD, 3.00, accuracy: 0.0001)
    }

    func testRefreshOnEmptyDirectorySetsErrorMessage() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("claude-code-store-empty-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = ClaudeCodeHistoryStore(directory: tempDir)
        await store.refresh()

        XCTAssertNotNil(store.errorMessage)
        XCTAssertTrue(store.buckets(for: .day).isEmpty)
    }
}
