import Foundation
import Combine
import Security

/// Anmeldung mit ChatGPT und das Zugangstoken für die Abo-Nutzung.
///
/// Ein Actor, weil das Refresh-Token bei jeder Erneuerung wechselt: Laufen zwei
/// Erneuerungen gleichzeitig, macht die zweite die erste wertlos, und die
/// Anmeldung ist weg. Deshalb teilen sich gleichzeitige Aufrufer genau eine
/// laufende Erneuerung (`laufendeErneuerung`).
actor ChatGPTAuth {

    static let shared = ChatGPTAuth()

    private let session: URLSession
    private let service: String
    private let now: @Sendable () -> Date
    private var laufendeErneuerung: Task<ChatGPTSession, Error>?
    private var schluessel: [String: SecKey] = [:]

    init(session: URLSession = .shared,
         service: String = ChatGPTCredentialStore.defaultService,
         now: @escaping @Sendable () -> Date = Date.init) {
        self.session = session
        self.service = service
        self.now = now
    }

    // MARK: - Zugangstoken

    /// Ein gültiges Zugangstoken, bei Bedarf erneuert.
    ///
    /// `forceRefresh` nach einem 401: Das Token kann serverseitig verfallen sein,
    /// obwohl die Uhr noch Zeit anzeigt.
    func accessToken(forceRefresh: Bool = false) async throws -> String {
        guard let gespeichert = ChatGPTCredentialStore.loadSession(service: service) else {
            throw RemoteProviderError.signInRequired
        }
        if !forceRefresh, !gespeichert.needsRefresh(now: now()) {
            return gespeichert.accessToken
        }
        return try await erneuert().accessToken
    }

    private func erneuert() async throws -> ChatGPTSession {
        if let laufend = laufendeErneuerung { return try await laufend.value }
        let aufgabe = Task { try await self.erneuern() }
        laufendeErneuerung = aufgabe
        defer { laufendeErneuerung = nil }
        return try await aufgabe.value
    }

    private func erneuern() async throws -> ChatGPTSession {
        guard let alt = ChatGPTCredentialStore.loadSession(service: service),
              let clientID = ChatGPTCredentialStore.loadAccount(service: service)?.clientID
        else { throw RemoteProviderError.signInRequired }

        let request = ChatGPTOAuth.refreshRequest(refreshToken: alt.refreshToken, clientID: clientID)
        let (data, status) = try await senden(request)

        guard (200..<300).contains(status) else {
            // Nur bei einem endgültig wertlosen Token abmelden. Bei Netzfehlern
            // oder 5xx bleibt alles, wie es ist — sonst würde ein Funkloch den
            // Menschen abmelden.
            let code = ChatGPTOAuth.errorCode(from: data) ?? ""
            if ChatGPTOAuth.finalRefreshErrors.contains(code) || status == 401 {
                try? ChatGPTCredentialStore.deleteSession(service: service)
                await ChatGPTPlanStatus.melden(angemeldet: false)
                throw RemoteProviderError.signInRequired
            }
            throw status >= 500 ? RemoteProviderError.http(status: status)
                                : RemoteProviderError.unauthorized
        }

        let antwort: ChatGPTOAuth.TokenResponse
        do { antwort = try ChatGPTOAuth.parseTokenResponse(data) }
        catch { throw RemoteProviderError.malformedResponse }

        let neu = ChatGPTSession(accessToken: antwort.accessToken,
                                 // Kommt ausnahmsweise kein neues, gilt das alte weiter.
                                 refreshToken: antwort.refreshToken ?? alt.refreshToken,
                                 expiresAt: now().addingTimeInterval(antwort.expiresIn),
                                 scopes: antwort.scopes.isEmpty ? alt.scopes : antwort.scopes)
        try? ChatGPTCredentialStore.saveSession(neu, service: service)
        return neu
    }

    private func senden(_ request: URLRequest) async throws -> (Data, Int) {
        do {
            let (data, response) = try await session.data(for: request)
            return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
        } catch {
            throw RemoteHTTP.translate(error)
        }
    }

    // MARK: - Anmelden

    /// Der ganze Anmeldeablauf: Rückruf bereitstellen, Browser öffnen, auf den
    /// Rückruf warten, Code tauschen, ID-Token prüfen, speichern.
    ///
    /// `openBrowser` kommt von außen, damit dieser Actor keine Oberfläche kennt.
    /// Abbrechen geht über das Abbrechen der aufrufenden Aufgabe.
    func signIn(openBrowser: @escaping @Sendable (URL) async -> Void) async throws -> ChatGPTAccount {
        var konto: ChatGPTAccount
        do { konto = try ChatGPTCredentialStore.ensureAccount(service: service) }
        catch { throw ChatGPTAuthError.callbackFailed("Keychain") }

        let state = ChatGPTOAuth.randomToken()
        let nonce = ChatGPTOAuth.randomToken()
        let verifier = ChatGPTOAuth.randomToken()

        let server = try await LoopbackServer.start(preferredPort: ChatGPTPlan.preferredPort,
                                                    path: ChatGPTPlan.callbackPath,
                                                    page: Self.fertigSeite)
        defer { server.stop() }
        let redirect = ChatGPTOAuth.redirectURI(port: server.port)

        await openBrowser(ChatGPTOAuth.authorizeURL(
            account: konto, redirectURI: redirect, state: state, nonce: nonce,
            challenge: ChatGPTOAuth.codeChallenge(for: verifier)))

        let rueckruf: ChatGPTOAuth.Callback
        do {
            rueckruf = try ChatGPTOAuth.parseCallback(
                try await server.waitForCallback(timeout: 300),
                expectedState: state, knownClientID: konto.clientID)
        } catch ChatGPTAuthError.clientMismatch {
            // Im Browser wurde ein anderes Konto gewählt als das registrierte.
            // Die alte Registrierung passt dann nicht mehr; beim nächsten
            // Versuch registriert sich der Mac neu.
            konto.clientID = nil
            konto.idToken = nil
            try? ChatGPTCredentialStore.saveAccount(konto, service: service)
            throw ChatGPTAuthError.clientMismatch
        }

        let tauschen = ChatGPTOAuth.codeExchangeRequest(code: rueckruf.code,
                                                        clientID: rueckruf.clientID,
                                                        verifier: verifier,
                                                        redirectURI: redirect)
        let data: Data
        let status: Int
        do { (data, status) = try await senden(tauschen) }
        catch { throw ChatGPTAuthError.network }
        guard (200..<300).contains(status) else {
            throw ChatGPTAuthError.tokenRejected(status: status, code: ChatGPTOAuth.errorCode(from: data))
        }
        let antwort = try ChatGPTOAuth.parseTokenResponse(data)

        guard let idToken = antwort.idToken else { throw ChatGPTAuthError.invalidIDToken("fehlt") }
        let claims = try await pruefen(idToken, clientID: rueckruf.clientID, nonce: nonce)

        guard antwort.scopes.contains(ChatGPTPlan.usageScope) else {
            throw ChatGPTAuthError.missingUsageScope
        }
        guard let refresh = antwort.refreshToken else {
            throw ChatGPTAuthError.tokenRejected(status: status, code: "ohne refresh_token")
        }

        konto.clientID = rueckruf.clientID
        konto.idToken = idToken
        konto.email = claims.email
        konto.subject = claims.subject
        let sitzung = ChatGPTSession(accessToken: antwort.accessToken, refreshToken: refresh,
                                     expiresAt: now().addingTimeInterval(antwort.expiresIn),
                                     scopes: antwort.scopes)
        do {
            try ChatGPTCredentialStore.saveAccount(konto, service: service)
            try ChatGPTCredentialStore.saveSession(sitzung, service: service)
        } catch {
            throw ChatGPTAuthError.callbackFailed("Keychain")
        }
        await ChatGPTPlanStatus.melden(angemeldet: true)
        return konto
    }

    /// Prüft das ID-Token gegen OpenAIs Schlüssel. Ist der `kid` unbekannt, wird
    /// die Schlüsselliste einmal neu geholt — OpenAI kann sie jederzeit wechseln.
    private func pruefen(_ idToken: String, clientID: String,
                         nonce: String) async throws -> ChatGPTOAuth.IDClaims {
        let kid = Self.kid(of: idToken)
        if schluessel[kid] == nil {
            var request = URLRequest(url: ChatGPTPlan.jwksURL)
            request.timeoutInterval = 20
            let (data, status): (Data, Int)
            do { (data, status) = try await senden(request) }
            catch { throw ChatGPTAuthError.network }
            guard status == 200 else { throw ChatGPTAuthError.invalidIDToken("JWKS \(status)") }
            schluessel = ChatGPTOAuth.parseJWKS(data)
        }
        let bekannt = schluessel
        return try ChatGPTOAuth.validateIDToken(idToken, clientID: clientID, nonce: nonce,
                                                now: now()) { kid in
            guard let key = bekannt[kid] else { throw ChatGPTAuthError.invalidIDToken("Schlüssel") }
            return key
        }
    }

    private static func kid(of jwt: String) -> String {
        guard let kopf = jwt.split(separator: ".").first,
              let data = ChatGPTOAuth.base64URLDecode(kopf),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return "" }
        return json["kid"] as? String ?? ""
    }

    // MARK: - Abmelden

    /// Widerruft das Refresh-Token bei OpenAI und löscht die Anmeldung.
    ///
    /// Lokal wird **immer** gelöscht, auch wenn der Widerruf nicht durchgeht —
    /// der Rückgabewert sagt nur, ob OpenAI ihn bestätigt hat. Die Registrierung
    /// (Client-ID, Host-ID) bleibt, damit die nächste Anmeldung sie wiederverwendet.
    @discardableResult
    func signOut() async -> Bool {
        defer {
            try? ChatGPTCredentialStore.deleteSession(service: service)
        }
        guard let sitzung = ChatGPTCredentialStore.loadSession(service: service),
              let clientID = ChatGPTCredentialStore.loadAccount(service: service)?.clientID
        else {
            await ChatGPTPlanStatus.melden(angemeldet: false)
            return true
        }
        let request = ChatGPTOAuth.revokeRequest(refreshToken: sitzung.refreshToken,
                                                 clientID: clientID)
        var bestaetigt = false
        for versuch in 0..<3 {
            if let (_, status) = try? await senden(request) {
                if status == 200 { bestaetigt = true; break }
                if status < 500 { break }
            }
            if versuch < 2 { try? await Task.sleep(nanoseconds: UInt64(versuch + 1) * 1_000_000_000) }
        }
        await ChatGPTPlanStatus.melden(angemeldet: false)
        return bestaetigt
    }

    /// Was der Browser nach dem Rückruf zeigt. Zweisprachig, weil der Actor die
    /// eingestellte Oberflächensprache nicht kennt — und die Seite nur einen
    /// Satz lang zu sehen ist.
    private static let fertigSeite = """
    <!doctype html><html><head><meta charset="utf-8"><title>shout.</title>
    <style>body{font:16px -apple-system,sans-serif;background:#111;color:#eee;
    display:flex;align-items:center;justify-content:center;height:100vh;margin:0}
    p{max-width:28em;text-align:center;line-height:1.5}</style></head>
    <body><p><b>shout.</b><br>Du kannst dieses Fenster schließen und zu shout. zurückkehren.<br>
    <span style="color:#999">You can close this window and return to shout.</span></p></body></html>
    """
}

/// Was die Oberfläche über das Abo wissen muss, ohne die Keychain abzufragen:
/// ob angemeldet, und ob zuletzt das Limit erreicht war.
@MainActor
final class ChatGPTPlanStatus: ObservableObject {

    static let shared = ChatGPTPlanStatus()

    @Published private(set) var signedIn = ChatGPTCredentialStore.hasSession()
    @Published private(set) var account = ChatGPTCredentialStore.loadAccount()
    /// Wann das Limit zuletzt gemeldet wurde. Die Oberfläche zeigt dann den
    /// Weg zu „Nutzung verwalten" — einen Zeitpunkt fürs Zurücksetzen nennt
    /// OpenAI nicht, also wird auch keiner erfunden.
    @Published private(set) var limitReachedAt: Date?

    func refresh() {
        signedIn = ChatGPTCredentialStore.hasSession()
        account = ChatGPTCredentialStore.loadAccount()
        if !signedIn { limitReachedAt = nil }
    }

    func limitReached(at date: Date = Date()) {
        limitReachedAt = date
    }

    nonisolated static func melden(angemeldet: Bool) async {
        await MainActor.run {
            shared.refresh()
            if angemeldet { shared.limitReachedAt = nil }
        }
    }
}
