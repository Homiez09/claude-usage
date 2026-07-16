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
    @Published var notificationsEnabled: Bool {
        didSet {
            UserDefaults.standard.set(notificationsEnabled, forKey: "PrefNotifyEnabled")
            if notificationsEnabled {
                notifier.requestAuthorizationIfNeeded()
            }
        }
    }
    @Published var sessionEndNotificationsEnabled: Bool {
        didSet {
            UserDefaults.standard.set(sessionEndNotificationsEnabled, forKey: "PrefNotifySessionEnd")
            if sessionEndNotificationsEnabled {
                notifier.requestAuthorizationIfNeeded()
            }
        }
    }

    /// จุดข้อมูล (เวลา, %) ของ session ปัจจุบัน เก็บจากการ poll แต่ละรอบ
    /// เพื่อประเมิน burn rate — ล้างทิ้งเมื่อ session รีเซ็ต (% ตกลง)
    @Published private(set) var burnSamples: [BurnRateSample] = []

    private let service: ClaudeUsageService
    private let keychain: KeychainHelper
    private let notifier = UsageNotifier()
    private var firedAlertThresholds: [String: Int] = [:]
    /// % ของ session จากรอบ refresh ก่อนหน้า ใช้ตรวจว่าโควตาเพิ่งรีเซ็ต
    private var lastSessionPercent: Int?
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
        self.notificationsEnabled = UserDefaults.standard.object(forKey: "PrefNotifyEnabled") == nil ? true : UserDefaults.standard.bool(forKey: "PrefNotifyEnabled")
        self.sessionEndNotificationsEnabled = UserDefaults.standard.object(forKey: "PrefNotifySessionEnd") == nil ? true : UserDefaults.standard.bool(forKey: "PrefNotifySessionEnd")

        let activityMonitor = activityMonitor ?? ClaudeCodeActivityMonitor()
        self.activityMonitor = activityMonitor
        let historyStore = historyStore ?? ClaudeCodeHistoryStore()
        self.historyStore = historyStore
        activityMonitor.onSessionsEnded = { [weak self] ended in
            guard let self, self.sessionEndNotificationsEnabled else { return }
            self.notifier.sendSessionEnded(ended)
        }
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

    /// เพซการใช้งาน session ปัจจุบัน (%/ชม.) จากจุดข้อมูลที่ poll มา
    var sessionBurnRatePerHour: Double? {
        BurnRateEstimator.ratePerHour(samples: burnSamples)
    }

    /// เวลาที่คาดว่า session จะแตะ 100% ถ้าคงเพซนี้ไว้
    var sessionProjectedFullAt: Date? {
        BurnRateEstimator.projectedFullDate(samples: burnSamples)
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
            recordBurnSample()
            evaluateAlerts()
        } catch UsageServiceError.unauthorized {
            // Cached org id might be stale for a different account; clear it so the next
            // attempt re-resolves it once the user provides a valid session key.
            keychain.deleteOrganizationId()
            errorMessage = UsageServiceError.unauthorized.localizedDescription
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// เก็บจุดข้อมูล burn rate ของ session ปัจจุบัน — ล้างทิ้งเมื่อ % ตกลง
    /// (แปลว่าโควตารีเซ็ตแล้ว) และเก็บเฉพาะช่วง 30 นาทีล่าสุดพอให้เพซนิ่ง
    private func recordBurnSample() {
        guard let percent = usage?.fiveHour?.utilization else { return }
        let now = Date()
        if let last = burnSamples.last, percent < last.percent {
            burnSamples.removeAll()
        }
        burnSamples.append(BurnRateSample(time: now, percent: percent))
        let cutoff = now.addingTimeInterval(-1800)
        burnSamples.removeAll { $0.time < cutoff }
    }

    /// เทียบเปอร์เซ็นต์ล่าสุดกับ threshold (80/95) แล้วยิง notification
    /// เฉพาะตอนข้ามขาขึ้น — สถานะกันยิงซ้ำอยู่ใน `firedAlertThresholds`
    /// รวมทั้งตรวจขาลง (โควตารีเซ็ตหลังจากเคยใกล้เต็ม) เพื่อแจ้งว่ากลับมาใช้ได้
    private func evaluateAlerts() {
        var entries: [(key: String, title: String, percent: Int)] = []
        if let percent = usage?.fiveHour?.utilization {
            entries.append(("session", "Current session", percent))
            if notificationsEnabled,
               UsageAlertPlanner.shouldNotifyReset(previousPercent: lastSessionPercent, currentPercent: percent) {
                notifier.sendQuotaReset()
            }
            lastSessionPercent = percent
        }
        for entry in usage?.limits ?? [] where entry.group == "weekly" {
            let title = entry.scope?.model?.displayName ?? "All models"
            entries.append(("\(entry.kind)-\(title)", title, entry.percent))
        }

        let (alerts, newState) = UsageAlertPlanner.plan(current: entries, firedThresholds: firedAlertThresholds)
        firedAlertThresholds = newState
        if notificationsEnabled {
            notifier.send(alerts)
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
