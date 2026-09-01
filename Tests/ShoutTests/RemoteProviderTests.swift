import XCTest

/// Tests für Anbieter-Katalog und Adressaufbau.
///
/// Der Adressaufbau bekommt so viel Aufmerksamkeit, weil er die häufigste
/// Fehlerquelle ist: Leute kopieren die Basis-URL aus einer Dokumentation und
/// erwischen dabei einen Schrägstrich zu viel, lassen `/v1` weg oder kopieren
/// gleich den ganzen Endpunkt mit. Jeder dieser Fälle ergibt sonst einen
/// 404, den niemand einem Tippfehler zuordnet.
final class RemoteProviderTests: XCTestCase {

    private func config(_ base: String) -> RemoteConfig {
        RemoteConfig(templateID: "test", baseURL: base, model: "irgendein-modell")
    }

    // MARK: - Adressaufbau

    func testBasisMitV1() {
        XCTAssertEqual(config("https://api.openai.com/v1").chatURL?.absoluteString,
                       "https://api.openai.com/v1/chat/completions")
    }

    /// Ein Schrägstrich am Ende darf nichts kaputt machen.
    func testBasisMitSchraegstrichAmEnde() {
        XCTAssertEqual(config("https://api.openai.com/v1/").chatURL?.absoluteString,
                       "https://api.openai.com/v1/chat/completions")
    }

    /// Mehrere Schrägstriche am Ende ebenso.
    func testBasisMitMehrerenSchraegstrichen() {
        XCTAssertEqual(config("https://api.openai.com/v1///").chatURL?.absoluteString,
                       "https://api.openai.com/v1/chat/completions")
    }

    /// Ohne Pfad ergänzen wir `/v1` — praktisch alle OpenAI-kompatiblen
    /// Endpunkte liegen dort, und „nur den Host eintragen" ist der häufigste
    /// Fall. Wo der Pfad anders lautet (Google: `/v1beta/openai`), steht er in
    /// der Vorlage und wird nicht angetastet.
    func testNurHostErgaenztV1() {
        XCTAssertEqual(config("https://api.openai.com").chatURL?.absoluteString,
                       "https://api.openai.com/v1/chat/completions")
    }

    func testNurHostMitPortErgaenztV1() {
        XCTAssertEqual(config("http://localhost:11434").chatURL?.absoluteString,
                       "http://localhost:11434/v1/chat/completions")
    }

    /// Ein abweichender Pfad bleibt unverändert — hier darf nichts „korrigiert"
    /// werden.
    func testAbweichenderPfadBleibt() {
        XCTAssertEqual(
            config("https://generativelanguage.googleapis.com/v1beta/openai").chatURL?.absoluteString,
            "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions")
    }

    /// Wer den vollständigen Endpunkt kopiert, soll trotzdem ankommen.
    func testVollstaendigKopierterEndpunktWirdBereinigt() {
        XCTAssertEqual(config("https://api.openai.com/v1/chat/completions").chatURL?.absoluteString,
                       "https://api.openai.com/v1/chat/completions")
    }

    func testVollstaendigKopierterAudioEndpunktWirdBereinigt() {
        XCTAssertEqual(config("https://api.openai.com/v1/audio/transcriptions").audioURL?.absoluteString,
                       "https://api.openai.com/v1/audio/transcriptions")
    }

    /// Auch quer: aus einer kopierten Chat-Adresse muss die Audio-Adresse
    /// entstehen können, sonst funktioniert nur der Schritt, den man zuerst
    /// eingerichtet hat.
    func testAusChatAdresseWirdAudioAdresse() {
        XCTAssertEqual(config("https://api.openai.com/v1/chat/completions").audioURL?.absoluteString,
                       "https://api.openai.com/v1/audio/transcriptions")
    }

    func testModellListeAdresse() {
        XCTAssertEqual(config("https://api.eurouter.ai/v1").modelsURL?.absoluteString,
                       "https://api.eurouter.ai/v1/models")
    }

    /// Leerzeichen aus der Zwischenablage werden entfernt.
    func testUmgebendeLeerzeichenWerdenEntfernt() {
        XCTAssertEqual(config("  https://api.x.ai/v1  ").chatURL?.absoluteString,
                       "https://api.x.ai/v1/chat/completions")
    }

    func testLeereBasisErgibtKeineAdresse() {
        XCTAssertNil(config("   ").chatURL)
    }

