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

    /// Was das Durchsuchen gefunden hat: Kennung → Pfad.
    ///
    /// Bewusst getrennt von `verknuepfungen`, obwohl beide gleich aussehen:
    /// Eine Verknüpfung sagt „das hier wurde benutzt und kann verschwinden",
    /// ein Fund sagt „das hier liegt dort, auch wenn keine berechenbare Form
    /// darauf zeigt". Aus einem Fund darf nie `nichtAuffindbar` werden — sonst
    /// machte ein aufgeräumter fremder Ordner aus einem nie benutzten Modell
    /// ein vermeintlich verschwundenes.
    var funde: [String: URL]

    init(gewaehlterBasisordner: URL?,
         vorgabeBasisordner: URL,
         suchordner: [URL],
         verknuepfungen: [String: URL],
         funde: [String: URL] = [:]) {
        self.gewaehlterBasisordner = gewaehlterBasisordner
        self.vorgabeBasisordner = vorgabeBasisordner
        self.suchordner = suchordner
        self.verknuepfungen = verknuepfungen
        self.funde = funde
    }

    private enum Schluessel {
        static let basis = "modelBaseDirectory"
        static let such = "modelSearchDirectories"
        static let verknuepft = "modelLinks"
        static let funde = "modelFinds"
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
        let gefunden = (defaults.dictionary(forKey: Schluessel.funde) as? [String: String] ?? [:])
            .mapValues { URL(fileURLWithPath: $0, isDirectory: true) }
        return ModelPaths(gewaehlterBasisordner: gewaehlt,
                          vorgabeBasisordner: vorgabe(),
                          suchordner: such,
                          verknuepfungen: verknuepft,
                          funde: gefunden)
    }

    /// Sichert die **Einstellungen**: Basisordner, Suchordner, gemerkte Funde.
    ///
    /// Die Verknüpfungen fasst diese Fassung mit Absicht NICHT an. Sie werden
    /// woanders geschrieben — `ShoutDownloader` merkt mitten in einem Download
    /// über `ModelPaths.verknuepfungMerken(_:pfad:in:)`, dass ein fremder
    /// Ordner mitbenutzt wurde. Ein Aufrufer mit einem älteren Stand in der
    /// Hand (die Modelle-Seite hält `pfade` als `@State`-Schnappschuss)
    /// schriebe seine veralteten Verknüpfungen darüber und löschte damit
    /// genau den Eintrag, der ein verschwundenes Fremdmodell als
    /// `nichtAuffindbar` statt `nichtVorhanden` ausweist — die Oberfläche böte
    /// für eine bloß abgezogene Platte einen Multi-GB-Download an.
    ///
    /// Zwei Wege wären möglich gewesen: die Oberfläche vor jedem Sichern neu
    /// laden lassen, oder diese Fassung die Verknüpfungen gar nicht anfassen
    /// lassen. Es ist der zweite geworden, weil er der schwerer falsch zu
    /// benutzende ist: Das Neuladen müsste jeder künftige Aufrufer von sich
    /// aus wieder mitbringen, und ein vergessenes Neuladen fällt erst auf,
    /// wenn eine Platte fehlt. Hier dagegen gibt es für die Verknüpfungen nur
    /// noch einen Schreibweg — `verknuepfungenSichern(in:)` bzw. die statische
    /// Kurzfassung —, und wer ihn nicht nimmt, kann nichts kaputt machen.
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
        defaults.set(funde.mapValues(\.path), forKey: Schluessel.funde)
    }

    /// Merkt sich, dass eine Kennung aus einem fremden Ordner benutzt wurde.
    ///
    /// Nur so kommt etwas in `verknuepfungen` — und nur deshalb kann
    /// `ModelStore.zustand(_:verknuepft:)` später `nichtAuffindbar` von
    /// `nichtVorhanden` unterscheiden. Eigene Downloads in den eigenen Ordner
    /// gehören hier NICHT hinein: Die findet die Suche von allein wieder, und
    /// ein Eintrag dafür machte aus einem selbst gelöschten Modell ein
    /// vermeintlich verschwundenes.
    mutating func verknuepfungMerken(_ kennung: String, pfad: URL) {
        verknuepfungen[kennung] = pfad
    }

    /// Übernimmt das Ergebnis eines Durchlaufs für **einen** Ordner.
    ///
    /// Die alten Funde aus genau diesem Ordner fallen vorher heraus: „Erneut
    /// durchsuchen" soll den Ordner abbilden, wie er jetzt ist, und nicht die
    /// Summe aller Durchläufe seit dem ersten. Funde aus anderen Ordnern
    /// bleiben unangetastet.
    mutating func fundeMerken(_ neue: [ModelFund], ausOrdner ordner: URL) {
        fundeVergessen(unter: ordner)
        for fund in neue { funde[fund.kennung] = fund.pfad }
    }

    /// Vergisst alle Funde, die unter `ordner` liegen — beim Entfernen eines
    /// Suchordners. Wer einen Ordner aus der Liste nimmt, will nicht, dass
    /// shout. weiter daraus lädt.
    mutating func fundeVergessen(unter ordner: URL) {
        funde = funde.filter { !ModelStore.istUnterhalb($0.value, ordner) }
    }

    /// Sichert **nur** die Verknüpfungen — der einzige Weg, auf dem sie
    /// überhaupt in die Einstellungen kommen (`sichern(in:)` fasst sie nicht
    /// an).
    ///
    /// Umgekehrt gilt dasselbe: Wer mitten in einem Download bloß einen Fund
    /// festhalten will, hat einen womöglich veralteten Stand in der Hand und
    /// würde über `sichern(in:)` eine inzwischen getroffene Wahl des Nutzers
    /// überschreiben. Diese Fassung fasst die anderen Schlüssel nicht an — die
    /// Zusage aus `basisordner` bleibt unangetastet.
    func verknuepfungenSichern(in defaults: UserDefaults) {
        defaults.set(verknuepfungen.mapValues(\.path), forKey: Schluessel.verknuepft)
    }

    /// Dasselbe für Aufrufer ohne eigenen `ModelPaths` — etwa `ShoutDownloader`
    /// mitten in einem `async` Download.
    ///
    /// Bewusst ohne `laden`/`sichern`: Die Kurzfassung kennt nur den einen
    /// Schlüssel und kann den Basisordner gar nicht erst anfassen, und sie
    /// braucht auch keine Vorgabe. Die Sperre hält zwei gleichzeitige Downloads
    /// auseinander, die sich sonst gegenseitig den Eintrag überschrieben.
    static func verknuepfungMerken(_ kennung: String, pfad: URL, in defaults: UserDefaults) {
        sperre.lock()
        defer { sperre.unlock() }
        var gemerkt = defaults.dictionary(forKey: Schluessel.verknuepft) as? [String: String] ?? [:]
        gemerkt[kennung] = pfad.path
        defaults.set(gemerkt, forKey: Schluessel.verknuepft)
    }

    private static let sperre = NSLock()

    /// Wechselt den Basisordner, **ohne etwas zu verschieben**.
    ///
    /// Der bisherige Ordner rutscht an die erste Stelle der Suchordner: Sonst
    /// gälten alle bisher geladenen Modelle mit einem Schlag als verschwunden,
    /// und shout. böte an, Gigabytes erneut zu laden, die schon da sind.
    /// Ein Umzug über Laufwerksgrenzen dauert Minuten und kann abbrechen —
    /// dafür ist der Gewinn zu klein.
    mutating func basisordnerWechseln(zu neu: URL) {
        let alt = basisordner
        // Ortsvergleiche laufen über `ModelStore.vergleichsform` — sonst gälten
        // `/tmp/x` und `/private/tmp/x` als zwei Ordner, und ein Wechsel auf
        // denselben Ordner in der anderen Schreibweise machte aus der Vorgabe
        // eine ausdrückliche Wahl und trüge sie zusätzlich als Suchordner ein.
        guard ModelStore.vergleichsform(alt) != ModelStore.vergleichsform(neu) else { return }
        gewaehlterBasisordner = neu
        // Der neue Basisordner darf nicht zusätzlich als Suchordner stehen,
        // sonst erschiene jedes Modell doppelt.
        suchordner.removeAll { ModelStore.vergleichsform($0) == ModelStore.vergleichsform(neu) }
        if !suchordner.contains(where: { ModelStore.vergleichsform($0) == ModelStore.vergleichsform(alt) }) {
            suchordner.insert(alt, at: 0)
        }
    }

    var store: ModelStore {
        ModelStore(basisordner: basisordner, suchordner: suchordner,
                   gemerkteFunde: funde)
    }
}
