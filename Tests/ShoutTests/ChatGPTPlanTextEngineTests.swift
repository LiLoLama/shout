import XCTest

/// Die Abo-Engine. OpenAI schreibt für diesen Weg vieles anders vor als für die
/// API mit Schlüssel — jede Abweichung davon heißt: Anfrage abgelehnt, und der
/// Mensch bekommt nur noch Rohtext.
final class ChatGPTPlanTextEngineTests: XCTestCase {

    override func setUp() {
        super.setUp()
        StubURLProtocol.reset()
    }

    override func tearDown() {
        StubURLProtocol.reset()
        super.tearDown()
    }

    /// Zählt, wie oft und mit welchem Wunsch ein Token geholt wurde.
    private final class Tokens: @unchecked Sendable {
        var anfragen: [Bool] = []
        func quelle() -> ChatGPTPlanTextEngine.TokenSource {
            { erneuern in
                self.anfragen.append(erneuern)
                return erneuern ? "frisch" : "alt"
            }
        }
    }

    private final class Uhr: @unchecked Sendable {
        var jetzt = Date(timeIntervalSince1970: 1_790_000_000)
    }

    private func engine(tokens: Tokens = Tokens(), uhr: Uhr = Uhr(),
                        onPlanLimit: (@Sendable () -> Void)? = nil) -> ChatGPTPlanTextEngine {
        ChatGPTPlanTextEngine(model: "gpt-6-luna",
                              token: tokens.quelle(),
                              session: StubURLProtocol.session(),
                              timeout: 5,
                              now: { uhr.jetzt },
                              onPlanLimit: onPlanLimit)
    }

    private static func strom(_ ereignisse: [[String: Any]]) -> StubURLProtocol.Antwort {
        var text = ""
        for e in ereignisse {
            let data = try! JSONSerialization.data(withJSONObject: e)
            text += "event: \(e["type"] as! String)\ndata: \(String(decoding: data, as: UTF8.self))\n\n"
        }
        return .init(body: Data(text.utf8), headers: ["Content-Type": "text/event-stream"])
    }

    private static func textStrom(_ teile: [String]) -> StubURLProtocol.Antwort {
        strom([["type": "response.created", "response": ["id": "r1"]]]
              + teile.map { ["type": "response.output_text.delta", "delta": $0] }
              + [["type": "response.completed",
                  "response": ["id": "r1", "usage": ["input_tokens": 10, "output_tokens": 5]]]])
    }

    private static func fehler(_ status: Int, code: String, param: String? = nil) -> StubURLProtocol.Antwort {
        var error: [String: Any] = ["code": code, "message": "x", "type": "invalid_request_error"]
        if let param { error["param"] = param }
        let data = try! JSONSerialization.data(withJSONObject: ["error": error])
        return .init(status: status, body: data)
    }

