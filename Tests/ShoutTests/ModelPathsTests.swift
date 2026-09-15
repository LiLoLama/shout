import XCTest

final class ModelPathsTests: XCTestCase {

    private var wurzel: URL!
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUpWithError() throws {
        wurzel = FileManager.default.temporaryDirectory
            .appendingPathComponent("shout-modelpaths-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: wurzel, withIntermediateDirectories: true)
        suiteName = "shout-test-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: wurzel)
        defaults.removePersistentDomain(forName: suiteName)
    }

    private func ordner(_ name: String) -> URL {
        wurzel.appendingPathComponent(name, isDirectory: true)
    }

    /// Der Wächter gegen einen unbeabsichtigten Neu-Download: Ohne Einstellung
    /// zeigt der Basisordner auf denselben Ort wie vor der Umstellung. Deshalb
    /// wird die Vorgabe zur Laufzeit erfragt, nicht fest geschrieben.
    func testOhneEinstellungGiltDieVorgabe() {
        let erwartet = ordner("hf-cache")
        let pfade = ModelPaths.laden(aus: defaults, vorgabe: { erwartet })
        XCTAssertEqual(pfade.basisordner, erwartet)
        XCTAssertTrue(pfade.suchordner.isEmpty)
    }

    func testGesicherteEinstellungUeberlebtDasLaden() {
        var pfade = ModelPaths.laden(aus: defaults, vorgabe: { self.ordner("vorgabe") })
        pfade.basisordner = ordner("platte")
        pfade.suchordner = [ordner("lmstudio")]
        pfade.sichern(in: defaults)

        let neu = ModelPaths.laden(aus: defaults, vorgabe: { self.ordner("vorgabe") })
        XCTAssertEqual(neu.basisordner, ordner("platte"))
        XCTAssertEqual(neu.suchordner, [ordner("lmstudio")])
    }

    /// Ein Ordnerwechsel bewegt nichts. Der alte Ordner rutscht nach vorn in
    /// die Suchordner — sonst gälten alle bisherigen Modelle als verschwunden.
    func testOrdnerwechselMachtAltenZumErstenSuchordner() {
        var pfade = ModelPaths.laden(aus: defaults, vorgabe: { self.ordner("alt") })
        pfade.basisordnerWechseln(zu: ordner("neu"))
        XCTAssertEqual(pfade.basisordner, ordner("neu"))
        XCTAssertEqual(pfade.suchordner.first, ordner("alt"))
    }

    /// Zweimal derselbe Wechsel darf den Ordner nicht doppelt eintragen.
    func testOrdnerwechselDoppeltErzeugtKeineDoppelung() {
        var pfade = ModelPaths.laden(aus: defaults, vorgabe: { self.ordner("alt") })
        pfade.basisordnerWechseln(zu: ordner("neu"))
        pfade.basisordnerWechseln(zu: ordner("alt"))
        pfade.basisordnerWechseln(zu: ordner("neu"))
        XCTAssertEqual(pfade.basisordner, ordner("neu"))
        XCTAssertEqual(Set(pfade.suchordner).count, pfade.suchordner.count)
    }

    /// Der neue Basisordner darf nicht gleichzeitig als Suchordner stehen
    /// bleiben — sonst erschiene jedes Modell doppelt.
    func testNeuerBasisordnerVerlaesstDieSuchordner() {
        var pfade = ModelPaths.laden(aus: defaults, vorgabe: { self.ordner("alt") })
        pfade.suchordner = [ordner("neu"), ordner("lmstudio")]
        pfade.basisordnerWechseln(zu: ordner("neu"))
        XCTAssertFalse(pfade.suchordner.contains(ordner("neu")))
        XCTAssertTrue(pfade.suchordner.contains(ordner("lmstudio")))
    }

    func testStoreUebernimmtReihenfolge() {
        var pfade = ModelPaths.laden(aus: defaults, vorgabe: { self.ordner("basis") })
        pfade.suchordner = [ordner("a"), ordner("b")]
        XCTAssertEqual(pfade.store.orteInReihenfolge,
                       [ordner("basis"), ordner("a"), ordner("b")])
    }
}
