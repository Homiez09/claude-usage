import Foundation
import CoreServices

/// One Claude Code session (one `claude` process/terminal), labeled with its
/// auto-generated title when known.
struct ClaudeCodeSessionStatus: Identifiable, Equatable {
    let id: String
    let displayName: String
    let isActive: Bool
    let lastActivity: Date
    let model: String?
    let totalTokens: Int
}

/// Detects which Claude Code sessions are actively working right now, across
/// every project on this Mac, and drives the menu bar icon's bounce animation
/// while at least one is.
@MainActor
final class ClaudeCodeActivityMonitor: ObservableObject {
    @Published private(set) var sessions: [ClaudeCodeSessionStatus] = []
    @Published private(set) var isActive = false
    @Published private(set) var animationPhase: Double = 0

    private let directory: URL
    private let activeWindow: TimeInterval
    private var pollTimer: Timer?
    private var animationTimer: Timer?
    private var streamRef: FSEventStreamRef?
    private var titleCache: [String: String] = [:]
    
    private var lastPollTime = Date.distantPast
    private var pendingPollTask: Task<Void, Never>?

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

                let info = parseSessionFile(fileURL: fileURL)

                sessions.append(ClaudeCodeSessionStatus(
                    id: sessionID,
                    displayName: title ?? friendlyProjectName(from: projectDir.lastPathComponent),
                    isActive: isActive,
                    lastActivity: modified,
                    model: cleanModelName(info.model),
                    totalTokens: info.totalTokens
                ))
            }
        }

        sessions.sort { $0.lastActivity > $1.lastActivity }
        return ScanResult(sessions: sessions, newlyResolvedTitles: newTitles)
    }

    struct SessionTranscriptInfo {
        let model: String?
        let totalTokens: Int
    }

    nonisolated static func parseSessionFile(fileURL: URL) -> SessionTranscriptInfo {
        guard let contents = try? String(contentsOf: fileURL, encoding: .utf8) else {
            return SessionTranscriptInfo(model: nil, totalTokens: 0)
        }
        var model: String?
        var total = 0
        var seenMessageIDs = Set<String>()
        
        contents.enumerateLines { line, _ in
            guard line.contains("\"type\":\"assistant\"") else { return } // Fast pre-filter!
            guard let data = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { return }
            
            if obj["type"] as? String == "assistant",
               let message = obj["message"] as? [String: Any],
               let messageID = message["id"] as? String,
               let usage = message["usage"] as? [String: Any] {
                
                guard seenMessageIDs.insert(messageID).inserted else { return }
                
                let input = usage["input_tokens"] as? Int ?? 0
                let output = usage["output_tokens"] as? Int ?? 0
                let cacheWrite = usage["cache_creation_input_tokens"] as? Int ?? 0
                let cacheRead = usage["cache_read_input_tokens"] as? Int ?? 0
                let turnTotal = input + output + cacheWrite + cacheRead
                
                total += turnTotal
                
                if let modelStr = message["model"] as? String, modelStr != "<synthetic>" {
                    model = modelStr
                }
            }
        }
        return SessionTranscriptInfo(model: model, totalTokens: total)
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
