import XCTest

@MainActor
final class NoteStoreScratchpadTests: XCTestCase {

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

    func testAnlegenMitFestemTitelUndLeeremText() throws {
        let s = u.store()
        guard case .saved(let notiz) = s.create(title: "Eingang", body: "", pinned: true) else {
            return XCTFail("nicht angelegt")
        }
        XCTAssertEqual(notiz.fileName, "Eingang.md")
        XCTAssertTrue(notiz.pinned)
        XCTAssertTrue(notiz.titleIsFixed)
        XCTAssertEqual(s.notes.map(\.id), [notiz.id])
        XCTAssertTrue(NoteFile.parse(try XCTUnwrap(u.lies("Eingang.md"))).pinned)
    }

    func testAnlegenAufBelegtenNamen() throws {
        try u.schreibe("Eingang.md", "fremd")
        let s = u.store()
        guard case .saved(let notiz) = s.create(title: "Eingang", body: "", pinned: true) else {
            return XCTFail("nicht angelegt")
        }
        XCTAssertEqual(notiz.fileName, "Eingang 2.md")
        XCTAssertEqual(u.text("Eingang.md"), "fremd")
    }

    func testAnlegenOhneOrdnerScheitert() {
        let s = u.store(ordner: u.wurzel.appendingPathComponent("fehlt", isDirectory: true))
        XCTAssertEqual(s.create(title: "Eingang", body: "", pinned: true), .failed)
    }

    func testUmbenennenWirdGemeldet() throws {
        try u.schreibe("Eingang.md", "x")
        let s = u.store()
        var gemeldet: [(String, String)] = []
        s.observeRenames { gemeldet.append(($0, $1)) }
        s.rename(s.notes[0].id, to: "Sammelstelle")
        XCTAssertEqual(gemeldet.count, 1)
        XCTAssertEqual(gemeldet.first?.0, "Eingang.md")
        XCTAssertEqual(gemeldet.first?.1, "Sammelstelle.md")
    }

    // MARK: - Ergänzungen: Robustheit

    /// Ein Titel, der nach dem Säubern leer ist, legt nichts an.
    func testAnlegenMitLeeremTitelScheitert() {
        let s = u.store()
        XCTAssertEqual(s.create(title: " ?:* . ", body: "", pinned: true), .failed)
        XCTAssertEqual(u.dateien(), [])
    }

    /// Ein ausgelagerter iCloud-Platzhalter belegt den Namen ebenfalls.
    func testAnlegenUmgehtICloudPlatzhalter() throws {
        try u.schreibe(".Eingang.md.icloud", "")
        let s = u.store()
        guard case .saved(let notiz) = s.create(title: "Eingang", body: "", pinned: true) else {
            return XCTFail("nicht angelegt")
        }
        XCTAssertEqual(notiz.fileName, "Eingang 2.md")
    }

    /// Wer erst nach der Namenswahl auftaucht, wird nicht überschrieben:
    /// Das exklusive Schreiben lehnt eine vorhandene Datei ab.
    func testExklusivesSchreibenUeberschreibtNie() throws {
        try u.schreibe("Eingang.md", "fremd")
        let s = u.store()
        var note = Note.blank()
        note.body = "neu"
        XCTAssertEqual(s.writeExclusively(note, to: u.ordner.appendingPathComponent("Eingang.md")), .exists)
        XCTAssertEqual(u.text("Eingang.md"), "fremd")
        XCTAssertEqual(u.dateien(), ["Eingang.md"], "kein Rest einer Zwischendatei")
    }

    func testExklusivesSchreibenLegtNeueDateiAn() throws {
        let s = u.store()
        var note = Note.blank()
        note.body = "neu"
        guard case .written = s.writeExclusively(note, to: u.ordner.appendingPathComponent("Neu.md")) else {
            return XCTFail("nicht geschrieben")
        }
        XCTAssertEqual(u.text("Neu.md"), "neu")
        XCTAssertEqual(u.dateien(), ["Neu.md"])
    }

    /// Umbenennen auf den eigenen Namen meldet nichts.
    func testUmbenennenAufGleichenNamenMeldetNichts() throws {
        try u.schreibe("Eingang.md", "x")
        let s = u.store()
        var gemeldet = 0
        s.observeRenames { _, _ in gemeldet += 1 }
        s.rename(s.notes[0].id, to: "Eingang")
        XCTAssertEqual(gemeldet, 0)
    }

    // MARK: - Download-Merker

    /// Ein Platzhalter bleibt nur im Merker, solange er Platzhalter ist: Ist er
    /// geladen, verschwindet der Name — wird er erneut ausgelagert, gilt er wieder als neu.
    func testDownloadMerkerLeertSichNachDemLaden() throws {
        try u.schreibe(".Idee.md.icloud", "")
        let s = u.store()
        XCTAssertEqual(s.requestedDownloads, ["Idee.md"])
        s.reload()
        XCTAssertEqual(s.requestedDownloads, ["Idee.md"], "solange Platzhalter: bleibt")

        try FileManager.default.removeItem(at: u.ordner.appendingPathComponent(".Idee.md.icloud"))
        try u.schreibe("Idee.md", "geladen")
        s.reload()
        XCTAssertEqual(s.requestedDownloads, [])

        try FileManager.default.removeItem(at: u.ordner.appendingPathComponent("Idee.md"))
        try u.schreibe(".Idee.md.icloud", "")
        s.reload()
        XCTAssertEqual(s.requestedDownloads, ["Idee.md"], "erneut ausgelagert: wieder angefordert")
    }

    // MARK: - create und Watcher

    private func warte(bis bedingung: () -> Bool, timeout: TimeInterval = 8) {
        let ende = Date().addingTimeInterval(timeout)
        while !bedingung() && Date() < ende {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
    }

    /// Legt `create` den Ordner erst an, muss der Watcher danach laufen.
    func testAnlegenStartetDenWatcher() throws {
        let neuerOrdner = u.wurzel.appendingPathComponent("Neu", isDirectory: true)
        let s = NoteStore(folder: neuerOrdner, bufferFolder: u.puffer, watch: true, createIfMissing: true)
        guard case .saved = s.create(title: "Eingang", body: "", pinned: true) else {
            return XCTFail("nicht angelegt")
        }
        // FSEvents braucht einen Moment, bis der Strom läuft.
        RunLoop.current.run(until: Date().addingTimeInterval(0.7))
        try Data("fremd".utf8).write(to: neuerOrdner.appendingPathComponent("Fremd.md"))
        warte(bis: { s.notes.count == 2 })
        XCTAssertEqual(s.notes.count, 2, "externe Datei wurde nicht bemerkt")
    }

    /// Fehlt der Ordner, sieht der Store später nach, ob er wieder da ist.
    func testAnlegenOhneOrdnerPlantetNeuesPruefen() throws {
        let fehlt = u.wurzel.appendingPathComponent("Stick", isDirectory: true)
        let s = NoteStore(folder: fehlt, bufferFolder: u.puffer, watch: true, createIfMissing: false)
        XCTAssertEqual(s.create(title: "Eingang", body: "", pinned: true), .failed)
        XCTAssertEqual(s.folderState, .unreachable)
        try FileManager.default.createDirectory(at: fehlt, withIntermediateDirectories: true)
        try Data("da".utf8).write(to: fehlt.appendingPathComponent("Da.md"))
        warte(bis: { s.notes.count == 1 }, timeout: 12)
        XCTAssertEqual(s.notes.count, 1)
    }
}
