import Foundation

/// Preis eines Textmodells, in **USD je Million Token**.
struct ModelPrice: Codable, Equatable, Sendable {
    var input: Double
    var output: Double
}

/// Preis einer Transkription, in **USD je Minute** — so rechnen die Anbieter
/// dort ab, nicht nach Token.
struct AudioPrice: Codable, Equatable, Sendable {
    var perMinute: Double
}

/// Preistabelle. Mitgeliefert im Programm, auf Knopfdruck aktualisierbar.
///
/// **Näherung, und die Oberfläche sagt das auch.** Abgerechnet wird beim
/// Anbieter; hier steht, was zum Zeitpunkt des Releases (bzw. des letzten
/// Abrufs) veröffentlicht war. Die Endpunkte der Anbieter liefern Modell-IDs,
/// aber praktisch nie Preise — deshalb ist die einzige maschinenlesbare Quelle
/// die freie Modell-API von OpenRouter.
struct PriceTable: Codable, Equatable, Sendable {

    /// Wann diese Tabelle entstanden ist — steht in der Oberfläche als „Stand".
    var updated: Date
    /// Textmodelle, Schlüssel ist die Modell-ID.
    var text: [String: ModelPrice]
    /// Transkriptions-Modelle.
    var audio: [String: AudioPrice]

    /// Preis eines Modells.
    ///
    /// Erst genau, dann ohne Organisationsvorsilbe: OpenRouter nennt dasselbe
    /// Modell „openai/gpt-5-mini", OpenAI selbst nur „gpt-5-mini". Ohne diesen
    /// zweiten Versuch wäre die halbe Tabelle nutzlos.
    ///
    /// Ist nichts zu finden, kommt `nil` — **es wird keine Zahl erfunden.** Eine
    /// erfundene Kostenanzeige ist schlimmer als keine.
    func price(forText model: String) -> ModelPrice? {
        Self.lookup(model, in: text)
    }

    func price(forAudio model: String) -> AudioPrice? {
        Self.lookup(model, in: audio)
    }

    private static func lookup<V>(_ model: String, in table: [String: V]) -> V? {
        let key = model.lowercased()
        if let exakt = table.first(where: { $0.key.lowercased() == key })?.value { return exakt }
        let ohneVorsilbe = key.split(separator: "/").last.map(String.init) ?? key
        return table.first { eintrag in
            let kandidat = eintrag.key.lowercased()
            let kandidatOhne = kandidat.split(separator: "/").last.map(String.init) ?? kandidat
            return kandidatOhne == ohneVorsilbe
        }?.value
    }

    /// Die mitgelieferte Tabelle. Stand: 01.09.2026, Angaben in USD.
    ///
    /// Bewusst kurz und auf die Modelle beschränkt, die der Katalog vorschlägt:
    /// Eine lange handgepflegte Liste veraltet nur an mehr Stellen gleichzeitig.
    /// Alles Übrige holt der „Preise aktualisieren"-Knopf.
    static let bundled = PriceTable(
        updated: Date(timeIntervalSince1970: 1_788_220_800),   // 2026-09-01
        text: [
            "gpt-5-mini": ModelPrice(input: 0.25, output: 2.00),
            "gpt-5": ModelPrice(input: 1.25, output: 10.00),
            "claude-haiku-4.5": ModelPrice(input: 1.00, output: 5.00),
            "claude-sonnet-4.5": ModelPrice(input: 3.00, output: 15.00),
            "gemini-2.5-flash": ModelPrice(input: 0.30, output: 2.50),
            "gemini-2.5-pro": ModelPrice(input: 1.25, output: 10.00),
            "mistral-small-latest": ModelPrice(input: 0.20, output: 0.60),
            "mistral-large-latest": ModelPrice(input: 2.00, output: 6.00),
            "deepseek-chat": ModelPrice(input: 0.27, output: 1.10),
            "llama-3.3-70b-versatile": ModelPrice(input: 0.59, output: 0.79),
            "grok-4-fast": ModelPrice(input: 0.20, output: 0.50),
            "grok-4": ModelPrice(input: 3.00, output: 15.00),
        ],
        audio: [
            "whisper-1": AudioPrice(perMinute: 0.006),
            "gpt-4o-mini-transcribe": AudioPrice(perMinute: 0.003),
            "whisper-large-v3": AudioPrice(perMinute: 0.00185),
            "whisper-large-v3-turbo": AudioPrice(perMinute: 0.00067),
            "voxtral-mini-latest": AudioPrice(perMinute: 0.001),
        ])
}

/// Rechnet gemessenen Verbrauch in Geld um und formatiert ihn.
enum ProviderCosts {

    /// Kosten eines Textverbrauchs. `nil`, wenn der Preis unbekannt ist.
    static func cost(tokens: TokenCount, price: ModelPrice?) -> Double? {
        guard let price else { return nil }
        return Double(tokens.prompt) / 1_000_000 * price.input
             + Double(tokens.completion) / 1_000_000 * price.output
    }

    static func cost(seconds: Double, price: AudioPrice?) -> Double? {
        guard let price else { return nil }
        return seconds / 60 * price.perMinute
    }

    /// Geldbetrag für die Oberfläche. Bewusst mehr Stellen bei kleinen Beträgen —
    /// „$0,00" für ein Diktat wäre keine Auskunft.
    static func format(usd: Double) -> String {
        if usd == 0 { return "$0" }
        if usd < 0.01 { return String(format: "$%.4f", usd) }
        if usd < 1 { return String(format: "$%.3f", usd) }
        return String(format: "$%.2f", usd)
    }

    /// Vorab-Schätzung für ein typisches Diktat: rund 700 Zeichen hinein, ebenso
    /// viele heraus, dazu die Systemanweisung. Vier Zeichen je Token ist die
    /// gängige Faustregel für europäische Sprachen.
    static let typicalDictation = TokenCount(prompt: 400, completion: 180)
}
