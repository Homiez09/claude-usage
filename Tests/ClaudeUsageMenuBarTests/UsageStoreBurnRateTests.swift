import XCTest
@testable import ClaudeUsageMenuBar

/// คืนค่า utilization ตามลำดับการเรียก `/usage` แต่ละครั้ง — ให้เทสต์จำลอง
/// หลายรอบ poll ที่เปอร์เซ็นต์ไต่ขึ้น (หรือรีเซ็ตลง) ได้ ต้องใช้ class เพราะ
/// ต้องเก็บ state (`callIndex`) ข้ามการเรียกหลายครั้ง
private final class SequencedNetworkClient: NetworkClient, @unchecked Sendable {
    var utilizations: [Int]
    private var callIndex = 0

    init(utilizations: [Int]) {
        self.utilizations = utilizations
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let url = request.url!
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!

        if url.path == "/api/organizations" {
            return (Data(#"[{"uuid":"org-1"}]"#.utf8), response)
        }

        let percent = utilizations[min(callIndex, utilizations.count - 1)]
        callIndex += 1
        let json = """
        { "five_hour": { "utilization": \(percent), "resets_at": "2026-07-13T07:30:00+00:00" }, "limits": [] }
        """
        return (Data(json.utf8), response)
    }
}

/// Uses a dedicated Keychain namespace, per this project's testing rules —
/// never touch `SessionStore.shared`.
@MainActor
final class UsageStoreBurnRateTests: XCTestCase {
    private var directory: URL!
    private var sessionStore: SessionStore!

    override func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("UsageStoreBurnRateTests-\(UUID().uuidString)", isDirectory: true)
        sessionStore = SessionStore(directory: directory, namespace: "com.claudeusage.menubar.tests.burnrate")
        sessionStore.saveSessionKey("test-session")
    }

    override func tearDown() {
        sessionStore.deleteSessionKey()
        sessionStore.deleteOrganizationId()
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }

    func testBurnSamplesAccumulateAcrossRefreshes() async {
        let client = SequencedNetworkClient(utilizations: [10, 20, 30])
        let store = UsageStore(service: ClaudeUsageService(client: client), sessionStore: sessionStore, autoStart: false)

        await store.refresh()
        await store.refresh()
        await store.refresh()

        XCTAssertEqual(store.burnSamples.count, 3)
        XCTAssertEqual(store.burnSamples.map(\.percent), [10, 20, 30])
    }

    func testBurnSamplesResetWhenUtilizationDropsBelowLast() async {
        let client = SequencedNetworkClient(utilizations: [50, 70, 5])
        let store = UsageStore(service: ClaudeUsageService(client: client), sessionStore: sessionStore, autoStart: false)

        await store.refresh()
        await store.refresh()
        await store.refresh() // simulated quota reset: 70 -> 5

        XCTAssertEqual(store.burnSamples.count, 1)
        XCTAssertEqual(store.burnSamples.first?.percent, 5)
    }
}
