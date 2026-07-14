import Foundation
import Combine

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
    @Published var islandPulseToken: String {
        didSet {
            UserDefaults.standard.set(islandPulseToken, forKey: "PrefIslandPulseToken")
            triggerIslandPulseNotification()
        }
    }

    private let service: ClaudeUsageService
    private let keychain: KeychainHelper
    private var timer: Timer?
    private let refreshInterval: TimeInterval
    private var webServer: LocalWebServer?
    private var cancellables = Set<AnyCancellable>()

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
        self.islandPulseToken = UserDefaults.standard.string(forKey: "PrefIslandPulseToken") ?? ""

        let activityMonitor = activityMonitor ?? ClaudeCodeActivityMonitor()
        self.activityMonitor = activityMonitor
        let historyStore = historyStore ?? ClaudeCodeHistoryStore()
        self.historyStore = historyStore
        
        // Listen to active session changes to update Island Pulse Live Activity instantly
        activityMonitor.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                DispatchQueue.main.async {
                    self.triggerIslandPulseNotification()
                }
            }
            .store(in: &cancellables)

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
            triggerIslandPulseNotification()
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

    private func resetsInHoursAndMinutes() -> String {
        guard let resetsAt = sessionResetsAt else { return "" }
        let diffMs = resetsAt.timeIntervalSince(Date())
        if diffMs <= 0 { return "" }
        let mins = Int(diffMs / 60)
        let hrs = mins / 60
        let rem = mins % 60
        if hrs > 0 {
            return "\(hrs)h \(rem)m"
        } else {
            return "\(rem)m"
        }
    }

    func triggerIslandPulseNotification() {
        let token = islandPulseToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { return }

        let sessionPct = sessionPercent ?? 0
        let weeklyPct = weeklyPercent ?? 0
        let progress = Double(sessionPct) / 100.0

        let resetTime = resetsInHoursAndMinutes()
        let resetSuffix = resetTime.isEmpty ? "" : " · resets in \(resetTime)"

        let active = activityMonitor.activeSessions
        let message: String
        let status: String
        let metric: String

        if !active.isEmpty {
            let session = active[0]
            var detail = session.displayName
            if let model = session.model {
                detail += " (\(model))"
            }
            message = "Active: \(detail)\(resetSuffix)"
            status = "running"
            metric = "\(sessionPct)%"
        } else {
            message = "Session: \(sessionPct)% · Weekly: \(weeklyPct)%\(resetSuffix)"
            status = "success"
            metric = "\(sessionPct)%"
        }

        let payload: [String: Any] = [
            "job_id": "claude-usage",
            "title": "Claude Usage",
            "message": message,
            "metric": metric,
            "progress": progress,
            "status": status
        ]

        guard let url = URL(string: "https://api.islandpulse.dev/notify") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)

        URLSession.shared.dataTask(with: request) { _, _, _ in }.resume()
    }
}
