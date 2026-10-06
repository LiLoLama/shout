import Foundation

/// Wohin ein Diktat geht. Festgelegt beim Start der Aufnahme — späteres Klicken
/// ändert es nicht.
enum DictationTarget: Equatable {
    /// Wie bisher: Einfügen in die App, die beim Start vorne war.
    case frontApp(bundleID: String?)
    /// An den Cursor einer Notiz im Panel.
    case scratchpad(noteID: UUID)
    /// Angehängt an die Eingangs-Notiz.
    case inbox
    /// Eine gesprochene Anweisung für den Zauberstab dieser Notiz — kein Diktat.
    case instruction(noteID: UUID)

    /// Ziel der normalen Diktiertaste: ins Panel, wenn es den Tastatur-Fokus hat
    /// und eine Notiz offen ist; sonst in die App davor.
    static func forDictationKey(panelIsKey: Bool, activeNote: UUID?, frontBundleID: String?) -> DictationTarget {
        if panelIsKey, let activeNote { return .scratchpad(noteID: activeNote) }
        return .frontApp(bundleID: frontBundleID)
    }

    /// Für den Ton der Aufbereitung. Notizen bekommen den neutralen.
    var formatterBundleID: String? {
        if case .frontApp(let id) = self { return id }
        return nil
    }

    var isFrontApp: Bool {
        if case .frontApp = self { return true }
        return false
    }

    var isInstruction: Bool {
        if case .instruction = self { return true }
        return false
    }
}
