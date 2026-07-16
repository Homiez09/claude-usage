import XCTest
@testable import ClaudeUsageMenuBar

final class ModelBreakdownTests: XCTestCase {
    private func makeTempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @MainActor
    func testModelBreakdownGroupsBySnapshotAndAlias() async throws {
        let tempDir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let projectDir = tempDir.appendingPathComponent("proj")
        try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)

        let lines = """
        {"type":"assistant","timestamp":"2026-07-13T05:00:00.000Z","message":{"id":"msg_1","model":"claude-sonnet-5","usage":{"input_tokens":100,"output_tokens":50}}}
        {"type":"assistant","timestamp":"2026-07-13T05:01:00.000Z","message":{"id":"msg_2","model":"claude-sonnet-5-20250929","usage":{"input_tokens":100,"output_tokens":50}}}
        {"type":"assistant","timestamp":"2026-07-13T05:02:00.000Z","message":{"id":"msg_3","model":"claude-haiku-4-5","usage":{"input_tokens":100,"output_tokens":50}}}
        """
        try lines.write(to: projectDir.appendingPathComponent("session.jsonl"), atomically: true, encoding: .utf8)

        let store = ClaudeCodeHistoryStore(directory: tempDir)
        await store.refresh()

        let breakdown = store.modelBreakdown()
        let sonnetEntry = breakdown.first { $0.name == "Sonnet 5" }
        let haikuEntry = breakdown.first { $0.name == "Haiku 4.5" }

        XCTAssertEqual(sonnetEntry?.tokens, 300) // two records combined (snapshot + alias grouped together)
        XCTAssertEqual(haikuEntry?.tokens, 150)
        XCTAssertEqual(breakdown.count, 2)
    }

    @MainActor
    func testModelBreakdownEmptyWhenNoRecords() async throws {
        let tempDir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let store = ClaudeCodeHistoryStore(directory: tempDir)
        await store.refresh()
        XCTAssertTrue(store.modelBreakdown().isEmpty)
    }

    @MainActor
    func testModelBreakdownSortedByCostDescending() async throws {
        let tempDir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let projectDir = tempDir.appendingPathComponent("proj")
        try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)

        // Opus (higher per-token rate) with fewer tokens should still cost more than Haiku with more tokens.
        let lines = """
        {"type":"assistant","timestamp":"2026-07-13T05:00:00.000Z","message":{"id":"msg_1","model":"claude-haiku-4-5","usage":{"input_tokens":1000000,"output_tokens":0}}}
        {"type":"assistant","timestamp":"2026-07-13T05:01:00.000Z","message":{"id":"msg_2","model":"claude-opus-4-8","usage":{"input_tokens":1000000,"output_tokens":0}}}
        """
        try lines.write(to: projectDir.appendingPathComponent("session.jsonl"), atomically: true, encoding: .utf8)

        let store = ClaudeCodeHistoryStore(directory: tempDir)
        await store.refresh()

        let breakdown = store.modelBreakdown()
        XCTAssertEqual(breakdown.first?.name, "Opus 4.8")
    }
}
