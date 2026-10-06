import XCTest

@MainActor
final class NotesPageModelVersionsTests: XCTestCase {

    private var u: NotizUmgebung!
    private var suite: String!
    private var defaults: UserDefaults!
    private var versionen: NoteVersions!

    override func setUpWithError() throws {
        Loc.shared.apply("de")
        u = try NotizUmgebung()
        suite = "shout-versionen-seite-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
        versionen = NoteVersions(root: u.wurzel.appendingPathComponent("Versionen"))
    }

    override func tearDown() {
        u.aufraeumen()
        defaults.removePersistentDomain(forName: suite)
        Loc.shared.apply("system")
        super.tearDown()
    }

    private func seite() throws -> NotesPageModel {
        try u.schreibe("A.md", "jetzt")
        let m = NotesPageModel(store: u.store(), defaults: defaults,
                               rescueDirectory: u.wurzel.appendingPathComponent("Rettung"))
        m.versions = versionen
        return m
    }

    func testWiederherstellenInDerOffenenNotiz() throws {
        let m = try seite()
        let a = m.store.notes[0].id
        m.select(a)
        versionen.save("früher", for: "A.md")
        let stand = try XCTUnwrap(m.versionList(for: a).first)
        XCTAssertTrue(m.restore(stand, of: a))
        XCTAssertEqual(m.session?.note.body, "früher")
        XCTAssertEqual(u.text("A.md"), "früher")
        XCTAssertEqual(versionen.list(for: "A.md").first?.text(), "jetzt", "vorher gesichert")
    }

    func testWiederherstellenOhneOffeneSitzung() throws {
        let m = try seite()
        let a = m.store.notes[0].id
        versionen.save("früher", for: "A.md")
        let stand = try XCTUnwrap(m.versionList(for: a).first)
        XCTAssertTrue(m.restore(stand, of: a))
        XCTAssertEqual(u.text("A.md"), "früher")
        XCTAssertNil(m.registry.session(id: a), "kurz geholt, wieder freigegeben")
    }

    func testWaehrendEinesTransformsNicht() throws {
        let m = try seite()
        let a = m.store.notes[0].id
        m.select(a)
        versionen.save("früher", for: "A.md")
        let stand = try XCTUnwrap(m.versionList(for: a).first)
        m.session?.beginTransform("…") {}
        XCTAssertFalse(m.restore(stand, of: a))
        XCTAssertEqual(m.session?.note.body, "jetzt")
    }

    /// Alles markiert und gelöscht, die leere Fassung gesichert: Die früheren
    /// Stände müssen sich zurückholen lassen, obwohl ein leerer Stand nie gesichert wird.
    func testWiederherstellenInEineLeereNotiz() throws {
        let m = try seite()
        let a = m.store.notes[0].id
        m.select(a)
        versionen.save("früher", for: "A.md")
        let offen = try XCTUnwrap(m.session)
        offen.edit("")
        offen.flush()
        XCTAssertEqual(u.text("A.md"), "")
        let stand = try XCTUnwrap(m.versionList(for: a).first(where: { $0.text() == "früher" }))
        XCTAssertTrue(m.restore(stand, of: a))
        XCTAssertEqual(m.session?.note.body, "früher")
        XCTAssertEqual(u.text("A.md"), "früher")
    }

    func testWiederherstellenInEineNotizNurAusLeerraum() throws {
        let m = try seite()
        let a = m.store.notes[0].id
        m.select(a)
        versionen.save("früher", for: "A.md")
        m.session?.edit("  \n\n")
        m.session?.flush()
        let stand = try XCTUnwrap(m.versionList(for: a).first(where: { $0.text() == "früher" }))
        XCTAssertTrue(m.restore(stand, of: a))
        XCTAssertEqual(u.text("A.md"), "früher")
    }

    func testOhneVersionenLeereListe() throws {
        let m = try seite()
        m.versions = nil
        XCTAssertTrue(m.versionList(for: m.store.notes[0].id).isEmpty)
    }

    func testNichtSicherbarerIststandVerhindertDasErsetzen() throws {
        let m = try seite()
        let a = m.store.notes[0].id
        m.select(a)
        versionen.save("früher", for: "A.md")
        let stand = try XCTUnwrap(m.versionList(for: a).first)
        // Die Wurzel ist eine Datei: Darin lässt sich nichts sichern.
        let kaputt = u.wurzel.appendingPathComponent("KeinOrdner")
        try Data("x".utf8).write(to: kaputt)
        m.versions = NoteVersions(root: kaputt)
        XCTAssertFalse(m.restore(stand, of: a))
        XCTAssertEqual(m.session?.note.body, "jetzt")
        XCTAssertEqual(u.text("A.md"), "jetzt")
    }

    func testKonfliktBeimWiederherstellenIstKeinErfolg() throws {
        let m = try seite()
        let a = m.store.notes[0].id
        m.select(a)
        versionen.save("früher", for: "A.md")
        let stand = try XCTUnwrap(m.versionList(for: a).first)
        // Von außen geändert, nachdem die Notiz geöffnet wurde.
        try u.schreibe("A.md", "fremd", zeit: Date().addingTimeInterval(60))
        XCTAssertFalse(m.restore(stand, of: a))
        let texte = u.dateien().compactMap { u.text($0) }
        XCTAssertNotNil(m.session?.conflictNotice, "der Hinweis auf die Konfliktdatei bleibt sichtbar")
        XCTAssertTrue(texte.contains("fremd"), "die fremde Fassung bleibt")
        XCTAssertTrue(texte.contains("früher") || m.session?.note.body == "früher",
                      "der wiederhergestellte Text geht nicht verloren")
    }
}
