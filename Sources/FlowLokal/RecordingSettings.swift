import AppKit
import Combine

/// Aufnahme-Einstellungen: Modus (Halten/Umschalten), Hotkey, Auto-Stopp.
/// Persistiert in UserDefaults.
@MainActor
final class RecordingSettings: ObservableObject {

    enum Mode: String {
        case hold      // Taste halten (Push-to-talk)
        case toggle    // einmal drücken = läuft, nochmal = stopp
    }

    @Published var mode: Mode { didSet { d.set(mode.rawValue, forKey: K.mode) } }
    @Published var autoStop: Bool { didSet { d.set(autoStop, forKey: K.autoStop) } }
    @Published var silenceSeconds: Double { didSet { d.set(silenceSeconds, forKey: K.silence) } }

    /// Hotkey. Bei `isModifierOnly` ist `keyCode` der Virtual-Key einer Modifier-Taste
    /// (z. B. 61 = rechte ⌥) und wird über flagsChanged erkannt; sonst normale Taste + Modifier.
    @Published var keyCode: UInt16 { didSet { d.set(Int(keyCode), forKey: K.keyCode) } }
    @Published var modifiers: UInt { didSet { d.set(Int(modifiers), forKey: K.mods) } }
    @Published var isModifierOnly: Bool { didSet { d.set(isModifierOnly, forKey: K.modOnly) } }

    /// UI-Zustand: gerade wird eine neue Taste aufgenommen (nicht persistiert).
    @Published var isCapturing = false
    /// Kurzer Hinweis während der Aufnahme (z. B. „bitte mit Modifier kombinieren").
    @Published var captureHint: String?

    private let d = UserDefaults.standard
    private enum K {
        static let mode = "rec.mode", autoStop = "rec.autoStop", silence = "rec.silence"
        static let keyCode = "rec.keyCode", mods = "rec.mods", modOnly = "rec.modOnly"
    }

    init() {
        mode = Mode(rawValue: d.string(forKey: K.mode) ?? "") ?? .hold
        autoStop = d.object(forKey: K.autoStop) as? Bool ?? false
        silenceSeconds = d.object(forKey: K.silence) as? Double ?? 1.5
        if d.object(forKey: K.keyCode) != nil {
            keyCode = UInt16(d.integer(forKey: K.keyCode))
            modifiers = UInt(d.integer(forKey: K.mods))
            isModifierOnly = d.bool(forKey: K.modOnly)
        } else {
            // Standard: rechte Wahltaste als Push-to-talk (wie bisher).
            keyCode = 61
            modifiers = 0
            isModifierOnly = true
        }
    }

    // MARK: - Setzen (vom Hotkey-Recorder)

    func setModifierOnly(keyCode: UInt16) {
        isModifierOnly = true
        self.keyCode = keyCode
        modifiers = 0
    }

    func setRegular(keyCode: UInt16, modifiers rawFlags: NSEvent.ModifierFlags) {
        isModifierOnly = false
        self.keyCode = keyCode
        modifiers = rawFlags.intersection([.command, .option, .control, .shift]).rawValue
    }

    // MARK: - Abgleich mit Events

    /// Für flagsChanged: liefert true/false = Modifier-Hotkey gedrückt/losgelassen, nil = kein Treffer.
    func modifierPressed(in event: NSEvent) -> Bool? {
        guard isModifierOnly, event.keyCode == keyCode else { return nil }
        return event.modifierFlags.contains(Self.flag(forModifierKeyCode: keyCode))
    }

    func matchesKeyDown(_ event: NSEvent) -> Bool {
        guard !isModifierOnly, event.keyCode == keyCode else { return false }
        let mask: NSEvent.ModifierFlags = [.command, .option, .control, .shift]
        return event.modifierFlags.intersection(mask).rawValue == (modifiers & mask.rawValue)
    }

    func matchesKeyUp(_ event: NSEvent) -> Bool {
        guard !isModifierOnly else { return false }
        return event.keyCode == keyCode
    }

    // MARK: - Anzeige

    var hotkeyDescription: String {
        if isModifierOnly { return Self.modifierName(forKeyCode: keyCode) }
        let f = NSEvent.ModifierFlags(rawValue: modifiers)
        var s = ""
        if f.contains(.control) { s += "⌃" }
        if f.contains(.option) { s += "⌥" }
        if f.contains(.shift) { s += "⇧" }
        if f.contains(.command) { s += "⌘" }
        return s + Self.keyName(forKeyCode: keyCode)
    }

    // MARK: - Tabellen

    static func flag(forModifierKeyCode kc: UInt16) -> NSEvent.ModifierFlags {
        switch kc {
        case 54, 55: return .command
        case 56, 60: return .shift
        case 58, 61: return .option
        case 59, 62: return .control
        case 63: return .function
        default: return []
        }
    }

    static func modifierName(forKeyCode kc: UInt16) -> String {
        switch kc {
        case 55: return Loc.t("linke ⌘")
        case 54: return Loc.t("rechte ⌘")
        case 56: return Loc.t("linke ⇧")
        case 60: return Loc.t("rechte ⇧")
        case 58: return Loc.t("linke ⌥")
        case 61: return Loc.t("rechte ⌥")
        case 59: return Loc.t("linke ⌃")
        case 62: return Loc.t("rechte ⌃")
        case 63: return "fn"
        default: return Loc.f("Taste %d", Int(kc))
        }
    }

    static func keyName(forKeyCode kc: UInt16) -> String {
        let map: [UInt16: String] = [
            49: Loc.t("Leertaste"), 36: "⏎", 48: "⇥", 53: "esc",
            122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
            98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
            0: "A", 11: "B", 8: "C", 2: "D", 14: "E", 3: "F", 5: "G", 4: "H",
            34: "I", 38: "J", 40: "K", 37: "L", 46: "M", 45: "N", 31: "O", 35: "P",
            12: "Q", 15: "R", 1: "S", 17: "T", 32: "U", 9: "V", 13: "W", 7: "X",
            16: "Y", 6: "Z"
        ]
        return map[kc] ?? Loc.f("Taste %d", Int(kc))
    }
}
