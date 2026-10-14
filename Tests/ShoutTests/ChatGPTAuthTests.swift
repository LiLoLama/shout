import XCTest

/// Erneuern, Abmelden, Rückruf — die Teile der Anmeldung mit Zustand.
final class ChatGPTAuthTests: XCTestCase {

    /// Eigene Service-Kennung: Die Tests fassen die echte Anmeldung nicht an.
    private let service = "com.inthezone.flowlokal.chatgpt.tests"

    private final class Uhr: @unchecked Sendable {
        var jetzt = Date(timeIntervalSince1970: 1_790_000_000)
    }

    override func setUp() {
        super.setUp()
        StubURLProtocol.reset()
        aufraeumen()
    }

    override func tearDown() {
        StubURLProtocol.reset()
        aufraeumen()
        super.tearDown()
    }

    private func aufraeumen() {
        try? ProviderKeychain.delete(for: "registration", service: service)
        try? ProviderKeychain.delete(for: "session", service: service)
    }

    private func anmelden(ablauf: Date, uhr: Uhr) throws {
        try ChatGPTCredentialStore.saveAccount(
            ChatGPTAccount(hostID: "urn:uuid:test", clientID: "oaiapp_1"), service: service)
        try ChatGPTCredentialStore.saveSession(
            ChatGPTSession(accessToken: "A1", refreshToken: "R1", expiresAt: ablauf,
                           scopes: [ChatGPTPlan.usageScope]), service: service)
    }

    private func auth(_ uhr: Uhr) -> ChatGPTAuth {
        ChatGPTAuth(session: StubURLProtocol.session(), service: service, now: { uhr.jetzt })
    }

    private static func tokenAntwort(_ access: String, refresh: String) -> StubURLProtocol.Antwort {
        let json = """
        {"access_token":"\(access)","refresh_token":"\(refresh)","token_type":"Bearer",
         "expires_in":3600,"scope":"openid offline_access chatgpt.tokens.use.direct"}
        """
        return .init(body: Data(json.utf8))
    }

    // MARK: - Gültiges Token

    func testGueltigesTokenOhneNetz() async throws {
        let uhr = Uhr()
        try anmelden(ablauf: uhr.jetzt.addingTimeInterval(3000), uhr: uhr)
        let token = try await auth(uhr).accessToken()
        XCTAssertEqual(token, "A1")
        XCTAssertTrue(StubURLProtocol.anfragen.isEmpty)
    }

    func testOhneAnmeldung() async {
        do {
            _ = try await auth(Uhr()).accessToken()
            XCTFail("Hätte scheitern müssen")
        } catch {
            XCTAssertEqual(error as? RemoteProviderError, .signInRequired)
        }
    }

    // MARK: - Erneuern

    /// Kurz vor Ablauf wird erneuert, und das neue Refresh-Token ersetzt das alte.
    func testErneuernErsetztBeideTokens() async throws {
        let uhr = Uhr()
        try anmelden(ablauf: uhr.jetzt.addingTimeInterval(60), uhr: uhr)
        StubURLProtocol.antworten = [Self.tokenAntwort("A2", refresh: "R2")]

        let token = try await auth(uhr).accessToken()

        XCTAssertEqual(token, "A2")
        let gespeichert = try XCTUnwrap(ChatGPTCredentialStore.loadSession(service: service))
        XCTAssertEqual(gespeichert.refreshToken, "R2")
        XCTAssertEqual(gespeichert.expiresAt, uhr.jetzt.addingTimeInterval(3600))
        let rumpf = String(decoding: StubURLProtocol.anfragen[0].body, as: UTF8.self)
        XCTAssertTrue(rumpf.contains("refresh_token=R1"))
        XCTAssertTrue(rumpf.contains("client_id=oaiapp_1"))
    }

    /// Gleichzeitige Aufrufer teilen sich EINE Erneuerung. Zwei würden sich
    /// gegenseitig das rotierende Refresh-Token ungültig machen.
    func testGleichzeitigeAufruferTeilenEineErneuerung() async throws {
        let uhr = Uhr()
        try anmelden(ablauf: uhr.jetzt.addingTimeInterval(60), uhr: uhr)
        StubURLProtocol.antworten = [Self.tokenAntwort("A2", refresh: "R2"),
                                     Self.tokenAntwort("A3", refresh: "R3")]
        let a = auth(uhr)

        async let eins = a.accessToken()
        async let zwei = a.accessToken()
        async let drei = a.accessToken()
        let tokens = try await [eins, zwei, drei]

        XCTAssertEqual(Set(tokens), ["A2"])
        XCTAssertEqual(StubURLProtocol.anfragen.count, 1)
    }

