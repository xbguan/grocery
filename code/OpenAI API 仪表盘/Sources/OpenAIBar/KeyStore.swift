import Foundation
import Security

/// API Key 存储在 macOS 钥匙串，不写入任何明文配置文件。
enum KeyStore {
    private static let service = "com.xbguan.openai-api-dashboard"
    private static let legacyService = "com.xbguan.openaibar"
    private static let account = "openai-admin-key"

    private static func baseQuery(_ svc: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: svc,
            kSecAttrAccount as String: account
        ]
    }

    static func load() -> String? {
        if let key = read(service) { return key }
        // 旧版服务名迁移
        if let key = read(legacyService) {
            if save(key) { delete(legacyService) }
            return key
        }
        return nil
    }

    private static func read(_ svc: String) -> String? {
        var query = baseQuery(svc)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    static func save(_ key: String) -> Bool {
        guard let data = key.data(using: .utf8) else { return false }

        let updateStatus = SecItemUpdate(baseQuery(service) as CFDictionary,
                                         [kSecValueData as String: data] as CFDictionary)
        if updateStatus == errSecSuccess { return true }

        guard updateStatus == errSecItemNotFound else {
            NSLog("OpenAIBar: Keychain update failed (\(updateStatus))")
            return false
        }

        var add = baseQuery(service)
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        add[kSecAttrLabel as String] = "OpenAI API 仪表盘 Admin Key"
        let addStatus = SecItemAdd(add as CFDictionary, nil)
        if addStatus != errSecSuccess {
            NSLog("OpenAIBar: Keychain add failed (\(addStatus))")
        }
        return addStatus == errSecSuccess
    }

    static func delete() {
        delete(service)
        delete(legacyService)
    }

    private static func delete(_ svc: String) {
        SecItemDelete(baseQuery(svc) as CFDictionary)
    }

    static var hasKey: Bool { load()?.isEmpty == false }
}
