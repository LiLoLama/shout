import AppKit
import Carbon.HIToolbox

/// Eine Tastenkombination für die globalen Tasten des Scratchpads. Gespeichert
/// in NSEvent-Form (wie die Diktiertaste), umgerechnet für Carbon.
struct HotkeyCombo: Codable, Equatable {
    var keyCode: UInt16
    /// `NSEvent.ModifierFlags.rawValue`, nur ⌘ ⌥ ⌃ ⇧.
    var modifiers: UInt

    init(keyCode: UInt16, flags: NSEvent.ModifierFlags) {
        self.keyCode = keyCode
        modifiers = flags.intersection([.command, .option, .control, .shift]).rawValue
    }

    var flags: NSEvent.ModifierFlags { NSEvent.ModifierFlags(rawValue: modifiers) }

    var carbonModifiers: UInt32 {
        var ergebnis: UInt32 = 0
        if flags.contains(.command) { ergebnis |= UInt32(cmdKey) }
        if flags.contains(.option) { ergebnis |= UInt32(optionKey) }
        if flags.contains(.control) { ergebnis |= UInt32(controlKey) }
        if flags.contains(.shift) { ergebnis |= UInt32(shiftKey) }
        return ergebnis
    }

    /// ⌃⌥N — erzeugt in keiner üblichen Belegung ein Zeichen.
    static let scratchpadDefault = HotkeyCombo(keyCode: 45, flags: [.control, .option])
    /// ⌃⌥I
    static let inboxDefault = HotkeyCombo(keyCode: 34, flags: [.control, .option])

    /// „⌃⌥N“
    @MainActor
    var display: String {
        var text = ""
        if flags.contains(.control) { text += "⌃" }
        if flags.contains(.option) { text += "⌥" }
        if flags.contains(.shift) { text += "⇧" }
        if flags.contains(.command) { text += "⌘" }
        return text + RecordingSettings.keyName(forKeyCode: keyCode)
    }
}
