import XCTest

@MainActor
final class NoteEditorSessionTests: XCTestCase {

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

    func testEingabeSichertNachVerzoegerung() async throws {
        let s = u.store()
        let sitzung = NoteEditorSession(note: .blank(), store: s, saveDelay: 0.05)
        sitzung.edit("Erste Gedanken zum Projekt")
        XCTAssertEqual(sitzung.status, .dirty)
        XCTAssertEqual(u.dateien(), [])

        try await Task.sleep(for: .milliseconds(400))
        XCTAssertEqual(sitzung.status, .clean)
        XCTAssertEqual(sitzung.note.fileName, "Erste Gedanken zum Projekt.md")
        XCTAssertEqual(u.text("Erste Gedanken zum Projekt.md"), "Erste Gedanken zum Projekt")
    }

    func testFlushSichertSofort() {
        let s = u.store()
        let sitzung = NoteEditorSession(note: .blank(), store: s, saveDelay: 60)
        sitzung.edit("Sofort sichern bitte")
        sitzung.flush()
        XCTAssertEqual(sitzung.status, .clean)
        XCTAssertEqual(u.dateien(), ["Sofort sichern bitte.md"])
    }

    func testAenderungVonAussenWirdUebernommenWennSauber() throws {
        try u.schreibe("X.md", "alt", zeit: Date().addingTimeInterval(-60))
        let s = u.store()
        let sitzung = NoteEditorSession(note: s.notes[0], store: s)
        try u.schreibe("X.md", "neu", zeit: Date())
        s.reload()
        XCTAssertEqual(sitzung.note.body, "neu")
        XCTAssertEqual(sitzung.externalRevision, 1)
        XCTAssertEqual(sitzung.status, .clean)
    }

    /// Der Editor verliert beim Neuladen seine Auswahl, meldet es aber nicht: Eine
    /// veraltete, nicht leere Auswahl dürfte sonst beim Ablegen einen falschen
    /// Ausschnitt senden.
    func testNeuladenVonAussenKuerztDieAuswahl() throws {
        try u.schreibe("X.md", "ein langer alter Text", zeit: Date().addingTimeInterval(-60))
        let s = u.store()
        let sitzung = NoteEditorSession(note: s.notes[0], store: s)
        sitzung.selectionChanged(NSRange(location: 12, length: 5))
        try u.schreibe("X.md", "kurz", zeit: Date())
        s.reload()
        XCTAssertEqual(sitzung.note.body, "kurz")
        XCTAssertEqual(sitzung.lastSelection, NSRange(location: 4, length: 0))
        XCTAssertEqual(NoteHandoff.content(body: sitzung.note.body, selection: sitzung.lastSelection), "kurz")
    }

    /// Ungesicherter Text wird nicht überschrieben. Beim Sichern entsteht die
    /// Konfliktdatei, der Editor zeigt danach die Fassung von außen.
    func testUngesichertPlusAussenGibtKonflikt() throws {
        try u.schreibe("X.md", "alt", zeit: Date().addingTimeInterval(-60))
        let s = u.store()
        let sitzung = NoteEditorSession(note: s.notes[0], store: s, saveDelay: 60)
        sitzung.edit("meins")
        try u.schreibe("X.md", "neu", zeit: Date())
        s.reload()
        XCTAssertEqual(sitzung.note.body, "meins")

        sitzung.flush()
        XCTAssertEqual(sitzung.conflictNotice, "X (Konflikt).md")
        XCTAssertEqual(sitzung.note.body, "neu")
        XCTAssertEqual(sitzung.externalRevision, 1)
        XCTAssertEqual(u.text("X (Konflikt).md"), "meins")

        sitzung.dismissNotice()
        XCTAssertNil(sitzung.conflictNotice)
    }

    func testGeloeschteNotizWirdFehlendUndLaesstSichWiederSichern() throws {
        try u.schreibe("X.md", "Text")
        let s = u.store()
        let sitzung = NoteEditorSession(note: s.notes[0], store: s)
        try FileManager.default.removeItem(at: u.ordner.appendingPathComponent("X.md"))
        s.reload()
        XCTAssertEqual(sitzung.status, .missing)

        sitzung.edit("Text, weiter bearbeitet")
        XCTAssertEqual(sitzung.status, .missing)   // kein Sichern ins Leere
        sitzung.restoreMissing()
        XCTAssertEqual(sitzung.status, .clean)
        XCTAssertEqual(u.text("X.md"), "Text, weiter bearbeitet")
    }

