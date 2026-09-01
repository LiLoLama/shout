import XCTest

final class ProviderKeychainTests: XCTestCase {

    /// Eigene Service-Kennung, damit die Tests die echte Keychain der App nicht
    /// anfassen.
    private let service = "com.inthezone.flowlokal.provider.tests"

    override func tearDown() {
        try? ProviderKeychain.delete(for: "test", service: service)
        super.tearDown()
    }

    // MARK: - Maskierung (reine Logik, immer prüfbar)

    /// So sieht der Schlüssel in der Oberfläche aus. Der vollständige Wert wird
    /// nie angezeigt — auch nicht „nur kurz zum Kontrollieren".
    func testMaskeZeigtVorsilbeUndVierZeichen() {
        XCTAssertEqual(ProviderKeychain.mask("sk-abcdefghij4f2a"), "sk-…4f2a")
    }

    func testMaskeErkenntUnterstrichAlsVorsilbe() {
        XCTAssertEqual(ProviderKeychain.mask("gsk_abcdefghij9c31"), "gsk_…9c31")
    }

    func testMaskeOhneVorsilbe() {
        XCTAssertEqual(ProviderKeychain.mask("abcdefghijklmnop"), "…mnop")
    }

    /// Bei einem kurzen Schlüssel wären vier Zeichen fast der ganze Wert. Dann
    /// wird nichts verraten.
    func testKurzerSchluesselWirdGarNichtGezeigt() {
        XCTAssertEqual(ProviderKeychain.mask("kurz"), "…")
        XCTAssertEqual(ProviderKeychain.mask("sk-kurz"), "sk-…")
    }

    func testLeererSchluesselErgibtLeereMaske() {
        XCTAssertEqual(ProviderKeychain.mask(""), "")
        XCTAssertEqual(ProviderKeychain.mask("   "), "")
    }

    /// Eine sehr lange Vorsilbe ist keine Vorsilbe, sondern der Schlüssel selbst.
    func testTrennzeichenWeitHintenGiltNichtAlsVorsilbe() {
        XCTAssertEqual(ProviderKeychain.mask("abcdefghij-klmnopqr"), "…opqr")
    }

    // MARK: - Rundlauf über die echte Keychain

    /// Ein nur ad-hoc signiertes Testpaket bekommt vom System nicht immer
    /// Keychain-Zugriff. Dann wird der Test übersprungen statt vorgetäuscht —
    /// ein grüner Test, der nichts geprüft hat, ist schlimmer als ein
    /// übersprungener.
    private func requireKeychain() throws {
        do {
            try ProviderKeychain.store("probe", for: "test", service: service)
        } catch let error as ProviderKeychain.Failure {
            throw XCTSkip("Keychain in dieser Testumgebung nicht verfügbar: \(error)")
        }
    }

    func testSchreibenUndLesen() throws {
        try requireKeychain()
        try ProviderKeychain.store("sk-abcdefghij4f2a", for: "test", service: service)
        XCTAssertEqual(ProviderKeychain.read(for: "test", service: service), "sk-abcdefghij4f2a")
    }

    /// Zweimal schreiben ersetzt, statt einen zweiten Eintrag anzulegen.
    func testUeberschreiben() throws {
        try requireKeychain()
        try ProviderKeychain.store("erster", for: "test", service: service)
        try ProviderKeychain.store("zweiter", for: "test", service: service)
        XCTAssertEqual(ProviderKeychain.read(for: "test", service: service), "zweiter")
    }

    func testLoeschen() throws {
        try requireKeychain()
        try ProviderKeychain.store("sk-abcdefghij4f2a", for: "test", service: service)
        try ProviderKeychain.delete(for: "test", service: service)
        XCTAssertNil(ProviderKeychain.read(for: "test", service: service))
    }

    /// Löschen, was nicht da ist, ist kein Fehler — sonst müsste jede
    /// Aufrufstelle vorher prüfen.
    func testLoeschenOhneEintragIstKeinFehler() throws {
        try requireKeychain()
        try ProviderKeychain.delete(for: "test", service: service)
        XCTAssertNoThrow(try ProviderKeychain.delete(for: "test", service: service))
    }

    func testUnbekannterAnbieterHatKeinenSchluessel() throws {
        try requireKeychain()
        XCTAssertNil(ProviderKeychain.read(for: "gibtesnicht", service: service))
        XCTAssertFalse(ProviderKeychain.has(templateID: "gibtesnicht", service: service))
    }

    /// Anbieter teilen sich keinen Schlüssel.
    func testSchluesselSindProAnbieterGetrennt() throws {
        try requireKeychain()
        try ProviderKeychain.store("schluessel-a", for: "test", service: service)
        XCTAssertNil(ProviderKeychain.read(for: "test-anderer", service: service))
        try? ProviderKeychain.delete(for: "test-anderer", service: service)
    }
}
