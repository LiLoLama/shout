import Foundation

/// Wo die Modelle liegen — als Einstellung, getrennt von der Logik.
///
/// `ModelStore` beantwortet Fragen, `ModelPaths` merkt sich die Antworten.
/// Die Trennung hält den Store frei von `UserDefaults` und damit prüfbar.
struct ModelPaths {

    /// Wohin shout. selbst herunterlädt.
    var basisordner: URL
    /// Fremde Ordner, in denen mitbenutzt wird. Reihenfolge = Vorrang.
    var suchordner: [URL]
    /// Zuletzt bekannter Pfad je Modell-Kennung. Nur dafür da, „nicht
    /// auffindbar" von „nie da gewesen" zu unterscheiden.
    var verknuepfungen: [String: URL]

    private enum Schluessel {
        static let basis = "modelBaseDirectory"
        static let such = "modelSearchDirectories"
        static let verknuepft = "modelLinks"
    }

    /// Lädt die Einstellung. `vorgabe` wird **zur Laufzeit** erfragt und nur
    /// benutzt, wenn nichts gespeichert ist.
    ///
    /// Sie darf nicht durch einen festen Pfad ersetzt werden: Der Standardort
    /// des Hugging-Face-Caches achtet auf `HF_HUB_CACHE` und `HF_HOME`. Wer
    /// eine davon gesetzt hat, bekäme sonst beim ersten Start nach dem Update
    /// sämtliche Modelle erneut heruntergeladen.
    static func laden(aus defaults: UserDefaults, vorgabe: () -> URL) -> ModelPaths {
        // isDirectory: true ist Pflicht, nicht Kosmetik: Ohne sie fehlt der
        // rekonstruierten URL der abschließende Schrägstrich, den `ordner(_:)`
        // in den Tests (und jeder andere Aufrufer) mitführt — zwei sonst
        // identische Ordner-URLs wären dann per `==` verschieden, solange der
        // Ordner nicht schon auf der Platte liegt.
        let basis = defaults.string(forKey: Schluessel.basis)
            .map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? vorgabe()
        let such = (defaults.stringArray(forKey: Schluessel.such) ?? [])
            .map { URL(fileURLWithPath: $0, isDirectory: true) }
        let verknuepft = (defaults.dictionary(forKey: Schluessel.verknuepft) as? [String: String] ?? [:])
            .mapValues { URL(fileURLWithPath: $0, isDirectory: true) }
        return ModelPaths(basisordner: basis, suchordner: such, verknuepfungen: verknuepft)
    }

    func sichern(in defaults: UserDefaults) {
        defaults.set(basisordner.path, forKey: Schluessel.basis)
        defaults.set(suchordner.map(\.path), forKey: Schluessel.such)
        defaults.set(verknuepfungen.mapValues(\.path), forKey: Schluessel.verknuepft)
    }

    /// Wechselt den Basisordner, **ohne etwas zu verschieben**.
    ///
    /// Der bisherige Ordner rutscht an die erste Stelle der Suchordner: Sonst
    /// gälten alle bisher geladenen Modelle mit einem Schlag als verschwunden,
    /// und shout. böte an, Gigabytes erneut zu laden, die schon da sind.
    /// Ein Umzug über Laufwerksgrenzen dauert Minuten und kann abbrechen —
    /// dafür ist der Gewinn zu klein.
    mutating func basisordnerWechseln(zu neu: URL) {
        let alt = basisordner
        guard alt.standardizedFileURL != neu.standardizedFileURL else { return }
        basisordner = neu
        // Der neue Basisordner darf nicht zusätzlich als Suchordner stehen,
        // sonst erschiene jedes Modell doppelt.
        suchordner.removeAll { $0.standardizedFileURL == neu.standardizedFileURL }
        if !suchordner.contains(where: { $0.standardizedFileURL == alt.standardizedFileURL }) {
            suchordner.insert(alt, at: 0)
        }
    }

    var store: ModelStore {
        ModelStore(basisordner: basisordner, suchordner: suchordner)
    }
}