    func testAnheftenNimmtUngesichertenTextMit() throws {
        try u.schreibe("X.md", "alt")
        let s = u.store()
        let sitzung = NoteEditorSession(note: s.notes[0], store: s, saveDelay: 60)
        sitzung.edit("neu getippt")
        sitzung.setPinned(true)
        let roh = try XCTUnwrap(u.lies("X.md"))
        XCTAssertTrue(NoteFile.parse(roh).pinned)
        XCTAssertEqual(NoteFile.parse(roh).body, "neu getippt")
    }

    func testUmbenennen() {
        let s = u.store()
        let sitzung = NoteEditorSession(note: .blank(), store: s, saveDelay: 60)
        sitzung.edit("eins zwei drei")
        XCTAssertTrue(sitzung.rename(to: "Neuer Name"))
        XCTAssertEqual(sitzung.note.fileName, "Neuer Name.md")
        XCTAssertEqual(u.dateien(), ["Neuer Name.md"])
    }

    func testPlatzhalterIstGesperrt() throws {
        try u.schreibe(".Fern.md.icloud", "")
        let s = u.store()
        let sitzung = NoteEditorSession(note: s.notes[0], store: s)
        XCTAssertEqual(sitzung.status, .placeholder)
        sitzung.edit("darf nicht")
        XCTAssertEqual(sitzung.note.body, "")
    }

    // MARK: - Sichern scheitert

    /// Nichts wurde geschrieben: Der Text bleibt ungesichert, die Sitzung meldet
    /// es, und das nächste Sichern versucht es erneut.
    func testScheiterndesSichernLaesstTextUngesichertUndWiederholt() throws {
        try u.schreibe("X.md", "alt", zeit: Date().addingTimeInterval(-60))
        let s = u.store()
        let sitzung = NoteEditorSession(note: s.notes[0], store: s, saveDelay: 60)
        sitzung.edit("meins")
        // Von außen geändert und nicht lesbar (Latin-1): der Store schreibt nichts.
        try Data([0x47, 0xFC, 0x6E]).write(to: u.ordner.appendingPathComponent("X.md"))

        sitzung.flush()
        XCTAssertEqual(sitzung.status, .dirty)
        XCTAssertTrue(sitzung.saveFailed)
        XCTAssertEqual(sitzung.note.body, "meins")
        XCTAssertEqual(try Data(contentsOf: u.ordner.appendingPathComponent("X.md")),
                       Data([0x47, 0xFC, 0x6E]), "die Fremddatei bleibt unangetastet")

        // Ursache beseitigt: gültiges UTF-8 mit demselben Text gilt als kein Konflikt.
        try u.schreibe("X.md", "meins", zeit: Date().addingTimeInterval(5))
        sitzung.flush()
        XCTAssertEqual(sitzung.status, .clean)
        XCTAssertFalse(sitzung.saveFailed)
        XCTAssertEqual(u.text("X.md"), "meins")
        XCTAssertNil(sitzung.conflictNotice)
    }

    /// Auch die nächste Eingabe stößt das Sichern wieder an.
    func testEingabeNachFehlschlagSichertErneut() async throws {
        try u.schreibe("X.md", "alt", zeit: Date().addingTimeInterval(-60))
        let s = u.store()
        let sitzung = NoteEditorSession(note: s.notes[0], store: s, saveDelay: 0.05)
        sitzung.edit("meins")
        try Data([0x47, 0xFC, 0x6E]).write(to: u.ordner.appendingPathComponent("X.md"))
        sitzung.flush()
        XCTAssertTrue(sitzung.saveFailed)

        try u.schreibe("X.md", "meins, mehr", zeit: Date().addingTimeInterval(5))
        sitzung.edit("meins, mehr")
        try await Task.sleep(for: .milliseconds(400))
        XCTAssertEqual(sitzung.status, .clean)
        XCTAssertFalse(sitzung.saveFailed)
    }

    // MARK: - Anheften

