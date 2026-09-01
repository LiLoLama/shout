import Foundation

/// Für welchen Verarbeitungsschritt eine Anbieter-Einstellung gilt. Beide sind
/// getrennt konfigurierbar: Man kann lokal transkribieren und extern aufbereiten
/// — oder Groq fürs Audio und EURouter für den Text nehmen.
enum EnginePurpose: String, Sendable, CaseIterable {
    case text
    case audio

    /// Schlüssel in `UserDefaults` für „auf diesem Gerät" gegen „Anbieter".
    var engineKey: String {
        switch self {
        case .text: return "formatEngine"
        case .audio: return "asrEngine"
        }
    }

    /// Schlüssel in `UserDefaults` für die Endpunkt-Konfiguration.
    var configKey: String {
        switch self {
        case .text: return "remoteConfigText"
        case .audio: return "remoteConfigAudio"
        }
    }
}

/// Eine mitgelieferte Anbieter-Vorlage. **Reine Daten** — ein neuer Anbieter ist
/// ein Listeneintrag, kein Code. Genau deshalb reicht ein einziger
/// OpenAI-kompatibler Client für alle.
struct ProviderTemplate: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    /// Leer bei „Eigener Endpunkt" — dort trägt der Nutzer sie ein.
    let baseURL: String
    /// Seite, auf der man den Schlüssel bekommt. Ohne diesen Link sucht man.
    let keyURL: String
    /// Zwei bis drei handverlesene Empfehlungen. Die vollständige, aktuelle
    /// Liste holt der „Modelle laden"-Knopf beim Anbieter selbst.
    let chatModels: [String]
    /// Empfehlungen für die Transkription. Kann leer sein, obwohl der Anbieter
    /// Audio kann (siehe `canAudio`).
    let audioModels: [String]
    /// Ob der Anbieter überhaupt transkribieren kann. Getrennt von
    /// `audioModels`, weil „Eigener Endpunkt" Audio kann, aber keine
    /// Modellvorschläge hat — dort weiß nur der Nutzer, was sein Server anbietet.
    let canAudio: Bool
    /// Anbieter auf dem eigenen Rechner brauchen keinen Schlüssel.
    let needsKey: Bool
    /// Ein Satz Einordnung für die Oberfläche.
    let note: String
}

/// Die mitgelieferten Vorlagen.
///
/// **Prüfstand der Basis-Adressen:** `eurouter` und `xai` sind am 01.09.2026
/// gegen die Dokumentation der Anbieter geprüft. Die übrigen stammen aus der
/// gängigen Dokumentation und sind vor dem Ausliefern einmal nachzuprüfen — eine
/// falsche Adresse in einer mitgelieferten Vorlage ist schlimmer als keine
/// Vorlage, weil der Fehlschlag dann wie ein Fehler der App aussieht.
///
/// Die Modell-IDs sind Startwerte für die Auswahl und veralten schneller als die
/// Adressen; der „Modelle laden"-Knopf und das freie Modellfeld sind die
/// Notausgänge, wenn eine Vorlage hinterherhängt.
enum ProviderCatalog {

