import Foundation
import CryptoKit
import IOKit

/// Stores the sensitive claude.ai session cookie as an AES-GCM encrypted file
/// under Application Support — deliberately *not* the macOS Keychain.
///
/// The Keychain ties each stored item to the creating app's code signature via
/// its ACL. Because this app is only ad-hoc signed (`-`), every `./build_app.sh`
/// rebuild produces a fresh signature, so macOS treats the new build as a
/// different identity and pops the "another app wants to use an item you saved"
/// authorization prompt — which looks exactly like malware asking for your
/// Keychain. Storing the cookie ourselves avoids that prompt entirely.
///
/// Instead of Keychain protection we get:
///  - AES-GCM encryption with a key derived from this Mac's hardware UUID, so
///    the file is bound to the machine and useless if copied to another Mac.
///  - `0600` POSIX permissions, so only the logged-in user can read the file.
/// This is a weaker guarantee than the Keychain (any process running *as you*
/// could still decrypt it), but it's an acceptable trade-off for a personal,
/// unsigned menu-bar utility and removes the confusing security prompt.
final class SessionStore {
    /// The real, production store used by the running app.
    /// Tests must never use this instance — construct `init(directory:namespace:)`
    /// with a temp directory + distinct namespace so a test run can't read back
    /// or clobber the user's actual saved session key.
    static let shared = SessionStore()

    private let directory: URL
    private let sessionFileName = "session.enc"
    private let orgIdDefaultsKey: String
    private let key: SymmetricKey

    /// Production instance: `~/Library/Application Support/ClaudeUsageMenuBar/`.
    convenience init() {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("ClaudeUsageMenuBar", isDirectory: true)
        self.init(directory: base, namespace: "com.claudeusage.menubar")
    }

    /// - Parameters:
    ///   - directory: where the encrypted session file lives (tests pass a temp dir).
    ///   - namespace: isolates the UserDefaults org-id key *and* the derived
    ///     encryption key, so distinct namespaces can't decrypt each other's files.
    init(directory: URL, namespace: String) {
        self.directory = directory
        self.orgIdDefaultsKey = "\(namespace).organizationId"
        self.key = Self.deriveKey(namespace: namespace)
        try? FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
    }

    private var sessionFileURL: URL {
        directory.appendingPathComponent(sessionFileName, isDirectory: false)
    }

    // MARK: - Session key (sensitive, AES-GCM encrypted on disk)

    @discardableResult
    func saveSessionKey(_ value: String) -> Bool {
        do {
            let sealed = try AES.GCM.seal(Data(value.utf8), using: key)
            guard let combined = sealed.combined else { return false }
            try combined.write(to: sessionFileURL, options: .atomic)
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o600], ofItemAtPath: sessionFileURL.path
            )
            return true
        } catch {
            return false
        }
    }

    func readSessionKey() -> String? {
        guard let combined = try? Data(contentsOf: sessionFileURL),
              let box = try? AES.GCM.SealedBox(combined: combined),
              let data = try? AES.GCM.open(box, using: key)
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    func deleteSessionKey() -> Bool {
        let fm = FileManager.default
        guard fm.fileExists(atPath: sessionFileURL.path) else { return true }
        do {
            try fm.removeItem(at: sessionFileURL)
            return true
        } catch {
            return false
        }
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

    // MARK: - Key derivation

    /// 256-bit key = SHA-256 of the machine's hardware UUID + namespace + a
    /// version tag. Deterministic across launches on the same Mac (so the file
    /// stays readable), but changes on a different machine (so a copied file
    /// can't be decrypted).
    private static func deriveKey(namespace: String) -> SymmetricKey {
        let machine = hardwareUUID() ?? "no-hardware-uuid-fallback"
        let material = Data("\(machine)|\(namespace)|ClaudeUsageMenuBar-session-v1".utf8)
        return SymmetricKey(data: SHA256.hash(data: material))
    }

    private static func hardwareUUID() -> String? {
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault, IOServiceMatching("IOPlatformExpertDevice")
        )
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        guard let cf = IORegistryEntryCreateCFProperty(
            service, kIOPlatformUUIDKey as CFString, kCFAllocatorDefault, 0
        ) else { return nil }
        return cf.takeRetainedValue() as? String
    }
}
