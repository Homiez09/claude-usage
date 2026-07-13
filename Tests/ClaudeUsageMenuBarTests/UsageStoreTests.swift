import XCTest
@testable import ClaudeUsageMenuBar

/// Uses a dedicated Keychain namespace so tests never touch the real
/// `KeychainHelper.shared` item the running app stores the user's actual
/// session key under.
@MainActor
final class UsageStoreTests: XCTestCase {
    private let keychain = KeychainHelper(service: "com.claudeusage.menubar.tests.store")

    override func tearDown() {
        keychain.deleteSessionKey()
        keychain.deleteOrganizationId()
        super.tearDown()
    }

    func testRefreshWithoutSessionKeySetsError() async {
        let store = UsageStore(keychain: keychain, autoStart: false)

        await store.refresh()

        XCTAssertNil(store.usage)
        XCTAssertNotNil(store.errorMessage)
    }

    func testSessionAndWeeklyPercentReadFromUsage() {
        let store = UsageStore(keychain: keychain, autoStart: false)
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
        let store = UsageStore(keychain: keychain, autoStart: false)
        XCTAssertNil(store.sessionPercent)
        XCTAssertNil(store.weeklyPercent)
    }

    func testHasSessionKeyReflectsKeychainState() {
        keychain.deleteSessionKey()
        let store = UsageStore(keychain: keychain, autoStart: false)
        XCTAssertFalse(store.hasSessionKey)

        keychain.saveSessionKey("test-value")
        XCTAssertTrue(store.hasSessionKey)
    }
}
