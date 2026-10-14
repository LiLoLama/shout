import XCTest
import Security

/// Die reinen Bausteine der ChatGPT-Anmeldung. Jeder Fehler hier ist entweder
/// eine Anmeldung, die nie klappt, oder — schlimmer — eine, die etwas annimmt,
/// was sie hätte ablehnen müssen.
final class ChatGPTOAuthTests: XCTestCase {

    private let konto = ChatGPTAccount(hostID: "urn:uuid:11111111-2222-3333-4444-555555555555")

    // MARK: - PKCE

    /// Prüfwert aus RFC 7636, Anhang B.
    func testCodeChallengeNachRFC7636() {
        XCTAssertEqual(ChatGPTOAuth.codeChallenge(for: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"),
                       "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    }

    func testZufallswerteSindBase64URLUndVerschieden() {
        let a = ChatGPTOAuth.randomToken()
        let b = ChatGPTOAuth.randomToken()
        XCTAssertNotEqual(a, b)
        XCTAssertEqual(a.count, 43)
        XCTAssertNil(a.rangeOfCharacter(from: CharacterSet(charactersIn: "+/=")))
    }

    // MARK: - Anmelde-Adresse

    private func parameter(_ url: URL) -> [String: String] {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        return Dictionary(items.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { a, _ in a })
    }

    func testErsteAnmeldungRegistriertDenMac() {
        let url = ChatGPTOAuth.authorizeURL(account: konto,
                                            redirectURI: "http://127.0.0.1:1455/auth/callback",
                                            state: "S", nonce: "N", challenge: "C")
        let p = parameter(url)
        XCTAssertEqual(url.host, "auth.openai.com")
        XCTAssertEqual(url.path, "/api/accounts/authorize")
        XCTAssertEqual(p["client_id"], "dynamic_agent_client")
        XCTAssertEqual(p["agent_name_hint"], "shout.")
        XCTAssertEqual(p["ext_agent_host_id"], konto.hostID)
        XCTAssertEqual(p["response_type"], "code")
        XCTAssertEqual(p["redirect_uri"], "http://127.0.0.1:1455/auth/callback")
        XCTAssertEqual(p["scope"],
                       "openid profile email offline_access resource.invoke chatgpt.tokens.use.direct")
        XCTAssertEqual(p["resource"], "https://api.openai.com/v1")
        XCTAssertEqual(p["state"], "S")
        XCTAssertEqual(p["nonce"], "N")
        XCTAssertEqual(p["code_challenge"], "C")
        XCTAssertEqual(p["code_challenge_method"], "S256")
        XCTAssertNil(p["id_token_hint"])
    }

    /// Danach: ausgestellte Client-ID, kein App-Name, ID-Token als Hinweis.
    func testSpaetereAnmeldungNutztAusgestellteClientID() {
        var registriert = konto
        registriert.clientID = "oaiapp_abc"
        registriert.idToken = "kopf.inhalt.signatur"
        let p = parameter(ChatGPTOAuth.authorizeURL(account: registriert, redirectURI: "x",
                                                    state: "S", nonce: "N", challenge: "C"))
        XCTAssertEqual(p["client_id"], "oaiapp_abc")
        XCTAssertNil(p["agent_name_hint"])
        XCTAssertEqual(p["id_token_hint"], "kopf.inhalt.signatur")
        XCTAssertEqual(p["ext_agent_host_id"], konto.hostID)
    }

    // MARK: - Rückruf

    private func q(_ paare: [String: String]) -> [URLQueryItem] {
        paare.map { URLQueryItem(name: $0.key, value: $0.value) }
    }

    func testRueckrufMitClientIDBeiErstanmeldung() throws {
        let r = try ChatGPTOAuth.parseCallback(q(["code": "K", "state": "S", "client_id": "oaiapp_1"]),
                                               expectedState: "S", knownClientID: nil)
        XCTAssertEqual(r, .init(code: "K", clientID: "oaiapp_1"))
    }

    /// Der State wird zuerst geprüft — auch vor einer Fehlermeldung, die ein
    /// fremder Rückruf sonst unterschieben könnte.
    func testFalscherStateWirdAbgelehnt() {
        XCTAssertThrowsError(try ChatGPTOAuth.parseCallback(
            q(["code": "K", "state": "fremd", "client_id": "oaiapp_1"]),
            expectedState: "S", knownClientID: nil)) {
            XCTAssertEqual($0 as? ChatGPTAuthError, .stateMismatch)
        }
        XCTAssertThrowsError(try ChatGPTOAuth.parseCallback(
            q(["error": "access_denied"]), expectedState: "S", knownClientID: nil)) {
            XCTAssertEqual($0 as? ChatGPTAuthError, .stateMismatch)
        }
    }

    func testAbgelehntImBrowser() {
        XCTAssertThrowsError(try ChatGPTOAuth.parseCallback(
            q(["error": "access_denied", "state": "S"]), expectedState: "S", knownClientID: nil)) {
            XCTAssertEqual($0 as? ChatGPTAuthError, .denied)
        }
    }

    /// Bei der erneuten Anmeldung darf die Client-ID fehlen — eine abweichende
    /// dagegen wird abgelehnt.
    func testErneuteAnmeldungClientID() throws {
        let ohne = try ChatGPTOAuth.parseCallback(q(["code": "K", "state": "S"]),
                                                  expectedState: "S", knownClientID: "oaiapp_1")
        XCTAssertEqual(ohne.clientID, "oaiapp_1")
        XCTAssertThrowsError(try ChatGPTOAuth.parseCallback(
            q(["code": "K", "state": "S", "client_id": "oaiapp_2"]),
            expectedState: "S", knownClientID: "oaiapp_1")) {
            XCTAssertEqual($0 as? ChatGPTAuthError, .clientMismatch)
        }
    }

    func testErstanmeldungOhneClientIDScheitert() {
        XCTAssertThrowsError(try ChatGPTOAuth.parseCallback(q(["code": "K", "state": "S"]),
                                                            expectedState: "S", knownClientID: nil))
    }

    // MARK: - Token-Endpunkt

    private func formular(_ request: URLRequest) -> [String: String] {
        let text = String(decoding: request.httpBody ?? Data(), as: UTF8.self)
        var ergebnis: [String: String] = [:]
        for paar in text.split(separator: "&") {
            let teile = paar.split(separator: "=", maxSplits: 1).map(String.init)
            ergebnis[teile[0]] = teile.count > 1 ? teile[1].removingPercentEncoding : ""
        }
        return ergebnis
    }

    func testCodeTausch() {
        let request = ChatGPTOAuth.codeExchangeRequest(code: "K+/=", clientID: "oaiapp_1",
                                                       verifier: "V", redirectURI: "http://127.0.0.1:1455/auth/callback")
        XCTAssertEqual(request.url, ChatGPTPlan.tokenURL)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"),
                       "application/x-www-form-urlencoded")
        let f = formular(request)
        XCTAssertEqual(f["grant_type"], "authorization_code")
        XCTAssertEqual(f["client_id"], "oaiapp_1")
        XCTAssertEqual(f["code"], "K+/=")
        XCTAssertEqual(f["code_verifier"], "V")
        XCTAssertEqual(f["redirect_uri"], "http://127.0.0.1:1455/auth/callback")
        XCTAssertEqual(f["resource"], "https://api.openai.com/v1")
        // „+" muss kodiert ankommen, sonst liest der Server ein Leerzeichen.
        XCTAssertFalse(String(decoding: request.httpBody!, as: UTF8.self).contains("K+"))
    }

    /// Beim Erneuern kein `scope` — sonst könnte die Berechtigung schrumpfen.
    func testErneuerungOhneScope() {
        let f = formular(ChatGPTOAuth.refreshRequest(refreshToken: "R", clientID: "oaiapp_1"))
        XCTAssertEqual(f["grant_type"], "refresh_token")
        XCTAssertEqual(f["refresh_token"], "R")
        XCTAssertEqual(f["client_id"], "oaiapp_1")
        XCTAssertEqual(f["resource"], "https://api.openai.com/v1")
        XCTAssertNil(f["scope"])
    }

    func testTokenAntwort() throws {
        let json = """
        {"access_token":"A","refresh_token":"R","id_token":"I","token_type":"Bearer",
         "expires_in":3600,"scope":"openid offline_access chatgpt.tokens.use.direct"}
        """
        let t = try ChatGPTOAuth.parseTokenResponse(Data(json.utf8))
        XCTAssertEqual(t.accessToken, "A")
        XCTAssertEqual(t.refreshToken, "R")
        XCTAssertEqual(t.idToken, "I")
        XCTAssertEqual(t.expiresIn, 3600)
        XCTAssertTrue(t.scopes.contains(ChatGPTPlan.usageScope))
    }

    func testFehlercodeAusTokenAntwort() {
        XCTAssertEqual(ChatGPTOAuth.errorCode(from: Data(#"{"error":"invalid_grant"}"#.utf8)),
                       "invalid_grant")
        XCTAssertEqual(ChatGPTOAuth.errorCode(from: Data(#"{"error":{"code":"refresh_token_reused"}}"#.utf8)),
                       "refresh_token_reused")
    }

    // MARK: - ID-Token

    private func schluesselpaar() throws -> (privat: SecKey, oeffentlich: SecKey) {
        let attribute: [String: Any] = [kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
                                        kSecAttrKeySizeInBits as String: 2048]
        var fehler: Unmanaged<CFError>?
        guard let privat = SecKeyCreateRandomKey(attribute as CFDictionary, &fehler),
              let oeffentlich = SecKeyCopyPublicKey(privat)
        else { throw XCTSkip("Kein RSA-Schlüssel erzeugbar") }
        return (privat, oeffentlich)
    }

    private func jwt(_ claims: [String: Any], privat: SecKey, kid: String = "k1",
                     alg: String = "RS256") throws -> String {
        let kopf = try JSONSerialization.data(withJSONObject: ["alg": alg, "kid": kid, "typ": "JWT"])
        let inhalt = try JSONSerialization.data(withJSONObject: claims)
        let eingabe = ChatGPTOAuth.base64URL(kopf) + "." + ChatGPTOAuth.base64URL(inhalt)
        let signatur = SecKeyCreateSignature(privat, .rsaSignatureMessagePKCS1v15SHA256,
                                             Data(eingabe.utf8) as CFData, nil)! as Data
        return eingabe + "." + ChatGPTOAuth.base64URL(signatur)
    }

    private let jetzt = Date(timeIntervalSince1970: 1_790_000_000)

    private func gueltigeClaims() -> [String: Any] {
        ["iss": "https://auth.openai.com", "aud": "oaiapp_1", "sub": "user-123",
         "email": "liam@example.com", "nonce": "N", "exp": 1_790_000_600]
    }

    func testGueltigesIDToken() throws {
        let paar = try schluesselpaar()
        let token = try jwt(gueltigeClaims(), privat: paar.privat)
        let claims = try ChatGPTOAuth.validateIDToken(token, clientID: "oaiapp_1", nonce: "N",
                                                      now: jetzt) { _ in paar.oeffentlich }
        XCTAssertEqual(claims, .init(subject: "user-123", email: "liam@example.com"))
    }

    /// Jede einzelne Abweichung muss zur Ablehnung führen.
    func testIDTokenAbweichungenWerdenAbgelehnt() throws {
        let paar = try schluesselpaar()
        let faelle: [(String, (inout [String: Any]) -> Void)] = [
            ("Aussteller", { $0["iss"] = "https://boese.example" }),
            ("Empfänger", { $0["aud"] = "oaiapp_fremd" }),
            ("abgelaufen", { $0["exp"] = 1_789_999_000 }),
            ("Nonce", { $0["nonce"] = "fremd" }),
        ]
        for (name, aendern) in faelle {
            var claims = gueltigeClaims()
            aendern(&claims)
            let token = try jwt(claims, privat: paar.privat)
            XCTAssertThrowsError(try ChatGPTOAuth.validateIDToken(
                token, clientID: "oaiapp_1", nonce: "N", now: jetzt) { _ in paar.oeffentlich },
                "\(name) hätte abgelehnt werden müssen")
        }
    }

    func testFremderSchluesselWirdAbgelehnt() throws {
        let echt = try schluesselpaar()
        let fremd = try schluesselpaar()
        let token = try jwt(gueltigeClaims(), privat: fremd.privat)
        XCTAssertThrowsError(try ChatGPTOAuth.validateIDToken(
            token, clientID: "oaiapp_1", nonce: "N", now: jetzt) { _ in echt.oeffentlich }) {
            XCTAssertEqual($0 as? ChatGPTAuthError, .invalidIDToken("Signatur"))
        }
    }

    func testAudAlsListe() throws {
        let paar = try schluesselpaar()
        var claims = gueltigeClaims()
        claims["aud"] = ["anderer", "oaiapp_1"]
        let token = try jwt(claims, privat: paar.privat)
        XCTAssertNoThrow(try ChatGPTOAuth.validateIDToken(
            token, clientID: "oaiapp_1", nonce: "N", now: jetzt) { _ in paar.oeffentlich })
    }

    /// Ein JWK aus Modulus und Exponent muss genau den Schlüssel ergeben, der
    /// die Signatur erzeugt hat — sonst schlägt jede echte Anmeldung fehl.
    func testJWKWirdZumSelbenSchluessel() throws {
        let paar = try schluesselpaar()
        let der = SecKeyCopyExternalRepresentation(paar.oeffentlich, nil)! as Data
        let (n, e) = try Self.modulusUndExponent(der)
        let jwks = """
        {"keys":[{"kty":"RSA","kid":"k1","alg":"RS256","use":"sig",
                  "n":"\(ChatGPTOAuth.base64URL(n))","e":"\(ChatGPTOAuth.base64URL(e))"}]}
        """
        let schluessel = ChatGPTOAuth.parseJWKS(Data(jwks.utf8))
        let gebaut = try XCTUnwrap(schluessel["k1"])
        let token = try jwt(gueltigeClaims(), privat: paar.privat)
        XCTAssertNoThrow(try ChatGPTOAuth.validateIDToken(
            token, clientID: "oaiapp_1", nonce: "N", now: jetzt) { _ in gebaut })
    }

    /// Liest `SEQUENCE { INTEGER n, INTEGER e }` — nur für diesen Test.
    private static func modulusUndExponent(_ der: Data) throws -> (Data, Data) {
        var i = der.startIndex
        func laenge() -> Int {
            let erstes = Int(der[i]); i += 1
            guard erstes & 0x80 != 0 else { return erstes }
            var n = 0
            for _ in 0..<(erstes & 0x7F) { n = n << 8 | Int(der[i]); i += 1 }
            return n
        }
        func integer() -> Data {
            precondition(der[i] == 0x02); i += 1
            let l = laenge()
            defer { i += l }
            return der.subdata(in: i..<(i + l))
        }
        guard der[i] == 0x30 else { throw XCTSkip("Unerwartetes DER") }
        i += 1
        _ = laenge()
        let n = integer()
        let e = integer()
        return (n, e)
    }
}
