import Foundation

/// Ein Abbruchwunsch, der die Strang-Grenze überquert.
///
/// `ModelScan.durchsuchen` fragt zwischen zwei Ordnern **synchron** nach, ob
/// abgebrochen werden soll — der Knopf, der das auslöst, sitzt aber auf dem
/// Hauptstrang, während die Suche abseits davon läuft. Ein `@State`-`Bool`
/// taugt dafür nicht: Er wäre von der Suche aus nur mit `await` zu lesen, und
/// `abbruch` nimmt keinen asynchronen Block.
///
/// Deshalb dieses winzige Stück gemeinsamer Zustand. `@unchecked Sendable` ist
/// hier belegbar und nicht geraten: Der einzige veränderliche Wert steckt
/// hinter einem `NSLock`, und er kann nur einmal von `false` auf `true`
/// wechseln. Ein verspätet gesehener Wert kostet höchstens einen weiteren
/// Ordner, er kann nie eine falsche Suche abbrechen.
final class AbbruchFlagge: @unchecked Sendable {

    private let schloss = NSLock()
    private var gesetzt = false

    init() {}

    /// Bittet um Abbruch. Mehrfaches Setzen ist harmlos.
    func setzen() {
        schloss.lock()
        defer { schloss.unlock() }
        gesetzt = true
    }

    /// Ob ein Abbruch gewünscht ist. Darf beliebig oft gefragt werden — die
    /// Suche fragt einmal je Ordner.
    var istGesetzt: Bool {
        schloss.lock()
        defer { schloss.unlock() }
        return gesetzt
    }
}
