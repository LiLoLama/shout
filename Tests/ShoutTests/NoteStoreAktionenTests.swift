import XCTest

@MainActor
final class NoteStoreAktionenTests: XCTestCase {

    private var u: NotizUmgebung!

    override func setUpWithError() throws {
        Loc.shared.apply("de")
        u = try NotizUmgebung()
    }

    override func tearDown() {
        u.aufraeumen()
        Loc.shared.apply("system")
        super.tearDown()
    }

    private func neu(_ s: NoteStore, _ text: String) throws -> Note {
        var n = Note.blank()
        n.body = text
        guard case .saved(let notiz) = s.save(n) else { XCTFail("nicht gesichert"); throw XCTSkip() }
        return notiz
    }

    func testUmbenennenHaeltDenTitelFest() throws {
        let s = u.store()
        let n = try neu(s, "Milch")
        let umbenannt = try XCTUnwrap(s.rename(n.id, to: "Einkauf: Samstag"))
        XCTAssertEqual(umbenannt.fileName, "Einkauf Samstag.md")
        XCTAssertTrue(umbenannt.titleIsFixed)
        XCTAssertEqual(umbenannt.id, n.id)
        XCTAssertEqual(u.dateien(), ["Einkauf Samstag.md"])
    }

    func testNurDieSchreibweiseAendern() throws {
        let s = u.store()
        let n = try neu(s, "idee eins zwei")
        XCTAssertEqual(s.rename(n.id, to: "Idee eins zwei")?.fileName, "Idee eins zwei.md")
        XCTAssertEqual(u.dateien(), ["Idee eins zwei.md"])
    }

    func testUmbenennenAufBelegtenNamen() throws {
        try u.schreibe("Idee.md", "andere")
        let s = u.store()
        let n = try neu(s, "Etwas ganz anderes")
        XCTAssertEqual(s.rename(n.id, to: "Idee")?.fileName, "Idee 2.md")
        XCTAssertEqual(u.text("Idee.md"), "andere")
    }

    func testLeererNameAendertNichts() throws {
        let s = u.store()
        let n = try neu(s, "Bleibt wie es ist")
        XCTAssertNil(s.rename(n.id, to: " ?: "))
        XCTAssertEqual(u.dateien(), ["Bleibt wie es ist.md"])
    }

    func testAnheftenSchreibtFrontmatterUndSortiert() throws {
        try u.schreibe("A.md", "a", zeit: Date().addingTimeInterval(-100))
        try u.schreibe("B.md", "b", zeit: Date())
        let s = u.store()
        XCTAssertEqual(s.notes.map(\.title), ["B", "A"])
        let a = try XCTUnwrap(s.notes.first { $0.title == "A" })
        _ = s.setPinned(a.id, true)
        XCTAssertEqual(s.notes.map(\.title), ["A", "B"])
        XCTAssertTrue(NoteFile.parse(try XCTUnwrap(u.lies("A.md"))).pinned)

        _ = s.setPinned(a.id, false)
        XCTAssertFalse(try XCTUnwrap(u.lies("A.md")).contains("pinned"))
    }

    func testLoeschenUndZurueckholen() throws {
        try u.schreibe("Weg.md", "weg damit")
        let s = u.store()
        let geloescht = try XCTUnwrap(s.delete(s.notes[0].id))
        XCTAssertEqual(s.notes, [])
        XCTAssertEqual(u.dateien(), [])

        let zurueck = try XCTUnwrap(s.undoDelete(geloescht))
        XCTAssertEqual(zurueck.title, "Weg")
        XCTAssertEqual(u.text("Weg.md"), "weg damit")
    }

    /// Ist der Name inzwischen neu vergeben, kommt die gelöschte Notiz als „Weg 2“ zurück.
    func testZurueckholenAufBelegtenNamen() throws {
        try u.schreibe("Weg.md", "alt")
        let s = u.store()
        let geloescht = try XCTUnwrap(s.delete(s.notes[0].id))
        try u.schreibe("Weg.md", "neu")
        s.reload()
        XCTAssertEqual(s.undoDelete(geloescht)?.fileName, "Weg 2.md")
        XCTAssertEqual(u.text("Weg.md"), "neu")
    }

    func testNeueNotizLaesstSichNichtLoeschen() {
        XCTAssertNil(u.store().delete(UUID()))
    }

    /// „Wieder sichern“: Die Datei wurde von außen entfernt, der Text lebt noch
    /// im Editor und wird unter seinem Titel neu angelegt.
    func testWiederSichern() throws {
        try u.schreibe("Verschwunden.md", "Text")
        let s = u.store()
        var n = s.notes[0]
        try FileManager.default.removeItem(at: u.ordner.appendingPathComponent("Verschwunden.md"))
        s.reload()
        n.body = "Text, noch im Editor"
        guard case .saved(let neu) = s.restore(n) else { return XCTFail("nicht gesichert") }
        XCTAssertEqual(neu.fileName, "Verschwunden.md")
        XCTAssertEqual(neu.id, n.id)
        XCTAssertEqual(u.text("Verschwunden.md"), "Text, noch im Editor")
    }

    // MARK: - Zusätzliche Absicherung (über den Plan hinaus)

    /// Eine Änderung von außen, die die Liste noch nicht kennt, darf beim
    /// Anheften nicht überschrieben werden.
    func testAnheftenUeberschreibtKeineAenderungVonAussen() throws {
        try u.schreibe("Doku.md", "alt", zeit: Date().addingTimeInterval(-100))
        let s = u.store()
        let id = s.notes[0].id
        try u.schreibe("Doku.md", "von außen geändert", zeit: Date())
        guard case .saved(let n)? = s.setPinned(id, true) else { return XCTFail("nicht gesichert") }
        XCTAssertEqual(n.body, "von außen geändert")
        XCTAssertEqual(u.text("Doku.md"), "von außen geändert")
        XCTAssertTrue(NoteFile.parse(try XCTUnwrap(u.lies("Doku.md"))).pinned)
    }

