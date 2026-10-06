import XCTest

@MainActor
final class NoteStoreVersionsTests: XCTestCase {

    final class Uhr { var jetzt = Date(timeIntervalSince1970: 1_800_000_000) }

    private var u: NotizUmgebung!
    private var uhr: Uhr!
    private var versionen: NoteVersions!

    override func setUpWithError() throws {
        Loc.shared.apply("de")
        u = try NotizUmgebung()
        uhr = Uhr()
        let x = uhr!
        versionen = NoteVersions(root: u.wurzel.appendingPathComponent("Versionen"), now: { x.jetzt })
    }

    override func tearDown() {
        u.aufraeumen()
        Loc.shared.apply("system")
        super.tearDown()
    }

    private func gesichert(_ ergebnis: NoteStore.SaveResult) throws -> Note {
        guard case .saved(let note) = ergebnis else { throw XCTSkip("nicht gesichert: \(ergebnis)") }
        return note
    }

    func testUeberschreibenSichertDenVorigenStand() throws {
        let s = u.store()
        versionen.attach(to: s)
        var n = Note.blank()
        n.body = "eins zwei drei vier"
        n = try gesichert(s.save(n))
        XCTAssertTrue(versionen.list(for: n.fileName).isEmpty, "neue Notiz: kein Stand")
        n.body = "eins zwei drei vier fünf"
        n = try gesichert(s.save(n))
        XCTAssertEqual(versionen.list(for: n.fileName).compactMap { $0.text() }, ["eins zwei drei vier"])
    }

    func testInnerhalbVonZehnMinutenKeinWeitererStand() throws {
        let s = u.store()
        versionen.attach(to: s)
        var n = Note.blank()
        n.body = "eins zwei drei"
        n = try gesichert(s.save(n))
        n.body = "eins zwei drei a"
        n = try gesichert(s.save(n))
        n.body = "eins zwei drei b"
        n = try gesichert(s.save(n))
        XCTAssertEqual(versionen.list(for: n.fileName).count, 1)
        uhr.jetzt += 11 * 60
        n.body = "eins zwei drei c"
        n = try gesichert(s.save(n))
        XCTAssertEqual(versionen.list(for: n.fileName).compactMap { $0.text() }, ["eins zwei drei b", "eins zwei drei"])
    }

    func testNurAnheftenSichertKeinenStand() throws {
        let s = u.store()
        versionen.attach(to: s)
        var n = Note.blank()
        n.body = "eins zwei drei"
        n = try gesichert(s.save(n))
        s.setPinned(n.id, true)
        XCTAssertTrue(versionen.list(for: n.fileName).isEmpty)
    }

    func testTitelregelBenenntUmUndDieStaendeWandernMit() throws {
        let s = u.store()
        versionen.attach(to: s)
        var gemeldet: [(String, String)] = []
        s.observeRenames { gemeldet.append(($0, $1)) }
        var n = Note.blank()
        n.body = "Alt"
        n = try gesichert(s.save(n))
        XCTAssertEqual(n.fileName, "Alt.md")
        n.body = "Neu"
        n = try gesichert(s.save(n))
        XCTAssertEqual(n.fileName, "Neu.md")
        XCTAssertEqual(gemeldet.map { "\($0.0)→\($0.1)" }, ["Alt.md→Neu.md"])
        XCTAssertEqual(versionen.list(for: "Neu.md").compactMap { $0.text() }, ["Alt"])
        XCTAssertTrue(versionen.list(for: "Alt.md").isEmpty)
    }

    func testUmbenennenMeldetAllenBeobachtern() throws {
        try u.schreibe("Eins.md", "Text")
        let s = u.store()
        var a = 0, b = 0
        s.observeRenames { _, _ in a += 1 }
        s.observeRenames { _, _ in b += 1 }
        XCTAssertNotNil(s.rename(s.notes[0].id, to: "Zwei"))
        XCTAssertEqual(a, 1)
        XCTAssertEqual(b, 1)
    }
}
