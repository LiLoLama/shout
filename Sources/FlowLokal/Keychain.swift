import Foundation
import Security

/// Kleiner Wrapper um die macOS-Keychain für einzelne String-Werte.
/// Wird als schwerer manipulierbarer Zweitanker für Trial-Start und
/// Lizenzschlüssel genutzt (statt reiner Klartext-Dateien/UserDefaults).
enum Keychain {
    private static let service = "com.inthezone.flowlokal"

    @discardableResult
    static func set(_ value: String, for account: String) -> Bool {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(base as CFDictionary)   // evtl. vorhandenen Eintrag entfernen (Fehler egal)
        var add = base
        add[kSecValueData as String] = Data(value.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let status = SecItemAdd(add as CFDictionary, nil)
        if status != errSecSuccess {
            // z. B. gesperrte Keychain, MDM-Restriktion → nicht still verschlucken.
            NSLog("shout: Keychain.set(\(account)) fehlgeschlagen (OSStatus \(status))")
            return false
        }
        return true
    }

    static func get(_ account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var out: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data,
              let value = String(data: data, encoding: .utf8) else { return nil }
        return value
    }

    @discardableResult
    static func delete(_ account: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            NSLog("shout: Keychain.delete(\(account)) fehlgeschlagen (OSStatus \(status))")
            return false
        }
        return true
    }
}
