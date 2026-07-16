import Foundation

@MainActor
final class ClaudeCodeHistoryStore: ObservableObject {
    @Published private(set) var records: [ClaudeCodeUsageRecord] = []
    @Published private(set) var isLoading = false
    @Published private(set) var lastScanned: Date?
    @Published private(set) var errorMessage: String?

    private let directory: URL
    private var autoRefreshTimer: Timer?
    private var fileCache: [URL: (modified: Date, records: [ClaudeCodeUsageRecord])] = [:]

    init(directory: URL = ClaudeCodeTranscriptScanner.projectsDirectory) {
        self.directory = directory
    }

    deinit {
        autoRefreshTimer?.invalidate()
    }

    func refreshIfNeeded() async {
        guard lastScanned == nil else { return }
        await refresh()
    }

    /// Keeps history fresh in the background (transcripts change slowly, so a
    /// long interval is fine) — needed so the iPhone page has data to show
    /// even if nobody has opened the History tab on the Mac yet.
    func startAutoRefresh(interval: TimeInterval = 300) {
        autoRefreshTimer?.invalidate()
        Task { await refreshIfNeeded() }
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
        RunLoop.main.add(timer, forMode: .common)
        autoRefreshTimer = timer
    }

    func stopAutoRefresh() {
        autoRefreshTimer?.invalidate()
        autoRefreshTimer = nil
    }

    func refresh() async {
        isLoading = true
        defer { isLoading = false }

        let directory = self.directory
        let existingCache = self.fileCache

        let (updatedCache, allRecords) = await Task.detached(priority: .utility) {
            var cache = existingCache
            let fileManager = FileManager.default
            
            var allRecords: [ClaudeCodeUsageRecord] = []
            var seenMessageIDs = Set<String>()
            
            guard let projectDirs = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else {
                return (cache, allRecords)
            }
            
            func scanFile(_ fileURL: URL) {
                guard let values = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]),
                      let modified = values.contentModificationDate
                else { return }

                let recordsForFile: [ClaudeCodeUsageRecord]
                if let cached = cache[fileURL], cached.modified == modified {
                    recordsForFile = cached.records
                } else {
                    recordsForFile = Self.parseFile(fileURL)
                    cache[fileURL] = (modified, recordsForFile)
                }

                for r in recordsForFile {
                    if seenMessageIDs.insert(r.messageID).inserted {
                        allRecords.append(r)
                    }
                }
            }
            
            for projectDir in projectDirs {
                let isDir = (try? projectDir.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
                if isDir {
                    if let files = try? fileManager.contentsOfDirectory(at: projectDir, includingPropertiesForKeys: [.contentModificationDateKey]) {
                        for fileURL in files where fileURL.pathExtension == "jsonl" {
                            scanFile(fileURL)
                        }
                    }
                } else if projectDir.pathExtension == "jsonl" {
                    scanFile(projectDir)
                }
            }
            // Sort records by date descending
            allRecords.sort { $0.date > $1.date }
            return (cache, allRecords)
        }.value

        self.fileCache = updatedCache
        self.records = allRecords
        lastScanned = Date()
        errorMessage = allRecords.isEmpty
            ? "ไม่พบข้อมูลการใช้งาน Claude Code ในเครื่องนี้"
            : nil
    }

    nonisolated private static func parseFile(_ fileURL: URL) -> [ClaudeCodeUsageRecord] {
        guard let contents = try? String(contentsOf: fileURL, encoding: .utf8) else { return [] }
        let projectName = fileURL.deletingLastPathComponent().lastPathComponent
        var fileRecords: [ClaudeCodeUsageRecord] = []

        contents.enumerateLines { line, _ in
            guard line.contains("\"type\":\"assistant\"") else { return } // Fast pre-filter!
            guard let (_, record) = ClaudeCodeTranscriptScanner.parseLine(line, projectName: projectName) else { return }
            fileRecords.append(record)
        }
        return fileRecords
    }

    func buckets(for granularity: UsageHistoryGranularity) -> [UsageHistoryBucket] {
        ClaudeCodeUsageAggregator.aggregate(records, by: granularity)
    }

    struct ProjectBreakdownItem: Codable, Identifiable {
        var id: String { name }
        let name: String
        let tokens: Int
        let costUSD: Double
    }

    func projectBreakdown() -> [ProjectBreakdownItem] {
        var breakdown: [String: (tokens: Int, cost: Double)] = [:]
        for r in records {
            let entry = breakdown[r.projectName, default: (0, 0.0)]
            breakdown[r.projectName] = (entry.tokens + r.totalTokens, entry.cost + r.estimatedCostUSD)
        }
        return breakdown.map { ProjectBreakdownItem(name: $0.key, tokens: $0.value.tokens, costUSD: $0.value.cost) }
            .sorted { $0.costUSD > $1.costUSD }
    }

    struct ModelBreakdownItem: Codable, Identifiable {
        var id: String { name }
        /// ชื่ออ่านง่ายจาก `ModelDisplayName` เช่น "Sonnet 4.5"
        let name: String
        let tokens: Int
        let costUSD: Double
    }

    /// รวมยอดตามโมเดล — จัดกลุ่มด้วยชื่ออ่านง่าย เพื่อให้ id แบบ snapshot
    /// ("claude-sonnet-5-20260101") กับ alias ("claude-sonnet-5") นับรวมกัน
    func modelBreakdown() -> [ModelBreakdownItem] {
        var breakdown: [String: (tokens: Int, cost: Double)] = [:]
        for r in records {
            let name = ModelDisplayName.display(for: r.model)
            let entry = breakdown[name, default: (0, 0.0)]
            breakdown[name] = (entry.tokens + r.totalTokens, entry.cost + r.estimatedCostUSD)
        }
        return breakdown.map { ModelBreakdownItem(name: $0.key, tokens: $0.value.tokens, costUSD: $0.value.cost) }
            .sorted { $0.costUSD > $1.costUSD }
    }
}
