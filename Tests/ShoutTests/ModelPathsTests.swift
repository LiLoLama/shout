import XCTest

final class ModelPathsTests: XCTestCase {

    private var wurzel: URL!
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUpWithError() throws {
        wurzel = FileManager.default.temporaryDirectory
            .appendingPathComponent("shout-modelpaths-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: wurzel, withIntermediateDirectories: true)
        suiteName = "shout-test-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: wurzel)
        defaults.removePersistentDomain(forName: suiteName)
    }

    private func ordner(_ name: String) -> URL {
        wurzel.appendingPathComponent(name, isDirectory: true)
    }

    /// Der Wächter gegen einen unbeabsichtigten Neu-Download: Ohne Einstellung
    /// zeigt der Basisordner auf denselben Ort wie vor der Umstellung. Deshalb
    /// wird die Vorgabe zur Laufzeit erfragt, nicht fest geschrieben.
    func testOhneEinstellungGiltDieVorgabe() {
        let erwartet = ordner("hf-cache")
        let pfade = ModelPaths.laden(aus: defaults, vorgabe: { erwartet })
        XCTAssertEqual(pfade.basisordner, erwartet)
        XCTAssertTrue(pfade.suchordner.isEmpty)
    }

    func testGesicherteEinstellungUeberlebtDasLaden() {
        var pfade = ModelPaths.laden(aus: defaults, vorgabe: { self.ordner("vorgabe") })
        pfade.basisordnerWechseln(zu: ordner("platte"))
        pfade.suchordner = [ordner("lmstudio")]
        pfade.sichern(in: defaults)

        let neu = ModelPaths.laden(aus: defaults, vorgabe: { self.ordner("vorgabe") })
        XCTAssertEqual(neu.basisordner, ordner("platte"))
        XCTAssertEqual(neu.suchordner, [ordner("lmstudio")])
    }

    /// Ein Ordnerwechsel bewegt nichts. Der alte Ordner rutscht nach vorn in
    /// die Suchordner — sonst gälten alle bisherigen Modelle als verschwunden.
    func testOrdnerwechselMachtAltenZumErstenSuchordner() {
        var pfade = ModelPaths.laden(aus: defaults, vorgabe: { self.ordner("alt") })
        pfade.basisordnerWechseln(zu: ordner("neu"))
        XCTAssertEqual(pfade.basisordner, ordner("neu"))
        XCTAssertEqual(pfade.suchordner.first, ordner("alt"))
    }

    /// Zweimal derselbe Wechsel darf den Ordner nicht doppelt eintragen.
    func testOrdnerwechselDoppeltErzeugtKeineDoppelung() {
        var pfade = ModelPaths.laden(aus: defaults, vorgabe: { self.ordner("alt") })
        pfade.basisordnerWechseln(zu: ordner("neu"))
        pfade.basisordnerWechseln(zu: ordner("alt"))
        pfade.basisordnerWechseln(zu: ordner("neu"))
        XCTAssertEqual(pfade.basisordner, ordner("neu"))
        XCTAssertEqual(Set(pfade.suchordner).count, pfade.suchordner.count)
    }

    /// Der neue Basisordner darf nicht gleichzeitig als Suchordner stehen
    /// bleiben — sonst erschiene jedes Modell doppelt.
    func testNeuerBasisordnerVerlaesstDieSuchordner() {
        var pfade = ModelPaths.laden(aus: defaults, vorgabe: { self.ordner("alt") })
        pfade.suchordner = [ordner("neu"), ordner("lmstudio")]
        pfade.basisordnerWechseln(zu: ordner("neu"))
        XCTAssertFalse(pfade.suchordner.contains(ordner("neu")))
        XCTAssertTrue(pfade.suchordner.contains(ordner("lmstudio")))
    }

    /// Das eigentliche Versprechen: Wer nichts einstellt, merkt nichts. Ohne
    /// gespeicherte Einstellung gibt es keinen gewählten Ordner — nur so können
    /// WhisperKit und MLX bei ihrem jeweiligen Standardort bleiben, statt über
    /// einen erfundenen gemeinsamen Pfad Gigabytes erneut zu laden.
    func testOhneEinstellungGibtEsKeinenGewaehltenOrdner() {
        let pfade = ModelPaths.laden(aus: defaults, vorgabe: { self.ordner("hf-cache") })
        XCTAssertNil(pfade.gewaehlterBasisordner)
        // Anzeige und Auflösung brauchen trotzdem einen brauchbaren Pfad.
        XCTAssertEqual(pfade.basisordner, ordner("hf-cache"))
    }

    /// Nach dem Sichern ist die Wahl ausdrücklich — und überlebt das Laden.
    func testGesicherteWahlGiltAlsGewaehlt() {
        var pfade = ModelPaths.laden(aus: defaults, vorgabe: { self.ordner("vorgabe") })
        pfade.basisordnerWechseln(zu: ordner("platte"))
        pfade.sichern(in: defaults)

        let neu = ModelPaths.laden(aus: defaults, vorgabe: { self.ordner("vorgabe") })
        XCTAssertEqual(neu.gewaehlterBasisordner, ordner("platte"))
        XCTAssertEqual(neu.basisordner, ordner("platte"))
    }

    /// Ein Ordnerwechsel ist eine bewusste Wahl — auch ohne vorheriges Sichern.
    func testOrdnerwechselSetztDieWahl() {
        var pfade = ModelPaths.laden(aus: defaults, vorgabe: { self.ordner("alt") })
        XCTAssertNil(pfade.gewaehlterBasisordner)
        pfade.basisordnerWechseln(zu: ordner("neu"))
        XCTAssertEqual(pfade.gewaehlterBasisordner, ordner("neu"))
        XCTAssertEqual(pfade.basisordner, ordner("neu"))
    }

    /// Die Falle, gegen die `basisordner` nur noch lesbar ist: Eine Oberfläche,
    /// die beim Öffnen den angezeigten Wert zurückschreibt, darf aus der bloßen
    /// Vorgabe keine ausdrückliche Wahl machen — sonst zöge allein das Öffnen
    /// der Einstellungen den Multi-GB-Neu-Download nach sich.
    func testZurueckschreibenDesAngezeigtenWertesErzeugtKeineWahl() {
        var pfade = ModelPaths.laden(aus: defaults, vorgabe: { self.ordner("vorgabe") })
        pfade.basisordnerWechseln(zu: pfade.basisordner)
        XCTAssertNil(pfade.gewaehlterBasisordner)
        XCTAssertEqual(pfade.basisordner, ordner("vorgabe"))
        // Und die Vorgabe darf sich auch nicht als Suchordner einschleichen.
        XCTAssertTrue(pfade.suchordner.isEmpty)
    }

    /// Ohne Wechsel bleibt es bei der Vorgabe ohne Wahl — auch über das
    /// Sichern und Laden hinweg, und selbst wenn die Vorgabe sich ändert.
    func testOhneWechselBleibtEsBeiDerVorgabeOhneWahl() {
        var pfade = ModelPaths.laden(aus: defaults, vorgabe: { self.ordner("vorgabe") })
        XCTAssertNil(pfade.gewaehlterBasisordner)
        pfade.sichern(in: defaults)

        let neu = ModelPaths.laden(aus: defaults, vorgabe: { self.ordner("andere-vorgabe") })
        XCTAssertNil(neu.gewaehlterBasisordner)
        XCTAssertEqual(neu.basisordner, ordner("andere-vorgabe"))
    }

    /// Ein Sichern ohne eigene Wahl (etwa nur der Suchordner) darf die Vorgabe
    /// nicht heimlich zur Einstellung machen.
    func testSichernOhneWahlSchreibtKeinenBasisordner() {
        var pfade = ModelPaths.laden(aus: defaults, vorgabe: { self.ordner("vorgabe") })
        pfade.suchordner = [ordner("lmstudio")]
        pfade.sichern(in: defaults)

        let neu = ModelPaths.laden(aus: defaults, vorgabe: { self.ordner("andere-vorgabe") })
        XCTAssertNil(neu.gewaehlterBasisordner)
        XCTAssertEqual(neu.basisordner, ordner("andere-vorgabe"))
        XCTAssertEqual(neu.suchordner, [ordner("lmstudio")])
    }

    /// Die Verknüpfungen sind der einzige Unterschied zwischen „nicht
    /// auffindbar" und „nie da gewesen". Gehen sie beim Sichern verloren, böte
    /// shout. für ein bloß abgehängtes Laufwerk einen Neu-Download an.
    func testVerknuepfungenUeberlebenSichernUndLaden() {
        var pfade = ModelPaths.laden(aus: defaults, vorgabe: { self.ordner("vorgabe") })
        pfade.verknuepfungMerken("mlx-community/modell-a", pfad: ordner("platte/modell-a"))
        pfade.verknuepfungMerken("mlx-community/modell-b", pfad: ordner("lmstudio/modell-b"))
        pfade.verknuepfungenSichern(in: defaults)

        let neu = ModelPaths.laden(aus: defaults, vorgabe: { self.ordner("vorgabe") })
        XCTAssertEqual(neu.verknuepfungen,
                       ["mlx-community/modell-a": ordner("platte/modell-a"),
                        "mlx-community/modell-b": ordner("lmstudio/modell-b")])
    }

    /// Der Wächter gegen den Verlust: Die Oberfläche hält `pfade` als
    /// Schnappschuss. Merkt der Downloader währenddessen eine benutzte
    /// Fremdverknüpfung, darf ein späteres `sichern(in:)` aus dem alten Stand
    /// sie nicht wieder wegschreiben — sonst fiele ein verschwundenes
    /// Fremdmodell von `nichtAuffindbar` auf `nichtVorhanden` zurück, und die
    /// Oberfläche böte für eine bloß abgezogene Platte einen Multi-GB-Download
    /// an.
    func testSichernLoeschtGemerkteVerknuepfungenNicht() {
        // Der Stand, den die Oberfläche in der Hand hält: noch ohne Eintrag.
        var schnappschuss = ModelPaths.laden(aus: defaults, vorgabe: { self.ordner("vorgabe") })
        XCTAssertTrue(schnappschuss.verknuepfungen.isEmpty)

        // Währenddessen merkt der Downloader einen mitbenutzten fremden Ordner.
        ModelPaths.verknuepfungMerken("mlx-community/modell-a",
                                      pfad: ordner("lmstudio/modell-a"), in: defaults)

        // Und erst danach sichert die Oberfläche ihre Ordner-Einstellung.
        schnappschuss.suchordner = [ordner("lmstudio")]
        schnappschuss.sichern(in: defaults)

        let neu = ModelPaths.laden(aus: defaults, vorgabe: { self.ordner("vorgabe") })
        XCTAssertEqual(neu.suchordner, [ordner("lmstudio")])
        XCTAssertEqual(neu.verknuepfungen,
                       ["mlx-community/modell-a": ordner("lmstudio/modell-a")])
    }

    /// Der Wächter für den Weg aus dem Downloader: Ein Fund in einem fremden
    /// Ordner wird gemerkt, während der Nutzer nie einen Basisordner gewählt
    /// hat. Macht dieses Sichern aus der Vorgabe eine ausdrückliche Wahl, zieht
    /// es bei jedem Bestandsnutzer den Multi-GB-Neu-Download nach sich.
    func testVerknuepfungenSichernErzeugtKeineWahl() {
        var pfade = ModelPaths.laden(aus: defaults, vorgabe: { self.ordner("vorgabe") })
        pfade.verknuepfungMerken("mlx-community/modell-a", pfad: ordner("lmstudio/modell-a"))
        pfade.verknuepfungenSichern(in: defaults)

        let neu = ModelPaths.laden(aus: defaults, vorgabe: { self.ordner("andere-vorgabe") })
        XCTAssertNil(neu.gewaehlterBasisordner)
        XCTAssertEqual(neu.basisordner, ordner("andere-vorgabe"))
        XCTAssertEqual(neu.verknuepfungen,
                       ["mlx-community/modell-a": ordner("lmstudio/modell-a")])
    }

    /// Dasselbe für die Kurzfassung, die der Downloader benutzt: Sie ergänzt
    /// die vorhandenen Verknüpfungen und fasst sonst nichts an — weder eine
    /// getroffene Wahl noch die Suchordner.
    func testGemerkteVerknuepfungLaesstDieUebrigenEinstellungenInRuhe() {
        var pfade = ModelPaths.laden(aus: defaults, vorgabe: { self.ordner("vorgabe") })
        pfade.suchordner = [ordner("lmstudio")]
        pfade.verknuepfungMerken("mlx-community/modell-a", pfad: ordner("lmstudio/modell-a"))
        pfade.sichern(in: defaults)
        pfade.verknuepfungenSichern(in: defaults)

        ModelPaths.verknuepfungMerken("mlx-community/modell-b",
                                      pfad: ordner("platte/modell-b"), in: defaults)

        let neu = ModelPaths.laden(aus: defaults, vorgabe: { self.ordner("andere-vorgabe") })
        XCTAssertNil(neu.gewaehlterBasisordner)
        XCTAssertEqual(neu.basisordner, ordner("andere-vorgabe"))
        XCTAssertEqual(neu.suchordner, [ordner("lmstudio")])
        XCTAssertEqual(neu.verknuepfungen,
                       ["mlx-community/modell-a": ordner("lmstudio/modell-a"),
                        "mlx-community/modell-b": ordner("platte/modell-b")])
    }

    /// Die Funde des Durchsuchens müssen den Programmlauf überleben —
    /// sonst wäre „Erneut durchsuchen" bei jedem Start wieder nötig.
    func testFundeUeberlebenSichernUndLaden() {
        var pfade = ModelPaths.laden(aus: defaults, vorgabe: { self.ordner("vorgabe") })
        pfade.fundeMerken([ModelFund(kennung: "mlx-community/modell-a",
                                     pfad: ordner("archiv/tief/modell-a"),
                                     groesseBytes: 42)],
                          ausOrdner: ordner("archiv"))
        pfade.sichern(in: defaults)

        let neu = ModelPaths.laden(aus: defaults, vorgabe: { self.ordner("vorgabe") })
        XCTAssertEqual(neu.funde,
                       ["mlx-community/modell-a": ordner("archiv/tief/modell-a")])
        XCTAssertEqual(neu.store.gemerkteFunde, neu.funde)
    }

    /// „Erneut durchsuchen" bildet den Ordner ab, wie er jetzt ist: Was im
    /// zweiten Durchlauf fehlt, fällt heraus. Funde aus anderen Ordnern
    /// bleiben unangetastet.
    func testErneutesDurchsuchenErsetztNurDenEigenenOrdner() {
        var pfade = ModelPaths.laden(aus: defaults, vorgabe: { self.ordner("vorgabe") })
        pfade.fundeMerken([ModelFund(kennung: "mlx-community/modell-a",
                                     pfad: ordner("archiv/modell-a"), groesseBytes: 1),
                           ModelFund(kennung: "mlx-community/modell-b",
                                     pfad: ordner("archiv/modell-b"), groesseBytes: 1)],
                          ausOrdner: ordner("archiv"))
        pfade.fundeMerken([ModelFund(kennung: "mlx-community/modell-c",
                                     pfad: ordner("lmstudio/modell-c"), groesseBytes: 1)],
                          ausOrdner: ordner("lmstudio"))

        // Zweiter Durchlauf über „archiv": modell-b ist weg.
        pfade.fundeMerken([ModelFund(kennung: "mlx-community/modell-a",
                                     pfad: ordner("archiv/modell-a"), groesseBytes: 1)],
                          ausOrdner: ordner("archiv"))

        XCTAssertEqual(pfade.funde,
                       ["mlx-community/modell-a": ordner("archiv/modell-a"),
                        "mlx-community/modell-c": ordner("lmstudio/modell-c")])
    }

    /// Wer einen Suchordner entfernt, will nicht, dass shout. weiter daraus
    /// lädt — auch nicht über einen gemerkten Fund.
    func testEntfernterOrdnerVerliertSeineFunde() {
        var pfade = ModelPaths.laden(aus: defaults, vorgabe: { self.ordner("vorgabe") })
        pfade.fundeMerken([ModelFund(kennung: "mlx-community/modell-a",
                                     pfad: ordner("archiv/modell-a"), groesseBytes: 1)],
                          ausOrdner: ordner("archiv"))
        pfade.fundeMerken([ModelFund(kennung: "mlx-community/modell-c",
                                     pfad: ordner("lmstudio/modell-c"), groesseBytes: 1)],
                          ausOrdner: ordner("lmstudio"))

        pfade.fundeVergessen(unter: ordner("archiv"))
        XCTAssertEqual(pfade.funde,
                       ["mlx-community/modell-c": ordner("lmstudio/modell-c")])
    }

    /// Ein ähnlich benannter Nachbarordner darf beim Entfernen nicht
    /// mitgenommen werden.
    func testVergessenTrifftNurDenEigenenOrdner() {
        var pfade = ModelPaths.laden(aus: defaults, vorgabe: { self.ordner("vorgabe") })
        pfade.fundeMerken([ModelFund(kennung: "mlx-community/modell-a",
                                     pfad: ordner("archiv-alt/modell-a"), groesseBytes: 1)],
                          ausOrdner: ordner("archiv-alt"))
        pfade.fundeVergessen(unter: ordner("archiv"))
        XCTAssertEqual(pfade.funde,
                       ["mlx-community/modell-a": ordner("archiv-alt/modell-a")])
    }

    func testStoreUebernimmtReihenfolge() {
        var pfade = ModelPaths.laden(aus: defaults, vorgabe: { self.ordner("basis") })
        pfade.suchordner = [ordner("a"), ordner("b")]
        XCTAssertEqual(pfade.store.orteInReihenfolge,
                       [ordner("basis"), ordner("a"), ordner("b")])
    }
}
