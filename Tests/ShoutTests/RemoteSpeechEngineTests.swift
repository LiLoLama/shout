import XCTest

final class RemoteSpeechEngineTests: XCTestCase {

    private let config = RemoteConfig(templateID: "groq",
                                      baseURL: "https://api.groq.com/openai/v1",
                                      model: "whisper-large-v3-turbo")

    override func setUp() {
        super.setUp()
        StubURLProtocol.reset()
    }

    override func tearDown() {
        StubURLProtocol.reset()
        super.tearDown()
    }

    /// Kleiner Takt und kleine Fenster, damit die Tests nicht Megabyte bauen.
    /// Die Logik rechnet in Sekunden und ist taktunabhängig.
    private func engine(key: String? = "gsk_testschluessel12",
                        needsKey: Bool = true,
                        maxWindowSeconds: Double = 10) -> RemoteSpeechEngine {
        RemoteSpeechEngine(config: config, key: key, needsKey: needsKey,
                           providerName: "Groq", session: StubURLProtocol.session(),
                           timeout: 5, maxWindowSeconds: maxWindowSeconds,
                           sampleRate: 1_000)
    }

    private func samples(_ sekunden: Double) -> [Float] {
        let anzahl = Int(sekunden * 1_000)
        return (0..<anzahl).map { $0 % 2 == 0 ? Float(0.4) : Float(-0.4) }
    }

    private func verboseAntwort(_ text: String,
                               _ segmente: [(Double, Double, String)]) -> StubURLProtocol.Antwort {
        let liste = segmente.map {
            "{\"start\":\($0.0),\"end\":\($0.1),\"text\":\"\($0.2)\"}"
        }.joined(separator: ",")
        let json = "{\"text\":\"\(text)\",\"segments\":[\(liste)]}"
        return .init(body: Data(json.utf8))
    }

    // MARK: - Der Normalfall

    func testSegmenteWerdenUebernommen() async throws {
        StubURLProtocol.antworten = [
            verboseAntwort("Erster Satz. Zweiter Satz.",
                           [(0, 2, "Erster Satz."), (2, 4.5, "Zweiter Satz.")]),
        ]

        let ergebnis = try await engine().transcribe(samples: samples(5), language: "de")

        XCTAssertEqual(ergebnis.text, "Erster Satz. Zweiter Satz.")
        XCTAssertEqual(ergebnis.segments.count, 2)
        XCTAssertEqual(ergebnis.segments[0].start, 0)
        XCTAssertEqual(ergebnis.segments[1].end, 4.5)
    }

    func testAnfrageGehtAnDieAudioAdresse() async throws {
        StubURLProtocol.antworten = [verboseAntwort("ok", [(0, 1, "ok")])]
        _ = try await engine().transcribe(samples: samples(2), language: "de")
        XCTAssertEqual(StubURLProtocol.anfragen.first?.request.url?.absoluteString,
                       "https://api.groq.com/openai/v1/audio/transcriptions")
        XCTAssertEqual(StubURLProtocol.anfragen.first?.request.httpMethod, "POST")
    }

    /// Modell, Format und Sprache müssen im Rumpf ankommen, und die WAV-Datei
    /// muss als solche erkennbar sein.
    func testMultipartRumpfEnthaeltAllesNoetige() async throws {
        StubURLProtocol.antworten = [verboseAntwort("ok", [(0, 1, "ok")])]
        _ = try await engine().transcribe(samples: samples(2), language: "de")

        let rumpf = try XCTUnwrap(StubURLProtocol.anfragen.first?.body)
        let text = String(decoding: rumpf.prefix(2_000), as: UTF8.self)
        XCTAssertTrue(text.contains("name=\"model\""))
        XCTAssertTrue(text.contains("whisper-large-v3-turbo"))
        XCTAssertTrue(text.contains("name=\"response_format\""))
        XCTAssertTrue(text.contains("verbose_json"))
        XCTAssertTrue(text.contains("name=\"language\""))
        XCTAssertTrue(text.contains("filename=\"audio.wav\""))
        XCTAssertTrue(text.contains("Content-Type: audio/wav"))
        XCTAssertTrue(rumpf.range(of: Data("RIFF".utf8)) != nil, "Die WAV-Daten fehlen")
    }

