import Foundation

/// Das Textmodell **über das ChatGPT-Abo** des Nutzers („Sign in with ChatGPT",
/// Abo-Nutzung) — ein `POST /v1/responses` mit dem Zugangstoken der Anmeldung
/// statt eines API-Schlüssels.
///
/// Eine eigene Engine statt eines Schalters in `RemoteTextEngine`, weil sich
/// fast alles unterscheidet, was OpenAI für diesen Weg vorschreibt (Stand
/// 14.10.2026, developers.openai.com/siwc):
/// - Responses API statt `/chat/completions`, mit `store: false` und
///   `stream: true` als Pflicht.
/// - Keine System-Nachricht — die Anweisung steht in `instructions`.
/// - Kein `temperature`. Die Temperatur des Routers fällt hier ersatzlos weg.
/// - Eigene Fehlercodes (`subscription_sharing_…`), und bei einem Limit soll
///   die App aufhören zu fragen, statt es weiter zu versuchen.
///
/// Für den `Formatter` darüber ist es eine Engine wie jede andere: Prompts,
/// Abschnitte und der Kürzungs-Schutz greifen unverändert.
actor ChatGPTPlanTextEngine: TextEngine {

    /// Liefert ein Zugangstoken; `true` erzwingt eine Erneuerung.
    typealias TokenSource = @Sendable (_ forceRefresh: Bool) async throws -> String

    private let model: String
    private let endpoint: URL
    private let token: TokenSource
    private let session: URLSession
    private let timeout: TimeInterval
    private let now: @Sendable () -> Date
    private let onPlanLimit: (@Sendable () -> Void)?

    /// `none` hält die Antwortzeit beim Diktat klein — Aufräumen braucht kein
    /// Nachdenken, und GPT-6 Luna denkt sonst standardmäßig „medium". Kennt ein
    /// Modell den Wert nicht, fällt er nach der ersten Absage weg.
    private var reasoningEffort: String? = "none"

    /// Nach einem Limit-Fehler wird bis hierhin nicht mehr gefragt. Der Router
    /// fügt in der Zeit den Rohtext ein, ohne auf eine sichere Absage zu warten.
    private(set) var pausedUntil: Date?
    static let limitPause: TimeInterval = 15 * 60

    init(model: String,
         endpoint: URL = URL(string: ChatGPTPlan.resource + "/responses")!,
         token: @escaping TokenSource,
         session: URLSession = .shared,
         timeout: TimeInterval = 20,
         now: @escaping @Sendable () -> Date = Date.init,
         onPlanLimit: (@Sendable () -> Void)? = nil) {
        self.model = model
        self.endpoint = endpoint
        self.token = token
        self.session = session
        self.timeout = timeout
        self.now = now
        self.onPlanLimit = onPlanLimit
    }

    // MARK: - Zustand

    var isReady: Bool {
        guard let pausedUntil else { return true }
        return now() >= pausedUntil
    }

    let isLoading = false

    var displayName: String { "\(model) · ChatGPT-Abo" }

    let chunkTargetLength = 6000
    let chunkMinLength = 4000

    var callTimeout: TimeInterval? { timeout + 2 }

    func prepare(reset: Bool, onProgress: (@Sendable (Double) -> Void)?) async {
        onProgress?(1)
    }

    /// Absichtlich leer: Aufwärmen hieße eine Anfrage, die das Limit des
    /// Nutzers belastet, ohne etwas zu bringen.
    func warmUp() async {}

    // MARK: - Aufruf

    /// Was ein einzelner Versuch ergeben hat, wenn er nicht einfach scheitert.
    private enum Ausgang {
        case text(String)
        /// 401 — einmal mit erneuertem Token wiederholen.
        case erneutAnmelden
        /// Das Modell kennt `reasoning` nicht — ohne wiederholen.
        case ohneReasoning
    }

    func respond(system: String, user: String, temperature: Float) async throws -> String {
        if let pausedUntil, now() < pausedUntil { throw RemoteProviderError.planLimitReached }

        var erneuert = false
        var reasoningWeg = false
        while true {
            let zugang = try await token(erneuert)
            switch try await versuch(system: system, user: user, zugang: zugang,
                                     tokenFrisch: erneuert) {
            case .text(let text):
                return text
            case .erneutAnmelden:
                erneuert = true
            case .ohneReasoning:
                guard !reasoningWeg else { throw RemoteProviderError.http(status: 400) }
                reasoningWeg = true
                reasoningEffort = nil
            }
        }
    }

    private func versuch(system: String, user: String, zugang: String,
                         tokenFrisch: Bool) async throws -> Ausgang {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(zugang)", forHTTPHeaderField: "Authorization")

        var payload: [String: Any] = [
            "model": model,
            "instructions": system,
            "input": [[
                "type": "message",
                "role": "user",
                "content": [["type": "input_text", "text": user]],
            ]],
            "store": false,
            "stream": true,
        ]
        if let reasoningEffort { payload["reasoning"] = ["effort": reasoningEffort] }
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let bytes: URLSession.AsyncBytes
        let response: URLResponse
        do {
            (bytes, response) = try await session.bytes(for: request)
        } catch {
            throw RemoteHTTP.translate(error)
        }

        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            var rumpf = Data()
            do {
                for try await byte in bytes {
                    rumpf.append(byte)
                    if rumpf.count >= 64 * 1024 { break }
                }
            } catch {
                // Ein abgebrochener Fehlerrumpf ändert nichts am Status.
            }
            let headers = (response as? HTTPURLResponse)?.allHeaderFields ?? [:]
            return try fehler(status: status, body: rumpf, headers: headers,
                              tokenFrisch: tokenFrisch)
        }

        do {
            return .text(try await lesen(bytes.lines))
        } catch let fehler as RemoteProviderError {
            throw fehler
        } catch let fehler as Abgelehnt {
            return try ereignisFehler(fehler)
        } catch {
            throw RemoteHTTP.translate(error)
        }
    }

    /// Ein Fehler, der erst im Strom kommt (`response.failed`, `error`).
    private struct Abgelehnt: Error {
        let code: String?
        let param: String?
    }

    /// Liest den Ereignisstrom bis `response.completed`. Text ohne diesen
    /// Abschluss gilt nicht: Ein abgerissener Strom ist ein halber Text, und den
    /// darf der Router nicht für ein fertiges Ergebnis halten.
    private func lesen<S: AsyncSequence>(_ zeilen: S) async throws -> String where S.Element == String {
        var text = ""
        for try await zeile in zeilen {
            guard zeile.hasPrefix("data:") else { continue }
            let nutzlast = zeile.dropFirst(5).trimmingCharacters(in: .whitespaces)
            if nutzlast == "[DONE]" { break }
            guard let json = try? JSONSerialization.jsonObject(with: Data(nutzlast.utf8))
                    as? [String: Any],
                  let typ = json["type"] as? String
            else { continue }

            switch typ {
            case "response.output_text.delta":
                text += json["delta"] as? String ?? ""
            case "response.completed":
                if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                   let antwort = json["response"] as? [String: Any] {
                    text = Self.ausgabeText(antwort)
                }
                guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw RemoteProviderError.malformedResponse
                }
                return text
            case "response.failed":
                let fehler = (json["response"] as? [String: Any])?["error"] as? [String: Any]
                throw Abgelehnt(code: fehler?["code"] as? String, param: fehler?["param"] as? String)
            case "error":
                let fehler = json["error"] as? [String: Any] ?? json
                throw Abgelehnt(code: fehler["code"] as? String, param: fehler["param"] as? String)
            case "response.incomplete":
                throw RemoteProviderError.malformedResponse
            default:
                continue
            }
        }
        throw RemoteProviderError.malformedResponse
    }

    /// Der Text aus `response.output`, falls keine Deltas kamen.
    private static func ausgabeText(_ antwort: [String: Any]) -> String {
        let ausgaben = antwort["output"] as? [[String: Any]] ?? []
        return ausgaben
            .filter { $0["type"] as? String == "message" }
            .flatMap { $0["content"] as? [[String: Any]] ?? [] }
            .filter { $0["type"] as? String == "output_text" }
            .compactMap { $0["text"] as? String }
            .joined()
    }

    // MARK: - Fehler

    /// Übersetzt eine Absage vor dem Strom. Die Codes stehen bei OpenAI unter
    /// „Errors and recovery"; der Rumpf kann `{"error":{…}}` oder `{"detail":…}`
    /// sein, und `detail` ist nur Diagnose, kein Code.
    private func fehler(status: Int, body: Data, headers: [AnyHashable: Any],
                        tokenFrisch: Bool) throws -> Ausgang {
        let json = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any]
        let fehler = json?["error"] as? [String: Any]
        let code = fehler?["code"] as? String
        let param = fehler?["param"] as? String

        if status == 401 {
            if !tokenFrisch { return .erneutAnmelden }
            throw RemoteProviderError.unauthorized
        }
        if let ausgang = try codeFehler(code: code, param: param) { return ausgang }
        try RemoteHTTP.check(status: status, body: body, headers: headers, model: model)
        throw RemoteProviderError.http(status: status)
    }

    private func ereignisFehler(_ fehler: Abgelehnt) throws -> Ausgang {
        if let ausgang = try codeFehler(code: fehler.code, param: fehler.param) { return ausgang }
        throw RemoteProviderError.malformedResponse
    }

    /// Die Codes, die eine eigene Reaktion brauchen. `nil` heißt: kein
    /// bekannter Code, weiter mit der allgemeinen Statusauswertung.
    private func codeFehler(code: String?, param: String?) throws -> Ausgang? {
        switch code {
        case "subscription_sharing_usage_limit_exceeded":
            pausedUntil = now().addingTimeInterval(Self.limitPause)
            onPlanLimit?()
            throw RemoteProviderError.planLimitReached
        case "subscription_sharing_user_not_eligible":
            throw RemoteProviderError.planNotEligible
        case "subscription_sharing_invalid_user":
            throw RemoteProviderError.unauthorized
        case "subscription_sharing_usage_unavailable", "subscription_sharing_user_unavailable":
            throw RemoteProviderError.http(status: 503)
        case "subscription_sharing_unsupported_capability":
            let p = param?.lowercased() ?? ""
            if p.contains("reasoning"), reasoningEffort != nil { return .ohneReasoning }
            if p.contains("model") { throw RemoteProviderError.unknownModel(model) }
            throw RemoteProviderError.http(status: 400)
        default:
            return nil
        }
    }
}

/// Die Modelle, die das Abo dieses Kontos anbietet. Wie `ProviderModels` nur
/// auf Knopfdruck.
///
/// Die Abo-Doku spricht von Einträgen mit `slug`, `display_name` und
/// `visibility`; die gewöhnliche Modell-Liste hat `id`. Gelesen wird beides,
/// und was ausdrücklich nicht gelistet sein soll, bleibt draußen.
enum ChatGPTPlanModels {

    static func fetch(token: String,
                      url: URL = URL(string: ChatGPTPlan.resource + "/models")!,
                      session: URLSession = .shared) async throws -> [String] {
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

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

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { throw RemoteProviderError.malformedResponse }
        let eintraege = (json["data"] ?? json["models"]) as? [[String: Any]] ?? []
        let ids = eintraege.compactMap { eintrag -> String? in
            if let sichtbar = eintrag["visibility"] as? String, sichtbar != "list" { return nil }
            let id = (eintrag["slug"] as? String) ?? (eintrag["id"] as? String)
            return id?.isEmpty == false ? id : nil
        }
        guard !ids.isEmpty else { throw RemoteProviderError.malformedResponse }
        return Array(Set(ids)).sorted()
    }
}
