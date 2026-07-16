import Foundation
import CoreServices

/// One Claude Code session (one `claude` process/terminal, or one subagent
/// spawned by a session), labeled with its auto-generated title when known.
struct ClaudeCodeSessionStatus: Identifiable, Equatable {
    let id: String
    let displayName: String
    let isActive: Bool
    let lastActivity: Date
    let model: String?
    /// `true` for a subagent transcript (`<session>/subagents/agent-*.jsonl`),
    /// `false` for a top-level user-facing session.
    let isSubagent: Bool
    /// The subagent's type (e.g. "general-purpose"), from its `.meta.json`
    /// sidecar. Always `nil` for top-level sessions.
    let subagentType: String?
}

/// Detects which Claude Code sessions are actively working right now, across
/// every project on this Mac, and drives the menu bar icon's bounce animation
/// while at least one is.
@MainActor
final class ClaudeCodeActivityMonitor: ObservableObject {
    @Published private(set) var sessions: [ClaudeCodeSessionStatus] = []
    @Published private(set) var isActive = false
    @Published private(set) var animationPhase: Double = 0

    /// เรียกบน MainActor เมื่อ session ที่ทำงานต่อเนื่องนานพอเพิ่งกลายเป็น idle
    /// (ตามเกณฑ์ของ `SessionEndPlanner`) — `UsageStore` ใช้ต่อยอดเป็น notification
    var onSessionsEnded: (([SessionEndPlanner.EndedSession]) -> Void)?

    private let directory: URL
    private let activeWindow: TimeInterval
    private var pollTimer: Timer?
    private var animationTimer: Timer?
    private var streamRef: FSEventStreamRef?
    private var titleCache: [String: String] = [:]
    
