import XCTest

@MainActor
final class NoteVersionsTests: XCTestCase {

    /// Stellbare Uhr.
    final class Uhr { var jetzt = Date(timeIntervalSince1970: 1_800_000_000) }

    private var wurzel: URL!
    private var uhr: Uhr!
    private var v: NoteVersions!

    override func setUpWithError() throws {
        wurzel = FileManager.default.temporaryDirectory.appendingPathComponent("shout-versionen-\(UUID().uuidString)")
        uhr = Uhr()
        let u = uhr!
        v = NoteVersions(root: wurzel, now: { u.jetzt })
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: wurzel)
        super.tearDown()
    }

    func testSichernLegtStandUndNamenAn() throws {
        let url = try XCTUnwrap(v.save("Stand 1", for: "Notiz.md"))
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "Stand 1")
        let name = try String(contentsOf: v.folder(for: "Notiz.md").appendingPathComponent("name.txt"), encoding: .utf8)
        XCTAssertEqual(name, "Notiz.md")
        XCTAssertEqual(v.list(for: "Notiz.md").map { $0.text() }, ["Stand 1"])
    }

    func testGleicherTextWieDerNeuesteWirdNichtDoppeltGesichert() {
        v.save("A", for: "N.md")
        uhr.jetzt += 60
        XCTAssertNil(v.save("A", for: "N.md"))
        XCTAssertEqual(v.list(for: "N.md").count, 1)
    }

    func testLeererTextWirdNichtGesichert() {
        XCTAssertNil(v.save("  \n", for: "N.md"))
    }

    func testHoechstensAlleZehnMinutenBeimBearbeiten() {
        XCTAssertNotNil(v.saveIfDue("A", for: "N.md"))
        uhr.jetzt += 9 * 60
        XCTAssertNil(v.saveIfDue("B", for: "N.md"))
        uhr.jetzt += 2 * 60
        XCTAssertNotNil(v.saveIfDue("C", for: "N.md"))
        XCTAssertEqual(v.list(for: "N.md").compactMap { $0.text() }, ["C", "A"])
    }

    func testZweiStaendeInDerselbenSekunde() {
        v.save("A", for: "N.md")
        v.save("B", for: "N.md")
        XCTAssertEqual(v.list(for: "N.md").compactMap { $0.text() }, ["B", "A"])
    }

    func testHoechstensDreissigStaende() {
        for i in 0..<32 {
            uhr.jetzt += 1
            v.save("Stand \(i)", for: "N.md")
        }
        let liste = v.list(for: "N.md")
        XCTAssertEqual(liste.count, NoteVersions.maxCount)
        XCTAssertEqual(liste.first?.text(), "Stand 31")
        XCTAssertEqual(liste.last?.text(), "Stand 2")
    }

    func testOrdnerHaengtNichtAnGrossKleinschreibung() {
        XCTAssertEqual(v.folder(for: "Notiz.md"), v.folder(for: "notiz.md"))
    }

    func testUmbenennenNimmtStaendeMit() {
        v.save("A", for: "Alt.md")
        v.moveVersions(from: "Alt.md", to: "Neu.md")
        XCTAssertTrue(v.list(for: "Alt.md").isEmpty)
        XCTAssertEqual(v.list(for: "Neu.md").compactMap { $0.text() }, ["A"])
        let name = try? String(contentsOf: v.folder(for: "Neu.md").appendingPathComponent("name.txt"), encoding: .utf8)
        XCTAssertEqual(name, "Neu.md")
    }

    func testUmbenennenAufVorhandeneStaendeLegtZusammen() {
        v.save("alt", for: "Neu.md")
        uhr.jetzt += 5
        v.save("A", for: "Alt.md")
        v.moveVersions(from: "Alt.md", to: "Neu.md")
        XCTAssertEqual(v.list(for: "Neu.md").compactMap { $0.text() }, ["A", "alt"])
    }

    func testAufraeumenErstNachDreissigTagenOhneDatei() {
        v.save("A", for: "Weg.md")
        v.save("B", for: "Da.md")
        v.cleanUp(keeping: ["Da.md"])                 // merkt sich „verwaist seit"
        XCTAssertFalse(v.list(for: "Weg.md").isEmpty)
        uhr.jetzt += 31 * 24 * 60 * 60
        v.cleanUp(keeping: ["da.md"])
        XCTAssertTrue(v.list(for: "Weg.md").isEmpty)
        XCTAssertFalse(v.list(for: "Da.md").isEmpty)
    }

    func testWiederAufgetauchteDateiSetztDieFristZurueck() {
        v.save("A", for: "N.md")
        v.cleanUp(keeping: [])
        uhr.jetzt += 20 * 24 * 60 * 60
        v.cleanUp(keeping: ["N.md"])                  // wieder da: Marke weg
        uhr.jetzt += 20 * 24 * 60 * 60
        v.cleanUp(keeping: [])                        // neu verwaist, Frist beginnt neu
        XCTAssertFalse(v.list(for: "N.md").isEmpty)
    }

    func testZwoelfStaendeInDerselbenSekundeOrdinalSortieren() {
        for i in 0..<12 {
            v.save(String(i), for: "N.md")
        }
        let liste = v.list(for: "N.md")
        XCTAssertEqual(liste.count, 12)
        XCTAssertEqual(liste.first?.text(), "11")
        XCTAssertEqual(liste.last?.text(), "0")
    }

    func testDreissigAusZweiunddreissigInDerselbenSekunde() {
        for i in 0..<32 {
            v.save(String(i), for: "N.md")
        }
        let liste = v.list(for: "N.md")
        XCTAssertEqual(liste.count, NoteVersions.maxCount)
        XCTAssertEqual(liste.first?.text(), "31")
        XCTAssertEqual(liste.last?.text(), "2")
    }

    func testUhrRueckwaerts() {
        // 30 Stände speichern
        for i in 0..<30 {
            v.save(String(i), for: "N.md")
            uhr.jetzt += 1
        }
        // Uhr um 1 Stunde zurückdrehen
        uhr.jetzt -= 60 * 60
        // Neuer Stand wird trotzdem als neuer erkannt (bekommt Stempel des neuesten + Ordnung)
        v.save("neu", for: "N.md")
        let liste = v.list(for: "N.md")
        XCTAssertEqual(liste.first?.text(), "neu")
    }

    func testUhrRueckwaertsBlockiertDasSichernBeimBearbeitenNicht() {
        XCTAssertNotNil(v.saveIfDue("A", for: "N.md"))
        uhr.jetzt -= 60 * 60
        XCTAssertNotNil(v.saveIfDue("B", for: "N.md"))
        XCTAssertEqual(v.list(for: "N.md").first?.text(), "B")
    }

    func testUnicodeNormalisierung() {
        // NFC und NFD sollten denselben Ordner ergeben
        let nfc = "Ä.md"  // Precomposed
        let nfd = "A\u{0308}.md"  // Decomposed (A + combining diaeresis)
        XCTAssertEqual(v.folder(for: nfc), v.folder(for: nfd))

        // Speichern unter NFC und auslesen unter NFD sollte funktionieren
        v.save("test1", for: nfc)
        let liste = v.list(for: nfd)
        XCTAssertEqual(liste.first?.text(), "test1")
    }

    func testAufraeumenOhneNameTxt() {
        // Speichern und danach name.txt löschen
        v.save("Stand", for: "Notiz.md")
        let ordner = v.folder(for: "Notiz.md")
        try? FileManager.default.removeItem(at: ordner.appendingPathComponent("name.txt"))

        // cleanUp(keeping: []) setzt die Verwaist-Marke
        v.cleanUp(keeping: [])

        // 31 Tage später
        uhr.jetzt += 31 * 24 * 60 * 60

        // cleanUp mit Notiz im keeping sollte Stände behalten
        v.cleanUp(keeping: ["Notiz.md"])
        let liste = v.list(for: "Notiz.md")
        XCTAssertFalse(liste.isEmpty)
    }

    func testAufraeumenMitiCloudPlatzhalter() {
        // Versionen für N.md speichern
        v.save("Stand", for: "N.md")

        // cleanUp(keeping: []) setzt die Verwaist-Marke
        v.cleanUp(keeping: [])

        // 31 Tage + 1 Minute später
        uhr.jetzt += 31 * 24 * 60 * 60 + 60

        // cleanUp mit Platzhalter sollte N.md's Versionen behalten
        v.cleanUp(keeping: [".N.md.icloud"])
        let liste = v.list(for: "N.md")
        XCTAssertFalse(liste.isEmpty)
    }
}
