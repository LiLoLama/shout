import Foundation

/// Wo die Modelle liegen — als Einstellung, getrennt von der Logik.
///
/// `ModelStore` beantwortet Fragen, `ModelPaths` merkt sich die Antworten.
/// Die Trennung hält den Store frei von `UserDefaults` und damit prüfbar.
struct ModelPaths {

    /// Der **ausdrücklich gewählte** Basisordner — `nil`, solange in den
    /// Einstellungen nichts steht.
    ///
    /// Der Unterschied zu `basisordner` ist der ganze Zweck dieses Feldes:
    /// WhisperKit und MLX haben je einen eigenen Standardort. Wer beiden einen
    /// erfundenen gemeinsamen Pfad unterschiebt, bloß weil ein Ordner wählbar
    /// geworden ist, schickt jeden Bestandsnutzer in einen Multi-GB-Download.
    /// Deshalb: Ist hier nichts gesetzt, geht jeder Lader seinen bisherigen Weg.
    private(set) var gewaehlterBasisordner: URL?

    /// Der Ort, der gilt, solange nichts gewählt ist. Zur Laufzeit erfragt,
    /// nie fest verdrahtet (siehe `laden(aus:vorgabe:)`).
    private let vorgabeBasisordner: URL

    /// Wohin shout. selbst herunterlädt — immer ein konkreter Pfad.
    ///
    /// Oberfläche und `ModelStore` brauchen einen Ordner zum Anzeigen und
    /// Auflösen, auch wenn der Nutzer nie etwas eingestellt hat. Zum Weiterreichen
    /// an WhisperKit oder den Hub ist dagegen `gewaehlterBasisordner` das
    /// richtige Feld.
    ///
    /// **Nur lesbar, mit Absicht.** Ein Setter wäre eine Falle: Jede Zuweisung
    /// — auch `pfade.basisordner = pfade.basisordner` — machte aus der bloßen
    /// Vorgabe eine ausdrückliche Wahl. Eine Oberfläche, die beim Öffnen den
    /// angezeigten Wert zurückschreibt, löste damit still genau den
    /// Multi-GB-Neu-Download aus, den `gewaehlterBasisordner` verhindern soll.
    /// Änderungen laufen deshalb ausschließlich über `basisordnerWechseln(zu:)`,
    /// das den Gleichheitsfall abfängt.
    var basisordner: URL { gewaehlterBasisordner ?? vorgabeBasisordner }

    /// Fremde Ordner, in denen mitbenutzt wird. Reihenfolge = Vorrang.
    var suchordner: [URL]
    /// Zuletzt bekannter Pfad je Modell-Kennung. Nur dafür da, „nicht
    /// auffindbar" von „nie da gewesen" zu unterscheiden.
    var verknuepfungen: [String: URL]

    init(gewaehlterBasisordner: URL?,
         vorgabeBasisordner: URL,
         suchordner: [URL],
         verknuepfungen: [String: URL]) {
        self.gewaehlterBasisordner = gewaehlterBasisordner
        self.vorgabeBasisordner = vorgabeBasisordner
        self.suchordner = suchordner
        self.verknuepfungen = verknuepfungen
    }

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
    ///
    /// Ob der Wert gespeichert war oder aus `vorgabe` stammt, bleibt erhalten:
    /// `gewaehlterBasisordner` trägt genau diese Unterscheidung.
    static func laden(aus defaults: UserDefaults, vorgabe: () -> URL) -> ModelPaths {
        // isDirectory: true ist Pflicht, nicht Kosmetik: Ohne sie fehlt der
        // rekonstruierten URL der abschließende Schrägstrich, den `ordner(_:)`
        // in den Tests (und jeder andere Aufrufer) mitführt — zwei sonst
        // identische Ordner-URLs wären dann per `==` verschieden, solange der
        // Ordner nicht schon auf der Platte liegt.
        let gewaehlt = defaults.string(forKey: Schluessel.basis)
            .map { URL(fileURLWithPath: $0, isDirectory: true) }
        let such = (defaults.stringArray(forKey: Schluessel.such) ?? [])
            .map { URL(fileURLWithPath: $0, isDirectory: true) }
        let verknuepft = (defaults.dictionary(forKey: Schluessel.verknuepft) as? [String: String] ?? [:])
            .mapValues { URL(fileURLWithPath: $0, isDirectory: true) }
        return ModelPaths(gewaehlterBasisordner: gewaehlt,
                          vorgabeBasisordner: vorgabe(),
                          suchordner: such,
                          verknuepfungen: verknuepft)
    }

    func sichern(in defaults: UserDefaults) {
        // Nur eine echte Wahl wird geschrieben. Würde hier die Vorgabe landen,
        // wäre „nichts eingestellt" ab dem nächsten Start eine ausdrückliche
        // Wahl — und aus einem beiläufigen Sichern der Suchordner entstünde
        // genau der Neu-Download, den `gewaehlterBasisordner` verhindert.
        if let gewaehlterBasisordner {
            defaults.set(gewaehlterBasisordner.path, forKey: Schluessel.basis)
        } else {
            defaults.removeObject(forKey: Schluessel.basis)
        }
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
        gewaehlterBasisordner = neu
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
