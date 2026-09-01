import Foundation

/// Holt aktuelle Preise — **nur auf Knopfdruck**, wie die Modell-Listen.
///
/// Quelle ist die freie Modell-API von OpenRouter. Das ist die einzige
/// maschinenlesbare Preisliste, die hunderte Modelle mehrerer Anbieter abdeckt
/// und ohne Schlüssel abrufbar ist; die Endpunkte der Anbieter selbst liefern
/// Modell-IDs, aber praktisch nie Preise.
///
/// Damit sind die Zahlen eine **Näherung** für Anbieter, bei denen man direkt
/// kauft: OpenRouter gibt weiter, was es selbst zahlt, und das liegt nah an den
/// Listenpreisen, ist aber nicht dieselbe Rechnung. Die Oberfläche sagt das.
///
/// Transkriptions-Preise stehen dort nicht — die bleiben aus der mitgelieferten
/// Tabelle. Deshalb wird zusammengeführt und nicht ersetzt.
enum PriceFetch {

    static let openRouterModelsURL = URL(string: "https://openrouter.ai/api/v1/models")!

    static func fetch(session: URLSession = .shared,
                      timeout: TimeInterval = 30,
                      now: () -> Date = Date.init) async throws -> PriceTable {
        var request = URLRequest(url: openRouterModelsURL)
        request.timeoutInterval = timeout

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw RemoteHTTP.translate(error)
        }

        let http = response as? HTTPURLResponse
        try RemoteHTTP.check(status: http?.statusCode ?? 0, body: data,
                             headers: http?.allHeaderFields ?? [:], model: "")

        return try parse(data, now: now())
    }

    /// Wandelt die Antwort um. Die Preise stehen dort als Zeichenketten und **je
    /// einzelnem Token** — unsere Tabelle rechnet je Million, wie die Anbieter es
    /// auf ihren Seiten ausweisen.
    static func parse(_ data: Data, now: Date) throws -> PriceTable {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let eintraege = json["data"] as? [[String: Any]]
        else { throw RemoteProviderError.malformedResponse }

        var text: [String: ModelPrice] = [:]
        for eintrag in eintraege {
            guard let id = eintrag["id"] as? String, !id.isEmpty,
                  let pricing = eintrag["pricing"] as? [String: Any],
                  let prompt = zahl(pricing["prompt"]),
                  let completion = zahl(pricing["completion"])
            else { continue }
            // Kostenlose Modelle mit 0 sind gültig und sollen als 0 erscheinen —
            // aber nur, wenn beide Werte wirklich da waren.
            text[id] = ModelPrice(input: prompt * 1_000_000, output: completion * 1_000_000)
        }
        guard !text.isEmpty else { throw RemoteProviderError.malformedResponse }

        // Die mitgelieferten Werte bleiben als Rückfall stehen, wo der Abruf
        // nichts hergibt: Audio überhaupt, und Modelle, die OpenRouter nicht
        // führt (etwa die Transkriptions-Modelle von Groq).
        var zusammen = PriceTable.bundled.text
        zusammen.merge(text) { _, neu in neu }

        return PriceTable(updated: now, text: zusammen, audio: PriceTable.bundled.audio)
    }

    /// OpenRouter liefert Zahlen als Zeichenkette („0.00000025"). Manche
    /// Spiegelungen liefern echte Zahlen — beides wird genommen.
    private static func zahl(_ wert: Any?) -> Double? {
        if let d = wert as? Double { return d }
        if let i = wert as? Int { return Double(i) }
        if let s = wert as? String { return Double(s) }
        return nil
    }
}
