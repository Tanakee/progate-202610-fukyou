import Foundation
import Security

/// ログインのトークンを Keychain に1つだけ保存する
enum Keychain {
    private static let service = "com.tanakee.oshikaze"
    private static let account = "authToken"

    private static var query: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    static func loadToken() -> String? {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(request as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func saveToken(_ token: String) {
        deleteToken()
        var item = query
        item[kSecValueData as String] = Data(token.utf8)
        // バックグラウンドで再生中も通信するので、端末のロック中でも読めるようにする
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(item as CFDictionary, nil)
    }

    static func deleteToken() {
        SecItemDelete(query as CFDictionary)
    }
}