    static let all: [ProviderTemplate] = [
        ProviderTemplate(
            id: "openai", name: "OpenAI",
            baseURL: "https://api.openai.com/v1",
            keyURL: "https://platform.openai.com/api-keys",
            chatModels: ["gpt-5-mini", "gpt-5"],
            audioModels: ["gpt-4o-mini-transcribe", "whisper-1"],
            canAudio: true, needsKey: true,
            note: "Der Referenz-Endpunkt. Kann Text und Transkription."),

        ProviderTemplate(
            id: "openrouter", name: "OpenRouter",
            baseURL: "https://openrouter.ai/api/v1",
            keyURL: "https://openrouter.ai/keys",
            chatModels: ["openai/gpt-5-mini", "anthropic/claude-sonnet-4.5"],
            audioModels: [],
            canAudio: false, needsKey: true,
            note: "Ein Schlüssel für hunderte Modelle. Keine Transkription."),

        ProviderTemplate(
            id: "eurouter", name: "EURouter",
            baseURL: "https://api.eurouter.ai/v1",
            keyURL: "https://www.eurouter.ai",
            chatModels: ["openai/gpt-oss-120b", "mistral/mistral-large"],
            audioModels: [],
            canAudio: false, needsKey: true,
            note: "Verarbeitung ausschließlich in der EU, ein Schlüssel für über "
                + "100 Modelle. Keine Transkription."),

        ProviderTemplate(
            id: "groq", name: "Groq",
            baseURL: "https://api.groq.com/openai/v1",
            keyURL: "https://console.groq.com/keys",
            chatModels: ["llama-3.3-70b-versatile"],
            audioModels: ["whisper-large-v3-turbo", "whisper-large-v3"],
            canAudio: true, needsKey: true,
            note: "Sehr schnell — die interessanteste Wahl fürs Live-Diktat."),

        ProviderTemplate(
            id: "mistral", name: "Mistral",
            baseURL: "https://api.mistral.ai/v1",
            keyURL: "https://console.mistral.ai/api-keys",
            chatModels: ["mistral-large-latest", "mistral-small-latest"],
            audioModels: ["voxtral-mini-latest"],
            canAudio: true, needsKey: true,
            note: "Europäischer Anbieter, kann Text und Transkription."),

        ProviderTemplate(
            id: "deepseek", name: "DeepSeek",
            baseURL: "https://api.deepseek.com/v1",
            keyURL: "https://platform.deepseek.com/api_keys",
            chatModels: ["deepseek-chat"],
            audioModels: [],
            canAudio: false, needsKey: true,
            note: "Günstig. Keine Transkription."),

        ProviderTemplate(
            id: "anthropic", name: "Anthropic",
            baseURL: "https://api.anthropic.com/v1",
            keyURL: "https://console.anthropic.com/settings/keys",
            chatModels: ["claude-sonnet-4.5", "claude-haiku-4.5"],
            audioModels: [],
            canAudio: false, needsKey: true,
            note: "Über die OpenAI-Kompatibilitätsschicht. Keine Transkription."),

        ProviderTemplate(
            id: "gemini", name: "Google Gemini",
            baseURL: "https://generativelanguage.googleapis.com/v1beta/openai",
            keyURL: "https://aistudio.google.com/apikey",
            chatModels: ["gemini-2.5-flash", "gemini-2.5-pro"],
            audioModels: [],
            canAudio: false, needsKey: true,
            note: "Über die OpenAI-Kompatibilitätsschicht. Keine Transkription."),

        ProviderTemplate(
            id: "xai", name: "xAI · Grok",
            baseURL: "https://api.x.ai/v1",
            keyURL: "https://console.x.ai",
            chatModels: ["grok-4", "grok-4-fast"],
            audioModels: [],
            canAudio: false, needsKey: true,
            note: "Schlüssel aus der xAI-Konsole. Ein SuperGrok-Abo gilt hier "
                + "NICHT — Abos enthalten keinen API-Zugang."),

        ProviderTemplate(
            id: "ollama", name: "Ollama",
            baseURL: "http://localhost:11434/v1",
            keyURL: "https://ollama.com/download",
            chatModels: ["gemma3:12b", "qwen3:14b"],
            audioModels: [],
            canAudio: false, needsKey: false,
            note: "Läuft auf deinem eigenen Rechner — auch auf einem anderen im "
                + "eigenen Netz. Dann verlässt nichts dein Netzwerk."),

        ProviderTemplate(
            id: "lmstudio", name: "LM Studio",
            baseURL: "http://localhost:1234/v1",
            keyURL: "https://lmstudio.ai",
            chatModels: [],
            audioModels: [],
            canAudio: false, needsKey: false,
            note: "Wie Ollama: dein eigener Rechner, dein eigenes Netz."),

        ProviderTemplate(
            id: "custom", name: "Eigener Endpunkt",
            baseURL: "",
            keyURL: "",
            chatModels: [],
            audioModels: [],
            canAudio: true, needsKey: true,
            note: "Alles selbst eintragen — für whisper.cpp-Server, vLLM, "
                + "Pauschal-Abos mit eigenem Endpunkt und alles andere "
                + "OpenAI-kompatible."),
    ]

