import XCTest

@MainActor
final class NotesPageModelTests: XCTestCase {

    private var u: NotizUmgebung!
    private var suite: String!
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        Loc.shared.apply("de")
        u = try NotizUmgebung()
        suite = "shout-notespage-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() {
        u.aufraeumen()
        defaults.removePersistentDomain(forName: suite)
        Loc.shared.apply("system")
        super.tearDown()
    }

    /// A ist die älteste, C die neueste — die Liste zeigt C, B, A.
    private func dreiNotizen() throws -> NotesPageModel {
        try u.schreibe("A.md", "eins", zeit: Date().addingTimeInterval(-30))
        try u.schreibe("B.md", "zwei", zeit: Date().addingTimeInterval(-20))
        try u.schreibe("C.md", "drei", zeit: Date().addingTimeInterval(-10))
        return NotesPageModel(store: u.store(), defaults: defaults)
    }

    private func id(_ m: NotesPageModel, _ titel: String) -> UUID {
        m.store.notes.first { $0.title == titel }!.id
    }

    func testNeueNotiz() {
        let m = NotesPageModel(store: u.store(), defaults: defaults)
        m.createNote()
        XCTAssertEqual(m.session?.note.isNew, true)
    }

    func testAuswahlwechselSichertVorher() throws {
        let m = try dreiNotizen()
        m.select(id(m, "A"))
        m.session?.edit("eins, geändert")
        m.select(id(m, "B"))
        XCTAssertEqual(u.text("A.md"), "eins, geändert")
        XCTAssertEqual(m.session?.note.title, "B")
    }

    func testSucheFiltert() throws {
        let m = try dreiNotizen()
        m.query = "zwei"
        XCTAssertEqual(m.results.map(\.note.title), ["B"])
    }

    func testPfeilnavigation() throws {
        let m = try dreiNotizen()
        m.moveSelection(by: 1)                      // nichts gewählt → erste
        XCTAssertEqual(m.session?.note.title, "C")
        m.moveSelection(by: 1)
        XCTAssertEqual(m.session?.note.title, "B")
        m.moveSelection(by: 5)                      // bleibt am Ende stehen
        XCTAssertEqual(m.session?.note.title, "A")
        m.moveSelection(by: -1)
        XCTAssertEqual(m.session?.note.title, "B")
    }

    func testLoeschenWaehltNachbarnUndRueckgaengig() throws {
        let m = try dreiNotizen()
        m.select(id(m, "B"))
        m.delete(id(m, "B"))
        XCTAssertEqual(m.session?.note.title, "A")
        XCTAssertEqual(m.lastDeleted?.title, "B")
        XCTAssertEqual(m.results.map(\.note.title), ["C", "A"])

        m.undoDelete()
        XCTAssertNil(m.lastDeleted)
        XCTAssertEqual(m.session?.note.title, "B")
        XCTAssertEqual(u.text("B.md"), "zwei")
    }

    /// Eine nie gesicherte Notiz hat keine Datei — „Löschen“ verwirft sie einfach.
    func testNeueNotizLoeschenVerwirft() {
        let m = NotesPageModel(store: u.store(), defaults: defaults)
        m.createNote()
        m.delete(m.session!.id)
        XCTAssertNil(m.session)
        XCTAssertNil(m.lastDeleted)
    }

    func testAnheftenUndUmbenennenUeberDieSitzung() throws {
        let m = try dreiNotizen()
        m.select(id(m, "A"))
        m.session?.edit("eins, ungesichert")
        m.togglePin(id(m, "A"))
        XCTAssertEqual(m.results.first?.note.title, "A")
        XCTAssertEqual(u.text("A.md"), "eins, ungesichert")

        m.rename(id(m, "A"), to: "Erste")
        XCTAssertEqual(m.session?.note.fileName, "Erste.md")
    }

    func testOrdnerwechsel() throws {
        let m = try dreiNotizen()
        m.select(id(m, "A"))
        let anderer = u.wurzel.appendingPathComponent("Anderer", isDirectory: true)
        try FileManager.default.createDirectory(at: anderer, withIntermediateDirectories: true)
        m.changeFolder(to: anderer)
        XCTAssertNil(m.session)
        XCTAssertEqual(m.store.notes, [])
        XCTAssertEqual(defaults.string(forKey: NotesFolder.defaultsKey), anderer.standardizedFileURL.path)
    }

    // MARK: - Ungesicherter Text bleibt, wenn das Sichern scheitert

    /// Öffnet A, tippt, und macht die Datei von außen unlesbar (Latin-1, neueres
    /// mtime): Der Store schreibt nichts, der Text lebt nur in der Sitzung.
    private func sitzungMitScheiterndemSichern() throws -> NotesPageModel {
        let m = try dreiNotizen()
        m.select(id(m, "A"))
        m.session?.edit("meins")
        try Data([0x47, 0xFC, 0x6E]).write(to: u.ordner.appendingPathComponent("A.md"))
        return m
    }

    func testAuswahlwechselBleibtStehen() throws {
        let m = try sitzungMitScheiterndemSichern()
        let a = id(m, "A")
        m.select(id(m, "B"))
        XCTAssertEqual(m.session?.id, a)
        XCTAssertEqual(m.session?.note.body, "meins")
        m.createNote()
        XCTAssertEqual(m.session?.id, a)
    }

    func testLoeschenMitUngesichertemTextLoeschtNicht() throws {
        let m = try sitzungMitScheiterndemSichern()
        let a = id(m, "A")
        m.delete(a)
        XCTAssertEqual(m.session?.id, a)
        XCTAssertEqual(m.session?.note.body, "meins")
        XCTAssertNil(m.lastDeleted)
        XCTAssertEqual(u.dateien(), ["A.md", "B.md", "C.md"])
    }

    func testOrdnerwechselMitUngesichertemTextBleibtStehen() throws {
        let m = try sitzungMitScheiterndemSichern()
        let anderer = u.wurzel.appendingPathComponent("Anderer", isDirectory: true)
        try FileManager.default.createDirectory(at: anderer, withIntermediateDirectories: true)
        XCTAssertFalse(m.changeFolder(to: anderer))
        XCTAssertEqual(m.session?.note.body, "meins")
        XCTAssertEqual(m.store.folder.standardizedFileURL, u.ordner.standardizedFileURL)
        XCTAssertNil(defaults.string(forKey: NotesFolder.defaultsKey))
    }

    /// Das Zurückholen liest den Ordner neu ein; die unlesbare Fremddatei fällt aus
    /// der Liste, die Sitzung gilt als „fehlt“ und `flush()` legt ihren Text neu an.
    /// Nichts geht verloren, und B ist zurück.
    func testRueckgaengigVerliertKeinenOffenenText() throws {
        let m = try dreiNotizen()
        m.select(id(m, "B"))
        m.delete(id(m, "B"))                        // Sitzung wechselt zu A
        XCTAssertEqual(m.session?.note.title, "A")
        m.session?.edit("meins")
        try Data([0x47, 0xFC, 0x6E]).write(to: u.ordner.appendingPathComponent("A.md"))

        m.undoDelete()
        XCTAssertEqual(u.text("B.md"), "zwei", "B ist zurück")
        XCTAssertEqual(m.session?.note.title, "B")
        XCTAssertEqual(u.text("A 2.md"), "meins", "der offene Text wurde neu angelegt")
        XCTAssertNil(m.lastDeleted)
    }

    /// Getippter Text in einer neuen Notiz wird beim Löschen erst gesichert und
    /// landet dann im Papierkorb — er ist per Rückgängig zurückzuholen.
    func testNeueNotizMitTextLoeschenGehtInDenPapierkorb() {
        let m = NotesPageModel(store: u.store(), defaults: defaults)
        m.createNote()
        m.session?.edit("Gedanke")
        m.delete(m.session!.id)
        XCTAssertNil(m.session)
        XCTAssertNotNil(m.lastDeleted)
        m.undoDelete()
        XCTAssertEqual(m.session?.note.body, "Gedanke")
    }

    /// Ausweg bei dauerhaft gescheitertem Sichern: Verwerfen gibt die Seite frei,
    /// ohne zu sichern — die fremde Datei bleibt Byte für Byte, wie sie war.
    func testVerwerfenGibtDieSeiteFreiOhneZuSichern() throws {
        let m = try sitzungMitScheiterndemSichern()
        let a = id(m, "A")
        let b = id(m, "B")
        m.select(b)
        XCTAssertEqual(m.session?.id, a, "gesperrt, solange der Text ungesichert ist")
        XCTAssertEqual(m.session?.saveFailed, true)

        m.discardSession()
        XCTAssertNil(m.session)
        m.select(b)
        XCTAssertEqual(m.session?.id, b)
        XCTAssertEqual(try Data(contentsOf: u.ordner.appendingPathComponent("A.md")), Data([0x47, 0xFC, 0x6E]))
    }

    func testOrdnerwechselGibtTrueZurueck() throws {
        let m = try dreiNotizen()
        let anderer = u.wurzel.appendingPathComponent("Anderer", isDirectory: true)
        try FileManager.default.createDirectory(at: anderer, withIntermediateDirectories: true)
        XCTAssertTrue(m.changeFolder(to: anderer))
    }

    // MARK: - Rettungskopie beim Beenden

    /// Scheitert das Sichern beim Beenden, landet der Text in einer eigenen Datei
    /// im Rettungsordner — die fremde Datei im Notizordner bleibt unberührt.
    func testRettungskopieSchreibtUngesichertenText() throws {
        let m = try sitzungMitScheiterndemSichern()
        m.flush()
        let rettung = u.wurzel.appendingPathComponent("Rettung", isDirectory: true)

        let url = m.writeRescueCopyIfNeeded(in: rettung)

        let datei = try XCTUnwrap(url)
        XCTAssertEqual(datei.deletingLastPathComponent().standardizedFileURL, rettung.standardizedFileURL)
        XCTAssertTrue(datei.lastPathComponent.hasPrefix("A "), datei.lastPathComponent)
        XCTAssertEqual(datei.pathExtension, "md")
        XCTAssertEqual(try String(contentsOf: datei, encoding: .utf8), "meins")
        let inhalt = try FileManager.default.contentsOfDirectory(atPath: rettung.path)
        XCTAssertEqual(inhalt.count, 1)
        XCTAssertEqual(try Data(contentsOf: u.ordner.appendingPathComponent("A.md")), Data([0x47, 0xFC, 0x6E]))
    }

    func testRettungskopieOhneUngesichertenTextSchreibtNichts() throws {
        let m = try dreiNotizen()
        let rettung = u.wurzel.appendingPathComponent("Rettung", isDirectory: true)
        XCTAssertNil(m.writeRescueCopyIfNeeded(in: rettung), "keine Sitzung")

        m.select(id(m, "A"))
        m.session?.edit("eins, geändert")
        m.flush()
        XCTAssertNil(m.writeRescueCopyIfNeeded(in: rettung), "alles gesichert")
        XCTAssertFalse(FileManager.default.fileExists(atPath: rettung.path))
    }

    /// Beenden abgebrochen, dann erneut beendet: Derselbe Text wird nicht noch
    /// einmal gerettet. Erst geänderter Text bekommt eine neue Kopie.
    func testZweitesBeendenSchreibtKeineGleicheRettungskopie() throws {
        let m = try sitzungMitScheiterndemSichern()
        let rettung = u.wurzel.appendingPathComponent("Rettung", isDirectory: true)
        m.flush()
        let erste = try XCTUnwrap(m.writeRescueCopyIfNeeded(in: rettung))

        m.flush()
        XCTAssertEqual(m.writeRescueCopyIfNeeded(in: rettung), erste)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: rettung.path).count, 1)

        m.session?.edit("meins, mehr")
        m.flush()
        let zweite = try XCTUnwrap(m.writeRescueCopyIfNeeded(in: rettung))
        XCTAssertNotEqual(zweite, erste)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: rettung.path).count, 2)
    }

    // MARK: - Gerettete Notizen zurückholen

    /// Die Seite zeigt gerettete Notizen an und holt sie unter freien Namen in
    /// den Notizordner. Die Rettungsdatei verschwindet erst nach dem Schreiben.
    func testGeretteteNotizenWerdenInDenOrdnerGeholt() throws {
        let rettung = u.wurzel.appendingPathComponent("Rettung", isDirectory: true)
        try FileManager.default.createDirectory(at: rettung, withIntermediateDirectories: true)
        try Data("gerettet eins".utf8).write(to: rettung.appendingPathComponent("A 2026-10-05 14-32-11.md"))
        try Data("gerettet zwei".utf8).write(to: rettung.appendingPathComponent("Unbenannt 2026-10-05 14-32-12.md"))
        try Data("keine Notiz".utf8).write(to: rettung.appendingPathComponent("liesmich.txt"))
        try u.schreibe("A 2026-10-05 14-32-11.md", "schon da")
        let m = NotesPageModel(store: u.store(), defaults: defaults, rescueDirectory: rettung)
        XCTAssertEqual(m.rescuedFiles.map(\.lastPathComponent).sorted(),
                       ["A 2026-10-05 14-32-11.md", "Unbenannt 2026-10-05 14-32-12.md"])

        XCTAssertEqual(m.adoptRescuedNotes(), 2)
        XCTAssertEqual(m.rescuedFiles, [])
        XCTAssertEqual(u.text("A 2026-10-05 14-32-11.md"), "schon da")
        XCTAssertEqual(u.text("A 2026-10-05 14-32-11 2.md"), "gerettet eins")
        XCTAssertEqual(u.text("Unbenannt 2026-10-05 14-32-12.md"), "gerettet zwei")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: rettung.path), ["liesmich.txt"])
        XCTAssertEqual(m.store.notes.count, 3)
    }

    /// Ist der Notizordner nicht erreichbar, bleibt die Rettungsdatei liegen.
    func testGeretteteNotizBleibtWennDerOrdnerFehlt() throws {
        let rettung = u.wurzel.appendingPathComponent("Rettung", isDirectory: true)
        try FileManager.default.createDirectory(at: rettung, withIntermediateDirectories: true)
        let datei = rettung.appendingPathComponent("A 2026-10-05 14-32-11.md")
        try Data("gerettet".utf8).write(to: datei)
        let fehlt = u.wurzel.appendingPathComponent("abgesteckt", isDirectory: true)
        let m = NotesPageModel(store: u.store(ordner: fehlt), defaults: defaults, rescueDirectory: rettung)
        XCTAssertEqual(m.rescuedFiles.count, 1)

        XCTAssertEqual(m.adoptRescuedNotes(), 0)
        XCTAssertEqual(m.rescuedFiles.count, 1)
        XCTAssertEqual(try String(contentsOf: datei, encoding: .utf8), "gerettet")
    }

    /// Eine Rettungskopie, die während der Sitzung entsteht (Beenden abgebrochen),
    /// erscheint sofort im Hinweis.
    func testRettungskopieErscheintImHinweis() throws {
        let rettung = u.wurzel.appendingPathComponent("Rettung", isDirectory: true)
        try u.schreibe("A.md", "eins")
        let m = NotesPageModel(store: u.store(), defaults: defaults, rescueDirectory: rettung)
        m.select(id(m, "A"))
        m.session?.edit("meins")
        try Data([0x47, 0xFC, 0x6E]).write(to: u.ordner.appendingPathComponent("A.md"))
        m.flush()
        XCTAssertEqual(m.rescuedFiles, [])

        XCTAssertNotNil(m.writeRescueCopyIfNeeded(in: m.rescueDirectory))
        XCTAssertEqual(m.rescuedFiles.count, 1)
    }
}
