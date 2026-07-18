import XCTest
@testable import ClaudeUsageMenuBar

/// Uses a temp directory + dedicated namespace so tests never touch the real
/// `SessionStore.shared` file the running app stores the user's actual session
/// key under.
@MainActor
final class UsageStoreTests: XCTestCase {
    private var directory: URL!
    private var sessionStore: SessionStore!

    override func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("UsageStoreTests-\(UUID().uuidString)", isDirectory: true)
        sessionStore = SessionStore(directory: directory, namespace: "com.claudeusage.menubar.tests.usagestore")
    }

    override func tearDown() {
        sessionStore.deleteSessionKey()
        sessionStore.deleteOrganizationId()
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }

    func testRefreshWithoutSessionKeySetsError() async {
        let store = UsageStore(sessionStore: sessionStore, autoStart: false)

        await store.refresh()

        XCTAssertNil(store.usage)
        XCTAssertNotNil(store.errorMessage)
    }

    func testSessionAndWeeklyPercentReadFromUsage() {
        let store = UsageStore(sessionStore: sessionStore, autoStart: false)
        store.usage = UsageResponse(
            fiveHour: LimitWindow(utilization: 41, resetsAt: "2026-07-13T07:30:00+00:00"),
            sevenDay: LimitWindow(utilization: 43, resetsAt: nil),
            limits: [
                LimitEntry(group: "weekly", kind: "weekly_all", percent: 90, resetsAt: nil, severity: "normal", scope: nil)
            ]
        )
        XCTAssertEqual(store.sessionPercent, 41)
        XCTAssertEqual(store.weeklyPercent, 90)
        XCTAssertNotNil(store.sessionResetsAt)
    }

    func testSessionAndWeeklyPercentNilWhenNoUsageLoaded() {
        let store = UsageStore(sessionStore: sessionStore, autoStart: false)
        XCTAssertNil(store.sessionPercent)
        XCTAssertNil(store.weeklyPercent)
    }

    func testHasSessionKeyReflectsKeychainState() {
        sessionStore.deleteSessionKey()
        let store = UsageStore(sessionStore: sessionStore, autoStart: false)
        XCTAssertFalse(store.hasSessionKey)

        sessionStore.saveSessionKey("test-value")
        XCTAssertTrue(store.hasSessionKey)
    }
}
