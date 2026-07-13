import Foundation

/// One Claude Code session (one `claude` process/terminal), labeled with its
/// auto-generated title when known.
struct ClaudeCodeSessionStatus: Identifiable, Equatable {
    let id: String
    let displayName: String
    let isActive: Bool
    let lastActivity: Date
}

/// Detects which Claude Code sessions are actively working right now, across
/// every project on this Mac, and drives the menu bar icon's bounce animation
/// while at least one is.
///
/// There's no IPC/status API to query — instead this watches
/// `~/.claude/projects/<project>/<session-id>.jsonl`, which Claude Code
/// appends to on each turn (a tool call, a streamed reply, etc). A single
/// write can be followed by tens of seconds of silence — a slow bash
/// command, a web fetch, or just the model thinking — with no new bytes on
/// disk even though the session is very much still working. An 8s window
/// (this monitor's original value) mistook those pauses for "idle", and made
/// concurrent sessions look like they were never active at the same time
/// (each writes on its own schedule, so a narrow window rarely catches two
/// at once). The window is widened accordingly — see `activeWindow` below.
@MainActor
final class ClaudeCodeActivityMonitor: ObservableObject {
    @Published private(set) var sessions: [ClaudeCodeSessionStatus] = []
    @Published private(set) var isActive = false
    @Published private(set) var animationPhase: Double = 0

    private let directory: URL
    private let activeWindow: TimeInterval
    private var pollTimer: Timer?
    private var animationTimer: Timer?
    private var titleCache: [String: String] = [:]

    init(
        directory: URL = ClaudeCodeTranscriptScanner.projectsDirectory,
        activeWindow: TimeInterval = 45,
        autoStart: Bool = false
    ) {
        self.directory = directory
        self.activeWindow = activeWindow
        if autoStart {
            start()
        }
    }

    deinit {
        pollTimer?.invalidate()
        animationTimer?.invalidate()
    }

    var activeSessions: [ClaudeCodeSessionStatus] {
        sessions.filter { $0.isActive }
    }

    func start() {
        pollTimer?.invalidate()
        Task { await poll() }
        let timer = Timer(timeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.poll() }
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
        stopAnimation()
    }

    private func poll() async {
        let directory = self.directory
        let window = self.activeWindow
        let cachedTitles = self.titleCache
        let result = await Task.detached(priority: .utility) {
            Self.scanSessions(directory: directory, activeWindow: window, cachedTitles: cachedTitles)
        }.value

        titleCache.merge(result.newlyResolvedTitles) { _, new in new }
        sessions = result.sessions
        setActive(result.sessions.contains { $0.isActive })
    }

    private func setActive(_ active: Bool) {
        guard active != isActive else { return }
        isActive = active
        if active {
            startAnimation()
        } else {
            stopAnimation()
            animationPhase = 0
        }
    }

    private func startAnimation() {
        guard animationTimer == nil else { return }
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.animationPhase = (self.animationPhase + 0.1).truncatingRemainder(dividingBy: 2)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        animationTimer = timer
    }

    private func stopAnimation() {
        animationTimer?.invalidate()
        animationTimer = nil
    }

    // MARK: - Pure, testable scanning logic

    struct ScanResult {
        let sessions: [ClaudeCodeSessionStatus]
        let newlyResolvedTitles: [String: String]
    }

    /// Pure, testable check: does any `.jsonl` file under `directory` have a
    /// modification time within `window` seconds of now? Kept for the simple
    /// single-boolean case (and its existing tests); `scanSessions` below is
    /// the full per-session version used in production.
    nonisolated static func isRecentlyModified(directory: URL, within window: TimeInterval, now: Date = Date()) -> Bool {
        scanSessions(directory: directory, activeWindow: window, cachedTitles: [:], now: now)
            .sessions.contains { $0.isActive }
    }

    /// Enumerates every `<session>.jsonl` directly under each project
    /// directory (never the nested `subagents/` transcripts — those aren't
    /// separate user-facing sessions), determines which are active, and
    /// resolves a display name for each newly-seen active session.
    nonisolated static func scanSessions(
        directory: URL,
        activeWindow: TimeInterval,
        cachedTitles: [String: String],
        now: Date = Date()
    ) -> ScanResult {
        let fileManager = FileManager.default
        guard let projectDirs = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey]
        ) else {
            return ScanResult(sessions: [], newlyResolvedTitles: [:])
        }

        let cutoff = now.addingTimeInterval(-activeWindow)
        var sessions: [ClaudeCodeSessionStatus] = []
        var newTitles: [String: String] = [:]

        for projectDir in projectDirs {
            guard (try? projectDir.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else { continue }
            guard let files = try? fileManager.contentsOfDirectory(
                at: projectDir,
                includingPropertiesForKeys: [.contentModificationDateKey]
            ) else { continue }

            for fileURL in files where fileURL.pathExtension == "jsonl" {
                guard let values = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]),
                      let modified = values.contentModificationDate
                else {
                    continue
                }

                let sessionID = fileURL.deletingPathExtension().lastPathComponent
                let isActive = modified > cutoff

                var title = cachedTitles[sessionID]
                if title == nil, isActive, let extracted = extractTitle(from: fileURL) {
                    title = extracted
                    newTitles[sessionID] = extracted
                }

                sessions.append(ClaudeCodeSessionStatus(
                    id: sessionID,
                    displayName: title ?? friendlyProjectName(from: projectDir.lastPathComponent),
                    isActive: isActive,
                    lastActivity: modified
                ))
            }
        }

        sessions.sort { $0.lastActivity > $1.lastActivity }
        return ScanResult(sessions: sessions, newlyResolvedTitles: newTitles)
    }

    /// Reads a session transcript's first `ai-title` entry — the short,
    /// human-readable task description Claude Code auto-generates per
    /// session. Never reads message content otherwise.
    nonisolated static func extractTitle(from fileURL: URL) -> String? {
        guard let contents = try? String(contentsOf: fileURL, encoding: .utf8) else { return nil }
        var result: String?
        contents.enumerateLines { line, stop in
            guard let data = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  obj["type"] as? String == "ai-title",
                  let title = obj["aiTitle"] as? String
            else {
                return
            }
            result = title
            stop = true
        }
        return result
    }

    /// Fallback label when no title has been resolved yet: Claude Code encodes
    /// a session's working directory into its project folder name by
    /// replacing every "/" (and, ambiguously, "_") with "-", so exact
    /// reconstruction isn't possible — this strips the home-directory prefix
    /// and turns the rest into something readable.
    nonisolated static func friendlyProjectName(from encodedDirectoryName: String) -> String {
        var name = encodedDirectoryName
        if name.hasPrefix("-") {
            name.removeFirst()
        }

        let homeEncoded = FileManager.default.homeDirectoryForCurrentUser.path
            .split(separator: "/")
            .joined(separator: "-")
        if name.hasPrefix(homeEncoded) {
            name.removeFirst(homeEncoded.count)
        }
        if name.hasPrefix("-") {
            name.removeFirst()
        }

        guard !name.isEmpty else { return "Unknown project" }
        return name.replacingOccurrences(of: "-", with: " ")
    }
}
