import Foundation
import Security

/// Reads, writes, and deletes archive passwords in the user's login Keychain, keyed by the archive's
/// volume + inode identifier (falling back to its standardized path when the file is not yet on disk).
enum Keychain {
    static let defaultService = "com.oddurs.zipboy.archive-password"

    /// A stable account key for `url`: its filesystem resource identifier (`volume:inode`) when available,
    /// or its standardized path.
    static func accountKey(for url: URL) -> String {
        if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
            let sysNum = attrs[.systemNumber] as? NSNumber,
            let fileNum = attrs[.systemFileNumber] as? UInt64
        {
            return "inode:\(sysNum.uint64Value):\(fileNum)"
        }
        return "path:\(url.standardizedFileURL.path)"
    }

    static func password(for url: URL, service: String = defaultService) -> String? {
        for key in candidateKeys(for: url) {
            if let found = read(account: key, service: service) {
                return found
            }
        }
        return nil
    }

    @discardableResult
    static func setPassword(_ password: String, for url: URL, service: String = defaultService) -> Bool {
        deletePassword(for: url, service: service)
        guard let data = password.data(using: .utf8) else { return false }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: accountKey(for: url),
            kSecAttrLabel as String: "Zipboy (\(url.lastPathComponent))",
            kSecValueData as String: data,
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        return status == errSecSuccess
    }

    static func deletePassword(for url: URL, service: String = defaultService) {
        for key in candidateKeys(for: url) {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: key,
            ]
            SecItemDelete(query as CFDictionary)
        }
    }

    private static func candidateKeys(for url: URL) -> [String] {
        let primary = accountKey(for: url)
        let fallback = "path:\(url.standardizedFileURL.path)"
        return primary == fallback ? [primary] : [primary, fallback]
    }

    private static func read(account: String, service: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