    /// Bei „automatisch" wird gar kein Sprachfeld geschickt — dann erkennt der
    /// Anbieter selbst, genau wie das lokale Modell.
    func testOhneSpracheKeinSprachfeld() async throws {
        StubURLProtocol.antworten = [verboseAntwort("ok", [(0, 1, "ok")])]
        _ = try await engine().transcribe(samples: samples(2), language: nil)
        let rumpf = try XCTUnwrap(StubURLProtocol.anfragen.first?.body)
        let text = String(decoding: rumpf.prefix(2_000), as: UTF8.self)
        XCTAssertFalse(text.contains("name=\"language\""))
    }

    func testSchluesselGehtAlsBearerMit() async throws {
        StubURLProtocol.antworten = [verboseAntwort("ok", [(0, 1, "ok")])]
        _ = try await engine().transcribe(samples: samples(2), language: "de")
        XCTAssertEqual(StubURLProtocol.anfragen.first?.request
            .value(forHTTPHeaderField: "Authorization"), "Bearer gsk_testschluessel12")
    }

    // MARK: - Ohne Zeitmarken

    /// Liefert der Anbieter nur Fließtext, entsteht EIN Ersatzsegment über die
    /// ganze Länge. Diktat und .txt funktionieren damit, Untertitel nicht — das
    /// ist die bewusste Notlösung, und sie ist besser als eine erfundene
    /// Zeitmarke.
    func testOhneSegmenteEntstehtEinErsatzsegment() async throws {
        StubURLProtocol.antworten = [.init(body: Data("{\"text\":\"Nur Fließtext.\"}".utf8))]

        let ergebnis = try await engine().transcribe(samples: samples(7), language: "de")

        XCTAssertEqual(ergebnis.text, "Nur Fließtext.")
        XCTAssertEqual(ergebnis.segments.count, 1)
        XCTAssertEqual(ergebnis.segments.first?.start, 0)
        XCTAssertEqual(ergebnis.segments.first?.end ?? 0, 7, accuracy: 0.01)
    }

    /// Leerer Text ergibt kein Ersatzsegment — eine stille Aufnahme hat einfach
    /// keinen Inhalt.
    func testLeererTextErgibtKeinSegment() async throws {
        StubURLProtocol.antworten = [.init(body: Data("{\"text\":\"\"}".utf8))]
        let ergebnis = try await engine().transcribe(samples: samples(3), language: "de")
        XCTAssertEqual(ergebnis.text, "")
        XCTAssertTrue(ergebnis.segments.isEmpty)
    }

    /// Lehnt der Anbieter `verbose_json` ab (400), wird einmal mit `json`
    /// wiederholt. Sonst wäre die Transkription bei neueren Modellen unbenutzbar,
    /// die nur das einfache Format können.
    func testAbgelehntesFormatWirdEinmalMitJsonWiederholt() async throws {
        StubURLProtocol.antworten = [
            .fehlerAntwort(status: 400, message: "response_format verbose_json not supported"),
            .init(body: Data("{\"text\":\"Doch gegangen.\"}".utf8)),
        ]

        let ergebnis = try await engine().transcribe(samples: samples(4), language: "de")

        XCTAssertEqual(ergebnis.text, "Doch gegangen.")
        XCTAssertEqual(StubURLProtocol.anfragen.count, 2)
        let zweiter = String(decoding: StubURLProtocol.anfragen[1].body.prefix(2_000), as: UTF8.self)
        XCTAssertTrue(zweiter.contains("json"))
        XCTAssertFalse(zweiter.contains("verbose_json"))
    }

    // MARK: - Lange Aufnahmen

    /// 25 Sekunden bei Zehn-Sekunden-Fenstern: drei Anfragen, ein Ergebnis.
    func testLangeAufnahmeLaeuftInMehrerenFenstern() async throws {
        StubURLProtocol.antworten = [
            verboseAntwort("Teil eins.", [(0, 5, "Teil eins.")]),
            verboseAntwort("Teil zwei.", [(0, 5, "Teil zwei.")]),
            verboseAntwort("Teil drei.", [(0, 5, "Teil drei.")]),
        ]

        let ergebnis = try await engine(maxWindowSeconds: 10)
            .transcribe(samples: samples(25), language: "de")

        XCTAssertEqual(StubURLProtocol.anfragen.count, 3)
        XCTAssertEqual(ergebnis.text, "Teil eins. Teil zwei. Teil drei.")
        XCTAssertEqual(ergebnis.segments.count, 3)
    }