    static func template(id: String) -> ProviderTemplate? {
        all.first { $0.id == id }
    }

    /// Vorlagen, die den gewünschten Schritt überhaupt können.
    static func templates(for purpose: EnginePurpose) -> [ProviderTemplate] {
        switch purpose {
        case .text: return all
        case .audio: return all.filter(\.canAudio)
        }
    }
}

/// Die Einstellung eines Anbieters für einen Schritt. **Ohne Schlüssel** — der
/// liegt in der Keychain und darf nie in `UserDefaults` oder ins Backup.
struct RemoteConfig: Codable, Equatable, Sendable {
    var templateID: String
    var baseURL: String
    var model: String

    // MARK: - Adressen

    var chatURL: URL? { url(appending: "chat/completions") }
    var audioURL: URL? { url(appending: "audio/transcriptions") }
    var modelsURL: URL? { url(appending: "models") }

    /// Baut die Endpunkt-Adresse aus der Basis.
    ///
    /// Die Regeln sind an den Fehlern orientiert, die Leute wirklich machen:
    /// - Leerzeichen aus der Zwischenablage fliegen raus.
    /// - Schrägstriche am Ende werden entfernt, auch mehrere.
    /// - Wer den **ganzen** Endpunkt kopiert hat, landet trotzdem richtig: die
    ///   bekannten Endpunkt-Pfade werden abgeschnitten. Das erlaubt auch den
    ///   Quereinstieg — aus einer kopierten Chat-Adresse entsteht die
    ///   Audio-Adresse, sonst funktionierte nur der Schritt, den man zuerst
    ///   eingerichtet hat.
    /// - Steht **gar kein** Pfad da (nur Host, evtl. mit Port), ergänzen wir
    ///   `/v1`. Praktisch alle OpenAI-kompatiblen Endpunkte liegen dort, und
    ///   „nur den Host eintragen" ist der häufigste Fall.
    ///
    /// Was NICHT passiert: ein vorhandener, abweichender Pfad wird nie
    /// „korrigiert". Google liegt unter `/v1beta/openai`, und daran darf keine
    /// Klugheit der App etwas ändern.
    private func url(appending path: String) -> URL? {
        var text = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        while text.hasSuffix("/") { text.removeLast() }

        for endpoint in ["/chat/completions", "/audio/transcriptions", "/models"]
        where text.hasSuffix(endpoint) {
            text.removeLast(endpoint.count)
            break
        }
        while text.hasSuffix("/") { text.removeLast() }

        guard var comps = URLComponents(string: text), let host = comps.host, !host.isEmpty,
              let scheme = comps.scheme, scheme == "http" || scheme == "https"
        else { return nil }

        if comps.path.isEmpty { comps.path = "/v1" }
        comps.path += "/" + path
        return comps.url
    }

    // MARK: - Speichern

    func save(purpose: EnginePurpose, in defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: purpose.configKey)
    }

    static func load(purpose: EnginePurpose,
                     from defaults: UserDefaults = .standard) -> RemoteConfig? {
        guard let data = defaults.data(forKey: purpose.configKey) else { return nil }
        return try? JSONDecoder().decode(RemoteConfig.self, from: data)
    }

    /// Startwerte aus einer Vorlage.
    init(template: ProviderTemplate, purpose: EnginePurpose) {
        self.templateID = template.id
        self.baseURL = template.baseURL
        switch purpose {
        case .text: self.model = template.chatModels.first ?? ""
        case .audio: self.model = template.audioModels.first ?? ""
        }
    }

    init(templateID: String, baseURL: String, model: String) {
        self.templateID = templateID
        self.baseURL = baseURL
        self.model = model
    }
}