    /// Eine Änderung von außen am Frontmatter geht beim Anheften nicht verloren,
    /// auch wenn die Sitzung sie noch nicht gesehen hat.
    func testAnheftenNachStillerAenderungVonAussenBehaeltFremdesFrontmatter() throws {
        try u.schreibe("X.md", "alt", zeit: Date().addingTimeInterval(-60))
        let s = u.store()
        let sitzung = NoteEditorSession(note: s.notes[0], store: s, saveDelay: 60)
        try u.schreibe("X.md", "---\ntags: [a]\n---\nalt", zeit: Date())

        sitzung.setPinned(true)
        let geparst = NoteFile.parse(try XCTUnwrap(u.lies("X.md")))
        XCTAssertTrue(geparst.pinned)
        XCTAssertEqual(geparst.extraFrontmatter, ["tags: [a]"])
        XCTAssertEqual(geparst.body, "alt")
        XCTAssertEqual(sitzung.status, .clean)
        XCTAssertTrue(sitzung.note.pinned)
    }

    func testAnheftenNachFehlgeschlagenemSichernBehaeltText() throws {
        try u.schreibe("X.md", "alt", zeit: Date().addingTimeInterval(-60))
        let s = u.store()
        let sitzung = NoteEditorSession(note: s.notes[0], store: s, saveDelay: 60)
        sitzung.edit("meins")
        try Data([0x47, 0xFC, 0x6E]).write(to: u.ordner.appendingPathComponent("X.md"))

        sitzung.setPinned(true)
        XCTAssertEqual(sitzung.status, .dirty)
        XCTAssertTrue(sitzung.saveFailed)
        XCTAssertEqual(sitzung.note.body, "meins")
        XCTAssertTrue(sitzung.note.pinned, "die Absicht bleibt im Speicher")
    }

    func testAnheftenEinerNeuenNotizSchreibtErstBeimSichern() {
        let s = u.store()
        let sitzung = NoteEditorSession(note: .blank(), store: s, saveDelay: 60)
        sitzung.setPinned(true)
        XCTAssertEqual(u.dateien(), [])
        XCTAssertTrue(sitzung.note.pinned)

        sitzung.edit("Angeheftet von Anfang an")
        sitzung.flush()
        let roh = u.lies("Angeheftet von Anfang an.md")
        XCTAssertEqual(roh.map { NoteFile.parse($0).pinned }, true)
    }

    func testAnheftenEinerFehlendenNotizWirdMitWiederSichernGeschrieben() throws {
        try u.schreibe("X.md", "Text")
        let s = u.store()
        let sitzung = NoteEditorSession(note: s.notes[0], store: s)
        try FileManager.default.removeItem(at: u.ordner.appendingPathComponent("X.md"))
        s.reload()
        XCTAssertEqual(sitzung.status, .missing)

        sitzung.setPinned(true)
        XCTAssertEqual(sitzung.status, .missing)
        XCTAssertEqual(u.dateien(), [])
        sitzung.restoreMissing()
        XCTAssertEqual(sitzung.status, .clean)
        XCTAssertEqual(u.lies("X.md").map { NoteFile.parse($0).pinned }, true)
    }

    // MARK: - Umbenennen

    func testUmbenennenNachFehlgeschlagenemSichernBehaeltText() throws {
        try u.schreibe("X.md", "alt", zeit: Date().addingTimeInterval(-60))
        let s = u.store()
        let sitzung = NoteEditorSession(note: s.notes[0], store: s, saveDelay: 60)
        sitzung.edit("meins")
        try Data([0x47, 0xFC, 0x6E]).write(to: u.ordner.appendingPathComponent("X.md"))

        XCTAssertFalse(sitzung.rename(to: "Anders"))
        XCTAssertEqual(sitzung.status, .dirty)
        XCTAssertTrue(sitzung.saveFailed)
        XCTAssertEqual(sitzung.note.body, "meins", "der ungesicherte Text darf nicht durch die alte Fassung ersetzt werden")
        XCTAssertEqual(u.dateien(), ["X.md"])
    }

    // MARK: - Gepuffert

    /// Nach `.buffered` steht im Store noch der alte Text. Anheften darf darauf
    /// nicht aufsetzen: Der Puffer bekäme die alte Fassung, die Sitzung auch.
    func testAnheftenNachPufferNimmtNeuenTextMit() throws {
        try u.schreibe("X.md", "alt", zeit: Date().addingTimeInterval(-60))
        let s = u.store()
        let sitzung = NoteEditorSession(note: s.notes[0], store: s, saveDelay: 60)
        let weg = u.wurzel.appendingPathComponent("abgesteckt", isDirectory: true)
        try FileManager.default.moveItem(at: u.ordner, to: weg)

        sitzung.edit("neu unterwegs")
        sitzung.flush()
        XCTAssertEqual(sitzung.status, .clean)
        XCTAssertEqual(s.folderState, .unreachable)

        sitzung.setPinned(true)
        let roh = try String(contentsOf: u.puffer.appendingPathComponent("X.md"), encoding: .utf8)
        XCTAssertEqual(NoteFile.parse(roh).body, "neu unterwegs")
        XCTAssertTrue(NoteFile.parse(roh).pinned)
        XCTAssertEqual(sitzung.note.body, "neu unterwegs")
        XCTAssertTrue(sitzung.note.pinned)
    }

