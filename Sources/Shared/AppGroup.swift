import Foundation

/// Geteilter Speicher zwischen der Haupt-App und der Tastatur-Erweiterung.
/// iOS verbietet Tastaturen den Mikrofonzugriff — die App diktiert, legt das
/// Ergebnis hier ab, und die Tastatur fügt es ins Textfeld ein.
enum AppGroup {
    static let id = "group.com.inthezone.shout"

    private static let textKey = "pendingDictation"
    private static let dateKey = "pendingDictationDate"

    private static var store: UserDefaults? { UserDefaults(suiteName: id) }

    /// Legt ein frisch diktiertes Ergebnis für die Tastatur ab (mit Zeitstempel).
    static func setPendingDictation(_ text: String) {
        store?.set(text, forKey: textKey)
        store?.set(Date().timeIntervalSince1970, forKey: dateKey)
    }

    /// Zuletzt abgelegtes Diktat (oder nil, wenn keins/leer).
    static func pendingDictation() -> String? {
        guard let text = store?.string(forKey: textKey), !text.isEmpty else { return nil }
        return text
    }

    /// Zeitstempel des zuletzt abgelegten Diktats (0 = keins).
    static func pendingDate() -> Double { store?.double(forKey: dateKey) ?? 0 }

    static func clearPending() {
        store?.removeObject(forKey: textKey)
        store?.removeObject(forKey: dateKey)
    }
}
