import Foundation
import Security
import os

/// Keychain-backed credential storage using the Security framework.
///
/// Use this instead of ``FileCredentialStore`` when the app is properly signed
/// (Developer ID or App Store). Ad-hoc signed apps trigger repeated Keychain
/// unlock prompts, which is why ``FileCredentialStore`` is the default for
/// development builds.
public enum KeychainCredentialStore {
    private static let log = Logger(subsystem: "cn.liujiangnan.WorkDock", category: "KeychainCreds")

    public static func set(service: String, account: String, value: String) {
        let data = Data(value.utf8)
        // Delete existing first (add fails if duplicate)
        delete(service: service, account: account)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        if status != errSecSuccess {
            log.error("set failed: \(SecCopyErrorMessageString(status, nil) as String? ?? "unknown", privacy: .public)")
        }
    }

    public static func get(service: String, account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public static func delete(service: String, account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