    func testUmbenennenNachPufferVerliertKeinenText() throws {
        try u.schreibe("X.md", "alt", zeit: Date().addingTimeInterval(-60))
        let s = u.store()
        let sitzung = NoteEditorSession(note: s.notes[0], store: s, saveDelay: 60)
        let weg = u.wurzel.appendingPathComponent("abgesteckt", isDirectory: true)
        try FileManager.default.moveItem(at: u.ordner, to: weg)
        sitzung.edit("neu unterwegs")
        sitzung.flush()

        sitzung.rename(to: "Anders")
        let roh = try String(contentsOf: u.puffer.appendingPathComponent("X.md"), encoding: .utf8)
        XCTAssertEqual(NoteFile.parse(roh).body, "neu unterwegs")
        XCTAssertEqual(sitzung.note.body, "neu unterwegs")
    }

    // MARK: - Fehlend: Text geht beim Schließen nicht verloren

    func testFlushLegtFehlendeNotizMitGetipptemTextNeuAn() throws {
        try u.schreibe("X.md", "Text")
        let s = u.store()
        let sitzung = NoteEditorSession(note: s.notes[0], store: s, saveDelay: 60)
        try FileManager.default.removeItem(at: u.ordner.appendingPathComponent("X.md"))
        s.reload()
        XCTAssertFalse(sitzung.hasUnsavedText)

        sitzung.edit("Text, weiter bearbeitet")
        XCTAssertTrue(sitzung.hasUnsavedText)
        sitzung.flush()
        XCTAssertEqual(sitzung.status, .clean)
        XCTAssertFalse(sitzung.hasUnsavedText)
        XCTAssertEqual(u.text("X.md"), "Text, weiter bearbeitet")
    }

    func testFlushOhneGetipptenTextLegtFehlendeNotizNichtNeuAn() throws {
        try u.schreibe("X.md", "Text")
        let s = u.store()
        let sitzung = NoteEditorSession(note: s.notes[0], store: s, saveDelay: 60)
        try FileManager.default.removeItem(at: u.ordner.appendingPathComponent("X.md"))
        s.reload()
        sitzung.flush()
        XCTAssertEqual(sitzung.status, .missing)
        XCTAssertEqual(u.dateien(), [])
    }

    func testAnheftenEinerFehlendenNotizZaehltAlsUngesichert() throws {
        try u.schreibe("X.md", "Text")
        let s = u.store()
        let sitzung = NoteEditorSession(note: s.notes[0], store: s, saveDelay: 60)
        try FileManager.default.removeItem(at: u.ordner.appendingPathComponent("X.md"))
        s.reload()

        sitzung.setPinned(true)
        XCTAssertTrue(sitzung.hasUnsavedText)
        sitzung.flush()
        XCTAssertEqual(u.lies("X.md").map { NoteFile.parse($0).pinned }, true)
    }

    // MARK: - Wiederholung

    func testNachFehlschlagVersuchtDieSitzungEsVonAlleinErneut() async throws {
        try u.schreibe("X.md", "alt", zeit: Date().addingTimeInterval(-60))
        let s = u.store()
        let sitzung = NoteEditorSession(note: s.notes[0], store: s, saveDelay: 60, retryDelay: 0.05)
        sitzung.edit("meins")
        try Data([0x47, 0xFC, 0x6E]).write(to: u.ordner.appendingPathComponent("X.md"))
        sitzung.flush()
        XCTAssertTrue(sitzung.saveFailed)

        try u.schreibe("X.md", "meins", zeit: Date().addingTimeInterval(5))
        try await Task.sleep(for: .milliseconds(400))
        XCTAssertEqual(sitzung.status, .clean)
        XCTAssertFalse(sitzung.saveFailed)
    }