    /// Ein endgültig wertloses Refresh-Token meldet ab.
    func testWertlosesRefreshTokenMeldetAb() async throws {
        let uhr = Uhr()
        try anmelden(ablauf: uhr.jetzt.addingTimeInterval(60), uhr: uhr)
        StubURLProtocol.antworten = [.init(status: 400, body: Data(#"{"error":"invalid_grant"}"#.utf8))]
        do {
            _ = try await auth(uhr).accessToken()
            XCTFail("Hätte scheitern müssen")
        } catch {
            XCTAssertEqual(error as? RemoteProviderError, .signInRequired)
        }
        XCTAssertNil(ChatGPTCredentialStore.loadSession(service: service))
        XCTAssertEqual(ChatGPTCredentialStore.loadAccount(service: service)?.clientID, "oaiapp_1",
                       "Die Registrierung bleibt für die nächste Anmeldung")
    }

    /// Ein Funkloch darf niemanden abmelden.
    func testNetzfehlerBehaeltDieAnmeldung() async throws {
        let uhr = Uhr()
        try anmelden(ablauf: uhr.jetzt.addingTimeInterval(60), uhr: uhr)
        StubURLProtocol.antworten = [.init(error: URLError(.notConnectedToInternet))]
        do {
            _ = try await auth(uhr).accessToken()
            XCTFail("Hätte scheitern müssen")
        } catch {
            XCTAssertTrue((error as? RemoteProviderError)?.isTransient == true)
        }
        XCTAssertNotNil(ChatGPTCredentialStore.loadSession(service: service))
    }

    func testServerfehlerBehaeltDieAnmeldung() async throws {
        let uhr = Uhr()
        try anmelden(ablauf: uhr.jetzt.addingTimeInterval(60), uhr: uhr)
        StubURLProtocol.antworten = [.init(status: 502)]
        do {
            _ = try await auth(uhr).accessToken()
            XCTFail("Hätte scheitern müssen")
        } catch {
            XCTAssertEqual(error as? RemoteProviderError, .http(status: 502))
        }
        XCTAssertNotNil(ChatGPTCredentialStore.loadSession(service: service))
    }

    // MARK: - Abmelden

    func testAbmeldenWiderruftUndLoescht() async throws {
        let uhr = Uhr()
        try anmelden(ablauf: uhr.jetzt.addingTimeInterval(3000), uhr: uhr)
        StubURLProtocol.antworten = [.init(status: 200)]

        let bestaetigt = await auth(uhr).signOut()

        XCTAssertTrue(bestaetigt)
        XCTAssertNil(ChatGPTCredentialStore.loadSession(service: service))
        XCTAssertEqual(StubURLProtocol.anfragen[0].request.url, ChatGPTPlan.revokeURL)
        let rumpf = String(decoding: StubURLProtocol.anfragen[0].body, as: UTF8.self)
        XCTAssertTrue(rumpf.contains("token=R1"))
        XCTAssertTrue(rumpf.contains("token_type_hint=refresh_token"))
    }

    /// Auch ohne Bestätigung wird lokal gelöscht.
    func testAbmeldenOhneBestaetigungLoeschtTrotzdem() async throws {
        let uhr = Uhr()
        try anmelden(ablauf: uhr.jetzt.addingTimeInterval(3000), uhr: uhr)
        StubURLProtocol.antworten = [.init(status: 400)]
        let bestaetigt = await auth(uhr).signOut()
        XCTAssertFalse(bestaetigt)
        XCTAssertNil(ChatGPTCredentialStore.loadSession(service: service))
    }

    // MARK: - Registrierung

    func testHostIDBleibtStabil() throws {
        let erste = try ChatGPTCredentialStore.ensureAccount(service: service)
        let zweite = try ChatGPTCredentialStore.ensureAccount(service: service)
        XCTAssertEqual(erste.hostID, zweite.hostID)
        XCTAssertTrue(erste.hostID.hasPrefix("urn:uuid:"))
    }

    // MARK: - Rückruf auf 127.0.0.1

    func testLoopbackNimmtDenRueckrufEntgegen() async throws {
        let server = try await LoopbackServer.start(preferredPort: 0, path: "/auth/callback",
                                                    page: "fertig")
        defer { server.stop() }
        XCTAssertGreaterThan(server.port, 0)

        async let warten = server.waitForCallback(timeout: 5)
        let falsch = URL(string: "http://127.0.0.1:\(server.port)/favicon.ico")!
        let (_, r404) = try await URLSession.shared.data(from: falsch)
        XCTAssertEqual((r404 as? HTTPURLResponse)?.statusCode, 404)

        let url = URL(string: "http://127.0.0.1:\(server.port)/auth/callback?code=K&state=S")!
        let (data, antwort) = try await URLSession.shared.data(from: url)
        XCTAssertEqual((antwort as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertEqual(String(decoding: data, as: UTF8.self), "fertig")

        let items = try await warten
        XCTAssertEqual(items.first { $0.name == "code" }?.value, "K")
        XCTAssertEqual(items.first { $0.name == "state" }?.value, "S")
    }

    func testLoopbackZeitgrenze() async throws {
        let server = try await LoopbackServer.start(preferredPort: 0, path: "/auth/callback",
                                                    page: "")
        defer { server.stop() }
        do {
            _ = try await server.waitForCallback(timeout: 0.2)
            XCTFail("Hätte ablaufen müssen")
        } catch {
            XCTAssertEqual(error as? ChatGPTAuthError, .timedOut)
        }
    }

    /// Ist der Wunsch-Port belegt, wird ein anderer genommen.
    func testBelegterPortWeichtAus() async throws {
        let erster = try await LoopbackServer.start(preferredPort: 0, path: "/auth/callback", page: "")
        defer { erster.stop() }
        let zweiter = try await LoopbackServer.start(preferredPort: erster.port,
                                                     path: "/auth/callback", page: "")
        defer { zweiter.stop() }
        XCTAssertNotEqual(erster.port, zweiter.port)
    }
}
