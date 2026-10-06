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

    func testOhneVersionenLeereListe() throws {
        let m = try seite()
        m.versions = nil
        XCTAssertTrue(m.versionList(for: m.store.notes[0].id).isEmpty)
    }
}
