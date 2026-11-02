import Foundation
import LocalAuthentication
import Security

/// API Key 存储在 macOS 钥匙串，不写入任何明文配置文件。
enum KeyStore {
    private static let service = "com.xbguan.openai-api-dashboard"
    private static let legacyService = "com.xbguan.openaibar"
    private static let account = "openai-admin-key-v2"
    private static let legacyAccount = "openai-admin-key"

    private static func baseQuery(_ svc: String, account: String = account) -> [String: Any] {
        let context = LAContext()
        context.interactionNotAllowed = true
        return [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: svc,
            kSecAttrAccount as String: account,
            // 旧签名无权访问旧条目时直接返回错误，绝不弹出钥匙串授权框。
            kSecUseAuthenticationContext as String: context
        ]
    }

    static func load() -> String? {
        if let key = read(service, account: account) { return key }
        // 能无弹窗读取旧条目时迁移；否则由用户在设置中重新输入一次。
        for svc in [service, legacyService] {
            guard let key = read(svc, account: legacyAccount) else { continue }
            save(key)
            return key
        }
        return nil
    }

    private static func read(_ svc: String, account: String) -> String? {
        var query = baseQuery(svc, account: account)
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
        delete(service, account: legacyAccount)
        delete(legacyService, account: legacyAccount)
    }

    private static func delete(_ svc: String, account: String = account) {
        SecItemDelete(baseQuery(svc, account: account) as CFDictionary)
    }

    static var hasKey: Bool { load()?.isEmpty == false }
}
