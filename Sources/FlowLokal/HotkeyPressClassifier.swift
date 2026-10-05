import Foundation

/// Tippen oder Halten der Scratchpad-Taste. Rein: Der Aufrufer meldet Drücken,
/// Loslassen und — per Zeitgeber nach `holdThreshold` — einen Zwischenstand.
struct HotkeyPressClassifier {

    static let holdThreshold: TimeInterval = 0.35

    enum Outcome: Equatable {
        case tap
        case holdBegan
        case holdEnded
    }

    private var gedruecktSeit: TimeInterval?
    private var haelt = false

    mutating func press(at zeit: TimeInterval) {
        // Schon gedrückt (Auto-Repeat, verlorenes Loslassen): ignorieren, sonst käme `.holdBegan` zweimal.
        guard gedruecktSeit == nil else { return }
        gedruecktSeit = zeit
        haelt = false
    }

    /// Vom Zeitgeber. Liefert `.holdBegan` genau einmal, wenn die Taste lange genug unten ist.
    mutating func tick(at zeit: TimeInterval) -> Outcome? {
        // Kleine Toleranz: Zeitgeber feuern gelegentlich minimal zu früh.
        guard let seit = gedruecktSeit, !haelt, zeit - seit >= Self.holdThreshold - 0.02 else { return nil }
        haelt = true
        return .holdBegan
    }

    mutating func release(at zeit: TimeInterval) -> Outcome? {
        guard gedruecktSeit != nil else { return nil }
        defer {
            gedruecktSeit = nil
            haelt = false
        }
        return haelt ? .holdEnded : .tap
    }
}