    // MARK: - Fehlend, dann wieder da

    /// Kommt eine gelöschte Notiz aus dem Papierkorb zurück (mit derselben ID),
    /// während hier weitergeschrieben wurde, ersetzt die Fassung vom Ordner den
    /// Text nicht still: Beim Sichern entsteht eine Konfliktdatei.
    func testRueckgaengigBeiBearbeitetemTextOhneDateiGibtKonflikt() throws {
        try u.schreibe("X.md", "Text", zeit: Date().addingTimeInterval(-60))
        let s = u.store()
        let sitzung = NoteEditorSession(note: s.notes[0], store: s, saveDelay: 60)
        let geloescht = try XCTUnwrap(s.delete(sitzung.id))
        XCTAssertEqual(sitzung.status, .missing)
        sitzung.edit("Text, weiter bearbeitet")

        XCTAssertNotNil(s.undoDelete(geloescht))
        XCTAssertEqual(sitzung.note.body, "Text, weiter bearbeitet")
        XCTAssertEqual(sitzung.status, .dirty)

        sitzung.flush()
        XCTAssertEqual(sitzung.status, .clean)
        XCTAssertEqual(sitzung.conflictNotice, "X (Konflikt).md")
        XCTAssertEqual(u.text("X (Konflikt).md"), "Text, weiter bearbeitet")
        XCTAssertEqual(u.text("X.md"), "Text")
        XCTAssertEqual(sitzung.note.body, "Text")
    }

    /// Ohne eigene Änderung wird die zurückgeholte Datei einfach übernommen.
    func testRueckgaengigOhneEigeneAenderungWirdUebernommen() throws {
        try u.schreibe("X.md", "Text", zeit: Date().addingTimeInterval(-60))
        let s = u.store()
        let sitzung = NoteEditorSession(note: s.notes[0], store: s, saveDelay: 60)
        let geloescht = try XCTUnwrap(s.delete(sitzung.id))
        XCTAssertEqual(sitzung.status, .missing)

        XCTAssertNotNil(s.undoDelete(geloescht))
        XCTAssertEqual(sitzung.status, .clean)
        XCTAssertEqual(sitzung.note.body, "Text")
        XCTAssertNil(sitzung.conflictNotice)
    }

    // MARK: - Wiederherstellen nur auf ausdrücklichen flush

    /// Ein noch laufender Sicherungs-Zeitgeber darf eine von außen gelöschte
    /// Notiz nicht neu anlegen: Der Nutzer soll „fehlt“ sehen.
    func testZeitgeberLegtVonAussenGeloeschteNotizNichtNeuAn() async throws {
        try u.schreibe("X.md", "alt", zeit: Date().addingTimeInterval(-60))
        let s = u.store()
        let sitzung = NoteEditorSession(note: s.notes[0], store: s, saveDelay: 0.05)
        sitzung.edit("meins")
        try FileManager.default.removeItem(at: u.ordner.appendingPathComponent("X.md"))
        s.reload()
        XCTAssertEqual(sitzung.status, .missing)

        try await Task.sleep(for: .milliseconds(400))
        XCTAssertEqual(sitzung.status, .missing)
        XCTAssertEqual(u.dateien(), [])

        sitzung.flush()   // ausdrücklich (Schließen, Beenden): jetzt wird gerettet
        XCTAssertEqual(sitzung.status, .clean)
        XCTAssertEqual(u.text("X.md"), "meins")
    }

    func testAnheftenUndUmbenennenLegenFehlendeNotizNichtNeuAn() throws {
        try u.schreibe("X.md", "alt", zeit: Date().addingTimeInterval(-60))
        let s = u.store()
        let sitzung = NoteEditorSession(note: s.notes[0], store: s, saveDelay: 60)
        sitzung.edit("meins")
        try FileManager.default.removeItem(at: u.ordner.appendingPathComponent("X.md"))
        s.reload()
        XCTAssertEqual(sitzung.status, .missing)

        sitzung.setPinned(true)
        XCTAssertEqual(sitzung.status, .missing)
        XCTAssertEqual(u.dateien(), [])
        XCTAssertFalse(sitzung.rename(to: "Anders"))
        XCTAssertEqual(sitzung.status, .missing)
        XCTAssertEqual(u.dateien(), [])
        XCTAssertEqual(sitzung.note.body, "meins")
    }

    // MARK: - Wiederholung genau einmal

