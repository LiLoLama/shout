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
        didSet { d.set(isEnabled, forKey: K.aktiv); onChange?() }
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
