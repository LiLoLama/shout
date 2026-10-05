import Foundation

/// Ein aufgeschobenes Beenden (`.terminateLater`) bekommt genau eine Antwort.
///
/// Läuft beim Beenden noch ein Diktat, wartet die App auf seine Zustellung. Danach
/// – oder wenn der Sicherheits-Zeitgeber zuerst abläuft – entscheiden die üblichen
/// Prüfungen (Notizen, Mitschnitt, Dateien), und AppKit erfährt das Ergebnis über
/// `NSApp.reply(toApplicationShouldTerminate:)`. Beide Wege können eintreten, auch
/// ineinander verschachtelt (ein modaler Hinweis lässt den Main-Actor weiterlaufen).
/// Geantwortet wird trotzdem nur einmal.
@MainActor
final class DeferredTermination {
    private var antwort: ((Bool) -> Void)?

    /// `reply`: bekommt `true` für „beenden“ und `false` für „abbrechen“.
    init(reply: @escaping (Bool) -> Void) {
        antwort = reply
    }

    /// Noch keine Antwort unterwegs.
    var isPending: Bool { antwort != nil }

    /// Ruft `decide` nur beim ersten Mal auf und gibt dessen Ergebnis weiter.
    /// Schon während `decide` läuft, gilt die Antwort als vergeben: Ein zweiter
    /// Aufruf in dieser Zeit (etwa aus einem modalen Hinweis heraus) tut nichts
    /// und fragt auch nichts.
    /// - Returns: `true`, wenn dieser Aufruf geantwortet hat.
    @discardableResult
    func resolve(_ decide: () -> Bool) -> Bool {
        guard let antwort else { return false }
        self.antwort = nil
        antwort(decide())
        return true
    }
}
