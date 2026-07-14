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

    func testScanSessionsResolvesModelForActiveSession() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let transcript = """
        {"type":"assistant","message":{"id":"msg_0","model":"claude-sonnet-5","usage":{}}}
        """
        _ = try makeProjectFile(in: dir, project: "-Users-me-project", sessionID: "session-1", content: transcript)

        let result = ClaudeCodeActivityMonitor.scanSessions(
            directory: dir,
            activeWindow: 8,
            cachedTitles: [:],
            now: Date()
        )

        XCTAssertTrue(result.sessions[0].isActive)
        XCTAssertEqual(result.sessions[0].model, "claude-sonnet-5")
    }

    /// Guards the perf fix: re-reading and re-parsing every historical
    /// transcript's full content on every poll (to resolve a `model` that's
    /// never shown for inactive sessions anyway) was the app's main memory/CPU
    /// cost, so inactive sessions must never pay for `parseSessionFile`.
    func testScanSessionsDoesNotResolveModelForInactiveSession() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let transcript = """
        {"type":"assistant","message":{"id":"msg_0","model":"claude-sonnet-5","usage":{}}}
        """
        _ = try makeProjectFile(in: dir, project: "-Users-me-project", sessionID: "session-1", content: transcript)

        let farFuture = Date().addingTimeInterval(60)
        let result = ClaudeCodeActivityMonitor.scanSessions(
            directory: dir,
            activeWindow: 8,
            cachedTitles: [:],
            now: farFuture
        )

        XCTAssertFalse(result.sessions[0].isActive)
        XCTAssertNil(result.sessions[0].model)
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

    func testScanSessionsIncludesActiveSubagentLabeledFromMeta() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let sessionID = "session-1"
        _ = try makeProjectFile(in: dir, project: "-Users-me-project", sessionID: sessionID)

        let subagentsDir = dir
            .appendingPathComponent("-Users-me-project")
            .appendingPathComponent(sessionID)
            .appendingPathComponent("subagents")
        try FileManager.default.createDirectory(at: subagentsDir, withIntermediateDirectories: true)
        try "{}".write(to: subagentsDir.appendingPathComponent("agent-abc123.jsonl"), atomically: true, encoding: .utf8)
        try #"{"agentType":"general-purpose","description":"Log work to brain"}"#.write(
            to: subagentsDir.appendingPathComponent("agent-abc123.meta.json"),
            atomically: true,
            encoding: .utf8
        )

        let result = ClaudeCodeActivityMonitor.scanSessions(
            directory: dir,
            activeWindow: 8,
            cachedTitles: [:],
            now: Date()
        )

        XCTAssertEqual(result.sessions.count, 2)
        let subagent = try XCTUnwrap(result.sessions.first { $0.isSubagent })
        XCTAssertTrue(subagent.isActive)
        XCTAssertEqual(subagent.displayName, "Log work to brain")
        XCTAssertEqual(subagent.subagentType, "general-purpose")

        let mainSession = try XCTUnwrap(result.sessions.first { !$0.isSubagent })
        XCTAssertNil(mainSession.subagentType)
    }

    func testScanSessionsIgnoresStaleSubagent() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let sessionID = "session-1"
        _ = try makeProjectFile(in: dir, project: "-Users-me-project", sessionID: sessionID)

        let subagentsDir = dir
            .appendingPathComponent("-Users-me-project")
            .appendingPathComponent(sessionID)
            .appendingPathComponent("subagents")
        try FileManager.default.createDirectory(at: subagentsDir, withIntermediateDirectories: true)
        try "{}".write(to: subagentsDir.appendingPathComponent("agent-abc123.jsonl"), atomically: true, encoding: .utf8)

        let farFuture = Date().addingTimeInterval(60)
        let result = ClaudeCodeActivityMonitor.scanSessions(
            directory: dir,
            activeWindow: 8,
            cachedTitles: [:],
            now: farFuture
        )

        let subagent = try XCTUnwrap(result.sessions.first { $0.isSubagent })
        XCTAssertFalse(subagent.isActive)
    }

    func testSubagentDisplayNamePrefersDescriptionThenAgentTypeThenDefault() {
        XCTAssertEqual(
            ClaudeCodeActivityMonitor.subagentDisplayName(agentType: "general-purpose", description: "Do the thing"),
            "Do the thing"
        )
        XCTAssertEqual(
            ClaudeCodeActivityMonitor.subagentDisplayName(agentType: "general-purpose", description: nil),
            "general-purpose"
        )
        XCTAssertEqual(
            ClaudeCodeActivityMonitor.subagentDisplayName(agentType: nil, description: nil),
            "Subagent"
        )
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
