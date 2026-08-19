import Foundation

/// Erkennt den Doppeltipp auf dem Diktier-Hotkey (Aufnahme-Art „Doppeltipp").
///
/// Reine Zeitlogik ohne AppKit: die Zeitstempel kommen von außen herein, damit
/// sich das Verhalten in Tests durchspielen lässt. Gemessen wird — wie beim
/// Doppelklick — der Abstand zwischen den beiden *Anschlägen*; wie lange die
/// Taste dabei gehalten wird, spielt keine Rolle. Das Loslassen interessiert
/// diesen Modus gar nicht, deshalb kennt der Detektor nur `handleDown`.
struct DoubleTapDetector {

    enum Action: Equatable { case none, start, stop }

    /// Maximaler Abstand zwischen den zwei Anschlägen.
    var window: TimeInterval = 0.4

    /// Sperrfrist nach dem Start: ein versehentlicher dritter schneller Tipp
    /// soll die gerade begonnene Aufnahme nicht sofort wieder beenden.
    var guardTime: TimeInterval = 0.25

    /// Anschlag des noch offenen ersten Tipps (nil = kein Tipp offen).
    private var lastDown: TimeInterval?
    /// Wann die Aufnahme per Doppeltipp begann — Grundlage der Sperrfrist.
    private var startedAt: TimeInterval?

    /// Verarbeitet einen Tastendruck und sagt, was zu tun ist.
    mutating func handleDown(at now: TimeInterval, isRecording: Bool) -> Action {
        if isRecording {
            // Innerhalb der Sperrfrist zählt der Druck als Teil des Doppeltipps.
            if let started = startedAt, now - started < guardTime { return .none }
            lastDown = nil
            startedAt = nil
            return .stop
        }
        if let last = lastDown, now - last <= window {
            lastDown = nil
            startedAt = now
            return .start
        }
        // Zu langsam (oder erster Tipp überhaupt) → das ist der neue erste Tipp.
        lastDown = now
        return .none
    }
}