    func testUnsinnErgibtKeineAdresse() {
        XCTAssertNil(config("kein-schema-und-kein-host").chatURL)
    }

    // MARK: - Katalog

    /// Bestätigte Adressen. Ändert sie jemand versehentlich, fällt es hier auf.
    func testBestaetigteBasisAdressen() {
        XCTAssertEqual(ProviderCatalog.template(id: "eurouter")?.baseURL,
                       "https://api.eurouter.ai/v1")
        XCTAssertEqual(ProviderCatalog.template(id: "xai")?.baseURL,
                       "https://api.x.ai/v1")
    }

    /// Jede Vorlage braucht eine gültige Adresse — eine kaputte Vorlage im
    /// Katalog ist schlimmer als keine Vorlage.
    func testAlleVorlagenHabenGueltigeAdressen() {
        for vorlage in ProviderCatalog.all where !vorlage.baseURL.isEmpty {
            let cfg = RemoteConfig(templateID: vorlage.id, baseURL: vorlage.baseURL, model: "x")
            XCTAssertNotNil(cfg.chatURL, "Vorlage \(vorlage.id) ergibt keine Chat-Adresse")
        }
    }

    func testVorlagenKennungenSindEindeutig() {
        let ids = ProviderCatalog.all.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count, "Doppelte Vorlagen-Kennung im Katalog")
    }

    /// „Eigener Endpunkt" hat absichtlich keine vorgegebene Adresse — der
    /// Nutzer trägt sie ein. Er muss aber Audio anbieten dürfen, obwohl keine
    /// Modelle vorgeschlagen werden (z. B. ein whisper.cpp-Server).
    func testEigenerEndpunktKannAudioOhneModellvorschlaege() {
        let eigen = ProviderCatalog.template(id: "custom")
        XCTAssertNotNil(eigen)
        XCTAssertTrue(eigen?.canAudio == true)
        XCTAssertTrue(eigen?.audioModels.isEmpty == true)
        XCTAssertTrue(eigen?.baseURL.isEmpty == true)
    }

    /// Anbieter, die auf dem eigenen Rechner laufen, brauchen keinen Schlüssel.
    /// Verlangt die Oberfläche dort trotzdem einen, kommt niemand weiter.
    func testLokaleAnbieterBrauchenKeinenSchluessel() {
        XCTAssertEqual(ProviderCatalog.template(id: "ollama")?.needsKey, false)
        XCTAssertEqual(ProviderCatalog.template(id: "lmstudio")?.needsKey, false)
    }

    /// Die Vorlage für xAI muss klarstellen, dass ein SuperGrok-Abo hier nicht
    /// zählt — sonst ist der erste Versuch ein Fehlschlag mit unklarer Ursache.
    func testXAIVorlageWarntVorAboVerwechslung() {
        let hinweis = ProviderCatalog.template(id: "xai")?.note ?? ""
        XCTAssertTrue(hinweis.contains("SuperGrok"),
                      "Der Hinweis muss das Abo ausdrücklich ausschließen")
    }

    // MARK: - Konfiguration speichern

    func testKonfigurationUeberlebtSpeichernUndLaden() {
        let defaults = UserDefaults(suiteName: "shout.tests.provider")!
        defaults.removePersistentDomain(forName: "shout.tests.provider")

        let cfg = RemoteConfig(templateID: "groq", baseURL: "https://api.groq.com/openai/v1",
                               model: "whisper-large-v3-turbo")
        cfg.save(purpose: .audio, in: defaults)

        XCTAssertEqual(RemoteConfig.load(purpose: .audio, from: defaults), cfg)
        XCTAssertNil(RemoteConfig.load(purpose: .text, from: defaults),
                     "Text und Audio werden getrennt gespeichert")
    }

    /// Der Schlüssel darf unter keinen Umständen in den Einstellungen landen.
    func testKonfigurationEnthaeltKeinenSchluessel() throws {
        let cfg = RemoteConfig(templateID: "openai", baseURL: "https://api.openai.com/v1",
                               model: "gpt-5-mini")
        let json = String(data: try JSONEncoder().encode(cfg), encoding: .utf8) ?? ""
        XCTAssertFalse(json.lowercased().contains("key"))
        XCTAssertFalse(json.lowercased().contains("token"))
        XCTAssertFalse(json.lowercased().contains("secret"))
    }
}
