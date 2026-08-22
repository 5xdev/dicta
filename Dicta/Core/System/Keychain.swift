import Foundation
import Security

/// Minimal generic-password Keychain wrapper for secrets (API keys).
enum Keychain {
    private static let service = "com.honeyyadav.dicta"

    static func get(_ account: String) -> String? {
        var query = query(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    static func set(_ value: String, for account: String) -> Bool {
        guard !value.isEmpty else { return delete(account) }
        let data = Data(value.utf8)
        let query = query(account)
        let update: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            // Deliberately the login (file-based) keychain, not kSecUseDataProtectionKeychain: the latter needs a
            // real signing identity, and ad-hoc CI builds have none. (kSecAttrAccessible is ignored here.)
            var insert = query
            insert[kSecValueData as String] = data
            return SecItemAdd(insert as CFDictionary, nil) == errSecSuccess
        }
        return status == errSecSuccess
    }

    @discardableResult
    static func delete(_ account: String) -> Bool {
        let status = SecItemDelete(query(account) as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    private static func query(_ account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}
