import Foundation
import Security

/// 敏感凭据(自定义的数据 API Key)只存系统钥匙串,不进 JSON、不进 UserDefaults。
enum KeychainStore {
    static let service = "io.primit.axblade"

    /// 返回 `SecItemAdd` 的状态码:写失败必须能被调用方看见,
    /// 否则界面会显示「已保存」而请求根本没有 Key。
    @discardableResult
    static func setSecret(_ value: String, account: String) -> OSStatus {
        deleteSecret(account: account)
        guard !value.isEmpty else { return errSecParam }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: Data(value.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        return SecItemAdd(query as CFDictionary, nil)
    }

    static func secret(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            // service 必须和写入时一致,否则同名 account 的其它条目也会命中。
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8),
              !value.isEmpty
        else { return nil }
        return value
    }

    static func deleteSecret(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}
