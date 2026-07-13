import XCTest
@testable import ClaudeUsageMenuBar

/// Uses a dedicated Keychain namespace so tests never touch the real
/// `KeychainHelper.shared` item the running app stores the user's actual
/// session key under.
final class KeychainHelperTests: XCTestCase {
    private let keychain = KeychainHelper(service: "com.claudeusage.menubar.tests.keychain")

    override func tearDown() {
        keychain.deleteSessionKey()
        keychain.deleteOrganizationId()
        super.tearDown()
    }

    func testSessionKeyRoundTrip() {
        let saved = keychain.saveSessionKey("sk-ant-sid01-test-value")
        XCTAssertTrue(saved)
        XCTAssertEqual(keychain.readSessionKey(), "sk-ant-sid01-test-value")
    }

    func testSessionKeyOverwrite() {
        keychain.saveSessionKey("first-value")
        keychain.saveSessionKey("second-value")
        XCTAssertEqual(keychain.readSessionKey(), "second-value")
    }

    func testSessionKeyDeletion() {
        keychain.saveSessionKey("to-be-deleted")
        XCTAssertTrue(keychain.deleteSessionKey())
        XCTAssertNil(keychain.readSessionKey())
    }

    func testDeletingMissingKeyStillReportsSuccess() {
        keychain.deleteSessionKey()
        XCTAssertTrue(keychain.deleteSessionKey())
    }

    func testOrganizationIdRoundTrip() {
        keychain.saveOrganizationId("403ee795-d4cd-40cc-8305-4028b5f1801d")
        XCTAssertEqual(keychain.readOrganizationId(), "403ee795-d4cd-40cc-8305-4028b5f1801d")
        keychain.deleteOrganizationId()
        XCTAssertNil(keychain.readOrganizationId())
    }

    func testDistinctServicesDoNotShareStorage() {
        let other = KeychainHelper(service: "com.claudeusage.menubar.tests.keychain.other")
        keychain.saveSessionKey("value-for-first-namespace")
        XCTAssertNil(other.readSessionKey())
        other.deleteSessionKey()
    }
}
