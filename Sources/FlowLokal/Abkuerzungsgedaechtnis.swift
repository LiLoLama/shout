import Foundation

/// Merkt sich, welche Kennungen über die Abkürzung aus einem fremden Ordner
/// geliefert wurden — und welche dabei nicht ladbar waren.
///
/// Der Grund ist ein stiller Dauerzustand: `ModelStore.istVollstaendig` prüft
/// nur, ob `config.json` und irgendeine `*.safetensors` da sind. Ein fremder
/// Ordner kann das bestehen und trotzdem nicht ladbar sein — fehlende
/// `tokenizer.json`, halber Shard-Satz, eine andere Architektur. `prepare`
/// schluckt den Fehler in ein `NSLog`, und weil die Abkürzung beim nächsten
/// Versuch wieder greift, nimmt **jeder** weitere Versuch denselben Weg. Die
/// Aufbereitung bliebe dauerhaft und unbemerkt tot.
///
/// Absichtlich klein: ein gemerkter Fehlschlag je Kennung, nur im Speicher.
/// Er muss den Programmlauf nicht überleben — wer shout. neu startet, darf es
/// noch einmal versuchen, und ein reparierter fremder Ordner soll nicht für
/// immer verbrannt sein.
final class Abkuerzungsgedaechtnis: @unchecked Sendable {

    /// Das Gedächtnis, das `ShoutDownloader` und `LocalTextEngine` teilen.
    /// Die beiden liegen an verschiedenen Enden desselben Vorgangs: Der eine
    /// liefert den Pfad, der andere erfährt, ob er taugte.
    static let geteilt = Abkuerzungsgedaechtnis()

    /// Eine Sperre statt eines Actors: Die Abfrage steckt mitten in einem
    /// synchronen Auflösungsweg, ein `await` wäre dort nicht zu haben.
    private let sperre = NSLock()
    /// Kennungen, die im laufenden Versuch über die Abkürzung kamen.
    private var abgekuerzt: Set<String> = []
    /// Kennungen, deren Abkürzung in einen Ladefehler lief.
    private var gescheitert: Set<String> = []

    /// Darf für diese Kennung noch abgekürzt werden?
    func darfAbkuerzen(_ kennung: String) -> Bool {
        sperre.lock()
        defer { sperre.unlock() }
        return !gescheitert.contains(kennung)
    }

    /// Hält fest, dass dieser Ladevorgang seinen Pfad aus der Abkürzung hat.
    /// Nur dann ist ein späterer Fehlschlag der Abkürzung zuzurechnen.
    func abkuerzungGemerkt(_ kennung: String) {
        sperre.lock()
        defer { sperre.unlock() }
        abgekuerzt.insert(kennung)
    }

    /// Das Laden hat geklappt — der gemerkte Hinweis wird nicht mehr gebraucht.
    func ladenGelungen(_ kennung: String) {
        sperre.lock()
        defer { sperre.unlock() }
        abgekuerzt.remove(kennung)
    }

    /// Das Laden ist gescheitert. Kam der Pfad aus der Abkürzung, wird sie für
    /// diese Kennung gesperrt: Der nächste Versuch geht an den Hub.
    ///
    /// Kam der Pfad NICHT aus der Abkürzung, passiert nichts — ein Fehler beim
    /// eigenen Download (Netz weg, Platte voll) darf einen brauchbaren fremden
    /// Ordner nicht in Verruf bringen.
    func ladenGescheitert(_ kennung: String) {
        sperre.lock()
        defer { sperre.unlock() }
        guard abgekuerzt.remove(kennung) != nil else { return }
        gescheitert.insert(kennung)
    }
}
