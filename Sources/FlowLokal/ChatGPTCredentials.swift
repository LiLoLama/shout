import Foundation

/// Feste Werte für „Sign in with ChatGPT" mit Abo-Nutzung.
///
/// Quelle: developers.openai.com/siwc und
/// https://auth.openai.com/.well-known/openid-configuration, geprüft am
/// 14.10.2026. Die Abo-Nutzung ist bei OpenAI noch eine Vorschau — ändert sich
/// dort etwas, ist das hier die eine Stelle dafür.
enum ChatGPTPlan {
    static let issuer = "https://auth.openai.com"
    static let authorizeURL = URL(string: "https://auth.openai.com/api/accounts/authorize")!
    static let tokenURL = URL(string: "https://auth.openai.com/api/accounts/oauth/token")!
    static let revokeURL = URL(string: "https://auth.openai.com/api/accounts/oauth/revoke")!
    static let jwksURL = URL(string: "https://auth.openai.com/.well-known/jwks.json")!

    /// Die Ressource, für die das Zugangstoken gilt — zugleich die Basis-Adresse
    /// der Inferenz. Nie ChatGPTs eigene `backend-api`.
    static let resource = "https://api.openai.com/v1"

    static let scopes = "openid profile email offline_access resource.invoke chatgpt.tokens.use.direct"
    /// Ohne diesen gewährten Scope läuft keine Anfrage über das Abo — die
    /// Anmeldung allein reicht nicht.
    static let usageScope = "chatgpt.tokens.use.direct"

    /// Nur bei der allerersten Anmeldung; danach gilt die ausgestellte Client-ID.
    static let registrationClientID = "dynamic_agent_client"
    static let agentName = "shout."

    static let callbackPath = "/auth/callback"
    /// Der Port aus OpenAIs Beispiel. Ist er belegt (z. B. weil Codex sich
    /// gerade anmeldet), nimmt der Rückruf einen freien — erlaubt ist das,
    /// solange Schema, Host und Pfad gleich bleiben.
    static let preferredPort: UInt16 = 1455

    /// „Nutzung verwalten": dort stellt der Nutzer das Limit dieser App ein.
    static let manageUsageURL = URL(string: "https://chatgpt.com/settings/usage")!
}

/// Die Registrierung dieses Macs bei OpenAI. Bleibt beim Abmelden erhalten:
/// Laut OpenAI soll eine erneute Anmeldung auf demselben Rechner dieselbe
/// Client-ID und Host-ID wiederverwenden, statt jedes Mal neu zu registrieren.
struct ChatGPTAccount: Codable, Equatable, Sendable {
    /// Stabile Kennung dieses Rechners (`urn:uuid:…`). Bewusst nichts, was den
    /// Menschen identifiziert — OpenAI verlangt einen undurchsichtigen Wert.
    var hostID: String
    /// Von OpenAI bei der ersten Anmeldung ausgestellt (`oaiapp_…`).
    var clientID: String?
    /// Das zuletzt geprüfte ID-Token, als `id_token_hint` für die nächste
    /// Anmeldung (überspringt die Kontoauswahl).
    var idToken: String?
    var email: String?
    var subject: String?
}

/// Die laufende Anmeldung. Wird beim Abmelden gelöscht.
struct ChatGPTSession: Codable, Equatable, Sendable {
    var accessToken: String
    /// Wechselt bei jeder Erneuerung — das alte ist danach wertlos.
    var refreshToken: String
    var expiresAt: Date
    var scopes: [String]

    /// Zwei Minuten Vorlauf: Ein Token, das mitten in der Anfrage abläuft,
    /// kostet einen 401 und einen zweiten Anlauf.
    func needsRefresh(now: Date) -> Bool {
        expiresAt.timeIntervalSince(now) < 120
    }
}

/// Verwahrt Registrierung und Anmeldung in der Keychain — unter einem eigenen
/// Dienst neben den API-Schlüsseln, mit denselben Regeln: nur auf diesem Gerät,
/// nie im Backup, nie im Log (siehe `ProviderKeychain`).
enum ChatGPTCredentialStore {

    static let defaultService = "com.inthezone.flowlokal.chatgpt"

    private static let accountKey = "registration"
    private static let sessionKey = "session"

    // MARK: - Registrierung

    static func loadAccount(service: String = defaultService) -> ChatGPTAccount? {
        decode(ChatGPTAccount.self, account: accountKey, service: service)
    }

    /// Die Registrierung — beim ersten Aufruf mit frischer Host-ID angelegt.
    /// OpenAI will die Host-ID festgelegt und gespeichert haben, bevor die
    /// erste Anmeldung beginnt.
    static func ensureAccount(service: String = defaultService) throws -> ChatGPTAccount {
        if let vorhanden = loadAccount(service: service) { return vorhanden }
        let neu = ChatGPTAccount(hostID: "urn:uuid:" + UUID().uuidString.lowercased())
        try saveAccount(neu, service: service)
        return neu
    }

    static func saveAccount(_ account: ChatGPTAccount, service: String = defaultService) throws {
        try encode(account, account: accountKey, service: service)
    }

    // MARK: - Anmeldung

    static func loadSession(service: String = defaultService) -> ChatGPTSession? {
        decode(ChatGPTSession.self, account: sessionKey, service: service)
    }

    static func saveSession(_ session: ChatGPTSession, service: String = defaultService) throws {
        try encode(session, account: sessionKey, service: service)
    }

    static func deleteSession(service: String = defaultService) throws {
        try ProviderKeychain.delete(for: sessionKey, service: service)
    }

    static func hasSession(service: String = defaultService) -> Bool {
        loadSession(service: service) != nil
    }

    // MARK: - Ablage

    /// JSON als Zeichenkette über `ProviderKeychain` — dieselbe Ablage, dieselben
    /// Zugriffsregeln, kein zweiter Keychain-Code.
    private static func encode<T: Encodable>(_ value: T, account: String, service: String) throws {
        let data = try JSONEncoder().encode(value)
        try ProviderKeychain.store(String(decoding: data, as: UTF8.self), for: account,
                                   service: service)
    }

    private static func decode<T: Decodable>(_ type: T.Type, account: String,
                                             service: String) -> T? {
        guard let text = ProviderKeychain.read(for: account, service: service) else { return nil }
        return try? JSONDecoder().decode(type, from: Data(text.utf8))
    }
}
