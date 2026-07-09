import Foundation

/// Alles, was shout. lokal speichert — als eine Datei zum manuellen Übertragen
/// auf ein anderes Gerät. Kein Server, keine Cloud.
struct BackupBundle: Codable {
    static let currentVersion = 1
    var version = currentVersion
    var exportedAt = Date()
    var dictionary: PersonalDictionary.Contents
    var history: [DictationHistory.Entry]
    var stats: StatsStore.Data
    var settings: SettingsSnapshot
}

/// Einstellungen (aus RecordingSettings + UserDefaults).
struct SettingsSnapshot: Codable {
    var mode: String?
    var autoStop: Bool?
    var silenceSeconds: Double?
    var keyCode: Int?
    var modifiers: Int?
    var isModifierOnly: Bool?
    var formattingEnabled: Bool?
    var preferredMicUID: String?
    var voiceProfile: String?
    // Hinweis: Ältere Backups enthalten noch ein "licenseKey"-Feld (aus der Zeit
    // vor Open Source) — Codable ignoriert unbekannte Schlüssel, Import bleibt kompatibel.
}
