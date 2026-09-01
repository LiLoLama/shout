import XCTest

@MainActor
final class ProviderCostsTests: XCTestCase {

    private var verzeichnis: URL!

    override func setUp() {
        super.setUp()
        verzeichnis = FileManager.default.temporaryDirectory
            .appendingPathComponent("shout-kosten-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: verzeichnis, withIntermediateDirectories: true)
        StubURLProtocol.reset()
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: verzeichnis)
        StubURLProtocol.reset()
        super.tearDown()
    }

    private func store() -> ProviderUsageStore { ProviderUsageStore(directory: verzeichnis) }

    private func datum(_ text: String) -> Date {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "Europe/Berlin")
        return f.date(from: text)!
    }

    // MARK: - Preistabelle

    func testPreisWirdGenauGefunden() {
        let preis = PriceTable.bundled.price(forText: "gpt-5-mini")
        XCTAssertEqual(preis?.input, 0.25)
        XCTAssertEqual(preis?.output, 2.00)
    }

    /// OpenRouter nennt dasselbe Modell „openai/gpt-5-mini", OpenAI selbst nur
    /// „gpt-5-mini". Ohne diesen zweiten Versuch wäre die halbe Tabelle nutzlos.
    func testPreisOhneOrganisationsvorsilbe() {
        XCTAssertEqual(PriceTable.bundled.price(forText: "openai/gpt-5-mini")?.input, 0.25)
    }

    func testGrossKleinschreibungIstEgal() {
        XCTAssertNotNil(PriceTable.bundled.price(forText: "GPT-5-Mini"))
    }

    /// **Es wird keine Zahl erfunden.** Eine falsche Kostenanzeige ist schlimmer
    /// als keine.
    func testUnbekanntesModellHatKeinenPreis() {
        XCTAssertNil(PriceTable.bundled.price(forText: "gibtesnicht-9000"))
        XCTAssertNil(ProviderCosts.cost(tokens: TokenCount(prompt: 1000, completion: 500),
                                        price: nil))
    }

    func testAudioPreisJeMinute() {
        let preis = PriceTable.bundled.price(forAudio: "whisper-large-v3-turbo")
        XCTAssertEqual(preis?.perMinute, 0.00067)
    }

    // MARK: - Rechnung

    /// Eine Million Eingabe-Token bei 0,25 $/Mio. sind genau 25 Cent.
    func testTextkostenRechnung() {
        let kosten = ProviderCosts.cost(tokens: TokenCount(prompt: 1_000_000, completion: 0),
                                        price: ModelPrice(input: 0.25, output: 2.00))
        XCTAssertEqual(kosten ?? 0, 0.25, accuracy: 0.0000001)
    }

    func testEinUndAusgabeWerdenGetrenntGerechnet() {
        let kosten = ProviderCosts.cost(tokens: TokenCount(prompt: 500_000, completion: 250_000),
                                        price: ModelPrice(input: 0.20, output: 4.00))
        XCTAssertEqual(kosten ?? 0, 0.1 + 1.0, accuracy: 0.0000001)
    }

    func testAudiokostenRechnung() {
        let kosten = ProviderCosts.cost(seconds: 600, price: AudioPrice(perMinute: 0.006))
        XCTAssertEqual(kosten ?? 0, 0.06, accuracy: 0.0000001)
    }

    /// Kleine Beträge brauchen mehr Stellen — „$0,00" für ein Diktat wäre keine
    /// Auskunft.
    func testKleineBetraegeBekommenMehrStellen() {
        XCTAssertEqual(ProviderCosts.format(usd: 0.0004), "$0.0004")
        XCTAssertEqual(ProviderCosts.format(usd: 0.42), "$0.420")
        XCTAssertEqual(ProviderCosts.format(usd: 12.5), "$12.50")
        XCTAssertEqual(ProviderCosts.format(usd: 0), "$0")
    }

    // MARK: - Verbrauch zählen

    func testTokenWerdenAufsummiert() {
        let s = store()
        s.record(tokens: TokenUsage(prompt: 100, completion: 50), provider: "OpenAI",
                 model: "gpt-5-mini")
        s.record(tokens: TokenUsage(prompt: 200, completion: 25), provider: "OpenAI",
                 model: "gpt-5-mini")

        XCTAssertEqual(s.month()?.totalTokens, 375)
    }

    func testSekundenWerdenAufsummiert() {
        let s = store()
        s.record(seconds: 30, provider: "Groq", model: "whisper-large-v3-turbo")
        s.record(seconds: 45, provider: "Groq", model: "whisper-large-v3-turbo")
        XCTAssertEqual(s.month()?.totalSeconds ?? 0, 75, accuracy: 0.01)
    }

    /// Aufgeschlüsselt nach Anbieter und Modell — sonst sieht man nicht, wohin
    /// das Geld geht.
    func testVerbrauchWirdNachAnbieterUndModellGetrennt() {
        let s = store()
        s.record(tokens: TokenUsage(prompt: 100, completion: 0), provider: "OpenAI",
                 model: "gpt-5-mini")
        s.record(tokens: TokenUsage(prompt: 100, completion: 0), provider: "Groq",
                 model: "llama-3.3-70b-versatile")
        XCTAssertEqual(s.month()?.tokens.count, 2)
    }

    /// Monate stehen nebeneinander: Der Monatswechsel setzt die Anzeige zurück,
    /// ohne die Vorgeschichte zu verlieren.
    func testMonateStehenNebeneinander() {
        let s = store()
        s.record(tokens: TokenUsage(prompt: 100, completion: 0), provider: "OpenAI",
                 model: "gpt-5-mini", date: datum("2026-08-15"))
        s.record(tokens: TokenUsage(prompt: 300, completion: 0), provider: "OpenAI",
                 model: "gpt-5-mini", date: datum("2026-09-02"))

        XCTAssertEqual(s.month(datum("2026-08-20"))?.totalTokens, 100)
        XCTAssertEqual(s.month(datum("2026-09-20"))?.totalTokens, 300)
        XCTAssertEqual(s.months.count, 2)
    }

    func testNullVerbrauchWirdNichtAufgezeichnet() {
        let s = store()
        s.record(tokens: TokenUsage(prompt: 0, completion: 0), provider: "X", model: "y")
        s.record(seconds: 0, provider: "X", model: "y")
        XCTAssertNil(s.month())
    }

    func testVerbrauchUeberlebtNeustart() {
        let erst = store()
        erst.record(tokens: TokenUsage(prompt: 100, completion: 50), provider: "OpenAI",
                    model: "gpt-5-mini")
        XCTAssertEqual(store().month()?.totalTokens, 150)
    }

    // MARK: - Kosten eines Monats

    func testMonatskostenWerdenSummiert() {
        let s = store()
        s.record(tokens: TokenUsage(prompt: 1_000_000, completion: 0), provider: "OpenAI",
                 model: "gpt-5-mini")                                   // 0,25
        s.record(seconds: 600, provider: "OpenAI", model: "whisper-1")   // 0,06

        let (usd, unbekannt) = s.cost()
        XCTAssertEqual(usd, 0.31, accuracy: 0.0001)
        XCTAssertFalse(unbekannt)
    }

    /// Ist ein Preis unbekannt, wird der Rest gerechnet UND gemeldet, dass etwas
    /// fehlt. Stillschweigend zu niedrig anzuzeigen wäre eine falsche Auskunft.
    func testUnbekannterPreisWirdGemeldet() {
        let s = store()
        s.record(tokens: TokenUsage(prompt: 1_000_000, completion: 0), provider: "OpenAI",
                 model: "gpt-5-mini")
        s.record(tokens: TokenUsage(prompt: 1_000_000, completion: 0), provider: "Eigen",
                 model: "mein-eigenes-modell")

        let (usd, unbekannt) = s.cost()
        XCTAssertEqual(usd, 0.25, accuracy: 0.0001)
        XCTAssertTrue(unbekannt)
    }

    func testModellWirdAusDemSchluesselGelesen() {
        XCTAssertEqual(ProviderUsageStore.model(from: "OpenAI · gpt-5-mini"), "gpt-5-mini")
        XCTAssertEqual(ProviderUsageStore.model(from: "OpenRouter · openai/gpt-5-mini"),
                       "openai/gpt-5-mini")
    }

    // MARK: - Preise abrufen

    private func openRouterAntwort(_ modelle: [(String, String, String)]) -> StubURLProtocol.Antwort {
        let liste = modelle.map {
            "{\"id\":\"\($0.0)\",\"pricing\":{\"prompt\":\"\($0.1)\",\"completion\":\"\($0.2)\"}}"
        }.joined(separator: ",")
        return .init(body: Data("{\"data\":[\(liste)]}".utf8))
    }

    /// OpenRouter liefert je Token, wir rechnen je Million — so, wie die Anbieter
    /// es auf ihren Seiten ausweisen.
    func testPreiseWerdenAufMillionUmgerechnet() async throws {
        StubURLProtocol.antworten = [
            openRouterAntwort([("openai/gpt-5-mini", "0.00000025", "0.000002")]),
        ]
        let tabelle = try await PriceFetch.fetch(session: StubURLProtocol.session(),
                                                now: { self.datum("2026-09-01") })
        let preis = tabelle.price(forText: "openai/gpt-5-mini")
        XCTAssertEqual(preis?.input ?? 0, 0.25, accuracy: 0.0001)
        XCTAssertEqual(preis?.output ?? 0, 2.0, accuracy: 0.0001)
    }

    /// Audio-Preise stehen dort nicht — sie müssen aus der mitgelieferten
    /// Tabelle übrig bleiben, sonst verschwindet die Kostenanzeige für die
    /// Transkription nach dem ersten Abruf.
    func testAudioPreiseBleibenErhalten() async throws {
        StubURLProtocol.antworten = [openRouterAntwort([("x/y", "0.000001", "0.000002")])]
        let tabelle = try await PriceFetch.fetch(session: StubURLProtocol.session())
        XCTAssertEqual(tabelle.price(forAudio: "whisper-large-v3-turbo")?.perMinute, 0.00067)
    }

    /// Modelle, die OpenRouter nicht führt, bleiben ebenfalls stehen.
    func testNichtGefuehrteModelleBleibenStehen() async throws {
        StubURLProtocol.antworten = [openRouterAntwort([("x/y", "0.000001", "0.000002")])]
        let tabelle = try await PriceFetch.fetch(session: StubURLProtocol.session())
        XCTAssertNotNil(tabelle.price(forText: "gpt-5-mini"))
    }

    func testKaputteAntwortWirft() async {
        StubURLProtocol.antworten = [.init(body: Data("<html/>".utf8))]
        do {
            _ = try await PriceFetch.fetch(session: StubURLProtocol.session())
            XCTFail("Muss werfen")
        } catch {
            XCTAssertEqual(error as? RemoteProviderError, .malformedResponse)
        }
    }

    /// Ein misslungener Abruf lässt die vorhandene Tabelle unberührt.
    func testMisslungenerAbrufLaesstDieTabelleUnberuehrt() async {
        let s = store()
        let vorher = s.prices
        StubURLProtocol.antworten = [.init(error: URLError(.notConnectedToInternet))]
        if let neu = try? await PriceFetch.fetch(session: StubURLProtocol.session()) {
            s.replacePrices(neu)
        }
        XCTAssertEqual(s.prices, vorher)
    }

    /// Eine gespeicherte Tabelle gewinnt nur, wenn sie NEUER ist als die
    /// mitgelieferte — sonst würde ein Programm-Update mit frischen Preisen von
    /// einem alten Abruf überstimmt.
    func testAlteGespeicherteTabelleWirdVonDerMitgeliefertenUeberstimmt() {
        let s = store()
        let alt = PriceTable(updated: datum("2020-01-01"),
                             text: ["gpt-5-mini": ModelPrice(input: 99, output: 99)],
                             audio: [:])
        s.replacePrices(alt)

        let neuerStore = store()
        XCTAssertEqual(neuerStore.prices.price(forText: "gpt-5-mini")?.input, 0.25)
    }

    func testNeueGespeicherteTabelleUeberlebtNeustart() {
        let s = store()
        let neu = PriceTable(updated: datum("2027-01-01"),
                             text: ["gpt-5-mini": ModelPrice(input: 0.99, output: 9.9)],
                             audio: [:])
        s.replacePrices(neu)
        XCTAssertEqual(store().prices.price(forText: "gpt-5-mini")?.input, 0.99)
    }
}