    /// **Der wichtigste Test hier.** Die Zeitmarken der späteren Fenster müssen
    /// um den Versatz verschoben sein, sonst beginnt in der .srt-Datei jeder
    /// Abschnitt wieder bei null.
    func testZeitmarkenWerdenUmDenVersatzVerschoben() async throws {
        StubURLProtocol.antworten = [
            verboseAntwort("eins", [(0, 5, "eins")]),
            verboseAntwort("zwei", [(0, 5, "zwei")]),
            verboseAntwort("drei", [(0, 5, "drei")]),
        ]

        let ergebnis = try await engine(maxWindowSeconds: 10)
            .transcribe(samples: samples(25), language: "de")

        let starts = ergebnis.segments.map(\.start)
        XCTAssertEqual(starts.count, 3)
        XCTAssertEqual(starts[0], 0, accuracy: 0.01)
        XCTAssertGreaterThan(starts[1], 5, "Zweites Fenster muss verschoben sein")
        XCTAssertGreaterThan(starts[2], starts[1], "Die Zeitmarken müssen steigen")
    }

    /// Ein dauerhaft scheiterndes Fenster lässt den ganzen Aufruf scheitern —
    /// keine stille Lücke im Transkript.
    func testScheiterndesFensterLaesstDenGanzenAufrufScheitern() async {
        StubURLProtocol.antworten = [
            verboseAntwort("Teil eins.", [(0, 5, "Teil eins.")]),
            .fehlerAntwort(status: 503),
            .fehlerAntwort(status: 503),
            verboseAntwort("Teil drei.", [(0, 5, "Teil drei.")]),
        ]

        do {
            _ = try await engine(maxWindowSeconds: 10)
                .transcribe(samples: samples(25), language: "de")
            XCTFail("Ein scheiterndes Fenster muss den Aufruf scheitern lassen")
        } catch {
            XCTAssertEqual(error as? RemoteProviderError, .http(status: 503))
        }
    }

    /// Die verschickten Sekunden werden mitgezählt — Transkription wird pro
    /// Minute abgerechnet, nicht pro Token.
    func testVerschickteSekundenWerdenGezaehlt() async throws {
        StubURLProtocol.antworten = [
            verboseAntwort("a", [(0, 5, "a")]),
            verboseAntwort("b", [(0, 5, "b")]),
            verboseAntwort("c", [(0, 5, "c")]),
        ]
        let e = engine(maxWindowSeconds: 10)
        _ = try await e.transcribe(samples: samples(25), language: "de")
        let sekunden = await e.sentSeconds
        XCTAssertEqual(sekunden, 25, accuracy: 0.05)
    }

    // MARK: - Bereitschaft und Fehler

    func testOhneSchluesselWirdNichtGefragt() async {
        let e = engine(key: nil)
        let ready = await e.isReady
        XCTAssertFalse(ready)
        do {
            _ = try await e.transcribe(samples: samples(2), language: "de")
            XCTFail("Ohne Schlüssel muss der Aufruf werfen")
        } catch {
            XCTAssertEqual(error as? RemoteProviderError, .missingKey)
        }
        XCTAssertTrue(StubURLProtocol.anfragen.isEmpty)
    }

    func testAbgelehnterSchluessel() async {
        StubURLProtocol.antworten = [.fehlerAntwort(status: 401)]
        do {
            _ = try await engine().transcribe(samples: samples(2), language: "de")
            XCTFail("401 muss durchschlagen")
        } catch {
            XCTAssertEqual(error as? RemoteProviderError, .unauthorized)
        }
    }

    func testAufwaermenStelltKeineAnfrage() async throws {
        let e = engine()
        try await e.prepare(reset: false, onProgress: nil)
        await e.warmUp(language: "de")
        XCTAssertTrue(StubURLProtocol.anfragen.isEmpty)
    }

    func testAnzeigenameNenntModellUndAnbieter() async {
        let name = await engine().displayName
        XCTAssertEqual(name, "whisper-large-v3-turbo · Groq")
    }
}
