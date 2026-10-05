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
}
