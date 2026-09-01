import XCTest

final class RemoteTextEngineTests: XCTestCase {

    private let config = RemoteConfig(templateID: "openai",
                                      baseURL: "https://api.openai.com/v1",
                                      model: "gpt-5-mini")

    override func setUp() {
        super.setUp()
        StubURLProtocol.reset()
    }

    override func tearDown() {
        StubURLProtocol.reset()
        super.tearDown()
    }

    private func engine(key: String? = "sk-testschluessel1234",
                        needsKey: Bool = true,
                        config: RemoteConfig? = nil) -> RemoteTextEngine {
        RemoteTextEngine(config: config ?? self.config,
                         key: key,
                         needsKey: needsKey,
                         providerName: "OpenAI",
                         session: StubURLProtocol.session(),
                         timeout: 5)
    }

    // MARK: - Der Normalfall

    func testAntwortWirdAusgepackt() async throws {
        StubURLProtocol.antworten = [.chatAntwort("Der Termin am Dienstag klappt nicht.")]

        let text = try await engine().respond(system: "Räum auf.", user: "also äh dienstag",
                                              temperature: 0.2)

        XCTAssertEqual(text, "Der Termin am Dienstag klappt nicht.")
    }

    /// Modell, Rollen und Temperatur müssen im Rumpf ankommen — sonst antwortet
    /// ein anderes Modell als eingestellt, und niemand merkt es.
    func testAnfrageEnthaeltModellRollenUndTemperatur() async throws {
        StubURLProtocol.antworten = [.chatAntwort("ok")]

        _ = try await engine().respond(system: "Systemanweisung", user: "Nutzertext",
                                       temperature: 0.2)

        let body = try XCTUnwrap(StubURLProtocol.anfragen.first?.body)
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["model"] as? String, "gpt-5-mini")
        XCTAssertEqual(json["temperature"] as? Double, 0.2)
        XCTAssertEqual(json["stream"] as? Bool, false)

