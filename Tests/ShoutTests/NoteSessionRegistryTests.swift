import XCTest

@MainActor
final class NoteSessionRegistryTests: XCTestCase {

    private var u: NotizUmgebung!
    private var suite: String!
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        Loc.shared.apply("de")
        u = try NotizUmgebung()
        suite = "shout-registry-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() {
        u.aufraeumen()
        defaults.removePersistentDomain(forName: suite)
        Loc.shared.apply("system")
        super.tearDown()
    }

    /// Macht das nächste Sichern von `X.md` unmöglich: eine fremde, nicht lesbare
    /// Änderung mit neuerem mtime. Der Store liefert dann `.failed`.
    private func machSichernUnmoeglich() throws {
        let url = u.ordner.appendingPathComponent("X.md")
        try Data([0x47, 0xFC, 0x6E]).write(to: url)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(60)], ofItemAtPath: url.path)
    }

    func testGleicheNotizGleicheSitzung() throws {
        try u.schreibe("X.md", "a")
        let store = u.store()
        let r = NoteSessionRegistry(store: store, saveDelay: 60)
        let eins = r.acquire(store.notes[0])
        let zwei = r.acquire(store.notes[0])
        XCTAssertTrue(eins === zwei)
    }

    func testLetzterHalterSichertUndGibtFrei() throws {
        try u.schreibe("X.md", "a")
        let store = u.store()
        let r = NoteSessionRegistry(store: store, saveDelay: 60)
        let s = r.acquire(store.notes[0])
        _ = r.acquire(store.notes[0])
        s.edit("a b")
        r.release(s)
        XCTAssertNotNil(r.session(id: s.id))          // ein Halter übrig
        r.release(s)
        XCTAssertNil(r.session(id: s.id))
        XCTAssertEqual(u.text("X.md"), "a b")
    }

    /// Bleibt Text ungesichert, behält die Registry die Sitzung — sonst wäre er beim Beenden weg.
    func testUngesichertBleibtNachFreigabe() throws {
        try u.schreibe("X.md", "a")
        let store = u.store()
        let r = NoteSessionRegistry(store: store, saveDelay: 60)
        let s = r.acquire(store.notes[0])
        s.edit("neu")
        try machSichernUnmoeglich()
        r.release(s)
        XCTAssertTrue(r.session(id: s.id) === s)
        XCTAssertEqual(r.unsavedSessions.map(\.id), [s.id])
        // Wer sie wieder öffnet, bekommt dieselbe Sitzung mit ihrem Text.
        XCTAssertEqual(r.acquire(store.notes[0]).note.body, "neu")
    }

    func testFlushAllMeldetUngesicherte() throws {
        try u.schreibe("X.md", "a")
        try u.schreibe("Y.md", "b")
        let store = u.store()
        let r = NoteSessionRegistry(store: store, saveDelay: 60)
        let x = r.acquire(store.notes.first { $0.title == "X" }!)
        let y = r.acquire(store.notes.first { $0.title == "Y" }!)
        x.edit("x neu")
        y.edit("y neu")
        try machSichernUnmoeglich()
        let offen = r.flushAll()
        XCTAssertEqual(offen.map(\.id), [x.id])
        XCTAssertEqual(u.text("Y.md"), "y neu")
    }

    func testVerwerfenMeldetAlleHalter() throws {
        try u.schreibe("X.md", "a")
        let store = u.store()
        let r = NoteSessionRegistry(store: store, saveDelay: 60)
        var gemeldet: [UUID] = []
        r.onDiscard { gemeldet.append($0) }
        let s = r.acquire(store.notes[0])
        r.discard(s)
        XCTAssertNil(r.session(id: s.id))
        XCTAssertEqual(gemeldet, [s.id])
    }

    func testRettungskopienFuerAlleUngesicherten() throws {
        try u.schreibe("X.md", "a")
        let store = u.store()
        let r = NoteSessionRegistry(store: store, saveDelay: 60)
        let s = r.acquire(store.notes[0])
        s.edit("gerettet")
        try machSichernUnmoeglich()
        r.flushAll()
        let rettung = u.wurzel.appendingPathComponent("Rettung", isDirectory: true)
        let ergebnis = r.writeRescueCopies(in: rettung)
        XCTAssertEqual(ergebnis.written.count, 1)
        XCTAssertTrue(ergebnis.failed.isEmpty)
        let inhalt = try String(contentsOf: ergebnis.written[0], encoding: .utf8)
        XCTAssertTrue(inhalt.contains("gerettet"))
        // Ein zweiter Versuch mit demselben Text schreibt keine zweite Kopie.
        XCTAssertEqual(r.writeRescueCopies(in: rettung).written, ergebnis.written)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: rettung.path).count, 1)
    }

    /// Seite und Registry teilen sich die Sitzung: Was die Seite öffnet, findet das Panel wieder.
    func testSeiteNutztDieRegistry() throws {
        try u.schreibe("X.md", "a")
        let store = u.store()
        let r = NoteSessionRegistry(store: store, saveDelay: 60)
        let seite = NotesPageModel(store: store, registry: r, defaults: defaults)
        seite.select(store.notes[0].id)
        XCTAssertTrue(seite.session === r.session(id: store.notes[0].id))
    }

    /// Der Ordnerwechsel prüft ALLE Sitzungen, nicht nur die der Seite.
    func testOrdnerwechselScheitertAnUngesichertemPanelText() throws {
        try u.schreibe("X.md", "a")
        let store = u.store()
        let r = NoteSessionRegistry(store: store, saveDelay: 60)
        let seite = NotesPageModel(store: store, registry: r, defaults: defaults)
        let panelSitzung = r.acquire(store.notes[0])
        panelSitzung.edit("im Panel getippt")
        try machSichernUnmoeglich()
        let anderer = u.wurzel.appendingPathComponent("Anderer", isDirectory: true)
        try FileManager.default.createDirectory(at: anderer, withIntermediateDirectories: true)
        XCTAssertFalse(seite.changeFolder(to: anderer))
        XCTAssertEqual(store.folder.standardizedFileURL.path, u.ordner.standardizedFileURL.path)
    }

    func testOrdnerwechselMeldetSich() throws {
        let store = u.store()
        let r = NoteSessionRegistry(store: store, saveDelay: 60)
        let seite = NotesPageModel(store: store, registry: r, defaults: defaults)
        var gemeldet = false
        seite.onFolderChanged = { gemeldet = true }
        let anderer = u.wurzel.appendingPathComponent("Anderer", isDirectory: true)
        try FileManager.default.createDirectory(at: anderer, withIntermediateDirectories: true)
        XCTAssertTrue(seite.changeFolder(to: anderer))
        XCTAssertTrue(gemeldet)
    }

    // MARK: - Ergänzt: Freigabe mit ungesichertem Text, Verwerfen, Löschen

    /// Eine abgegebene, ungesicherte Sitzung wird beim Beenden mitgerettet.
    func testAbgegebeneUngesicherteSitzungWirdGerettet() throws {
        try u.schreibe("X.md", "a")
        let store = u.store()
        let r = NoteSessionRegistry(store: store, saveDelay: 60)
        let s = r.acquire(store.notes[0])
        s.edit("nur im Speicher")
        try machSichernUnmoeglich()
        r.release(s)
        let rettung = u.wurzel.appendingPathComponent("Rettung", isDirectory: true)
        let ergebnis = r.writeRescueCopies(in: rettung)
        XCTAssertEqual(ergebnis.written.count, 1)
        XCTAssertEqual(try String(contentsOf: ergebnis.written[0], encoding: .utf8), "nur im Speicher")
    }

    /// Lässt sich der Text später doch sichern, räumt `flushAll` die abgegebene Sitzung ab.
    func testAbgegebeneSitzungVerschwindetNachSpaeteremSichern() throws {
        try u.schreibe("X.md", "a")
        let store = u.store()
        let r = NoteSessionRegistry(store: store, saveDelay: 60)
        let s = r.acquire(store.notes[0])
        s.edit("später gesichert")
        try machSichernUnmoeglich()
        r.release(s)
        XCTAssertNotNil(r.session(id: s.id))
        // Die fremde Fassung ist wieder lesbar: Die Konfliktprüfung hebt beide auf.
        try u.schreibe("X.md", "fremd", zeit: Date().addingTimeInterval(120))
        XCTAssertTrue(r.flushAll().isEmpty)
        XCTAssertNil(r.session(id: s.id))
        let ordner = try FileManager.default.contentsOfDirectory(atPath: u.ordner.path)
        let texte = ordner.compactMap { u.text($0) }
        XCTAssertTrue(texte.contains("später gesichert"), "\(ordner)")
    }

    /// Eine verworfene Sitzung wird beim späteren Abgeben nicht mehr gesichert.
    func testAbgebenNachVerwerfenSichertNicht() throws {
        try u.schreibe("X.md", "a")
        let store = u.store()
        let r = NoteSessionRegistry(store: store, saveDelay: 60)
        let s = r.acquire(store.notes[0])
        _ = r.acquire(store.notes[0])
        s.edit("verworfen")
        r.discard(s)
        r.release(s)
        XCTAssertEqual(u.text("X.md"), "a")
        // Wer die Notiz neu öffnet, bekommt eine frische Sitzung mit dem Text der Datei.
        let neu = r.acquire(store.notes[0])
        XCTAssertFalse(neu === s)
        XCTAssertEqual(neu.note.body, "a")
    }

    /// Eine fremde Sitzung mit derselben ID (veraltet) verwirft nicht die gültige.
    func testVeralteteSitzungVerwirftNichtDieGueltige() throws {
        try u.schreibe("X.md", "a")
        let store = u.store()
        let r = NoteSessionRegistry(store: store, saveDelay: 60)
        var gemeldet: [UUID] = []
        r.onDiscard { gemeldet.append($0) }
        let gueltig = r.acquire(store.notes[0])
        let fremd = NoteEditorSession(note: store.notes[0], store: store, saveDelay: 60)
        r.discard(fremd)
        r.release(fremd)
        XCTAssertTrue(r.session(id: gueltig.id) === gueltig)
        XCTAssertEqual(gemeldet, [])
    }

    /// Verwirft das Panel die Sitzung, die auch die Seite zeigt, wird die Seite frei.
    func testVerwerfenImPanelSchliesstDieSeite() throws {
        try u.schreibe("X.md", "a")
        let store = u.store()
        let r = NoteSessionRegistry(store: store, saveDelay: 60)
        let seite = NotesPageModel(store: store, registry: r, defaults: defaults)
        seite.select(store.notes[0].id)
        let panel = r.acquire(store.notes[0])
        r.discard(panel)
        XCTAssertNil(seite.session)
    }

    /// Verwirft die Seite, erfährt es das Panel, das dieselbe Notiz hält.
    func testVerwerfenAufDerSeiteMeldetDasPanel() throws {
        try u.schreibe("X.md", "a")
        let store = u.store()
        let r = NoteSessionRegistry(store: store, saveDelay: 60)
        let seite = NotesPageModel(store: store, registry: r, defaults: defaults)
        var gemeldet: [UUID] = []
        r.onDiscard { gemeldet.append($0) }
        seite.select(store.notes[0].id)
        _ = r.acquire(store.notes[0])
        seite.discardSession()
        XCTAssertEqual(gemeldet, [store.notes[0].id])
        XCTAssertNil(r.session(id: store.notes[0].id))
    }

    /// Hält das Panel ungesicherten Text, den es nicht sichern kann, löscht die
    /// Seite die Datei nicht — sonst stünde die neuere Fassung nur im Speicher.
    func testSeiteLoeschtNichtUnterUngesichertemPanelText() throws {
        try u.schreibe("X.md", "a")
        let store = u.store()
        let r = NoteSessionRegistry(store: store, saveDelay: 60)
        let seite = NotesPageModel(store: store, registry: r, defaults: defaults)
        let id = store.notes[0].id
        let panel = r.acquire(store.notes[0])
        panel.edit("im Panel")
        try machSichernUnmoeglich()
        seite.delete(id)
        XCTAssertNil(seite.lastDeleted)
        XCTAssertTrue(FileManager.default.fileExists(atPath: u.ordner.appendingPathComponent("X.md").path))
        XCTAssertTrue(r.session(id: id) === panel)
        XCTAssertEqual(panel.note.body, "im Panel")
    }

    /// Löscht die Seite eine Notiz, die nur das Panel offen hat, wird ihr
    /// getippter Text erst gesichert (also mit in den Papierkorb) und das Panel erfährt es.
    func testSeiteLoeschtPanelNotizSichertUndMeldet() throws {
        try u.schreibe("X.md", "a")
        let store = u.store()
        let r = NoteSessionRegistry(store: store, saveDelay: 60)
        let seite = NotesPageModel(store: store, registry: r, defaults: defaults)
        var gemeldet: [UUID] = []
        r.onDiscard { gemeldet.append($0) }
        let id = store.notes[0].id
        let panel = r.acquire(store.notes[0])
        panel.edit("im Panel")
        seite.delete(id)
        XCTAssertNotNil(seite.lastDeleted)
        XCTAssertEqual(gemeldet, [id])
        XCTAssertNil(r.session(id: id))
        seite.undoDelete()
        XCTAssertEqual(seite.session?.note.body, "im Panel")
    }
}