/// Die echten Token-Zahlen einer Antwort. Grundlage der Kostenanzeige — dort
/// wird gezählt, nicht geschätzt.
struct TokenUsage: Sendable, Equatable {
    let prompt: Int
    let completion: Int
    var total: Int { prompt + completion }
}

/// Fehler eines Anbieter-Aufrufs.
///
/// Bewusst **ohne** fertige Anzeigetexte: Die Oberfläche ist zweisprachig und
/// übersetzt über `Loc.t`, was hier nur als Struktur ankommt. Und der
/// Schlüssel taucht in keinem Fall auf — auch nicht in `logDescription`.
enum RemoteProviderError: Error, Equatable {
    /// Es ist kein Schlüssel hinterlegt, der Anbieter braucht aber einen.
    case missingKey
    /// Die Basis-Adresse ergibt keine gültige Endpunkt-Adresse.
    case invalidBaseURL
    /// 401/403 — Schlüssel abgelehnt.
    case unauthorized
    /// 402 oder eine entsprechende Meldung — kein Guthaben.
    case noCredit
    /// 404 bzw. eine Meldung, die auf ein unbekanntes Modell zeigt.
    case unknownModel(String)
    /// 429 — zu viele Anfragen.
    case rateLimited(retryAfter: TimeInterval?)
    /// Alles andere mit Statuscode.
    case http(status: Int)
    /// Antwort kam an, war aber nicht verwertbar.
    case malformedResponse
    /// Zeitgrenze überschritten.
    case timedOut
    /// Gar keine Verbindung — Netz weg, Host unbekannt, oder der lokale Server
    /// (Ollama, LM Studio) läuft nicht. Eigener Fall, weil die Abhilfe eine
    /// völlig andere ist als bei einem abgelehnten Schlüssel.
    case cannotConnect(code: Int)

    /// Lohnt ein zweiter Versuch? Nur bei Ursachen, die von selbst weggehen.
    /// Ein abgelehnter Schlüssel oder ein unbekanntes Modell wird beim zweiten
    /// Mal genauso abgelehnt — das wäre nur Wartezeit und, bei Erfolg, Geld.
    var isTransient: Bool {
        switch self {
        case .timedOut, .rateLimited, .cannotConnect: return true
        case .http(let status): return status >= 500
        case .missingKey, .invalidBaseURL, .unauthorized, .noCredit,
             .unknownModel, .malformedResponse: return false
        }
    }

    /// Kurzform fürs Log. Enthält nie den Schlüssel und nie den Antwortrumpf,
    /// weil manche Anbieter darin die Anfrage samt Kopfzeilen spiegeln.
    var logDescription: String {
        switch self {
        case .missingKey: return "kein Schlüssel hinterlegt"
        case .invalidBaseURL: return "Basis-Adresse ungültig"
        case .unauthorized: return "Schlüssel abgelehnt (401/403)"
        case .noCredit: return "kein Guthaben (402)"
        case .unknownModel(let m): return "Modell unbekannt: \(m)"
        case .rateLimited(let after):
            return "Ratenlimit (429)" + (after.map { ", erneut in \(Int($0)) s" } ?? "")
        case .http(let status): return "HTTP \(status)"
        case .malformedResponse: return "Antwort nicht verwertbar"
        case .timedOut: return "Zeitgrenze überschritten"
        case .cannotConnect(let code): return "keine Verbindung (\(code))"
        }
    }
}

/// Gemeinsame Auswertung der Antworten — von Text- und Audio-Engine benutzt,
/// damit beide dieselben Fehler auf dieselbe Weise unterscheiden.
enum RemoteHTTP {

