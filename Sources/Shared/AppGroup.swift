import Foundation

/// Geteilter Speicher zwischen der Haupt-App und der Tastatur-Erweiterung.
/// iOS verbietet Tastaturen den Mikrofonzugriff — die App diktiert, legt das
/// Ergebnis hier ab, und die Tastatur fügt es ins Textfeld ein.
enum AppGroup {
    static let id = "group.com.inthezone.shout"

    enum DictationPhase: String {
        case idle
        case openingApp
        case recording
        case processing
        case ready
        case failed
        case cancelled
        case expired
        case inserted
    }

    private static let textKey = "pendingDictation"
    private static let dateKey = "pendingDictationDate"
    private static let phaseKey = "pendingDictationPhase"

    /// Ein Keyboard-Ergebnis ist nur für den unmittelbaren Rückweg gedacht. Alte
    /// Texte dürfen bei einem späteren Diktat nicht überraschend wieder auftauchen.
    private static let defaultMaxAge: TimeInterval = 15 * 60

    private static var store: UserDefaults? { UserDefaults(suiteName: id) }

    /// Legt ein frisch diktiertes Ergebnis für die Tastatur ab (mit Zeitstempel).
    static func setPendingDictation(_ text: String) {
        store?.set(text, forKey: textKey)
        store?.set(Date().timeIntervalSince1970, forKey: dateKey)
        setPhase(.ready)
    }

    /// Zuletzt abgelegtes Diktat (oder nil, wenn keins/leer).
    static func pendingDictation(maxAge: TimeInterval = defaultMaxAge) -> String? {
        guard let text = store?.string(forKey: textKey), !text.isEmpty else { return nil }
        let timestamp = pendingDate()
        guard timestamp > 0, Date().timeIntervalSince1970 - timestamp <= maxAge else {
            clearPending()
            setPhase(.expired)
            return nil
        }
        return text
    }

    /// Zeitstempel des zuletzt abgelegten Diktats (0 = keins).
    static func pendingDate() -> Double { store?.double(forKey: dateKey) ?? 0 }

    static func setPhase(_ phase: DictationPhase) {
        store?.set(phase.rawValue, forKey: phaseKey)
    }

    static func phase() -> DictationPhase {
        guard let raw = store?.string(forKey: phaseKey),
              let phase = DictationPhase(rawValue: raw) else { return .idle }
        return phase
    }

    static func clearPending() {
        store?.removeObject(forKey: textKey)
        store?.removeObject(forKey: dateKey)
    }

    static func reset() {
        clearPending()
        setPhase(.idle)
    }
}
