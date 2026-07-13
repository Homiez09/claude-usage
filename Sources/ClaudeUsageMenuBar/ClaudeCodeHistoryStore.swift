import Foundation

@MainActor
final class ClaudeCodeHistoryStore: ObservableObject {
    @Published private(set) var records: [ClaudeCodeUsageRecord] = []
    @Published private(set) var isLoading = false
    @Published private(set) var lastScanned: Date?
    @Published private(set) var errorMessage: String?

    private let directory: URL
    private var autoRefreshTimer: Timer?

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
        let scanned = await Task.detached(priority: .utility) {
            ClaudeCodeTranscriptScanner.scan(directory: directory)
        }.value

        records = scanned
        lastScanned = Date()
        errorMessage = scanned.isEmpty
            ? "ไม่พบข้อมูลการใช้งาน Claude Code ในเครื่องนี้"
            : nil
    }

    func buckets(for granularity: UsageHistoryGranularity) -> [UsageHistoryBucket] {
        ClaudeCodeUsageAggregator.aggregate(records, by: granularity)
    }
}