        let messages = try XCTUnwrap(json["messages"] as? [[String: Any]])
        XCTAssertEqual(messages.count, 2)
        XCTAssertEqual(messages[0]["role"] as? String, "system")
        XCTAssertEqual(messages[0]["content"] as? String, "Systemanweisung")
        XCTAssertEqual(messages[1]["role"] as? String, "user")
        XCTAssertEqual(messages[1]["content"] as? String, "Nutzertext")
    }

    func testAnfrageGehtAnDieRichtigeAdresse() async throws {
        StubURLProtocol.antworten = [.chatAntwort("ok")]
        _ = try await engine().respond(system: "s", user: "u", temperature: 0.2)
        XCTAssertEqual(StubURLProtocol.anfragen.first?.request.url?.absoluteString,
                       "https://api.openai.com/v1/chat/completions")
        XCTAssertEqual(StubURLProtocol.anfragen.first?.request.httpMethod, "POST")
    }

    func testSchluesselGehtAlsBearerMit() async throws {
        StubURLProtocol.antworten = [.chatAntwort("ok")]
        _ = try await engine().respond(system: "s", user: "u", temperature: 0.2)
        let header = StubURLProtocol.anfragen.first?.request
            .value(forHTTPHeaderField: "Authorization")
        XCTAssertEqual(header, "Bearer sk-testschluessel1234")
    }

    // MARK: - Token-Zahlen werden übernommen, nicht geschätzt

    /// Die Kostenrechnung später darf nicht raten: Jede Antwort liefert die
    /// echten Zahlen mit.
    func testTokenZahlenWerdenUebernommen() async throws {
        StubURLProtocol.antworten = [.chatAntwort("ok", promptTokens: 321, completionTokens: 89)]

        let e = engine()
        _ = try await e.respond(system: "s", user: "u", temperature: 0.2)

        let usage = await e.lastUsage
        XCTAssertEqual(usage, TokenUsage(prompt: 321, completion: 89))
    }

    /// Manche Anbieter lassen `usage` weg. Dann gibt es keine Zahl — und keine
    /// erfundene.
    func testFehlendeTokenZahlenErgebenNil() async throws {
        let json = """
        {"choices":[{"message":{"role":"assistant","content":"ok"}}]}
        """
        StubURLProtocol.antworten = [.init(body: Data(json.utf8))]

        let e = engine()
        _ = try await e.respond(system: "s", user: "u", temperature: 0.2)

        let usage = await e.lastUsage
        XCTAssertNil(usage)
    }

    // MARK: - Fehler werden unterscheidbar

    func testAbgelehnterSchluessel() async {
        StubURLProtocol.antworten = [.fehlerAntwort(status: 401, message: "Invalid API key")]
        await erwarte(.unauthorized)
    }

    func testVerbotenGiltEbenfalsAlsSchluesselproblem() async {
        StubURLProtocol.antworten = [.fehlerAntwort(status: 403)]
        await erwarte(.unauthorized)
    }

    func testKeinGuthaben() async {
        StubURLProtocol.antworten = [.fehlerAntwort(status: 402, message: "Insufficient credits")]
        await erwarte(.noCredit)
    }

    /// 404 mit Modellhinweis ist ein unbekanntes Modell — die häufigste Ursache,
    /// wenn ein Modell aus einer veralteten Vorlage stammt.
    func testUnbekanntesModell() async {
        StubURLProtocol.antworten = [
            .fehlerAntwort(status: 404, message: "The model `gpt-5-mini` does not exist"),
        ]
        await erwarte(.unknownModel("gpt-5-mini"))
    }

    /// 404 ohne Modellhinweis ist dagegen eine falsche Adresse — und muss auch so
    /// gemeldet werden, sonst sucht man am falschen Ende.
    func testVierhundertvierOhneModellhinweisIstEinAdressfehler() async {
        StubURLProtocol.antworten = [.fehlerAntwort(status: 404, message: "Not Found")]
        await erwarte(.http(status: 404))
    }

    func testRatenlimitMitWartezeit() async {
        StubURLProtocol.antworten = [
            .fehlerAntwort(status: 429, message: "Rate limit reached",
                           headers: ["Retry-After": "12"]),
        ]
        await erwarte(.rateLimited(retryAfter: 12))
    }

    func testRatenlimitOhneWartezeit() async {
        StubURLProtocol.antworten = [.fehlerAntwort(status: 429)]
        await erwarte(.rateLimited(retryAfter: nil))
    }

    func testServerfehler() async {
        StubURLProtocol.antworten = [.fehlerAntwort(status: 503)]
        await erwarte(.http(status: 503))
    }

    func testZeitueberschreitung() async {
        StubURLProtocol.antworten = [
            .init(error: URLError(.timedOut)),
        ]
        await erwarte(.timedOut)
    }

    /// Eine Antwort ohne `choices` darf nicht abstürzen und nicht als leerer Text
    /// durchgehen — das Diktat soll dann den Rohtext bekommen.
    func testAntwortOhneChoicesIstEinFehler() async {
        StubURLProtocol.antworten = [.init(body: Data("{\"id\":\"x\"}".utf8))]
        await erwarte(.malformedResponse)
    }

    func testKeinJSONIstEinFehler() async {
        StubURLProtocol.antworten = [.init(body: Data("<html>Gateway</html>".utf8))]
        await erwarte(.malformedResponse)
    }

    /// Leerer Inhalt ist kein Ergebnis.
    func testLeererInhaltIstEinFehler() async {
        StubURLProtocol.antworten = [.chatAntwort("")]
        await erwarte(.malformedResponse)
    }

    // MARK: - Kein Schlüssel, keine Anfrage

    /// Ohne Schlüssel wird gar nicht erst gefragt: Der Router fügt dann den
    /// Rohtext ein, statt in einen 401 zu laufen.
    func testOhneSchluesselWirdNichtGefragt() async {
        StubURLProtocol.antworten = [.chatAntwort("sollte nie kommen")]
        let e = engine(key: nil)

        let ready = await e.isReady
        XCTAssertFalse(ready)

        do {
            _ = try await e.respond(system: "s", user: "u", temperature: 0.2)
            XCTFail("Ohne Schlüssel muss der Aufruf werfen")
        } catch {
            XCTAssertEqual(error as? RemoteProviderError, .missingKey)
        }
        XCTAssertTrue(StubURLProtocol.anfragen.isEmpty, "Es darf keine Anfrage rausgegangen sein")
    }

    /// Ollama und LM Studio brauchen keinen — dort ist ohne Schlüssel alles gut.
    func testAnbieterOhneSchluesselpflichtIstBereit() async throws {
        StubURLProtocol.antworten = [.chatAntwort("ok")]
        let e = engine(key: nil, needsKey: false,
                       config: RemoteConfig(templateID: "ollama",
                                            baseURL: "http://localhost:11434/v1",
                                            model: "gemma3:12b"))
        let ready = await e.isReady
        XCTAssertTrue(ready)

        let text = try await e.respond(system: "s", user: "u", temperature: 0.2)
        XCTAssertEqual(text, "ok")
        XCTAssertNil(StubURLProtocol.anfragen.first?.request
            .value(forHTTPHeaderField: "Authorization"))
    }

    /// Eine unbrauchbare Basis-Adresse macht die Engine nicht bereit — sonst
    /// scheitert jedes Diktat einzeln, statt einmal sichtbar zu sein.
    func testUngueltigeAdresseMachtNichtBereit() async {
        let e = engine(config: RemoteConfig(templateID: "custom", baseURL: "unsinn", model: "x"))
        let ready = await e.isReady
        XCTAssertFalse(ready)
    }

    // MARK: - Nichts laden, nichts aufwärmen

    /// Aufwärmen wäre bei einem Anbieter eine bezahlte Anfrage ohne Nutzen.
    func testAufwaermenStelltKeineAnfrage() async {
        let e = engine()
        await e.prepare(reset: false, onProgress: nil)
        await e.warmUp()
        XCTAssertTrue(StubURLProtocol.anfragen.isEmpty)
    }

    /// Größere Abschnitte als lokal: weniger Aufrufe, weniger Latenz, weniger
    /// Kosten.
    func testGroessereAbschnitteAlsLokal() async {
        let e = engine()
        let ziel = await e.chunkTargetLength
        let minimum = await e.chunkMinLength
        XCTAssertGreaterThan(ziel, 1500)
        XCTAssertGreaterThan(minimum, 1000)
        XCTAssertLessThan(minimum, ziel)
    }

    /// Der Anzeigename nennt Modell und Anbieter, damit im Dashboard steht,
    /// woher der Text kommt.
    func testAnzeigenameNenntModellUndAnbieter() async {
        let name = await engine().displayName
        XCTAssertEqual(name, "gpt-5-mini · OpenAI")
    }

    // MARK: - Hilfsmittel

    private func erwarte(_ erwartet: RemoteProviderError,
                         file: StaticString = #filePath, line: UInt = #line) async {
        do {
            _ = try await engine().respond(system: "s", user: "u", temperature: 0.2)
            XCTFail("Es hätte ein Fehler kommen müssen", file: file, line: line)
        } catch {
            XCTAssertEqual(error as? RemoteProviderError, erwartet, file: file, line: line)
        }
    }
}
