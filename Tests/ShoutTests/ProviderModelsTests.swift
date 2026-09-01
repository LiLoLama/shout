import XCTest

final class ProviderModelsTests: XCTestCase {

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

    private func liste(_ ids: [String]) -> StubURLProtocol.Antwort {
        let eintraege = ids.map { "{\"id\":\"\($0)\",\"object\":\"model\"}" }.joined(separator: ",")
        return .init(body: Data("{\"object\":\"list\",\"data\":[\(eintraege)]}".utf8))
    }

    // MARK: - Modell-Liste

    func testListeWirdAlphabetischGeliefert() async throws {
        StubURLProtocol.antworten = [liste(["gpt-5", "gpt-4o", "gpt-5-mini"])]

        let ids = try await ProviderModels.fetch(config: config, key: "sk-x", needsKey: true,
                                                 session: StubURLProtocol.session())

        XCTAssertEqual(ids, ["gpt-4o", "gpt-5", "gpt-5-mini"])
    }

    func testListeGehtAnDieModelsAdresse() async throws {
        StubURLProtocol.antworten = [liste(["a"])]
        _ = try await ProviderModels.fetch(config: config, key: "sk-x", needsKey: true,
                                           session: StubURLProtocol.session())
        XCTAssertEqual(StubURLProtocol.anfragen.first?.request.url?.absoluteString,
                       "https://api.openai.com/v1/models")
    }

    /// Ein Anbieter ohne Schlüsselpflicht (Ollama) wird ohne Kopfzeile gefragt.
    func testOhneSchluesselpflichtKeineKopfzeile() async throws {
        StubURLProtocol.antworten = [liste(["gemma3:12b"])]
        _ = try await ProviderModels.fetch(
            config: RemoteConfig(templateID: "ollama", baseURL: "http://localhost:11434/v1",
                                 model: "gemma3:12b"),
            key: nil, needsKey: false, session: StubURLProtocol.session())
        XCTAssertNil(StubURLProtocol.anfragen.first?.request
            .value(forHTTPHeaderField: "Authorization"))
    }

    func testLeereListeIstEinFehler() async {
        StubURLProtocol.antworten = [liste([])]
        do {
            _ = try await ProviderModels.fetch(config: config, key: "sk-x", needsKey: true,
                                               session: StubURLProtocol.session())
            XCTFail("Eine leere Liste ist nicht verwertbar")
        } catch {
            XCTAssertEqual(error as? RemoteProviderError, .malformedResponse)
        }
    }

    func testAbgelehnterSchluesselBeiDerListe() async {
        StubURLProtocol.antworten = [.fehlerAntwort(status: 401)]
        do {
            _ = try await ProviderModels.fetch(config: config, key: "sk-falsch", needsKey: true,
                                               session: StubURLProtocol.session())
            XCTFail("401 muss durchschlagen")
        } catch {
            XCTAssertEqual(error as? RemoteProviderError, .unauthorized)
        }
    }

    // MARK: - Verbindungstest

    /// Der Normalfall: Verbindung steht, und das eingetragene Modell steht auch
    /// wirklich in der Liste.
    func testVerbindungStehtUndModellIstDabei() async {
        StubURLProtocol.antworten = [liste(["gpt-5", "gpt-5-mini"])]

        let ergebnis = await ProviderProbe.run(config: config, key: "sk-x", needsKey: true,
                                               session: StubURLProtocol.session())

        guard case .ok(_, let gelistet) = ergebnis else {
            return XCTFail("Erwartet: ok, war: \(ergebnis)")
        }
        XCTAssertEqual(gelistet, true)
    }

    /// Der interessante Fall: Alles verbindet, aber das Modell aus einer
    /// veralteten Vorlage gibt es dort nicht. Das muss die Oberfläche sagen
    /// können, statt „Verbindung steht" zu melden und beim ersten Diktat zu
    /// scheitern.
    func testVerbindungStehtAberModellFehlt() async {
        StubURLProtocol.antworten = [liste(["gpt-4o"])]

        let ergebnis = await ProviderProbe.run(config: config, key: "sk-x", needsKey: true,
                                               session: StubURLProtocol.session())

        guard case .ok(_, let gelistet) = ergebnis else {
            return XCTFail("Erwartet: ok, war: \(ergebnis)")
        }
        XCTAssertEqual(gelistet, false)
    }

    /// Kein `/models`-Endpunkt heißt nicht, dass der Anbieter kaputt ist. Dann
    /// gilt die Verbindung als in Ordnung, über das Modell ist aber nichts
    /// bekannt — und genau das wird gemeldet, nicht „alles gut".
    func testOhneModellListeGiltDieVerbindungAlsInOrdnung() async {
        StubURLProtocol.antworten = [.fehlerAntwort(status: 404, message: "Not Found")]

        let ergebnis = await ProviderProbe.run(config: config, key: "sk-x", needsKey: true,
                                               session: StubURLProtocol.session())

        guard case .ok(_, let gelistet) = ergebnis else {
            return XCTFail("Erwartet: ok, war: \(ergebnis)")
        }
        XCTAssertNil(gelistet)
    }

    /// Eine Antwort, die keine Liste ist (manche Server antworten mit HTML),
    /// zählt genauso: verbunden, aber nichts über das Modell bekannt.
    func testUnverwertbareAntwortGiltAlsVerbundenOhneModellwissen() async {
        StubURLProtocol.antworten = [.init(body: Data("<html>ok</html>".utf8))]

        let ergebnis = await ProviderProbe.run(config: config, key: "sk-x", needsKey: true,
                                               session: StubURLProtocol.session())

        guard case .ok(_, let gelistet) = ergebnis else {
            return XCTFail("Erwartet: ok, war: \(ergebnis)")
        }
        XCTAssertNil(gelistet)
    }

    func testFalscherSchluesselWirdGemeldet() async {
        StubURLProtocol.antworten = [.fehlerAntwort(status: 401)]
        let ergebnis = await ProviderProbe.run(config: config, key: "sk-falsch", needsKey: true,
                                               session: StubURLProtocol.session())
        XCTAssertEqual(ergebnis, .failed(.unauthorized))
    }

    /// Läuft der lokale Server nicht, ist das der häufigste Ollama-Fall — und
    /// muss als Verbindungsproblem erkennbar sein, nicht als Schlüsselproblem.
    func testNichtLaufenderLokalerServer() async {
        StubURLProtocol.antworten = [.init(error: URLError(.cannotConnectToHost))]
        let ergebnis = await ProviderProbe.run(
            config: RemoteConfig(templateID: "ollama", baseURL: "http://localhost:11434/v1",
                                 model: "gemma3:12b"),
            key: nil, needsKey: false, session: StubURLProtocol.session())

        guard case .failed(let fehler) = ergebnis else {
            return XCTFail("Erwartet: failed, war: \(ergebnis)")
        }
        guard case .cannotConnect = fehler else {
            return XCTFail("Erwartet: cannotConnect, war: \(fehler)")
        }
    }

    func testFehlenderSchluesselWirdVorDerAnfrageGemeldet() async {
        let ergebnis = await ProviderProbe.run(config: config, key: nil, needsKey: true,
                                               session: StubURLProtocol.session())
        XCTAssertEqual(ergebnis, .failed(.missingKey))
        XCTAssertTrue(StubURLProtocol.anfragen.isEmpty)
    }
}
