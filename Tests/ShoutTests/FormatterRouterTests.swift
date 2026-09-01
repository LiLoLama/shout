import XCTest

/// Tests für den Aufbereitungs-Router.
///
/// Diese Prüfungen gab es vorher nicht, und zwar nicht aus Nachlässigkeit: Bis
/// zur Engine-Extraktion hing `Formatter` an MLX und lag deshalb nicht im
/// Testziel. Genau die Zusagen, auf die sich das Diktat verlässt — „niemals
/// blockieren", „nie stiller Inhaltsverlust" — waren damit unprüfbar.
final class FormatterRouterTests: XCTestCase {

    /// Baut einen Router auf eine feste Attrappe. Das Closure liefert immer
    /// dieselbe Instanz, damit der Test danach ihre Aufzeichnungen lesen kann.
    private func router(_ engine: StubTextEngine) -> Formatter {
        Formatter(makeEngine: { engine })
    }

    private let langesDiktat =
        "also ich wollte nur kurz sagen dass der Termin am Dienstag leider nicht "
      + "klappt weil ich da schon beim Zahnarzt bin"

    // MARK: - Kurze Diktate gehen gar nicht erst ans Modell

    /// Unter 40 Zeichen wird roh eingefügt. Das spart die LLM-Latenz — und wenn
    /// der Router hier trotzdem fragte, wäre bei einem Anbieter jedes „ja, passt"
    /// eine bezahlte Anfrage.
    func testKurzesDiktatErreichtDasModellNicht() async {
        let engine = StubTextEngine(fallback: "Sollte nie verwendet werden.")
        let formatter = router(engine)
        await formatter.load()

        let ergebnis = await formatter.format("Ja, passt so.", bundleID: nil)

        XCTAssertEqual(ergebnis, "Ja, passt so.")
        let prompts = await engine.recordedPrompts
        XCTAssertTrue(prompts.isEmpty, "Kurze Diktate dürfen keine Anfrage kosten")
    }

    /// Der Rohtext wird dabei getrimmt zurückgegeben, nicht unverändert.
    func testKurzesDiktatWirdGetrimmt() async {
        let formatter = router(StubTextEngine(fallback: "x"))
        await formatter.load()
        let ergebnis = await formatter.format("  Kurz und gut.  ", bundleID: nil)
        XCTAssertEqual(ergebnis, "Kurz und gut.")
    }

    // MARK: - Niemals blockieren

    /// Wirft die Engine (Netzfehler, kein Guthaben, Modell weg), kommt der
    /// Rohtext. Das ist die zentrale Zusage der App und gilt für einen Anbieter
    /// genauso wie für ein lokales Modell.
    func testFehlerDerEngineLiefertRohtext() async {
        let engine = StubTextEngine(answers: [nil])   // nil = wirft
        let formatter = router(engine)
        await formatter.load()

        let ergebnis = await formatter.format(langesDiktat, bundleID: nil)

        XCTAssertEqual(ergebnis, langesDiktat)
    }

    /// Ist keine Engine bereit, wird ebenfalls roh eingefügt — ohne Aufruf.
    func testNichtBereiteEngineLiefertRohtext() async {
        let engine = StubTextEngine(fallback: "Aufbereitet.", isReady: false)
        let formatter = router(engine)
        await formatter.load()

        let ergebnis = await formatter.format(langesDiktat, bundleID: nil)

        XCTAssertEqual(ergebnis, langesDiktat)
        let prompts = await engine.recordedPrompts
        XCTAssertTrue(prompts.isEmpty)
    }

    /// Leere Antwort ist kein Ergebnis, sondern ein Fehlschlag.
    func testLeereAntwortLiefertRohtext() async {
        let formatter = router(StubTextEngine(fallback: "   "))
        await formatter.load()
        let ergebnis = await formatter.format(langesDiktat, bundleID: nil)
        XCTAssertEqual(ergebnis, langesDiktat)
    }

    // MARK: - Der Kürzungs-Schutz greift auch bei fremden Modellen

    /// Antwortet das Modell auf das Diktat, statt es zu formatieren, verwirft der
    /// Router die Ausgabe. Der Test steht hier und nicht nur bei
    /// `FormattingGuardTests`, weil erst er belegt, dass der Router den Wächter
    /// tatsächlich anwendet — und damit auch für ein Cloud-Modell, das dazu
    /// deutlich mehr neigt als das lokale.
    func testAntwortStattFormatierungWirdVerworfen() async {
        let diktat = "Könntest du bitte im Internet nach dem Logo suchen und es dann "
                   + "in die Präsentation einfügen, danke"
        let engine = StubTextEngine(fallback: "Bitte gib mir den Text, den ich formatieren "
                                           + "soll. Ich kann keine Logos aus dem Internet suchen.")
        let formatter = router(engine)
        await formatter.load()

        let ergebnis = await formatter.format(diktat, bundleID: nil)

        XCTAssertEqual(ergebnis, diktat)
        let prompts = await engine.recordedPrompts
        XCTAssertEqual(prompts.count, 1, "Das Modell wurde gefragt, die Antwort dann verworfen")
    }

