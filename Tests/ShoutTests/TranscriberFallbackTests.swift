import XCTest

/// Tests für den Rückfall auf ein lokales Modell, wenn die Erkennung bei einem
/// Anbieter scheitert.
///
/// Die Richtung ist der Kern: **extern → lokal** ist immer unbedenklich, weil
/// dabei nichts das Gerät verlässt. Der umgekehrte Weg darf nie von selbst
/// passieren, und ein Test hält das fest.
final class TranscriberFallbackTests: XCTestCase {

    private func samples(_ sekunden: Double) -> [Float] {
        [Float](repeating: 0.2, count: Int(sekunden * 16_000))
    }

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: "transcriptionLanguage")
    }

    // MARK: - Der Rückfall greift

    /// Scheitert der Anbieter und liegt ein lokales Modell bereit, übernimmt es —
    /// ohne dass der Nutzer etwas merkt außer dass es funktioniert.
    func testLokalesModellUebernimmtBeiFehlerDesAnbieters() async throws {
        let anbieter = StubSpeechEngine(result: nil)          // wirft
        let lokal = StubSpeechEngine(result: SpeechResult(
            text: "Lokal erkannt.",
            segments: [TranscriptSegment(text: "Lokal erkannt.", start: 0, end: 2)]))

        let transcriber = Transcriber(makeEngine: { anbieter }, makeFallback: { lokal })
        try await transcriber.load()

        let text = try await transcriber.transcribe(samples(3))

        XCTAssertEqual(text, "Lokal erkannt.")
        let anbieterVersuche = await anbieter.transcribeCount
        let lokalVersuche = await lokal.transcribeCount
        XCTAssertEqual(anbieterVersuche, 1, "Der Anbieter wird zuerst gefragt")
        XCTAssertEqual(lokalVersuche, 1)
    }

    /// Auch für die Datei-Transkription mit Zeitmarken.
    func testRueckfallGiltAuchFuerSegmente() async throws {
        let anbieter = StubSpeechEngine(result: nil)
        let lokal = StubSpeechEngine(result: SpeechResult(
            text: "a b",
            segments: [TranscriptSegment(text: "a", start: 0, end: 1),
                       TranscriptSegment(text: "b", start: 1, end: 2)]))

        let transcriber = Transcriber(makeEngine: { anbieter }, makeFallback: { lokal })
        try await transcriber.load()

        let segmente = try await transcriber.transcribeSegments(samples(3))

        XCTAssertEqual(segmente.count, 2)
    }

    /// Der Rückfall wird EINMAL vorbereitet und danach weiterbenutzt — nicht bei
    /// jedem Diktat neu geladen.
    func testRueckfallWirdNurEinmalVorbereitet() async throws {
        let anbieter = StubSpeechEngine(result: nil)
        let lokal = StubSpeechEngine(result: SpeechResult(text: "ok", segments: []))

        let transcriber = Transcriber(makeEngine: { anbieter }, makeFallback: { lokal })
        try await transcriber.load()

        _ = try await transcriber.transcribe(samples(1))
        _ = try await transcriber.transcribe(samples(1))

        let vorbereitungen = await lokal.prepareCount
        XCTAssertEqual(vorbereitungen, 1, "Nicht bei jedem Diktat neu laden")
    }

    // MARK: - Wenn es keinen Rückfall gibt

    /// Ohne Rückfall (weil ohnehin lokal gearbeitet wird) schlägt der Fehler
    /// durch — das ist das bisherige Verhalten und muss so bleiben.
    func testOhneRueckfallSchlaegtDerFehlerDurch() async throws {
        let engine = StubSpeechEngine(result: nil)
        let transcriber = Transcriber(makeEngine: { engine })
        try await transcriber.load()

        do {
            _ = try await transcriber.transcribe(samples(1))
            XCTFail("Ohne Rückfall muss der Fehler durchschlagen")
        } catch {
            XCTAssertTrue(error is StubSpeechEngine.StubError)
        }
    }

    /// Liegt kein lokales Modell auf der Platte, ist der Rückfall nicht bereit —
    /// dann darf er nicht benutzt werden. `prepare` würde ohne Cache werfen; hier
    /// wird der Fall über `isReady == false` nachgebildet.
    func testNichtBereiterRueckfallWirdNichtBenutzt() async throws {
        let anbieter = StubSpeechEngine(result: nil)
        let lokal = StubSpeechEngine(result: SpeechResult(text: "sollte nie kommen",
                                                         segments: []),
                                     isReady: false)

        let transcriber = Transcriber(makeEngine: { anbieter }, makeFallback: { lokal })
        try await transcriber.load()

        do {
            _ = try await transcriber.transcribe(samples(1))
            XCTFail("Ohne bereites Ersatzmodell muss der Fehler durchschlagen")
        } catch {
            XCTAssertTrue(error is StubSpeechEngine.StubError)
        }
        let versuche = await lokal.transcribeCount
        XCTAssertEqual(versuche, 0, "Ein nicht geladenes Modell darf nicht gefragt werden")
    }

    /// **Wichtig für die Fehlermeldung:** Scheitert auch der Rückfall, muss der
    /// URSPRÜNGLICHE Fehler des Anbieters herauskommen. „Schlüssel abgelehnt"
    /// hilft weiter, „lokales Modell nicht gefunden" schickt den Nutzer ans
    /// falsche Ende — das lokale Modell war nie seine Absicht.
    func testBeiDoppeltemFehlerKommtDerFehlerDesAnbieters() async throws {
        let anbieter = FehlerSpeechEngine(fehler: RemoteProviderError.unauthorized)
        let lokal = StubSpeechEngine(result: nil)

        let transcriber = Transcriber(makeEngine: { anbieter }, makeFallback: { lokal })
        try await transcriber.load()

        do {
            _ = try await transcriber.transcribe(samples(1))
            XCTFail("Beide gescheitert — es muss werfen")
        } catch {
            XCTAssertEqual(error as? RemoteProviderError, .unauthorized,
                           "Es muss der Fehler des Anbieters sein, nicht der des Rückfalls")
        }
    }

    // MARK: - Nie in die andere Richtung

    /// Läuft die Erkennung lokal und scheitert, wird NICHT auf einen Anbieter
    /// ausgewichen. Der Weg nach draußen ist immer eine Entscheidung des Nutzers.
    func testEsGibtKeinenWegVonLokalNachAussen() async throws {
        let lokal = StubSpeechEngine(result: nil)
        // So baut EngineFactory es im lokalen Fall: gar kein Rückfall.
        let transcriber = Transcriber(makeEngine: { lokal }, makeFallback: { nil })
        try await transcriber.load()

        do {
            _ = try await transcriber.transcribe(samples(1))
            XCTFail("Muss werfen")
        } catch {
            XCTAssertTrue(error is StubSpeechEngine.StubError)
        }
    }
}

/// Attrappe, die einen bestimmten Fehler wirft.
private actor FehlerSpeechEngine: SpeechEngine {
    private let fehler: Error
    let isReady = true
    let displayName = "Fehler-Attrappe"

    init(fehler: Error) { self.fehler = fehler }

    func prepare(reset: Bool, onProgress: (@Sendable (Double) -> Void)?) async throws {}
    func warmUp(language: String?) async {}
    func transcribe(samples: [Float], language: String?) async throws -> SpeechResult {
        throw fehler
    }
}
