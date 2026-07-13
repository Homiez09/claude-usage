import Foundation
import Security

final class KeychainHelper {
    /// The real, production Keychain item used by the running app.
    /// Tests must never use this instance — use `init(service:)` with a
    /// distinct namespace instead, so test runs can't clobber or read back
    /// the user's actual saved session key.
    static let shared = KeychainHelper(service: "com.claudeusage.menubar")

    private let service: String
    private let sessionAccount = "sessionKey"
    private let orgIdDefaultsKey: String

    init(service: String) {
        self.service = service
        self.orgIdDefaultsKey = "\(service).organizationId"
    }

    // MARK: - Session key (sensitive, stored in Keychain)

    @discardableResult
    func saveSessionKey(_ value: String) -> Bool {
        let data = Data(value.utf8)
        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: sessionAccount
        ]
        SecItemDelete(baseQuery as CFDictionary)

        var attributes = baseQuery
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock

        let status = SecItemAdd(attributes as CFDictionary, nil)
        return status == errSecSuccess
    }

    func readSessionKey() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: sessionAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    func deleteSessionKey() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: sessionAccount
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    // MARK: - Organization id (not sensitive, cached in UserDefaults)

    func saveOrganizationId(_ value: String) {
        UserDefaults.standard.set(value, forKey: orgIdDefaultsKey)
    }

    func readOrganizationId() -> String? {
        UserDefaults.standard.string(forKey: orgIdDefaultsKey)
    }

    func deleteOrganizationId() {
        UserDefaults.standard.removeObject(forKey: orgIdDefaultsKey)
    }
}
