import XCTest
@testable import ClaudeUsageMenuBar

/// Uses a temp directory + dedicated namespace so tests never touch the real
/// `SessionStore.shared` file the running app stores the user's actual session
/// key under (Application Support/ClaudeUsageMenuBar).
final class SessionStoreTests: XCTestCase {
    private var directory: URL!
    private var store: SessionStore!

    override func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SessionStoreTests-\(UUID().uuidString)", isDirectory: true)
        store = SessionStore(directory: directory, namespace: "com.claudeusage.menubar.tests.store")
    }

    override func tearDown() {
        store.deleteSessionKey()
        store.deleteOrganizationId()
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }

    func testSessionKeyRoundTrip() {
        let saved = store.saveSessionKey("sk-ant-sid01-test-value")
        XCTAssertTrue(saved)
        XCTAssertEqual(store.readSessionKey(), "sk-ant-sid01-test-value")
    }

    func testSessionKeyOverwrite() {
        store.saveSessionKey("first-value")
        store.saveSessionKey("second-value")
        XCTAssertEqual(store.readSessionKey(), "second-value")
    }

    func testSessionKeyDeletion() {
        store.saveSessionKey("to-be-deleted")
        XCTAssertTrue(store.deleteSessionKey())
        XCTAssertNil(store.readSessionKey())
    }

    func testDeletingMissingKeyStillReportsSuccess() {
        store.deleteSessionKey()
        XCTAssertTrue(store.deleteSessionKey())
    }

    func testStoredFileIsEncryptedNotPlaintext() {
        store.saveSessionKey("sk-ant-sid01-super-secret")
        let raw = try? Data(contentsOf: directory.appendingPathComponent("session.enc"))
        XCTAssertNotNil(raw)
        // The plaintext cookie must not appear verbatim in the on-disk bytes.
        XCTAssertNil(raw.flatMap { String(data: $0, encoding: .utf8) }?.range(of: "sk-ant-sid01-super-secret"))
    }

    func testStoredFileHasOwnerOnlyPermissions() {
        store.saveSessionKey("value")
        let attrs = try? FileManager.default.attributesOfItem(
            atPath: directory.appendingPathComponent("session.enc").path
        )
        XCTAssertEqual(attrs?[.posixPermissions] as? NSNumber, NSNumber(value: 0o600))
    }

    func testOrganizationIdRoundTrip() {
        store.saveOrganizationId("403ee795-d4cd-40cc-8305-4028b5f1801d")
        XCTAssertEqual(store.readOrganizationId(), "403ee795-d4cd-40cc-8305-4028b5f1801d")
        store.deleteOrganizationId()
        XCTAssertNil(store.readOrganizationId())
    }

    func testDistinctNamespacesCannotDecryptEachOther() {
        store.saveSessionKey("value-for-first-namespace")
        // Same directory/file, but a different namespace derives a different key,
        // so the ciphertext can't be opened → reads back nil rather than leaking.
        let other = SessionStore(directory: directory, namespace: "com.claudeusage.menubar.tests.store.other")
        XCTAssertNil(other.readSessionKey())
    }
}
