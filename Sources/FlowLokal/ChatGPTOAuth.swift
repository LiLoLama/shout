import Foundation
import CryptoKit
import Security

/// Was bei der ChatGPT-Anmeldung schiefgehen kann. Wie `RemoteProviderError`
/// ohne Anzeigetexte und ohne Token-Werte — übersetzt wird in `ProviderText`.
enum ChatGPTAuthError: Error, Equatable {
    /// Der Nutzer hat abgebrochen (in der App oder im Browser).
    case cancelled
    /// Im Browser abgelehnt (`error=access_denied`).
    case denied
    /// Der Rückruf passt nicht zu diesem Anmeldeversuch.
    case stateMismatch
    /// OpenAI hat eine andere Client-ID zurückgegeben als die gespeicherte.
    case clientMismatch
    /// Rückruf ohne Code oder mit einem anderen Fehler.
    case callbackFailed(String)
    /// Das ID-Token hat die Prüfung nicht bestanden.
    case invalidIDToken(String)
    /// Angemeldet, aber ohne Erlaubnis, das Abo zu nutzen.
    case missingUsageScope
    /// Der Token-Tausch wurde abgelehnt.
    case tokenRejected(status: Int, code: String?)
    /// Kein Port auf 127.0.0.1 frei.
    case listenerFailed
    /// Fünf Minuten ohne Rückruf aus dem Browser.
    case timedOut
    /// Netz weg.
    case network
}

/// Die reinen Bausteine der Anmeldung: PKCE, Adressen, Rückruf, Token-Antwort,
/// ID-Token. Ohne Netz und ohne Zustand, damit alles davon prüfbar ist.
enum ChatGPTOAuth {

    // MARK: - Zufall und PKCE

