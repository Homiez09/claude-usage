import Foundation

@MainActor
final class UsageStore: ObservableObject {
    @Published var usage: UsageResponse?
    @Published var lastUpdated: Date?
    @Published var errorMessage: String?
    @Published var isLoading = false

    let activityMonitor: ClaudeCodeActivityMonitor
    let historyStore: ClaudeCodeHistoryStore

    @Published var barWidth: Double {
        didSet { UserDefaults.standard.set(barWidth, forKey: "PrefBarWidth") }
    }
    @Published var showSessionBar: Bool {
        didSet { UserDefaults.standard.set(showSessionBar, forKey: "PrefShowSessionBar") }
    }
    @Published var showWeeklyBar: Bool {
        didSet { UserDefaults.standard.set(showWeeklyBar, forKey: "PrefShowWeeklyBar") }
    }

    private let service: ClaudeUsageService
    private let keychain: KeychainHelper
    private var timer: Timer?
    private let refreshInterval: TimeInterval
    private var webServer: LocalWebServer?

    init(
        service: ClaudeUsageService = ClaudeUsageService(),
        keychain: KeychainHelper = .shared,
        refreshInterval: TimeInterval = 60,
        autoStart: Bool = true,
        enableLocalWebServer: Bool = false,
        activityMonitor: ClaudeCodeActivityMonitor? = nil,
        historyStore: ClaudeCodeHistoryStore? = nil
    ) {
        self.service = service
        self.keychain = keychain
        self.refreshInterval = refreshInterval

        let savedBarWidth = UserDefaults.standard.double(forKey: "PrefBarWidth")
        self.barWidth = savedBarWidth == 0 ? 26.0 : savedBarWidth
        self.showSessionBar = UserDefaults.standard.object(forKey: "PrefShowSessionBar") == nil ? true : UserDefaults.standard.bool(forKey: "PrefShowSessionBar")
        self.showWeeklyBar = UserDefaults.standard.object(forKey: "PrefShowWeeklyBar") == nil ? true : UserDefaults.standard.bool(forKey: "PrefShowWeeklyBar")

        let activityMonitor = activityMonitor ?? ClaudeCodeActivityMonitor()
        self.activityMonitor = activityMonitor
        let historyStore = historyStore ?? ClaudeCodeHistoryStore()
        self.historyStore = historyStore
        if autoStart {
            start()
            activityMonitor.start()
            historyStore.startAutoRefresh()
        }
        if enableLocalWebServer {
            startLocalWebServer()
        }
    }

    deinit {
        timer?.invalidate()
    }

    /// The Mac's LAN address (e.g. "http://192.168.1.23:8765") an iPhone on the
    /// same Wi-Fi can open in Safari, or nil if the local server isn't running
    /// or the Mac has no Wi-Fi IPv4 address to advertise.
    var localWebServerAddress: String? {
        guard let webServer, webServer.isRunning, let ip = LocalNetwork.currentIPv4Address() else {
            return nil
        }
        return "http://\(ip):\(webServer.port)"
    }

    func startLocalWebServer() {
        guard webServer == nil else { return }
        let server = LocalWebServer(store: self)
        server.start()
        webServer = server
    }

    func stopLocalWebServer() {
        webServer?.stop()
        webServer = nil
    }

    var hasSessionKey: Bool {
        keychain.readSessionKey()?.isEmpty == false
    }

    /// Current-session utilization, used for the menu bar icon's top bar.
    var sessionPercent: Int? {
        usage?.fiveHour?.utilization
    }

    /// "All models" weekly utilization, used for the menu bar icon's bottom bar.
    var weeklyPercent: Int? {
        usage?.limits.first(where: { $0.kind == "weekly_all" })?.percent
    }

    /// When the current session resets, used for the menu bar icon's countdown text.
    var sessionResetsAt: Date? {
        FlexibleISO8601.date(from: usage?.fiveHour?.resetsAt)
    }

    func start() {
        timer?.invalidate()
        Task { await refresh() }
        let timer = Timer(timeInterval: refreshInterval, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                await self.refresh()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func refresh() async {
        guard let sessionKey = keychain.readSessionKey(), !sessionKey.isEmpty else {
            errorMessage = UsageServiceError.noSessionKey.localizedDescription
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let organizationId = try await resolveOrganizationId(sessionKey: sessionKey)
            let result = try await service.fetchUsage(sessionKey: sessionKey, organizationId: organizationId)
            usage = result
            lastUpdated = Date()
            errorMessage = nil
        } catch UsageServiceError.unauthorized {
            // Cached org id might be stale for a different account; clear it so the next
            // attempt re-resolves it once the user provides a valid session key.
            keychain.deleteOrganizationId()
            errorMessage = UsageServiceError.unauthorized.localizedDescription
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func resolveOrganizationId(sessionKey: String) async throws -> String {
        if let cached = keychain.readOrganizationId() {
            return cached
        }
        let orgId = try await service.fetchOrganizationId(sessionKey: sessionKey)
        keychain.saveOrganizationId(orgId)
        return orgId
    }
}
