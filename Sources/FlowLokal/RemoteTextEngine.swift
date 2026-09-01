import Foundation

/// Das Textmodell **bei einem selbst gewählten Anbieter** — ein OpenAI-kompatibler
/// `/v1/chat/completions`-Aufruf.
///
/// Ein einziger Client genügt für OpenAI, OpenRouter, EURouter, Groq, Mistral,
/// DeepSeek, Anthropic, Google, xAI, Ollama, LM Studio und alles andere, was
/// diese Spezifikation erfüllt. Was sich unterscheidet, sind Daten in der
/// Vorlage, nicht Code.
///
/// Der Router darüber (`Formatter`) kennt keinen Unterschied zum lokalen Modell:
/// Prompts, Abschnittsbildung und der Kürzungs-Schutz greifen unverändert. Ein
/// Cloud-Modell, das auf das Diktat antwortet statt es zu formatieren, wird
/// genauso verworfen wie ein lokales.
actor RemoteTextEngine: TextEngine {

    private let config: RemoteConfig
    private let key: String?
    private let needsKey: Bool
    private let providerName: String
    private let session: URLSession
    private let timeout: TimeInterval

    /// Token-Zahlen der letzten Antwort — echt gemeldet, nicht geschätzt.
    /// Grundlage der Kostenanzeige.
    private(set) var lastUsage: TokenUsage?

    /// Wohin der gemessene Verbrauch gemeldet wird. Als Closure, damit die
    /// Engine nichts über den Verbrauchsspeicher wissen muss und Tests keine
    /// echten Dateien anfassen.
    private let onUsage: (@Sendable (TokenUsage) -> Void)?

    init(config: RemoteConfig,
         key: String?,
         needsKey: Bool,
         providerName: String,
         session: URLSession = .shared,
         timeout: TimeInterval = 15,
         onUsage: (@Sendable (TokenUsage) -> Void)? = nil) {
        self.onUsage = onUsage
        self.config = config
        self.key = key?.isEmpty == true ? nil : key
        self.needsKey = needsKey
        self.providerName = providerName
        self.session = session
        self.timeout = timeout
    }

    // MARK: - Zustand

    /// Bereit heißt hier: Die Adresse ist brauchbar und ein Schlüssel liegt vor,
    /// falls der Anbieter einen braucht.
    ///
    /// Das ist mehr als Formsache: Ist die Engine nicht bereit, fügt der Router
    /// den Rohtext ein, ohne zu fragen. Wäre `isReady` stattdessen immer `true`,
    /// liefe jedes einzelne Diktat in denselben 401 — statt dass der Fehler
    /// einmal in den Einstellungen sichtbar ist.
    var isReady: Bool {
        guard config.chatURL != nil else { return false }
        return !needsKey || key != nil
    }

    /// Es gibt nichts zu laden.
    let isLoading = false

    var displayName: String { "\(config.model) · \(providerName)" }

    /// Deutlich größer als lokal: Ein Modell mit großem Kontextfenster verträgt
    /// mehr, und jeder Aufruf kostet Zeit und Geld.
    let chunkTargetLength = 6000
    let chunkMinLength = 4000

    /// Etwas über der Zeitgrenze der Anfrage selbst: Normalerweise schlägt die
    /// `URLRequest`-Grenze zuerst zu und liefert einen genauen Fehler; diese hier
    /// ist das Netz darunter, falls die Sitzung wirklich hängt.
    var callTimeout: TimeInterval? { timeout + 2 }

    /// Nichts zu laden — der Fortschritt ist sofort vollständig, damit die
    /// Oberfläche keinen hängenden Balken zeigt.
    func prepare(reset: Bool, onProgress: (@Sendable (Double) -> Void)?) async {
        onProgress?(1)
    }

    /// Absichtlich leer. Aufwärmen wäre hier eine bezahlte Anfrage ohne jeden
    /// Nutzen — es gibt keine Metal-Pipeline zu kompilieren.
    func warmUp() async {}

    // MARK: - Aufruf

    func respond(system: String, user: String, temperature: Float) async throws -> String {
        guard let url = config.chatURL else { throw RemoteProviderError.invalidBaseURL }
        if needsKey, key == nil { throw RemoteProviderError.missingKey }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let key { request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization") }

        let payload: [String: Any] = [
            "model": config.model,
            "messages": [["role": "system", "content": system],
                         ["role": "user", "content": user]],
            // Gerundet: `Double(Float(0.2))` ist 0.20000000298023224, und das
            // stünde dann so im Rumpf. Anbieter nehmen es hin, aber es ist
            // Rauschen in jeder Anfrage und in jedem Fehlerbericht.
            "temperature": (Double(temperature) * 100).rounded() / 100,
            // Kein Streaming: Der Router braucht die ganze Antwort, bevor der
            // Kürzungs-Schutz urteilen kann.
            "stream": false,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw RemoteHTTP.translate(error)
        }

        let http = response as? HTTPURLResponse
        try RemoteHTTP.check(status: http?.statusCode ?? 0,
                             body: data,
                             headers: http?.allHeaderFields ?? [:],
                             model: config.model)

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String,
              !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { throw RemoteProviderError.malformedResponse }

        let usage = RemoteHTTP.usage(from: json)
        lastUsage = usage
        if let usage { onUsage?(usage) }
        return content
    }
}
