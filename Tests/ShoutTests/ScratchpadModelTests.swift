import XCTest

@MainActor
final class ScratchpadModelTests: XCTestCase {

    private var u: NotizUmgebung!
    private var suite: String!
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        Loc.shared.apply("de")
        u = try NotizUmgebung()
        suite = "shout-scratchpad-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() {
        u.aufraeumen()
        defaults.removePersistentDomain(forName: suite)
        Loc.shared.apply("system")
        super.tearDown()
    }

    private func modell(_ store: NoteStore? = nil) -> ScratchpadModel {
        let s = store ?? u.store()
        return ScratchpadModel(store: s, registry: NoteSessionRegistry(store: s, saveDelay: 60), defaults: defaults)
    }

    private func id(_ m: ScratchpadModel, _ titel: String) -> UUID {
        m.store.notes.first { $0.title == titel }!.id
    }

    func testBisFuenfTabsDannWirdDerAktiveErsetzt() {
        let m = modell()
        for _ in 0..<5 { XCTAssertNotNil(m.newTab()) }
        XCTAssertEqual(m.tabs.count, 5)
        let sechster = m.newTab()
        XCTAssertEqual(m.tabs.count, 5)
        XCTAssertEqual(m.activeIndex, 4)
        XCTAssertTrue(m.tabs[4] === sechster)
    }

    func testOeffnenWaehltVorhandenenTab() throws {
        try u.schreibe("A.md", "a")
        try u.schreibe("B.md", "b")
        let m = modell()
        m.open(id(m, "A"), inNewTab: true)
        m.open(id(m, "B"), inNewTab: true)
        m.open(id(m, "A"), inNewTab: true)
        XCTAssertEqual(m.tabs.count, 2)
        XCTAssertEqual(m.activeIndex, 0)
    }

    func testOeffnenMeldetFehlschlagBeiVollemPanelUndUngesichertemTab() throws {
        try u.schreibe("A.md", "a")
        try u.schreibe("B.md", "b")
        let m = modell()
        for _ in 0..<4 { m.newTab() }
        XCTAssertTrue(m.open(id(m, "A"), inNewTab: true))
        XCTAssertEqual(m.tabs.count, 5)
        m.active?.edit("meins")
        // Von außen unlesbar (Latin-1): Der Text lebt nur in der Sitzung.
        try Data([0x47, 0xFC, 0x6E]).write(to: u.ordner.appendingPathComponent("A.md"))
        XCTAssertFalse(m.open(id(m, "B"), inNewTab: true))
        XCTAssertEqual(m.tabs.count, 5)
        XCTAssertEqual(m.active?.note.body, "meins")
        XCTAssertFalse(m.open(UUID(), inNewTab: true))
    }

    func testSchliessenRuecktDieAuswahl() {
        let m = modell()
        m.newTab(); m.newTab(); m.newTab()
        XCTAssertEqual(m.activeIndex, 2)
        m.close(0)
        XCTAssertEqual(m.activeIndex, 1)
        m.close(1)
        XCTAssertEqual(m.activeIndex, 0)
        m.close(0)
        XCTAssertNil(m.activeIndex)
        XCTAssertTrue(m.tabs.isEmpty)
    }

    func testTabsUeberlebenDenNeustart() throws {
        try u.schreibe("A.md", "a")
        try u.schreibe("B.md", "b")
        let store = u.store()
        let m = modell(store)
        m.open(id(m, "A"), inNewTab: true)
        m.open(id(m, "B"), inNewTab: true)
        m.select(0)
        let zweites = modell(store)
        zweites.restoreTabs()
        XCTAssertEqual(zweites.tabs.map(\.note.title), ["A", "B"])
        XCTAssertEqual(zweites.activeIndex, 0)
    }

    func testOeffnenVerhaltenNeuerTab() throws {
        try u.schreibe("A.md", "Text")
        let m = modell()
        m.open(id(m, "A"), inNewTab: true)
        m.prepareForShowing(behavior: .newTab)
        XCTAssertEqual(m.tabs.count, 2)
        m.prepareForShowing(behavior: .newTab)      // vorderer Tab ist leer: kein dritter
        XCTAssertEqual(m.tabs.count, 2)
    }

    func testOeffnenVerhaltenAngeheftet() throws {
        try u.schreibe("A.md", "---\npinned: true\n---\nangeheftet")
        try u.schreibe("B.md", "b")
        let m = modell()
        m.prepareForShowing(behavior: .lastPinned)
        XCTAssertEqual(m.active?.note.title, "A")
    }

    func testOeffnenVerhaltenFortsetzenOhneTabs() {
        let m = modell()
        m.prepareForShowing(behavior: .resume)
        XCTAssertEqual(m.tabs.count, 1)
        XCTAssertEqual(m.active?.note.isNew, true)
    }

    func testDiktatTabNeuWennDerAktiveTextHat() throws {
        try u.schreibe("A.md", "Text")
        let m = modell()
        m.open(id(m, "A"), inNewTab: true)
        let neu = m.tabForDictation(newIfActiveHasText: true)
        XCTAssertEqual(neu?.note.isNew, true)
        XCTAssertTrue(m.tabForDictation(newIfActiveHasText: false) === neu)
    }

    func testDiktatLandetAmCursor() {
        let m = modell()
        let s = m.newTab()!
        s.edit("Hallo")
        s.selectionChanged(NSRange(location: 5, length: 0))
        XCTAssertTrue(m.insertDictation("Welt", into: s.id))
        XCTAssertEqual(s.note.body, "Hallo Welt")
    }

    /// Ist die Zielnotiz nicht mehr offen, entsteht ein neuer Tab — das Diktat geht nicht verloren.
    func testDiktatOhneZielInNeuenTab() {
        let m = modell()
        XCTAssertTrue(m.insertDictation("Gedanke", into: UUID()))
        XCTAssertEqual(m.active?.note.body, "Gedanke")
    }

    func testEingangWirdAngelegtUndAngehaengt() throws {
        let m = modell()
        let mittag = ISO8601DateFormatter().date(from: "2026-10-05T12:32:00Z")!
        XCTAssertTrue(m.appendToInbox("Milch kaufen", now: mittag, locale: Locale(identifier: "de_DE")))
        XCTAssertTrue(m.appendToInbox("Brot", now: mittag.addingTimeInterval(600), locale: Locale(identifier: "de_DE")))
        let roh = try XCTUnwrap(u.lies("Eingang.md"))
        let geparst = NoteFile.parse(roh)
        XCTAssertTrue(geparst.pinned)
        XCTAssertEqual(geparst.body.components(separatedBy: "## ").count - 1, 1)   // eine Tagesüberschrift
        XCTAssertTrue(geparst.body.contains("Milch kaufen"))
        XCTAssertTrue(geparst.body.contains("Brot"))
    }

    func testEingangFolgtDerUmbenennung() throws {
        let m = modell()
        XCTAssertTrue(m.appendToInbox("eins"))
        let eingang = try XCTUnwrap(m.store.notes.first { $0.fileName == "Eingang.md" })
        m.store.rename(eingang.id, to: "Sammelstelle")
        XCTAssertEqual(m.inboxFileName, "Sammelstelle.md")
        XCTAssertTrue(m.appendToInbox("zwei"))
        XCTAssertEqual(u.dateien(), ["Sammelstelle.md"])
        XCTAssertTrue(try XCTUnwrap(u.text("Sammelstelle.md")).contains("zwei"))
    }

    func testVerworfeneSitzungVerschwindetAusDenTabs() {
        let m = modell()
        let s = m.newTab()!
        m.discard(s)
        XCTAssertTrue(m.tabs.isEmpty)
        XCTAssertNil(m.activeIndex)
    }

    // MARK: - Ergänzt: leeres Diktat, ungesicherter Text, Ordnerwechsel

    /// Ein leeres Diktat ist kein Fehler — und legt keine Eingangs-Notiz an.
    func testLeeresDiktatLegtKeinenEingangAn() {
        let m = modell()
        XCTAssertTrue(m.appendToInbox(""))
        XCTAssertTrue(m.appendToInbox("  \n\t "))
        XCTAssertEqual(u.dateien(), [])
        XCTAssertTrue(m.store.notes.isEmpty)
    }

    /// Macht das nächste Sichern von `X.md` unmöglich: eine fremde, nicht lesbare
    /// Änderung mit neuerem mtime. Der Store liefert dann `.failed`.
    private func machSichernUnmoeglich() throws {
        let url = u.ordner.appendingPathComponent("X.md")
        try Data([0x47, 0xFC, 0x6E]).write(to: url)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(60)], ofItemAtPath: url.path)
    }

    /// Bleibt Text ungesichert, ersetzt kein neuer Tab den aktiven.
    func testUngesicherterTabWirdNichtErsetzt() throws {
        try u.schreibe("X.md", "a")
        let m = modell()
        for _ in 0..<4 { m.newTab() }
        m.open(id(m, "X"), inNewTab: true)
        XCTAssertEqual(m.tabs.count, 5)
        let x = try XCTUnwrap(m.active)
        x.edit("nur hier")
        try machSichernUnmoeglich()
        XCTAssertNil(m.newTab())
        XCTAssertTrue(m.active === x)
        XCTAssertEqual(x.note.body, "nur hier")
        XCTAssertTrue(m.registry.session(id: x.id) === x)
    }

    /// Ein Tab mit Text, der sich nicht sichern lässt, schließt nicht — sonst
    /// stünde der Text unsichtbar nur noch im Speicher. Er wird stattdessen gewählt.
    func testUngesicherterTabSchliesstNicht() throws {
        try u.schreibe("X.md", "a")
        let m = modell()
        m.open(id(m, "X"), inNewTab: true)
        m.newTab()
        let x = m.tabs[0]
        x.edit("nur hier")
        try machSichernUnmoeglich()
        m.close(0)
        XCTAssertEqual(m.tabs.count, 2)
        XCTAssertEqual(m.activeIndex, 0)
        XCTAssertTrue(m.active === x)
        XCTAssertEqual(x.note.body, "nur hier")
    }

    /// Ein neuer Tab vor dem ersten Einblenden überschreibt nicht die gemerkten Tabs.
    func testNeuerTabBehaeltDieGemerktenTabs() throws {
        try u.schreibe("A.md", "a")
        let store = u.store()
        let m = modell(store)
        m.open(id(m, "A"), inNewTab: true)
        let zweites = modell(store)
        XCTAssertNotNil(zweites.newTab())
        XCTAssertEqual(zweites.tabs.count, 2)
        XCTAssertEqual(zweites.tabs.first?.note.title, "A")
    }

    // MARK: - Fix nach Review

    /// Neue (nie gesicherte) Tabs werden nicht gemerkt — der aktive Tab wird deshalb
    /// über seinen Namen wiedergefunden, nicht über die Stelle.
    func testAktiverTabWirdNachNameWiederhergestellt() throws {
        try u.schreibe("A.md", "a")
        try u.schreibe("B.md", "b")
        let store = u.store()
        let m = modell(store)
        m.newTab()
        m.open(id(m, "A"), inNewTab: true)
        m.open(id(m, "B"), inNewTab: true)
        m.select(1)
        XCTAssertEqual(m.active?.note.title, "A")
        let zweites = modell(store)
        zweites.restoreTabs()
        XCTAssertEqual(zweites.tabs.map(\.note.title), ["A", "B"])
        XCTAssertEqual(zweites.active?.note.title, "A")
    }

    /// Ein leeres Diktat ist kein Fehler und öffnet keinen leeren Tab.
    func testLeeresDiktatOeffnetKeinenTab() {
        let m = modell()
        XCTAssertTrue(m.insertDictation("", into: UUID()))
        XCTAssertTrue(m.insertDictation(" \n ", into: UUID()))
        XCTAssertTrue(m.tabs.isEmpty)
    }

    /// Sichern vor dem ersten Einblenden überschreibt die gemerkten Tabs nicht.
    func testSichernBehaeltDieGemerktenTabs() throws {
        try u.schreibe("A.md", "a")
        let store = u.store()
        let m = modell(store)
        m.open(id(m, "A"), inNewTab: true)
        modell(store).flushAll()
        let drittes = modell(store)
        drittes.restoreTabs()
        XCTAssertEqual(drittes.tabs.map(\.note.title), ["A"])
    }

    /// Landet der Eingang in einer Konfliktdatei, meldet `appendToInbox` das —
    /// der Aufrufer legt den Text dann zusätzlich in die Zwischenablage.
    func testEingangImKonfliktMeldetFehlschlag() throws {
        try u.schreibe("Eingang.md", "alt", zeit: Date().addingTimeInterval(-60))
        let m = modell()
        XCTAssertNotNil(m.store.notes.first { $0.fileName == "Eingang.md" })
        try u.schreibe("Eingang.md", "fremd", zeit: Date())
        XCTAssertFalse(m.appendToInbox("Milch kaufen"))
        let texte = u.dateien().compactMap { u.text($0) }
        XCTAssertTrue(texte.contains { $0.contains("Milch kaufen") }, "\(u.dateien())")
    }

    /// Nach einem Ordnerwechsel hält das Panel keine Sitzungen des alten Ordners mehr,
    /// die die Registry nicht mehr kennt.
    func testOrdnerwechselRaeumtDieTabs() throws {
        try u.schreibe("A.md", "a")
        let store = u.store()
        let r = NoteSessionRegistry(store: store, saveDelay: 60)
        let m = ScratchpadModel(store: store, registry: r, defaults: defaults)
        let seite = NotesPageModel(store: store, registry: r, defaults: defaults)
        m.open(id(m, "A"), inNewTab: true)
        m.newTab()
        let anderer = u.wurzel.appendingPathComponent("Anderer", isDirectory: true)
        try FileManager.default.createDirectory(at: anderer, withIntermediateDirectories: true)
        XCTAssertTrue(seite.changeFolder(to: anderer))
        XCTAssertTrue(m.tabs.isEmpty)
        XCTAssertNil(m.activeIndex)
    }

    func testOrdnerwechselVergisstDenNamenDerEingangsNotiz() {
        let m = modell()
        m.inboxFileName = "Inbox 2.md"
        m.resetTabs()
        XCTAssertEqual(m.inboxFileName, Loc.t("Eingang.md"))
    }
}