    private var lastPollTime = Date.distantPast
    private var pendingPollTask: Task<Void, Never>?
    /// สถานะของ `SessionEndPlanner`: session ไหนเริ่ม active ตั้งแต่เมื่อไหร่
    private var activeSince: [String: Date] = [:]

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
        pendingPollTask?.cancel()
        if let streamRef = streamRef {
            FSEventStreamStop(streamRef)
            FSEventStreamInvalidate(streamRef)
            FSEventStreamRelease(streamRef)
        }
    }

    var activeSessions: [ClaudeCodeSessionStatus] {
        sessions.filter { $0.isActive }
    }

    func start() {
        pollTimer?.invalidate()
        stopWatcher()
        
        startWatcher()
        
        // Slow fallback timer (every 15 seconds) to guarantee robustness
        let timer = Timer(timeInterval: 15.0, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.poll() }
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
        
        Task { await poll() }
    }

    func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
        pendingPollTask?.cancel()
        pendingPollTask = nil
        stopWatcher()
        stopAnimation()
    }

    private func scheduleThrottlePoll() {
        guard pendingPollTask == nil else { return }
        
        let now = Date()
        let timeSinceLast = now.timeIntervalSince(lastPollTime)
        let delay = max(0.0, 1.2 - timeSinceLast)
        
        pendingPollTask = Task {
            if delay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
            guard !Task.isCancelled else { return }
            await self.poll()
            self.pendingPollTask = nil
        }
    }

    private func startWatcher() {
        let path = directory.path
        let pathsToWatch = [path] as CFArray
        
        var context = FSEventStreamContext(
            version: 0,
            info: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        
        let callback: FSEventStreamCallback = { (
            streamRef,
            clientCallBackInfo,
            numEvents,
            eventPaths,
            eventFlags,
            eventIds
        ) in
            guard let clientCallBackInfo = clientCallBackInfo else { return }
            let monitor = Unmanaged<ClaudeCodeActivityMonitor>.fromOpaque(clientCallBackInfo).takeUnretainedValue()
            Task { @MainActor in
                monitor.scheduleThrottlePoll()
            }
        }
        
        streamRef = FSEventStreamCreate(
            kCFAllocatorDefault,
            callback,
            &context,
            pathsToWatch,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            1.2, // Latency: 1.2s (Coalesce events inside macOS system level)
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer)
        )
        
        if let streamRef = streamRef {
            FSEventStreamSetDispatchQueue(streamRef, DispatchQueue.main)
            FSEventStreamStart(streamRef)
        }
    }

    private func stopWatcher() {
        if let streamRef = streamRef {
            FSEventStreamStop(streamRef)
            FSEventStreamInvalidate(streamRef)
            FSEventStreamRelease(streamRef)
            self.streamRef = nil
        }
    }

    private func poll() async {
        lastPollTime = Date()
        let directory = self.directory
        let window = self.activeWindow
        let cachedTitles = self.titleCache
        let result = await Task.detached(priority: .utility) {
            Self.scanSessions(directory: directory, activeWindow: window, cachedTitles: cachedTitles)
        }.value

        titleCache.merge(result.newlyResolvedTitles) { _, new in new }
        sessions = result.sessions
        setActive(result.sessions.contains { $0.isActive })

        let endPlan = SessionEndPlanner.plan(activeSince: activeSince, sessions: result.sessions)
        activeSince = endPlan.newActiveSince
        if !endPlan.ended.isEmpty {
            onSessionsEnded?(endPlan.ended)
        }
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
        let timer = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.animationPhase = (self.animationPhase + 0.2).truncatingRemainder(dividingBy: 2)
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
    /// directory, plus every subagent transcript nested at
    /// `<session>/subagents/agent-*.jsonl`, determines which are active, and
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

                // Full-content parse is only worth paying for on sessions that
                // are actually active right now — historical/idle transcripts
                // (the vast majority, once `~/.claude/projects` accumulates
                // weeks of history) never have their model shown anywhere, so
                // re-reading and re-parsing their entire file on every poll
                // was pure waste (and the biggest source of this monitor's
                // memory/CPU footprint).
                let info = isActive ? parseSessionFile(fileURL: fileURL) : SessionTranscriptInfo(model: nil)

                sessions.append(ClaudeCodeSessionStatus(
                    id: sessionID,
                    displayName: title ?? friendlyProjectName(from: projectDir.lastPathComponent),
                    isActive: isActive,
                    lastActivity: modified,
                    model: cleanModelName(info.model),
                    isSubagent: false,
                    subagentType: nil
                ))
            }

            for entryURL in files {
                guard (try? entryURL.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else { continue }
                sessions.append(contentsOf: scanSubagentSessions(sessionDir: entryURL, cutoff: cutoff))
            }
        }

        sessions.sort { $0.lastActivity > $1.lastActivity }
        return ScanResult(sessions: sessions, newlyResolvedTitles: newTitles)
    }

    /// Scans `<sessionDir>/subagents/agent-*.jsonl` for one session directory,
    /// pairing each transcript with its `.meta.json` sidecar (`agentType`,
    /// `description`) to produce a human-readable label.
    nonisolated static func scanSubagentSessions(sessionDir: URL, cutoff: Date) -> [ClaudeCodeSessionStatus] {
        let fileManager = FileManager.default
        let subagentsDir = sessionDir.appendingPathComponent("subagents")
        guard let files = try? fileManager.contentsOfDirectory(
            at: subagentsDir,
            includingPropertiesForKeys: [.contentModificationDateKey]
        ) else {
            return []
        }

        var result: [ClaudeCodeSessionStatus] = []
        for fileURL in files where fileURL.pathExtension == "jsonl" {
            guard let values = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]),
                  let modified = values.contentModificationDate
            else {
                continue
            }

            let isActive = modified > cutoff
            let baseName = fileURL.deletingPathExtension().lastPathComponent
            let meta = readSubagentMeta(baseName: baseName, in: subagentsDir)
            // Same active-only gating as the top-level loop above — a subagent
            // transcript stays on disk forever after it finishes, so without
            // this every historical subagent run would get fully re-read and
            // re-parsed on every poll too.
            let info = isActive ? parseSessionFile(fileURL: fileURL) : SessionTranscriptInfo(model: nil)

            result.append(ClaudeCodeSessionStatus(
                id: "\(sessionDir.lastPathComponent)/\(baseName)",
                displayName: subagentDisplayName(agentType: meta.agentType, description: meta.description),
                isActive: isActive,
                lastActivity: modified,
                model: cleanModelName(info.model),
                isSubagent: true,
                subagentType: meta.agentType
            ))
        }
        return result
    }

    struct SubagentMeta: Decodable {
        let agentType: String?
        let description: String?
    }

    /// Reads `<baseName>.meta.json` next to a subagent transcript — written
    /// once when the subagent is spawned, so no caching/staleness concerns.
    nonisolated static func readSubagentMeta(baseName: String, in directory: URL) -> SubagentMeta {
        let metaURL = directory.appendingPathComponent("\(baseName).meta.json")
        guard let data = try? Data(contentsOf: metaURL),
              let meta = try? JSONDecoder().decode(SubagentMeta.self, from: data)
        else {
            return SubagentMeta(agentType: nil, description: nil)
        }
        return meta
    }

    nonisolated static func subagentDisplayName(agentType: String?, description: String?) -> String {
        if let description, !description.isEmpty { return description }
        if let agentType, !agentType.isEmpty { return agentType }
        return "Subagent"
    }

    struct SessionTranscriptInfo {
        let model: String?
    }

    /// Full-content read of one transcript, kept only to find the most recent
    /// model in use — callers must gate this to active sessions (see
    /// `scanSessions`/`scanSubagentSessions`) since it loads the whole file.
    nonisolated static func parseSessionFile(fileURL: URL) -> SessionTranscriptInfo {
        guard let contents = try? String(contentsOf: fileURL, encoding: .utf8) else {
            return SessionTranscriptInfo(model: nil)
        }
        var model: String?

        contents.enumerateLines { line, _ in
            guard line.contains("\"type\":\"assistant\"") else { return } // Fast pre-filter!
            guard let data = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  obj["type"] as? String == "assistant",
                  let message = obj["message"] as? [String: Any],
                  let modelStr = message["model"] as? String,
                  modelStr != "<synthetic>"
            else { return }
            model = modelStr
        }
        return SessionTranscriptInfo(model: model)
    }

    nonisolated static func cleanModelName(_ model: String?) -> String? {
        return model
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
