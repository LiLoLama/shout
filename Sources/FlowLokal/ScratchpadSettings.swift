import AppKit
import Combine

/// Einstellungen des Scratchpads: an/aus, die zwei globalen Tasten, das
/// Verhalten beim Öffnen. In den UserDefaults.
@MainActor
final class ScratchpadSettings: ObservableObject {

    enum Role: String, CaseIterable {
        case scratchpad
        case inbox
    }

    @Published var isEnabled: Bool {
        didSet {
            d.set(isEnabled, forKey: K.aktiv)
            // Ausgeschaltet verschwinden die Tastenzeilen — eine laufende Aufnahme darf nicht hängen bleiben.
            if !isEnabled { capturing = nil; captureHint = nil }
            onChange?()
        }
    }
    @Published var openBehavior: ScratchpadModel.OpenBehavior {
        didSet { d.set(openBehavior.rawValue, forKey: K.oeffnen) }
    }
    @Published private(set) var combos: [Role: HotkeyCombo] = [:]
    /// „Von einer anderen App belegt“ je Rolle, gesetzt beim Registrieren.
    @Published var registrationProblems: [Role: String] = [:]
    /// Welche Taste gerade aufgenommen wird (Oberflächenzustand).
    @Published var capturing: Role?
    @Published var captureHint: String?
    /// Tasten oder an/aus geändert — der AppDelegate registriert neu.
    var onChange: (() -> Void)?

    private let d: UserDefaults
    private enum K {
        static let aktiv = "scratchpad.enabled"
        static let oeffnen = "scratchpad.openBehavior"
        static func kombi(_ rolle: Role) -> String { "scratchpad.combo.\(rolle.rawValue)" }
    }

    init(defaults: UserDefaults = .standard) {
        d = defaults
        isEnabled = defaults.object(forKey: K.aktiv) as? Bool ?? true
        openBehavior = ScratchpadModel.OpenBehavior(rawValue: defaults.string(forKey: K.oeffnen) ?? "") ?? .resume
        for rolle in Role.allCases {
            if let daten = defaults.data(forKey: K.kombi(rolle)) {
                if daten.isEmpty {
                    // Leere Daten: bewusst „Keine“.
                    combos[rolle] = nil
                } else {
                    // Beschädigt: die Vorgabe, nicht still „Keine“.
                    combos[rolle] = (try? JSONDecoder().decode(HotkeyCombo.self, from: daten))
                        ?? (rolle == .scratchpad ? .scratchpadDefault : .inboxDefault)
                }
            } else {
                combos[rolle] = rolle == .scratchpad ? .scratchpadDefault : .inboxDefault
            }
        }
    }

    /// Fürs Backup — einfache Werte: Das Backup läuft auch auf iOS und kennt `HotkeyCombo` nicht.
    struct BackupFields: Equatable {
        var enabled: Bool
        var openBehavior: String
        /// Rolle → `HotkeyCombo` als JSON; leere Daten heißen „Keine“.
        var keys: [String: Data]
    }

    var backupFields: BackupFields {
        // Feste Schlüsselreihenfolge: Gleiche Taste, gleiche Bytes (sonst wäre der Vergleich zufällig).
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return BackupFields(enabled: isEnabled,
                     openBehavior: openBehavior.rawValue,
                     keys: Dictionary(uniqueKeysWithValues: Role.allCases.map { rolle in
                         (rolle.rawValue, combos[rolle].flatMap { try? encoder.encode($0) } ?? Data())
                     }))
    }

    /// Aus einem Backup. Unbekanntes oder Beschädigtes bleibt, wie es ist.
    func apply(_ felder: BackupFields) {
        if let verhalten = ScratchpadModel.OpenBehavior(rawValue: felder.openBehavior) { openBehavior = verhalten }
        for rolle in Role.allCases {
            guard let daten = felder.keys[rolle.rawValue] else { continue }
            if daten.isEmpty {
                setCombo(nil, for: rolle)
            } else if let kombi = try? JSONDecoder().decode(HotkeyCombo.self, from: daten) {
                setCombo(kombi, for: rolle)
            }
        }
        isEnabled = felder.enabled
    }

    /// Bricht eine laufende Tastenaufnahme ab (z. B. wenn die Zeilen verschwinden)
    /// und lässt über `onChange` beide Tasten neu anmelden.
    func cancelCapture() {
        guard capturing != nil else { return }
        capturing = nil
        captureHint = nil
        onChange?()
    }

    func combo(for rolle: Role) -> HotkeyCombo? { combos[rolle] }

    func setCombo(_ kombi: HotkeyCombo?, for rolle: Role) {
        combos[rolle] = kombi
        d.set(kombi.flatMap { try? JSONEncoder().encode($0) } ?? Data(), forKey: K.kombi(rolle))
        onChange?()
    }

    /// Feste Kürzel von shout.
    static let reserved: [HotkeyCombo] = [
        HotkeyCombo(keyCode: 8, flags: [.command, .option]),     // ⌥⌘C Korrektur
        HotkeyCombo(keyCode: 9, flags: [.command, .control]),    // ⌃⌘V zuletzt Gesprochenes
    ]

    /// Warum eine Kombination für `rolle` nicht taugt — oder `nil`.
    func rejection(for kombi: HotkeyCombo, role rolle: Role,
                   dictationKey: (keyCode: UInt16, modifiers: UInt, isModifierOnly: Bool)) -> String? {
        // Ohne ⌃ oder ⌥ finge die Taste Kürzel anderer Apps ab (⌘N, ⌘⇧N …).
        guard !kombi.flags.intersection([.control, .option]).isEmpty else {
            return Loc.t("Mit ⌃ oder ⌥ kombinieren")
        }
        if Self.reserved.contains(kombi) { return Loc.t("Schon belegt") }
        for andere in Role.allCases where andere != rolle && combos[andere] == kombi {
            return Loc.t("Schon belegt")
        }
        let maske = NSEvent.ModifierFlags([.command, .option, .control, .shift]).rawValue
        if !dictationKey.isModifierOnly, dictationKey.keyCode == kombi.keyCode,
           dictationKey.modifiers & maske == kombi.modifiers {
            return Loc.t("Schon belegt")
        }
        return nil
    }
}