    /// Verschluckt das Modell den halben Abschnitt, gilt derselbe Rückfall.
    ///
    /// Das Diktat muss dafür mindestens 30 Wörter haben: Darunter prüft
    /// `FormattingGuard` die Länge absichtlich nicht, weil legitimes Bereinigen
    /// bei kurzen Diktaten schnell die halbe Wortzahl kostet.
    func testStarkGekuerzteAusgabeWirdVerworfen() async {
        let diktat =
            "also ich wollte nur kurz sagen dass der Termin am Dienstag leider nicht "
          + "klappt weil ich da schon beim Zahnarzt bin und danach muss ich noch zur "
          + "Post und dann hole ich die Kinder ab also frag am besten nochmal nach "
          + "einem anderen Tag in der Woche"
        XCTAssertGreaterThanOrEqual(diktat.split(whereSeparator: \.isWhitespace).count, 30)

        let engine = StubTextEngine(fallback: "Der Termin am Dienstag klappt nicht.")
        let formatter = router(engine)
        await formatter.load()

        let ergebnis = await formatter.format(diktat, bundleID: nil)

        XCTAssertEqual(ergebnis, diktat)
    }

    // MARK: - Abschnittsgröße kommt von der Engine

    /// Ein Modell mit großem Kontextfenster soll größere Stücke bekommen: weniger
    /// Aufrufe heißt bei einem Anbieter weniger Latenz und weniger Kosten.
    /// Derselbe Text muss deshalb je Engine unterschiedlich oft anfragen.
    func testGrosseAbschnitteErgebenWenigerAufrufe() async {
        let text = String(repeating: "Das ist ein vollständiger Satz zum Auffüllen. ", count: 120)

        let klein = StubTextEngine(fallback: "unbrauchbar", chunkTargetLength: 1500, chunkMinLength: 1000)
        let kleinerRouter = router(klein)
        await kleinerRouter.load()
        _ = await kleinerRouter.format(text, bundleID: nil)
        let kleineAufrufe = await klein.recordedPrompts.count

        let gross = StubTextEngine(fallback: "unbrauchbar", chunkTargetLength: 6000, chunkMinLength: 4000)
        let grosserRouter = router(gross)
        await grosserRouter.load()
        _ = await grosserRouter.format(text, bundleID: nil)
        let grosseAufrufe = await gross.recordedPrompts.count

        XCTAssertGreaterThan(kleineAufrufe, 1, "Der Text muss überhaupt geschnitten worden sein")

        XCTAssertGreaterThan(kleineAufrufe, grosseAufrufe,
                             "Die Engine bestimmt die Abschnittsgröße, nicht der Router")
    }

    // MARK: - Protokolle

    /// Ohne bereites Modell gibt es `nil`, nicht den Rohtext. Sonst stünden in der
    /// Oberfläche zwei identische Fassungen, und das sieht nach einem kaputten
    /// Protokoll aus.
    func testProtokollOhneModellIstNil() async {
        let formatter = router(StubTextEngine(fallback: "x", isReady: false))
        await formatter.load()
        let ergebnis = await formatter.minutes(from: langesDiktat)
        XCTAssertNil(ergebnis)
    }

    /// Leere Eingabe ergibt ebenfalls `nil`.
    func testProtokollAusLeeremTranskriptIstNil() async {
        let formatter = router(StubTextEngine(fallback: "x"))
        await formatter.load()
        let ergebnis = await formatter.minutes(from: "   ")
        XCTAssertNil(ergebnis)
    }

    /// Beim Protokoll darf der Kürzungs-Schutz NICHT greifen — eine
    /// Zusammenfassung ist naturgemäß kürzer als ihre Eingabe. Der Test hält das
    /// fest, weil ein späterer „Vereinheitlichungs"-Umbau genau hier Schaden
    /// anrichten würde.
    func testProtokollWirdNichtVomKuerzungsschutzVerworfen() async {
        let antwort = """
        TITEL: Terminabsage
        PUNKTE:
        - Dienstag klappt nicht
        TEXT:
        Der Termin am Dienstag klappt nicht.
        """
        let formatter = router(StubTextEngine(fallback: antwort))
        await formatter.load()

        let ergebnis = await formatter.minutes(from: langesDiktat)

        XCTAssertNotNil(ergebnis)
        XCTAssertTrue(ergebnis?.contains("Dienstag") == true)
    }

    // MARK: - Zustand für die Oberfläche

    func testAktivesModellHeisstStrichSolangeNichtBereit() async {
        let formatter = router(StubTextEngine(fallback: "x", isReady: false,
                                             displayName: "Irgendwas"))
        await formatter.load()
        let name = await formatter.activeModelName
        XCTAssertEqual(name, "—")
    }

    func testAktivesModellZeigtDenAnzeigenamenDerEngine() async {
        let formatter = router(StubTextEngine(fallback: "x", displayName: "GPT-5 mini · OpenRouter"))
        await formatter.load()
        let name = await formatter.activeModelName
        XCTAssertEqual(name, "GPT-5 mini · OpenRouter")
    }

    /// `reload` muss die Engine NEU bauen, nicht nur neu laden — beim Wechsel
    /// zwischen „auf diesem Gerät" und einem Anbieter ändert sich die Art der
    /// Engine, nicht nur das Modell.
    func testReloadBautDieEngineNeu() async {
        var gebaut = 0
        let formatter = Formatter(makeEngine: {
            gebaut += 1
            return StubTextEngine(fallback: "x")
        })
        await formatter.load()
        await formatter.reload()
        XCTAssertEqual(gebaut, 2)
    }

    /// Ein zweites `load` baut dagegen nichts neu und lädt nicht doppelt.
    func testZweitesLoadBautNichtsNeu() async {
        var gebaut = 0
        let formatter = Formatter(makeEngine: {
            gebaut += 1
            return StubTextEngine(fallback: "x")
        })
        await formatter.load()
        await formatter.load()
        XCTAssertEqual(gebaut, 1)
    }
}