    private func rumpf(_ index: Int = 0) throws -> [String: Any] {
        let body = try XCTUnwrap(StubURLProtocol.anfragen[index].body)
        return try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])
    }

    // MARK: - Der Normalfall

    func testDeltasWerdenZusammengesetzt() async throws {
        StubURLProtocol.antworten = [Self.textStrom(["Der Termin ", "am Dienstag ", "klappt."])]
        let text = try await engine().respond(system: "s", user: "u", temperature: 0.2)
        XCTAssertEqual(text, "Der Termin am Dienstag klappt.")
    }

    /// Die Vorgaben von OpenAI für die Abo-Nutzung — wörtlich.
    func testAnfrageNachAboVorgaben() async throws {
        StubURLProtocol.antworten = [Self.textStrom(["ok"])]
        _ = try await engine().respond(system: "Räum auf.", user: "also äh dienstag", temperature: 0.2)

        let request = StubURLProtocol.anfragen[0].request
        XCTAssertEqual(request.url?.absoluteString, "https://api.openai.com/v1/responses")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer alt")

        let json = try rumpf()
        XCTAssertEqual(json["model"] as? String, "gpt-6-luna")
        XCTAssertEqual(json["store"] as? Bool, false)
        XCTAssertEqual(json["stream"] as? Bool, true)
        XCTAssertEqual(json["instructions"] as? String, "Räum auf.")
        XCTAssertNil(json["temperature"], "temperature lehnt die Abo-Nutzung ab")
        XCTAssertNil(json["messages"])
        XCTAssertNil(json["max_output_tokens"])
        XCTAssertEqual((json["reasoning"] as? [String: Any])?["effort"] as? String, "none")

        let input = try XCTUnwrap(json["input"] as? [[String: Any]])
        XCTAssertEqual(input.count, 1)
        XCTAssertEqual(input[0]["role"] as? String, "user",
                       "Eine System-Nachricht im input wird abgelehnt")
        let inhalt = try XCTUnwrap(input[0]["content"] as? [[String: Any]])
        XCTAssertEqual(inhalt[0]["type"] as? String, "input_text")
        XCTAssertEqual(inhalt[0]["text"] as? String, "also äh dienstag")
    }

    /// Ohne Deltas steht der Text nur in der Abschlussmeldung.
    func testTextAusAbschlussmeldung() async throws {
        StubURLProtocol.antworten = [Self.strom([
            ["type": "response.completed", "response": [
                "output": [["type": "message", "content": [["type": "output_text", "text": "Fertig."]]]],
            ]],
        ])]
        let text = try await engine().respond(system: "s", user: "u", temperature: 0.2)
        XCTAssertEqual(text, "Fertig.")
    }

    /// Ein Strom ohne `response.completed` ist ein halber Text — der darf nicht
    /// als fertig durchgehen.
    func testAbgerissenerStromIstKeinErgebnis() async {
        StubURLProtocol.antworten = [Self.strom([
            ["type": "response.output_text.delta", "delta": "Der Termin am"],
        ])]
        do {
            _ = try await engine().respond(system: "s", user: "u", temperature: 0.2)
            XCTFail("Hätte scheitern müssen")
        } catch {
            XCTAssertEqual(error as? RemoteProviderError, .malformedResponse)
        }
    }

    func testUnvollstaendigeAntwortIstKeinErgebnis() async {
        StubURLProtocol.antworten = [Self.strom([
            ["type": "response.output_text.delta", "delta": "Der Termin am"],
            ["type": "response.incomplete", "response": ["incomplete_details": ["reason": "max_output_tokens"]]],
        ])]
        do {
            _ = try await engine().respond(system: "s", user: "u", temperature: 0.2)
            XCTFail("Hätte scheitern müssen")
        } catch {
            XCTAssertEqual(error as? RemoteProviderError, .malformedResponse)
        }
    }

    // MARK: - Anmeldung

    /// Ein 401 bekommt genau einen zweiten Versuch mit erneuertem Token.
    func test401ErneuertDasTokenEinmal() async throws {
        let tokens = Tokens()
        StubURLProtocol.antworten = [.fehlerAntwort(status: 401), Self.textStrom(["ok"])]
        let text = try await engine(tokens: tokens).respond(system: "s", user: "u", temperature: 0.2)
        XCTAssertEqual(text, "ok")
        XCTAssertEqual(tokens.anfragen, [false, true])
        XCTAssertEqual(StubURLProtocol.anfragen[1].request.value(forHTTPHeaderField: "Authorization"),
                       "Bearer frisch")
    }

    func testZweiter401IstEndgueltig() async {
        StubURLProtocol.antworten = [.fehlerAntwort(status: 401), .fehlerAntwort(status: 401)]
        do {
            _ = try await engine().respond(system: "s", user: "u", temperature: 0.2)
            XCTFail("Hätte scheitern müssen")
        } catch {
            XCTAssertEqual(error as? RemoteProviderError, .unauthorized)
            XCTAssertEqual(StubURLProtocol.anfragen.count, 2)
        }
    }

    func testOhneAnmeldungKeineAnfrage() async {
        let ohne = ChatGPTPlanTextEngine(model: "gpt-6-luna",
                                         token: { _ in throw RemoteProviderError.signInRequired },
                                         session: StubURLProtocol.session())
        do {
            _ = try await ohne.respond(system: "s", user: "u", temperature: 0.2)
            XCTFail("Hätte scheitern müssen")
        } catch {
            XCTAssertEqual(error as? RemoteProviderError, .signInRequired)
            XCTAssertTrue(StubURLProtocol.anfragen.isEmpty)
        }
    }

    // MARK: - Abo-Fehler

    /// Limit erreicht: Fehler melden, und danach nicht weiter anfragen, bis die
    /// Pause vorbei ist — so will es OpenAI.
    func testLimitPausiertWeitereAnfragen() async throws {
        let uhr = Uhr()
        let gemeldet = expectation(description: "Limit gemeldet")
        let e = engine(uhr: uhr, onPlanLimit: { gemeldet.fulfill() })
        StubURLProtocol.antworten = [Self.fehler(429, code: "subscription_sharing_usage_limit_exceeded")]

        do {
            _ = try await e.respond(system: "s", user: "u", temperature: 0.2)
            XCTFail("Hätte scheitern müssen")
        } catch {
            XCTAssertEqual(error as? RemoteProviderError, .planLimitReached)
        }
        await fulfillment(of: [gemeldet], timeout: 1)
        let bereit = await e.isReady
        XCTAssertFalse(bereit)

        do {
            _ = try await e.respond(system: "s", user: "u", temperature: 0.2)
            XCTFail("Hätte ohne Anfrage scheitern müssen")
        } catch {
            XCTAssertEqual(error as? RemoteProviderError, .planLimitReached)
        }
        XCTAssertEqual(StubURLProtocol.anfragen.count, 1, "Während der Pause keine Anfrage")

        uhr.jetzt = uhr.jetzt.addingTimeInterval(ChatGPTPlanTextEngine.limitPause + 1)
        let wiederBereit = await e.isReady
        XCTAssertTrue(wiederBereit)
    }

    /// Kein zweiter Versuch im Router: Ein Limit geht nicht in Sekunden weg.
    func testAboFehlerSindNichtVoruebergehend() {
        XCTAssertFalse(RemoteProviderError.planLimitReached.isTransient)
        XCTAssertFalse(RemoteProviderError.planNotEligible.isTransient)
        XCTAssertFalse(RemoteProviderError.signInRequired.isTransient)
    }

    func testNichtBerechtigt() async {
        StubURLProtocol.antworten = [Self.fehler(403, code: "subscription_sharing_user_not_eligible")]
        do {
            _ = try await engine().respond(system: "s", user: "u", temperature: 0.2)
            XCTFail("Hätte scheitern müssen")
        } catch {
            XCTAssertEqual(error as? RemoteProviderError, .planNotEligible)
        }
    }

    /// Kennt das Modell `reasoning` nicht, geht es ohne weiter — und bleibt so.
    func testOhneReasoningWiederholen() async throws {
        let e = engine()
        StubURLProtocol.antworten = [
            Self.fehler(400, code: "subscription_sharing_unsupported_capability", param: "reasoning.effort"),
            Self.textStrom(["ok"]),
            Self.textStrom(["noch mal"]),
        ]
        let text = try await e.respond(system: "s", user: "u", temperature: 0.2)
        XCTAssertEqual(text, "ok")
        XCTAssertNil(try rumpf(1)["reasoning"])

        _ = try await e.respond(system: "s", user: "u", temperature: 0.2)
        XCTAssertNil(try rumpf(2)["reasoning"], "Einmal abgelehnt, nicht wieder schicken")
    }

    func testUnbekanntesModell() async {
        StubURLProtocol.antworten = [
            Self.fehler(400, code: "subscription_sharing_unsupported_capability", param: "model"),
        ]
        do {
            _ = try await engine().respond(system: "s", user: "u", temperature: 0.2)
            XCTFail("Hätte scheitern müssen")
        } catch {
            XCTAssertEqual(error as? RemoteProviderError, .unknownModel("gpt-6-luna"))
        }
    }

    /// Vorübergehend nicht prüfbar → 503, und das darf der Router wiederholen.
    func testNutzungNichtPruefbarIstVoruebergehend() async {
        StubURLProtocol.antworten = [Self.fehler(503, code: "subscription_sharing_usage_unavailable")]
        do {
            _ = try await engine().respond(system: "s", user: "u", temperature: 0.2)
            XCTFail("Hätte scheitern müssen")
        } catch {
            XCTAssertEqual(error as? RemoteProviderError, .http(status: 503))
            XCTAssertTrue((error as? RemoteProviderError)?.isTransient == true)
        }
    }

    func testFehlerImStrom() async {
        StubURLProtocol.antworten = [Self.strom([
            ["type": "response.failed", "response": ["error": [
                "code": "subscription_sharing_usage_limit_exceeded", "message": "x"]]],
        ])]
        do {
            _ = try await engine().respond(system: "s", user: "u", temperature: 0.2)
            XCTFail("Hätte scheitern müssen")
        } catch {
            XCTAssertEqual(error as? RemoteProviderError, .planLimitReached)
        }
    }

    // MARK: - Modell-Liste

    func testModellListeLiestSlugUndSichtbarkeit() async throws {
        let json = """
        {"data":[{"slug":"gpt-6-luna","display_name":"GPT-6 Luna","visibility":"list"},
                 {"slug":"intern","visibility":"hide"},
                 {"id":"gpt-6.1-sol"}]}
        """
        StubURLProtocol.antworten = [.init(body: Data(json.utf8))]
        let ids = try await ChatGPTPlanModels.fetch(token: "T", session: StubURLProtocol.session())
        XCTAssertEqual(ids, ["gpt-6-luna", "gpt-6.1-sol"])
        XCTAssertEqual(StubURLProtocol.anfragen[0].request.value(forHTTPHeaderField: "Authorization"),
                       "Bearer T")
    }
}