    /// „Zurückholen“ legt nie eine Datei über eine vorhandene — auch nicht,
    /// wenn der Papierkorbeintrag selbst fehlt.
    func testZurueckholenOhnePapierkorbDateiVerliertNichts() throws {
        try u.schreibe("Weg.md", "behalten")
        let s = u.store()
        let geloescht = try XCTUnwrap(s.delete(s.notes[0].id))
        try u.schreibe("Weg.md", "neu")
        try FileManager.default.removeItem(at: geloescht.trashURL)
        s.reload()
        XCTAssertNil(s.undoDelete(geloescht))
        XCTAssertEqual(u.dateien(), ["Weg.md"])
        XCTAssertEqual(u.text("Weg.md"), "neu")
    }

    /// Ohne vorheriges `reload()` bleibt kein toter Eintrag mit derselben ID stehen.
    func testWiederSichernOhneEintragsDuplikat() throws {
        try u.schreibe("Verschwunden.md", "Text")
        let s = u.store()
        let n = s.notes[0]
        try FileManager.default.removeItem(at: u.ordner.appendingPathComponent("Verschwunden.md"))
        guard case .saved = s.restore(n) else { return XCTFail("nicht gesichert") }
        XCTAssertEqual(s.notes.count, 1)
        XCTAssertEqual(s.notes.map(\.id), [n.id])
    }

    /// Fehlt der Ordner, landet der Text im Puffer statt verloren zu gehen.
    func testWiederSichernBeiFehlendemOrdnerPuffert() throws {
        let s = u.store(ordner: u.wurzel.appendingPathComponent("Fehlt", isDirectory: true))
        var n = Note.blank()
        n.body = "Wichtiger Text"
        guard case .buffered(let gepuffert) = s.restore(n) else { return XCTFail("nicht gepuffert") }
        XCTAssertEqual(gepuffert.id, n.id)
        let imPuffer = (try? FileManager.default.contentsOfDirectory(atPath: u.puffer.path)) ?? []
        XCTAssertEqual(imPuffer.count, 1)
        XCTAssertEqual(s.folderState, .unreachable)
    }

    // MARK: - Nach dem Review

    /// Umbenennen darf keine veraltete Fassung mit neuem mtime versehen: Sonst
    /// hielte das nächste Einlesen den alten Text für aktuell.
    func testUmbenennenBehaeltAenderungVonAussen() throws {
        try u.schreibe("A.md", "alt", zeit: Date().addingTimeInterval(-100))
        let s = u.store()
        let id = s.notes[0].id
        try u.schreibe("A.md", "von außen geändert", zeit: Date())
        let umbenannt = try XCTUnwrap(s.rename(id, to: "B"))
        XCTAssertEqual(umbenannt.body, "von außen geändert")
        XCTAssertEqual(umbenannt.id, id)
        s.reload()
        XCTAssertEqual(s.notes.map(\.body), ["von außen geändert"])
        XCTAssertEqual(s.notes.map(\.id), [id])
        XCTAssertEqual(u.text("B.md"), "von außen geändert")
    }

    /// Existiert die Originaldatei noch, behalten beide Einträge verschiedene IDs;
    /// die wiederhergestellte Notiz behält ihre.
    func testWiederSichernBeiVorhandenerDateiHatEindeutigeIDs() throws {
        try u.schreibe("Doppelt.md", "Original")
        let s = u.store()
        let n = s.notes[0]
        guard case .saved(let kopie) = s.restore(n) else { return XCTFail("nicht gesichert") }
        XCTAssertEqual(kopie.fileName, "Doppelt 2.md")
        XCTAssertEqual(kopie.id, n.id)
        XCTAssertEqual(s.notes.count, 2)
        XCTAssertEqual(Set(s.notes.map(\.id)).count, 2)
        XCTAssertEqual(s.note(id: n.id)?.fileName, "Doppelt 2.md")
        XCTAssertEqual(u.text("Doppelt.md"), "Original")
    }

    func testZurueckholenBehaeltDieID() throws {
        try u.schreibe("Weg.md", "weg damit")
        let s = u.store()
        let id = s.notes[0].id
        let geloescht = try XCTUnwrap(s.delete(id))
        XCTAssertEqual(try XCTUnwrap(s.undoDelete(geloescht)).id, id)
    }

    /// Nicht erreichbarer Ordner: Die Pufferdatei trägt den Titel der Notiz,
    /// nicht einen aus dem Text abgeleiteten.
    func testWiederSichernBeiFehlendemOrdnerBehaeltDenTitel() throws {
        let s = u.store(ordner: u.wurzel.appendingPathComponent("Fehlt", isDirectory: true))
        var n = Note.blank()
        n.fileName = "Mein Titel.md"
        n.body = "Ganz anderer Anfang des Textes"
        guard case .buffered(let g) = s.restore(n) else { return XCTFail("nicht gepuffert") }
        XCTAssertEqual(g.fileName, "Mein Titel.md")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: u.puffer.path), ["Mein Titel.md"])
    }

    /// Scheitert der Papierkorb, weil die Datei weg ist, verschwindet der Eintrag.
    func testLoeschenEntferntEintragEinerVerschwundenenDatei() throws {
        try u.schreibe("Weg.md", "x")
        let s = u.store()
        let id = s.notes[0].id
        try FileManager.default.removeItem(at: u.ordner.appendingPathComponent("Weg.md"))
        XCTAssertNil(s.delete(id))
        XCTAssertEqual(s.notes, [])
    }
}