    /// 32 Zufallsbytes, base64url ohne Auffüllung — für `state`, `nonce` und
    /// den PKCE-Verifier.
    static func randomToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        precondition(status == errSecSuccess, "Keine Zufallszahlen")
        return base64URL(Data(bytes))
    }

    static func codeChallenge(for verifier: String) -> String {
        base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
    }

    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func base64URLDecode(_ text: Substring) -> Data? {
        var s = text.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while s.count % 4 != 0 { s += "=" }
        return Data(base64Encoded: s)
    }

    static func redirectURI(port: UInt16) -> String {
        "http://127.0.0.1:\(port)\(ChatGPTPlan.callbackPath)"
    }

    // MARK: - Anmelde-Adresse

    /// Die Adresse, die im Browser geöffnet wird.
    ///
    /// Erste Anmeldung: `dynamic_agent_client` plus App-Name. Danach die
    /// ausgestellte Client-ID, ohne App-Name, mit dem letzten ID-Token als
    /// Hinweis — so landet man ohne Kontoauswahl wieder im selben Konto.
    static func authorizeURL(account: ChatGPTAccount, redirectURI: String,
                             state: String, nonce: String, challenge: String) -> URL {
        var items = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id",
                         value: account.clientID ?? ChatGPTPlan.registrationClientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "scope", value: ChatGPTPlan.scopes),
            URLQueryItem(name: "resource", value: ChatGPTPlan.resource),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "nonce", value: nonce),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "ext_agent_host_id", value: account.hostID),
        ]
        if account.clientID == nil {
            items.append(URLQueryItem(name: "agent_name_hint", value: ChatGPTPlan.agentName))
        } else if let hint = account.idToken {
            items.append(URLQueryItem(name: "id_token_hint", value: hint))
        }
        var comps = URLComponents(url: ChatGPTPlan.authorizeURL, resolvingAgainstBaseURL: false)!
        comps.queryItems = items
        // `URLComponents` lässt „+" in Werten stehen; ein Server liest es als
        // Leerzeichen. Im Scope stehen echte Leerzeichen, die werden korrekt
        // zu %20 — aber ein „+" in einem Token darf nicht umgedeutet werden.
        comps.percentEncodedQuery = comps.percentEncodedQuery?
            .replacingOccurrences(of: "+", with: "%2B")
        return comps.url!
    }

    // MARK: - Rückruf

    struct Callback: Equatable {
        let code: String
        /// Die ausgestellte Client-ID. Bei einer erneuten Anmeldung kann sie
        /// fehlen — dann gilt die gespeicherte.
        let clientID: String
    }

    /// Prüft den Rückruf. `state` zuerst, vor allem anderen: Ein Rückruf, der
    /// nicht zu diesem Versuch gehört, wird nicht weiter angefasst.
    static func parseCallback(_ items: [URLQueryItem], expectedState: String,
                              knownClientID: String?) throws -> Callback {
        func wert(_ name: String) -> String? {
            items.first { $0.name == name }?.value.flatMap { $0.isEmpty ? nil : $0 }
        }
        guard wert("state") == expectedState else { throw ChatGPTAuthError.stateMismatch }
        if let fehler = wert("error") {
            throw fehler == "access_denied" ? ChatGPTAuthError.denied
                                            : ChatGPTAuthError.callbackFailed(fehler)
        }
        guard let code = wert("code") else { throw ChatGPTAuthError.callbackFailed("ohne Code") }

        let geliefert = wert("client_id")
        if let known = knownClientID {
            if let geliefert, geliefert != known { throw ChatGPTAuthError.clientMismatch }
            return Callback(code: code, clientID: known)
        }
        guard let geliefert else { throw ChatGPTAuthError.callbackFailed("ohne Client-ID") }
        return Callback(code: code, clientID: geliefert)
    }

    // MARK: - Token-Endpunkt

    static func codeExchangeRequest(code: String, clientID: String, verifier: String,
                                    redirectURI: String) -> URLRequest {
        formRequest(ChatGPTPlan.tokenURL, [
            ("grant_type", "authorization_code"),
            ("client_id", clientID),
            ("code", code),
            ("code_verifier", verifier),
            ("redirect_uri", redirectURI),
            ("resource", ChatGPTPlan.resource),
        ])
    }

    /// Ohne `scope` — so bleibt die gewährte Berechtigung, wie sie ist.
    static func refreshRequest(refreshToken: String, clientID: String) -> URLRequest {
        formRequest(ChatGPTPlan.tokenURL, [
            ("grant_type", "refresh_token"),
            ("client_id", clientID),
            ("refresh_token", refreshToken),
            ("resource", ChatGPTPlan.resource),
        ])
    }

    static func revokeRequest(refreshToken: String, clientID: String) -> URLRequest {
        formRequest(ChatGPTPlan.revokeURL, [
            ("token", refreshToken),
            ("token_type_hint", "refresh_token"),
            ("client_id", clientID),
        ])
    }

    private static func formRequest(_ url: URL, _ felder: [(String, String)]) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        // Streng nach RFC 3986: nur unreservierte Zeichen bleiben stehen. Die
        // Standardmenge von Foundation ließe „+", „&" und „=" durch.
        var erlaubt = CharacterSet.alphanumerics
        erlaubt.insert(charactersIn: "-._~")
        let rumpf = felder.map { name, wert in
            "\(name)=\(wert.addingPercentEncoding(withAllowedCharacters: erlaubt) ?? "")"
        }.joined(separator: "&")
        request.httpBody = Data(rumpf.utf8)
        return request
    }

    struct TokenResponse: Equatable {
        let accessToken: String
        let refreshToken: String?
        let idToken: String?
        let expiresIn: TimeInterval
        let scopes: [String]
    }

    static func parseTokenResponse(_ data: Data) throws -> TokenResponse {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let access = json["access_token"] as? String, !access.isEmpty
        else { throw ChatGPTAuthError.tokenRejected(status: 200, code: "ohne access_token") }
        let expires = (json["expires_in"] as? NSNumber)?.doubleValue ?? 3600
        let scopes = (json["scope"] as? String)?.split(separator: " ").map(String.init) ?? []
        return TokenResponse(accessToken: access,
                             refreshToken: json["refresh_token"] as? String,
                             idToken: json["id_token"] as? String,
                             expiresIn: expires,
                             scopes: scopes)
    }

    /// `error` aus einer abgelehnten Token-Antwort (`invalid_grant` usw.).
    static func errorCode(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        if let code = json["error"] as? String { return code }
        if let error = json["error"] as? [String: Any] { return error["code"] as? String }
        return nil
    }

    /// Refresh-Fehler, nach denen das gespeicherte Token endgültig wertlos ist.
    /// Bei allem anderen (Netz, 5xx) bleibt die Anmeldung erhalten.
    static let finalRefreshErrors: Set<String> = [
        "invalid_grant", "invalid_refresh_token", "token_expired",
        "refresh_token_expired", "refresh_token_invalidated", "refresh_token_reused",
    ]

    // MARK: - ID-Token

    struct IDClaims: Equatable {
        let subject: String
        let email: String?
    }

    /// Prüft ein ID-Token vollständig: Signatur (RS256), Aussteller, Empfänger,
    /// Ablauf und `nonce`. Erst danach darf die Anmeldung gespeichert werden.
    static func validateIDToken(_ jwt: String, clientID: String, nonce: String,
                                now: Date, key: (String) throws -> SecKey) throws -> IDClaims {
        let teile = jwt.split(separator: ".", omittingEmptySubsequences: false)
        guard teile.count == 3,
              let kopfDaten = base64URLDecode(teile[0]),
              let inhaltDaten = base64URLDecode(teile[1]),
              let signatur = base64URLDecode(teile[2]),
              let kopf = try? JSONSerialization.jsonObject(with: kopfDaten) as? [String: Any],
              let claims = try? JSONSerialization.jsonObject(with: inhaltDaten) as? [String: Any]
        else { throw ChatGPTAuthError.invalidIDToken("Format") }

        guard kopf["alg"] as? String == "RS256" else {
            throw ChatGPTAuthError.invalidIDToken("Verfahren")
        }
        let schluessel = try key(kopf["kid"] as? String ?? "")
        let signiert = Data("\(teile[0]).\(teile[1])".utf8)
        guard SecKeyVerifySignature(schluessel, .rsaSignatureMessagePKCS1v15SHA256,
                                    signiert as CFData, signatur as CFData, nil)
        else { throw ChatGPTAuthError.invalidIDToken("Signatur") }

        guard claims["iss"] as? String == ChatGPTPlan.issuer else {
            throw ChatGPTAuthError.invalidIDToken("Aussteller")
        }
        let empfaenger: [String]
        if let einer = claims["aud"] as? String { empfaenger = [einer] }
        else { empfaenger = claims["aud"] as? [String] ?? [] }
        guard empfaenger.contains(clientID) else {
            throw ChatGPTAuthError.invalidIDToken("Empfänger")
        }
        guard let exp = (claims["exp"] as? NSNumber)?.doubleValue,
              Date(timeIntervalSince1970: exp) > now
        else { throw ChatGPTAuthError.invalidIDToken("abgelaufen") }
        guard claims["nonce"] as? String == nonce else {
            throw ChatGPTAuthError.invalidIDToken("Nonce")
        }
        guard let sub = claims["sub"] as? String, !sub.isEmpty else {
            throw ChatGPTAuthError.invalidIDToken("ohne sub")
        }
        return IDClaims(subject: sub, email: claims["email"] as? String)
    }

    /// Die öffentlichen Schlüssel aus OpenAIs JWKS, nach `kid`.
    static func parseJWKS(_ data: Data) -> [String: SecKey] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let keys = json["keys"] as? [[String: Any]]
        else { return [:] }
        var ergebnis: [String: SecKey] = [:]
        for jwk in keys {
            guard jwk["kty"] as? String == "RSA",
                  let kid = jwk["kid"] as? String,
                  let n = (jwk["n"] as? String).flatMap({ base64URLDecode(Substring($0)) }),
                  let e = (jwk["e"] as? String).flatMap({ base64URLDecode(Substring($0)) }),
                  let key = rsaPublicKey(modulus: n, exponent: e)
            else { continue }
            ergebnis[kid] = key
        }
        return ergebnis
    }

    /// Baut einen RSA-Schlüssel aus Modulus und Exponent. Apple nimmt RSA-Schlüssel
    /// nur als PKCS#1-DER an (`SEQUENCE { INTEGER n, INTEGER e }`), deshalb wird
    /// das hier von Hand zusammengesetzt.
    static func rsaPublicKey(modulus: Data, exponent: Data) -> SecKey? {
        let der = derSequence(derInteger(modulus) + derInteger(exponent))
        let attribute: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass as String: kSecAttrKeyClassPublic,
        ]
        return SecKeyCreateWithData(der as CFData, attribute as CFDictionary, nil)
    }

    private static func derInteger(_ wert: Data) -> Data {
        var bytes = [UInt8](wert.drop { $0 == 0 })
        if bytes.isEmpty { bytes = [0] }
        // Höchstes Bit gesetzt hieße „negativ" — eine führende Null verhindert das.
        if bytes[0] & 0x80 != 0 { bytes.insert(0, at: 0) }
        return Data([0x02]) + derLength(bytes.count) + Data(bytes)
    }

    private static func derSequence(_ inhalt: Data) -> Data {
        Data([0x30]) + derLength(inhalt.count) + inhalt
    }

    private static func derLength(_ n: Int) -> Data {
        if n < 0x80 { return Data([UInt8(n)]) }
        var bytes: [UInt8] = []
        var rest = n
        while rest > 0 { bytes.insert(UInt8(rest & 0xFF), at: 0); rest >>= 8 }
        return Data([0x80 | UInt8(bytes.count)] + bytes)
    }
}