    /// Wirft den passenden Fehler, wenn der Status kein Erfolg ist.
    ///
    /// Die Unterscheidung bei 404 ist wichtig: Mit Modellhinweis im Rumpf ist es
    /// ein veraltetes Modell (der häufigste Fall, wenn eine Vorlage
    /// hinterherhängt), ohne Hinweis eine falsche Adresse. Beides braucht eine
    /// andere Abhilfe, und ein pauschales „404" schickt Leute ans falsche Ende.
    static func check(status: Int, body: Data, headers: [AnyHashable: Any],
                      model: String) throws {
        guard !(200..<300).contains(status) else { return }

        switch status {
        case 401, 403:
            throw RemoteProviderError.unauthorized
        case 402:
            throw RemoteProviderError.noCredit
        case 404:
            if message(from: body).lowercased().contains("model") {
                throw RemoteProviderError.unknownModel(model)
            }
            throw RemoteProviderError.http(status: 404)
        case 429:
            let retry = (headers["Retry-After"] as? String).flatMap(TimeInterval.init)
            throw RemoteProviderError.rateLimited(retryAfter: retry)
        default:
            throw RemoteProviderError.http(status: status)
        }
    }

    /// Übersetzt Netzfehler. Zeitüberschreitung bekommt einen eigenen Fall, weil
    /// der Router beim Diktat darauf eine harte Grenze setzt.
    static func translate(_ error: Error) -> RemoteProviderError {
        if let known = error as? RemoteProviderError { return known }
        guard let urlError = error as? URLError else { return .malformedResponse }
        if urlError.code == .timedOut { return .timedOut }
        return .cannotConnect(code: urlError.errorCode)
    }

    /// `error.message` aus dem Antwortrumpf — nur zur Fallunterscheidung, nie
    /// zur Anzeige und nie ins Log: Manche Anbieter spiegeln darin die Anfrage
    /// samt Kopfzeilen, und dann stünde der Schlüssel im Protokoll.
    static func message(from body: Data) -> String {
        guard let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any]
        else { return "" }
        if let error = json["error"] as? [String: Any],
           let text = error["message"] as? String { return text }
        if let text = json["message"] as? String { return text }
        return ""
    }

    static func usage(from json: [String: Any]) -> TokenUsage? {
        guard let usage = json["usage"] as? [String: Any],
              let prompt = usage["prompt_tokens"] as? Int,
              let completion = usage["completion_tokens"] as? Int
        else { return nil }
        return TokenUsage(prompt: prompt, completion: completion)
    }
}

/// Was für einen Schritt benutzt werden soll. Die Entscheidung steht hier statt
/// in `EngineFactory`, damit sie prüfbar ist — die Fabrik selbst kennt die
/// konkreten Engines und liegt deshalb nicht im Testziel.
enum EngineSelection: Equatable {
    case local
    case remote(config: RemoteConfig, template: ProviderTemplate)
}

extension EngineSelection {

    /// Trifft die Wahl aus Einstellung, gespeicherter Konfiguration und der
    /// Frage, ob ein Schlüssel hinterlegt ist.
    ///
    /// **Ohne Schlüssel wird lokal gearbeitet, nicht gescheitert.** Das ist die
    /// Regel, die einen importierten Sicherungsstand abfängt: Die Konfiguration
    /// reist im Backup mit (sie ist harmlos), der Schlüssel nicht. Auf dem neuen
    /// Gerät stünde sonst „Anbieter" in den Einstellungen, und jedes Diktat
    /// liefe in einen 401 — oder schlimmer, es ginge Text an einen Anbieter, für
    /// den der Mensch auf diesem Gerät nie einen Schlüssel eingetragen hat.
    static func decide(for purpose: EnginePurpose,
                       defaults: UserDefaults = .standard,
                       hasKey: (String) -> Bool = { ProviderKeychain.has(templateID: $0) })
    -> EngineSelection {
        guard defaults.string(forKey: purpose.engineKey) == "remote",
              let config = RemoteConfig.load(purpose: purpose, from: defaults),
              let template = ProviderCatalog.template(id: config.templateID),
              config.chatURL != nil
        else { return .local }

        if purpose == .audio, !template.canAudio { return .local }
        if template.needsKey, !hasKey(template.id) { return .local }
        return .remote(config: config, template: template)
    }
}