    func testWiederholungNachFehlschlagNurEinmal() async throws {
        try u.schreibe("X.md", "alt", zeit: Date().addingTimeInterval(-60))
        let s = u.store()
        let sitzung = NoteEditorSession(note: s.notes[0], store: s, saveDelay: 60, retryDelay: 0.1)
        sitzung.edit("meins")
        try Data([0x47, 0xFC, 0x6E]).write(to: u.ordner.appendingPathComponent("X.md"))
        sitzung.flush()
        XCTAssertTrue(sitzung.saveFailed)

        try await Task.sleep(for: .milliseconds(300))   // der eine Versuch ist gescheitert
        XCTAssertTrue(sitzung.saveFailed)
        try u.schreibe("X.md", "meins", zeit: Date().addingTimeInterval(5))
        try await Task.sleep(for: .milliseconds(500))
        XCTAssertEqual(sitzung.status, .dirty, "kein zweiter Versuch von allein")
        XCTAssertTrue(sitzung.saveFailed)
    }

    /// Scheitert „Wieder sichern“, wiederholt der Versuch genau das.
    func testWiederholungNachGescheitertemWiederSichernStelltWiederHer() async throws {
        try u.schreibe("X.md", "Text")
        let s = u.store()
        let sitzung = NoteEditorSession(note: s.notes[0], store: s, saveDelay: 60, retryDelay: 0.1)
        try FileManager.default.removeItem(at: u.ordner.appendingPathComponent("X.md"))
        s.reload()
        sitzung.edit("Text, weiter")
        // Ordner schreibgeschützt, Puffer unbrauchbar (eine Datei statt Ordner).
        try Data().write(to: u.puffer)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: u.ordner.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: u.ordner.path) }

        sitzung.flush()
        XCTAssertEqual(sitzung.status, .missing)
        XCTAssertTrue(sitzung.saveFailed)

        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: u.ordner.path)
        try await Task.sleep(for: .milliseconds(400))
        XCTAssertEqual(sitzung.status, .clean)
        XCTAssertEqual(u.text("X.md"), "Text, weiter")
    }

    // MARK: - Anheften geht beim Wiederauftauchen nicht verloren

    func testAnheftenBeiFehlenderDateiUeberlebtRueckgaengig() throws {
        try u.schreibe("X.md", "Text", zeit: Date().addingTimeInterval(-60))
        let s = u.store()
        let sitzung = NoteEditorSession(note: s.notes[0], store: s, saveDelay: 60)
        let geloescht = try XCTUnwrap(s.delete(sitzung.id))
        XCTAssertEqual(sitzung.status, .missing)
        sitzung.setPinned(true)

        XCTAssertNotNil(s.undoDelete(geloescht))
        XCTAssertTrue(sitzung.note.pinned)
        XCTAssertEqual(sitzung.status, .dirty)
        sitzung.flush()
        XCTAssertEqual(sitzung.status, .clean)
        XCTAssertEqual(u.lies("X.md").map { NoteFile.parse($0).pinned }, true)
        XCTAssertNil(sitzung.conflictNotice)
    }

    // MARK: - iCloud lagert aus, während Text ungesichert ist

    /// Die Datei wird ausgelagert, während getippter Text noch nicht gesichert
    /// ist. Der Platzhalter (leerer Text) darf ihn nicht ersetzen; beim Schließen
    /// landet er unter einem freien Namen neben der ausgelagerten Fassung.
    func testPlatzhalterLoeschtUngesichertenTextNicht() async throws {
        try u.schreibe("X.md", "Text", zeit: Date().addingTimeInterval(-60))
        let s = u.store()
        let sitzung = NoteEditorSession(note: s.notes[0], store: s, saveDelay: 0.05)
        sitzung.edit("Text, eins")
        sitzung.flush()
        XCTAssertEqual(sitzung.status, .clean)

        sitzung.edit("Text, zwei")
        try FileManager.default.removeItem(at: u.ordner.appendingPathComponent("X.md"))
        try u.schreibe(".X.md.icloud", "")
        s.reload()
        // Der Zeitgeber sichert ins Leere: Die Datei fehlt, der Text bleibt hier.
        try await Task.sleep(for: .milliseconds(400))
        XCTAssertEqual(sitzung.status, .missing)

        // Nächstes Einlesen (z. B. FSEvent), der Platzhalter steht in der Liste.
        try u.schreibe("Y.md", "andere Notiz")
        s.reload()
        XCTAssertEqual(sitzung.note.body, "Text, zwei")
        XCTAssertTrue(sitzung.hasUnsavedText)
        XCTAssertNotEqual(sitzung.status, .placeholder)

        sitzung.flush()
        XCTAssertFalse(sitzung.hasUnsavedText)
        XCTAssertEqual(u.text("X 2.md"), "Text, zwei")
    }

    // MARK: - Gepuffertes kommt als Konfliktdatei zurück

    /// Während der Ordner fehlte, wurde die Datei anderswo geändert. Die
    /// gepufferte Fassung wird Konfliktdatei — und die Sitzung sagt es, statt
    /// still die fremde Fassung zu zeigen.
    func testGepufferterTextAlsKonfliktdateiZurueckZeigtHinweis() async throws {
        try u.schreibe("X.md", "alt", zeit: Date().addingTimeInterval(-60))
        let s = u.store()
        let sitzung = NoteEditorSession(note: s.notes[0], store: s, saveDelay: 60)
        let weg = u.wurzel.appendingPathComponent("abgesteckt", isDirectory: true)
        try FileManager.default.moveItem(at: u.ordner, to: weg)
        sitzung.edit("meins unterwegs")
        sitzung.flush()
        XCTAssertEqual(s.folderState, .unreachable)

        let fremd = weg.appendingPathComponent("X.md")
        try Data("fremd".utf8).write(to: fremd)
        try FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: fremd.path)
        try FileManager.default.moveItem(at: weg, to: u.ordner)
        s.reload()

        XCTAssertEqual(u.dateien(), ["X (Konflikt).md", "X.md"])
        XCTAssertEqual(u.text("X (Konflikt).md"), "meins unterwegs")
        XCTAssertEqual(sitzung.conflictNotice, "X (Konflikt).md")
        XCTAssertEqual(sitzung.note.fileName, "X.md")
        XCTAssertEqual(sitzung.note.body, "fremd")
        XCTAssertNotEqual(s.notes.first { $0.fileName == "X (Konflikt).md" }?.id, sitzung.id)

        // Quittiert: Der Hinweis kommt nicht bei jedem Einlesen wieder.
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(s.returnedAsConflict, [:])
        sitzung.dismissNotice()
        s.reload()
        XCTAssertNil(sitzung.conflictNotice)
    }

    /// Eine neue, nur gepufferte Notiz, deren Name inzwischen einer anderen
    /// gehört: Die Sitzung folgt ihrem eigenen Text unter dem Konfliktnamen und
    /// liest beim nächsten Sichern nicht die fremde Datei unter ihrer ID.
    func testNeueGepufferteNotizFolgtIhrerKonfliktdatei() throws {
        let laufwerk = u.wurzel.appendingPathComponent("Laufwerk", isDirectory: true)
        let s = u.store(ordner: laufwerk)
        let sitzung = NoteEditorSession(note: .blank(), store: s, saveDelay: 60)
        sitzung.edit("Foo")
        sitzung.flush()
        XCTAssertEqual(sitzung.note.fileName, "Foo.md")

        try FileManager.default.createDirectory(at: laufwerk, withIntermediateDirectories: true)
        try Data("andere Notiz".utf8).write(to: laufwerk.appendingPathComponent("Foo.md"))
        s.reload()

        XCTAssertEqual(sitzung.note.fileName, "Foo (Konflikt).md")
        XCTAssertEqual(sitzung.note.body, "Foo")
        XCTAssertEqual(sitzung.status, .clean)
        XCTAssertNil(sitzung.conflictNotice)

        sitzung.edit("Foo und noch mehr")
        sitzung.flush()
        let dateien = try FileManager.default.contentsOfDirectory(atPath: laufwerk.path).sorted()
        XCTAssertEqual(dateien, ["Foo (Konflikt).md", "Foo.md"])
        let lies = { (name: String) in
            try NoteFile.parse(String(contentsOf: laufwerk.appendingPathComponent(name), encoding: .utf8)).body
        }
        XCTAssertEqual(try lies("Foo.md"), "andere Notiz")
        XCTAssertEqual(try lies("Foo (Konflikt).md"), "Foo und noch mehr")
        XCTAssertNotEqual(s.notes.first { $0.fileName == "Foo.md" }?.id, sitzung.id)
        XCTAssertNil(sitzung.conflictNotice)
    }
}
