import Foundation
import LocalAuthentication
import Security

struct KeyStore {
    static let admin = KeyStore(service: "com.xbguan.openai-api-dashboard")
    let service: String
    var keychain: SecKeychain? = nil
    private let account = "openai-admin-key-v3"

    // The file-based login keychain has its own UI policy for trusted-app ACLs.
    // Keep it disabled for this process, including concurrent and later requests.
    private func query(adding: Bool = false) -> [String: Any]? {
        guard SecKeychainSetUserInteractionAllowed(false) == errSecSuccess else { return nil }
        let context = LAContext()
        context.interactionNotAllowed = true
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecUseAuthenticationContext as String: context,
            kSecUseAuthenticationUI as String: kSecUseAuthenticationUIFail
        ]
        if let keychain {
            if adding { query[kSecUseKeychain as String] = keychain }
            else { query[kSecMatchSearchList as String] = [keychain] }
        }
        return query
    }

    func load() -> String? {
        guard var query = query() else { return nil }
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func save(_ key: String) -> Bool {
        guard let match = query() else { return false }
        let data = Data(key.utf8)
        let status = SecItemUpdate(match as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecSuccess { return true }
        guard status == errSecItemNotFound, var add = query(adding: true) else { return false }
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        add[kSecAttrLabel as String] = "OpenAI API 仪表盘 Admin Key"
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }

    func delete() -> Bool {
        guard let query = query() else { return false }
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
