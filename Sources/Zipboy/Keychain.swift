import Foundation
import Security

/// Reads, writes, and deletes archive passwords in the user's login Keychain, keyed by the archive's
/// path. Saving renames a new file over the old one, so the path is what lasts; an inode or a file ID
/// changes with every save. When an open archive moves, its document moves the item along.
enum Keychain {
    static let defaultService = "com.oddurs.zipboy.archive-password"

    /// Why a password couldn't be stored, in words for the alert that says so.
    struct Failure: LocalizedError {
        let status: OSStatus

        var errorDescription: String? { "Zipboy couldn’t remember the password in your Keychain." }
        var recoverySuggestion: String? {
            let reason = SecCopyErrorMessageString(status, nil) as String? ?? "Error \(status)."
            return "\(reason) You’ll be asked for the password the next time you open the archive."
        }
    }

    /// Symlinks resolved, so an archive reached through /tmp or /var finds the same item. Only the folder
    /// is resolved: Foundation resolves a path that no longer exists differently, and a moved archive's
    /// old path is looked up after the file has gone.
    static func accountKey(for url: URL) -> String {
        let file = url.standardizedFileURL
        let folder = file.deletingLastPathComponent().resolvingSymlinksInPath()
        return "path:\(folder.appendingPathComponent(file.lastPathComponent).path)"
    }

    static func password(for url: URL, service: String = defaultService) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: accountKey(for: url),
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func setPassword(_ password: String, for url: URL, service: String = defaultService) throws {
        deletePassword(for: url, service: service)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: accountKey(for: url),
            kSecAttrLabel as String: "Zipboy (\(url.lastPathComponent))",
            kSecValueData as String: Data(password.utf8),
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw Failure(status: status) }
    }

    static func deletePassword(for url: URL, service: String = defaultService) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: accountKey(for: url),
        ]
        SecItemDelete(query as CFDictionary)
    }

    /// Moves the password remembered for the archive that was at `old` to where it is now. The old item
    /// stays until the new one is stored, so a failure loses nothing.
    static func movePassword(from old: URL, to new: URL, service: String = defaultService) throws {
        guard accountKey(for: old) != accountKey(for: new), let password = password(for: old, service: service)
        else { return }
        try setPassword(password, for: new, service: service)
        deletePassword(for: old, service: service)
    }
}
