import AppKit

/// Was „Ablegen“ in die App davor bringt.
enum NoteHandoff {

    /// Die Auswahl, ohne (brauchbare) Auswahl die ganze Notiz — jeweils ohne
    /// Leerraum am Rand. `nil`, wenn nichts übrig bleibt.
    static func content(body: String, selection: NSRange) -> String? {
        let ns = body as NSString
        if selection.length > 0, selection.location >= 0, NSMaxRange(selection) <= ns.length {
            let auswahl = ns.substring(with: selection).trimmingCharacters(in: .whitespacesAndNewlines)
            if !auswahl.isEmpty { return auswahl }
        }
        let alles = body.trimmingCharacters(in: .whitespacesAndNewlines)
        return alles.isEmpty ? nil : alles
    }
}

/// Die App, in die abgelegt wird: die zuletzt aktive fremde App. Der Knopf im
/// Panel zeigt Symbol und Namen.
@MainActor
final class HandoffTarget: ObservableObject {
    @Published private(set) var app: NSRunningApplication?

    func update(_ app: NSRunningApplication?) { self.app = app }
}
