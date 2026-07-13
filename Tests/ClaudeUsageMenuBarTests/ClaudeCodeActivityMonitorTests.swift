import XCTest
@testable import ClaudeUsageMenuBar

final class ClaudeCodeActivityMonitorStaticTests: XCTestCase {
    private func makeTempDirectory() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("claude-code-activity-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Mimics `~/.claude/projects/<project>/<session>.jsonl` — a projects root
    /// containing one directory per project, each holding session transcripts.
    private func makeProjectFile(
        in projectsRoot: URL,
        project: String,
        sessionID: String,
        content: String = "{}"
    ) throws -> URL {
        let projectDir = projectsRoot.appendingPathComponent(project)
        try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)
        let fileURL = projectDir.appendingPathComponent("\(sessionID).jsonl")
        try content.write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    }

    func testDetectsRecentlyModifiedTranscript() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        _ = try makeProjectFile(in: dir, project: "-Users-me-project", sessionID: "session-1")

        XCTAssertTrue(
            ClaudeCodeActivityMonitor.isRecentlyModified(directory: dir, within: 8, now: Date())
        )
    }

    func testIgnoresStaleTranscript() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        _ = try makeProjectFile(in: dir, project: "-Users-me-project", sessionID: "session-1")

        // Simulate checking long after the file was last touched.
        let farFuture = Date().addingTimeInterval(60)
        XCTAssertFalse(
            ClaudeCodeActivityMonitor.isRecentlyModified(directory: dir, within: 8, now: farFuture)
        )
    }

    func testIgnoresNonJSONLFiles() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let projectDir = dir.appendingPathComponent("-Users-me-project")
        try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)
        try "not a transcript".write(
            to: projectDir.appendingPathComponent("notes.txt"),
            atomically: true,
            encoding: .utf8
        )

        XCTAssertFalse(
            ClaudeCodeActivityMonitor.isRecentlyModified(directory: dir, within: 8, now: Date())
        )
    }

    func testEmptyDirectoryIsNotActive() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        XCTAssertFalse(
            ClaudeCodeActivityMonitor.isRecentlyModified(directory: dir, within: 8, now: Date())
        )
    }

    func testScanSessionsLabelsActiveSessionByTitle() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let transcript = """
        {"type":"user","message":{"id":"msg_0"}}
        {"type":"ai-title","aiTitle":"Fix the login bug","sessionId":"session-1"}
        """
        _ = try makeProjectFile(in: dir, project: "-Users-me-project", sessionID: "session-1", content: transcript)

        let result = ClaudeCodeActivityMonitor.scanSessions(
            directory: dir,
            activeWindow: 8,
            cachedTitles: [:],
            now: Date()
        )

        XCTAssertEqual(result.sessions.count, 1)
        XCTAssertTrue(result.sessions[0].isActive)
        XCTAssertEqual(result.sessions[0].displayName, "Fix the login bug")
        XCTAssertEqual(result.newlyResolvedTitles["session-1"], "Fix the login bug")
    }

    func testScanSessionsFallsBackToProjectNameWhenNoTitle() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        _ = try makeProjectFile(in: dir, project: "-tmp-my-project", sessionID: "session-1")

        let result = ClaudeCodeActivityMonitor.scanSessions(
            directory: dir,
            activeWindow: 8,
            cachedTitles: [:],
            now: Date()
        )

        XCTAssertEqual(result.sessions.count, 1)
        XCTAssertEqual(result.sessions[0].displayName, "tmp my project")
        XCTAssertTrue(result.newlyResolvedTitles.isEmpty)
    }

    func testScanSessionsDoesNotResolveTitleForInactiveSessions() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let transcript = """
        {"type":"ai-title","aiTitle":"Should not be read","sessionId":"session-1"}
        """
        _ = try makeProjectFile(in: dir, project: "-Users-me-project", sessionID: "session-1", content: transcript)

        // "now" far in the future makes the file look stale/inactive.
        let farFuture = Date().addingTimeInterval(60)
        let result = ClaudeCodeActivityMonitor.scanSessions(
            directory: dir,
            activeWindow: 8,
            cachedTitles: [:],
            now: farFuture
        )

        XCTAssertEqual(result.sessions.count, 1)
        XCTAssertFalse(result.sessions[0].isActive)
        XCTAssertTrue(result.newlyResolvedTitles.isEmpty)
    }

    func testScanSessionsUsesCachedTitleWithoutRereading() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        _ = try makeProjectFile(in: dir, project: "-Users-me-project", sessionID: "session-1", content: "{}")

        let result = ClaudeCodeActivityMonitor.scanSessions(
            directory: dir,
            activeWindow: 8,
            cachedTitles: ["session-1": "Cached title"],
            now: Date()
        )

        XCTAssertEqual(result.sessions[0].displayName, "Cached title")
        XCTAssertTrue(result.newlyResolvedTitles.isEmpty)
    }

    func testScanSessionsAcrossMultipleProjects() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        _ = try makeProjectFile(in: dir, project: "-Users-me-project-a", sessionID: "session-a")
        _ = try makeProjectFile(in: dir, project: "-Users-me-project-b", sessionID: "session-b")

        let result = ClaudeCodeActivityMonitor.scanSessions(
            directory: dir,
            activeWindow: 8,
            cachedTitles: [:],
            now: Date()
        )

        XCTAssertEqual(result.sessions.count, 2)
        XCTAssertTrue(result.sessions.allSatisfy(\.isActive))
    }

    func testExtractTitleReturnsNilWhenAbsent() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let fileURL = dir.appendingPathComponent("session.jsonl")
        try """
        {"type":"user","message":{"id":"msg_0"}}
        """.write(to: fileURL, atomically: true, encoding: .utf8)

        XCTAssertNil(ClaudeCodeActivityMonitor.extractTitle(from: fileURL))
    }

    func testFriendlyProjectNameStripsHomePrefixAndDash() {
        let name = ClaudeCodeActivityMonitor.friendlyProjectName(from: "-tmp-some-project")
        XCTAssertEqual(name, "tmp some project")
    }
}

@MainActor
final class ClaudeCodeActivityMonitorInstanceTests: XCTestCase {
    func testStartsInactiveWithoutAutoStart() {
        let monitor = ClaudeCodeActivityMonitor(
            directory: FileManager.default.temporaryDirectory,
            autoStart: false
        )
        XCTAssertFalse(monitor.isActive)
        XCTAssertEqual(monitor.animationPhase, 0)
        XCTAssertTrue(monitor.sessions.isEmpty)
        XCTAssertTrue(monitor.activeSessions.isEmpty)
    }
}
