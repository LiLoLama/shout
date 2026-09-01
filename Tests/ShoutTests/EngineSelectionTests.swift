import XCTest

/// Tests für die Frage „auf diesem Gerät oder bei einem Anbieter".
///
/// Diese Entscheidung ist die heikelste Stelle des ganzen Vorhabens: Sie
/// bestimmt, ob Text das Gerät verlässt. Deshalb ist sie eine eigene, reine
/// Funktion mit eigenen Tests, statt in der Fabrik zu verschwinden.
final class EngineSelectionTests: XCTestCase {

    private var defaults: UserDefaults!
    private let suite = "shout.tests.selection"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    private func stelleEin(_ purpose: EnginePurpose, auf wert: String,
                           templateID: String, model: String = "irgendein-modell") {
        defaults.set(wert, forKey: purpose.engineKey)
        let vorlage = ProviderCatalog.template(id: templateID)
        var config = RemoteConfig(templateID: templateID,
                                  baseURL: vorlage?.baseURL ?? "https://example.com/v1",
                                  model: model)
        if config.baseURL.isEmpty { config.baseURL = "https://example.com/v1" }
        config.save(purpose: purpose, in: defaults)
    }

    // MARK: - Voreinstellung ist lokal

    /// Ohne jede Einstellung wird lokal gearbeitet. Das ist die Haltung des
    /// Programms und darf sich nie durch Zufall ändern.
    func testOhneEinstellungLokal() {
        XCTAssertEqual(EngineSelection.decide(for: .text, defaults: defaults, hasKey: { _ in true }),
                       .local)
        XCTAssertEqual(EngineSelection.decide(for: .audio, defaults: defaults, hasKey: { _ in true }),
                       .local)
    }

    /// Auch eine vollständige Anbieter-Konfiguration greift nicht, solange der
    /// Schalter auf „auf diesem Gerät" steht.
    func testKonfigurationOhneSchalterBleibtLokal() {
        stelleEin(.text, auf: "local", templateID: "openai")
        XCTAssertEqual(EngineSelection.decide(for: .text, defaults: defaults, hasKey: { _ in true }),
                       .local)
    }

    // MARK: - Der Anbieter-Fall

    func testMitSchalterUndSchluesselWirdExtern() {
        stelleEin(.text, auf: "remote", templateID: "openai", model: "gpt-5-mini")
        let wahl = EngineSelection.decide(for: .text, defaults: defaults, hasKey: { _ in true })
        guard case .remote(let config, let template) = wahl else {
            return XCTFail("Es hätte extern werden müssen, wurde: \(wahl)")
        }
        XCTAssertEqual(template.id, "openai")
        XCTAssertEqual(config.model, "gpt-5-mini")
    }

    // MARK: - Die Backup-Regel

    /// **Der wichtigste Test hier.** Ein Sicherungsstand nimmt die Konfiguration
    /// mit (harmlos), den Schlüssel nicht (der bleibt in der Keychain des alten
    /// Geräts). Auf dem neuen Gerät steht dann „Anbieter" in den Einstellungen,
    /// ohne dass ein Schlüssel da ist — und dann muss lokal gearbeitet werden.
    func testOhneSchluesselWirdLokalGearbeitet() {
        stelleEin(.text, auf: "remote", templateID: "openai")
        XCTAssertEqual(EngineSelection.decide(for: .text, defaults: defaults, hasKey: { _ in false }),
                       .local)
    }

    /// Anbieter auf dem eigenen Rechner brauchen keinen Schlüssel — dort darf die
    /// Regel nicht zuschlagen.
    func testAnbieterOhneSchluesselpflichtGehtOhneSchluessel() {
        stelleEin(.text, auf: "remote", templateID: "ollama", model: "gemma3:12b")
        let wahl = EngineSelection.decide(for: .text, defaults: defaults, hasKey: { _ in false })
        guard case .remote(_, let template) = wahl else {
            return XCTFail("Ollama braucht keinen Schlüssel, wurde: \(wahl)")
        }
        XCTAssertEqual(template.id, "ollama")
    }

    // MARK: - Unbrauchbare Einstellungen fallen zurück

    /// Eine Vorlage, die es nicht mehr gibt (aus einer älteren Programmversion),
    /// darf nicht dazu führen, dass gar nichts mehr funktioniert.
    func testUnbekannteVorlageWirdLokal() {
        defaults.set("remote", forKey: EnginePurpose.text.engineKey)
        RemoteConfig(templateID: "gibtesnichtmehr", baseURL: "https://example.com/v1",
                     model: "x").save(purpose: .text, in: defaults)
        XCTAssertEqual(EngineSelection.decide(for: .text, defaults: defaults, hasKey: { _ in true }),
                       .local)
    }

    /// Eine kaputte Adresse ebenso — lieber lokal aufbereiten als bei jedem
    /// Diktat scheitern.
    func testKaputteAdresseWirdLokal() {
        defaults.set("remote", forKey: EnginePurpose.text.engineKey)
        RemoteConfig(templateID: "custom", baseURL: "unsinn", model: "x")
            .save(purpose: .text, in: defaults)
        XCTAssertEqual(EngineSelection.decide(for: .text, defaults: defaults, hasKey: { _ in true }),
                       .local)
    }

    /// Fehlt die Konfiguration ganz, obwohl der Schalter steht: lokal.
    func testSchalterOhneKonfigurationWirdLokal() {
        defaults.set("remote", forKey: EnginePurpose.text.engineKey)
        XCTAssertEqual(EngineSelection.decide(for: .text, defaults: defaults, hasKey: { _ in true }),
                       .local)
    }

    /// Ein Anbieter, der keine Transkription kann, darf nicht für Audio gewählt
    /// werden — auch nicht, wenn es jemand von Hand einträgt.
    func testAnbieterOhneAudioWirdFuerAudioLokal() {
        stelleEin(.audio, auf: "remote", templateID: "openrouter")
        XCTAssertEqual(EngineSelection.decide(for: .audio, defaults: defaults, hasKey: { _ in true }),
                       .local)
    }

    /// Ein Anbieter, der Audio kann, geht dagegen durch.
    func testAnbieterMitAudioGehtFuerAudioDurch() {
        stelleEin(.audio, auf: "remote", templateID: "groq", model: "whisper-large-v3-turbo")
        let wahl = EngineSelection.decide(for: .audio, defaults: defaults, hasKey: { _ in true })
        guard case .remote(_, let template) = wahl else {
            return XCTFail("Groq kann Audio, wurde: \(wahl)")
        }
        XCTAssertEqual(template.id, "groq")
    }

    /// Text und Audio sind unabhängig: extern aufbereiten und lokal
    /// transkribieren muss möglich sein.
    func testTextUndAudioSindUnabhaengig() {
        stelleEin(.text, auf: "remote", templateID: "eurouter")
        let text = EngineSelection.decide(for: .text, defaults: defaults, hasKey: { _ in true })
        let audio = EngineSelection.decide(for: .audio, defaults: defaults, hasKey: { _ in true })
        if case .local = text { XCTFail("Text hätte extern sein müssen") }
        XCTAssertEqual(audio, .local)
    }
}
