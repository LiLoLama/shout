import Foundation
import Security

/// Verwahrt die API-Schlüssel der Anbieter — in der Keychain, nicht in
/// `UserDefaults`.
///
/// Drei Festlegungen, die alle einen Grund haben:
///
/// 1. **Ein Schlüssel je Anbieter**, nicht je Verarbeitungsschritt. Wer OpenAI
///    für Text und Transkription nutzt, trägt ihn einmal ein.
/// 2. **`…WhenUnlockedThisDeviceOnly`** — damit wandert der Schlüssel nicht über
///    die iCloud-Keychain auf andere Geräte. Das passt zur Haltung des
///    Programms: Es gibt hier keine Synchronisierung, und ein Backup enthält den
///    Schlüssel ausdrücklich nicht.
/// 3. **Der Wert wird nie vollständig angezeigt** (siehe `mask`) und nie
///    protokolliert.
enum ProviderKeychain {

    static let defaultService = "com.inthezone.flowlokal.provider"

    /// Ein Keychain-Fehler mit dem rohen `OSStatus`. Bewusst ohne Anzeigetext:
    /// die Oberfläche ist zweisprachig und übersetzt selbst.
    struct Failure: Error, CustomStringConvertible {
        let status: OSStatus
        var description: String { "Keychain-Fehler \(status)" }
    }

    // MARK: - Lesen und Schreiben

    static func store(_ key: String, for templateID: String,
                      service: String = defaultService) throws {
        let value = Data(key.trimmingCharacters(in: .whitespacesAndNewlines).utf8)
        // Erst löschen, dann schreiben: `SecItemUpdate` bräuchte eine
        // Unterscheidung, ob schon etwas da ist, und legt sonst Duplikate an.
        try? delete(for: templateID, service: service)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: templateID,
            kSecValueData as String: value,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw Failure(status: status) }
    }

    static func read(for templateID: String, service: String = defaultService) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: templateID,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let key = String(data: data, encoding: .utf8),
              !key.isEmpty
        else { return nil }
        return key
    }

    /// Löschen ist absichtlich idempotent — sonst müsste jede Aufrufstelle
    /// vorher prüfen, ob überhaupt etwas da ist.
    static func delete(for templateID: String, service: String = defaultService) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: templateID,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw Failure(status: status)
        }
    }

    static func has(templateID: String, service: String = defaultService) -> Bool {
        read(for: templateID, service: service) != nil
    }

    // MARK: - Anzeige

    /// Was in der Oberfläche steht, z. B. `sk-…4f2a`.
    ///
    /// Die Vorsilbe bleibt sichtbar, weil sie beim Erkennen hilft (welcher
    /// Anbieter) und nichts verrät. Die letzten vier Zeichen zeigen, ob der
    /// richtige Schlüssel hinterlegt ist. Bei kurzen Schlüsseln wären vier
    /// Zeichen fast der ganze Wert — dann wird nichts gezeigt.
    static func mask(_ key: String) -> String {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        var prefix = ""
        if let separator = trimmed.firstIndex(where: { $0 == "-" || $0 == "_" }),
           trimmed.distance(from: trimmed.startIndex, to: separator) <= 5 {
            prefix = String(trimmed[...separator])
        }
        guard trimmed.count >= 12 else { return prefix + "…" }
        return prefix + "…" + String(trimmed.suffix(4))
    }

    static func masked(for templateID: String, service: String = defaultService) -> String? {
        read(for: templateID, service: service).map(mask)
    }
}
