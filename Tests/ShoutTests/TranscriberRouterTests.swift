import XCTest

/// Tests für den Erkennungs-Router.
///
/// Auch diese Prüfungen gab es vorher nicht: `Transcriber` hing an WhisperKit
/// und lag nicht im Testziel. Der Plausibilitäts-Wachhund war einzeln geprüft
/// (`TranscriptPlausibilityTests`), aber nicht die Frage, ob der Router ihn
/// überhaupt anwendet — und ob er ihn bei Dateien richtigerweise NICHT anwendet.
final class TranscriberRouterTests: XCTestCase {

    private func router(_ engine: StubSpeechEngine) -> Transcriber {
        Transcriber(makeEngine: { engine })
    }

    /// Wie `router`, aber schon geladen. Ohne `load` gibt es keine Engine, und
    /// `transcribe` wirft dann `notLoaded` — was `testOhneGeladeneEngineWirft…`
    /// ausdrücklich prüft.
    private func loadedRouter(_ engine: StubSpeechEngine) async throws -> Transcriber {
        let transcriber = router(engine)
        try await transcriber.load()
        return transcriber
    }

    /// 16 kHz Mono — so kommen die Samples aus `AudioRecorder`.
    private func samples(seconds: Double) -> [Float] {
        [Float](repeating: 0, count: Int(seconds * 16_000))
    }

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: "transcriptionLanguage")
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: "transcriptionLanguage")
        super.tearDown()
    }

    // MARK: - Sprachwahl trifft der Router

    /// Ohne Einstellung gilt Deutsch — dieselbe Vorgabe wie bisher.
    func testOhneEinstellungWirdDeutschGewaehlt() async throws {
        let engine = StubSpeechEngine(result: SpeechResult(text: "Hallo", segments: []))
        _ = try await loadedRouter(engine).transcribe(samples(seconds: 1))
        let sprache = await engine.lastLanguage
        XCTAssertEqual(sprache, .some("de"))
    }

    /// „auto" wird zu `nil` — die Engine erkennt dann selbst. Das ist die
    /// Übersetzung, die vorher in den WhisperKit-Optionen steckte.
    func testAutomatischWirdZuNil() async throws {
        UserDefaults.standard.set("auto", forKey: "transcriptionLanguage")
        let engine = StubSpeechEngine(result: SpeechResult(text: "Hallo", segments: []))
        _ = try await loadedRouter(engine).transcribe(samples(seconds: 1))
        let sprache = await engine.lastLanguage
        XCTAssertEqual(sprache, .some(nil))
    }

    func testEingestellteSpracheWirdDurchgereicht() async throws {
        UserDefaults.standard.set("en", forKey: "transcriptionLanguage")
        let engine = StubSpeechEngine(result: SpeechResult(text: "Hello", segments: []))
        _ = try await loadedRouter(engine).transcribe(samples(seconds: 1))
        let sprache = await engine.lastLanguage
        XCTAssertEqual(sprache, .some("en"))
    }

    /// Das Aufwärmen läuft mit derselben Sprache wie das echte Diktat: bei fester
    /// Sprache entfällt die Erkennungsstufe, und dann wärmt man sonst etwas
    /// anderes auf als das, was danach läuft.
    func testAufwaermenNutztDieselbeSprache() async throws {
        UserDefaults.standard.set("en", forKey: "transcriptionLanguage")
        let engine = StubSpeechEngine()
        let transcriber = router(engine)
        try await transcriber.load()
        await transcriber.warmUp()
        let sprache = await engine.lastWarmUpLanguage
        XCTAssertEqual(sprache, .some("en"))
    }

    // MARK: - Ohne Engine gibt es einen Fehler, keinen leeren Text

    func testOhneGeladeneEngineWirftTranscribe() async {
        let transcriber = Transcriber(makeEngine: { StubSpeechEngine() })
        do {
            _ = try await transcriber.transcribe(samples(seconds: 1))
            XCTFail("Ohne geladene Engine muss transcribe werfen")
        } catch {
            XCTAssertTrue(error is TranscriberError)
        }
    }

    /// Ein leeres Transkript darf NICHT als Fehler durchgehen — sonst wäre eine
    /// stille Aufnahme ein Absturzgrund.
    func testLeeresErgebnisIstKeinFehler() async throws {
        let engine = StubSpeechEngine(result: SpeechResult(text: "", segments: []))
        let text = try await loadedRouter(engine).transcribe(samples(seconds: 1))
        XCTAssertEqual(text, "")
    }

    // MARK: - Text und Segmente sind zwei Wege

    /// Das Diktat nimmt `text`, die Datei-Transkription die Segmente. Die beiden
    /// dürfen sich unterscheiden (WhisperKit filtert die Steuermarken in beiden
    /// unterschiedlich) — der Router darf sie nicht ineinander umrechnen.
    func testDiktatNutztTextUndDateiNutztSegmente() async throws {
        let engine = StubSpeechEngine(result: SpeechResult(
            text: "Erster Satz. Zweiter Satz.",
            segments: [TranscriptSegment(text: "Erster Satz.", start: 0, end: 2),
                       TranscriptSegment(text: "Zweiter Satz.", start: 2, end: 4)]))
        let transcriber = try await loadedRouter(engine)

        let text = try await transcriber.transcribe(samples(seconds: 4))
        let segmente = try await transcriber.transcribeSegments(samples(seconds: 4))

        XCTAssertEqual(text, "Erster Satz. Zweiter Satz.")
        XCTAssertEqual(segmente.count, 2)
        XCTAssertEqual(segmente.first?.start, 0)
        XCTAssertEqual(segmente.last?.end, 4)
    }

    // MARK: - Der Wachhund wird angewandt — und bei Dateien nicht

    /// Der Fall aus dem Betrieb: Whisper beginnt erst bei Sekunde 40 von 104. Der
    /// Router muss das bemerken (Logausgabe), den Text aber unverändert
    /// zurückgeben — der Wachhund repariert nichts, er meldet nur.
    func testVerschluckterAnfangAendertDenTextNicht() async throws {
        let engine = StubSpeechEngine(result: SpeechResult(
            text: "nur der Rest des Diktats",
            segments: [TranscriptSegment(text: "nur der Rest des Diktats", start: 40, end: 104)]))

        let text = try await loadedRouter(engine).transcribe(samples(seconds: 104))

        XCTAssertEqual(text, "nur der Rest des Diktats")
    }

    /// Eine Datei mit langen Sprechpausen sieht für den Wachhund verdächtig aus,
    /// ist aber in Ordnung. `transcribeSegments` darf ihn deshalb nicht auslösen —
    /// hier festgehalten, damit eine späte „Vereinheitlichung" das nicht kaputt
    /// macht. Geprüft wird an der Wirkung: gleiche Eingabe, unveränderte Segmente.
    func testDateiTranskriptionLaeuftOhneWachhund() async throws {
        let engine = StubSpeechEngine(result: SpeechResult(
            text: "kurz",
            segments: [TranscriptSegment(text: "kurz", start: 55, end: 60)]))

        let segmente = try await loadedRouter(engine).transcribeSegments(samples(seconds: 600))

        XCTAssertEqual(segmente.count, 1)
        XCTAssertEqual(segmente.first?.text, "kurz")
    }

    // MARK: - Laden und Wechseln

    /// `reload` baut den Erkenner NEU — beim Wechsel zwischen „auf diesem Gerät"
    /// und einem Anbieter ändert sich die Art, nicht nur das Modell.
    func testReloadBautDenErkennerNeu() async throws {
        var gebaut = 0
        let transcriber = Transcriber(makeEngine: {
            gebaut += 1
            return StubSpeechEngine()
        })
        try await transcriber.load()
        try await transcriber.reload()
        XCTAssertEqual(gebaut, 2)
    }

    func testZweitesLoadBautNichtsNeu() async throws {
        var gebaut = 0
        let transcriber = Transcriber(makeEngine: {
            gebaut += 1
            return StubSpeechEngine()
        })
        try await transcriber.load()
        try await transcriber.load()
        XCTAssertEqual(gebaut, 1)
    }

    /// `load` lädt ohne Zurücksetzen, `reload` mit — das ist der Unterschied,
    /// über den die lokale Engine die Abkürzung „schon das richtige Modell
    /// geladen" nimmt.
    func testLoadOhneResetReloadMitReset() async throws {
        let engine = StubSpeechEngine()
        let transcriber = router(engine)
        try await transcriber.load()
        var reset = await engine.lastPrepareWasReset
        XCTAssertEqual(reset, false)
        try await transcriber.reload()
        reset = await engine.lastPrepareWasReset
        XCTAssertEqual(reset, true)
    }

    func testAktivesModellHeisstStrichSolangeNichtBereit() async throws {
        let transcriber = router(StubSpeechEngine(isReady: false, displayName: "Irgendwas"))
        try await transcriber.load()
        let name = await transcriber.activeModelName
        XCTAssertEqual(name, "—")
    }
}
