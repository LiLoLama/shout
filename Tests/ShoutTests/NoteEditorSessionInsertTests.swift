import XCTest

@MainActor
final class NoteEditorSessionInsertTests: XCTestCase {

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

    /// Ein Editor-Ersatz, der festhält, was ihm zum Einfügen gegeben wurde. Wie ein
    /// echter Editor meldet er die Änderung danach über `edit(_:from:)` — außer er
    /// soll es vergessen (`meldet = false`).
    private final class FakeEditor: NoteTextEditing {
        weak var sitzung: NoteEditorSession?
        var aufrufe: [(String, NoteEditorSession.InsertionPoint)] = []
        var nimmtAn = true
        var meldet = true
        func insertText(_ text: String, at point: NoteEditorSession.InsertionPoint) -> Bool {
            aufrufe.append((text, point))
            guard nimmtAn else { return false }
            if meldet, let sitzung { sitzung.edit(sitzung.note.body + text, from: self) }
            return true
        }
    }

    private func sitzung(_ text: String) throws -> NoteEditorSession {
        try u.schreibe("X.md", text)
        let s = u.store()
        return NoteEditorSession(note: s.notes[0], store: s, saveDelay: 60)
    }

    func testOhneEditorAmCursorMitLeerzeichen() throws {
        let s = try sitzung("Hallo Welt")
        s.selectionChanged(NSRange(location: 5, length: 0))
        XCTAssertTrue(s.insert("schöne", at: .cursor))
        XCTAssertEqual(s.note.body, "Hallo schöne Welt")
        XCTAssertEqual(s.status, .dirty)
        XCTAssertEqual(s.lastSelection, NSRange(location: 12, length: 0))
        XCTAssertEqual(s.editRevision, 1)
        XCTAssertNil(s.lastEditSource)
    }

    func testOhneEditorAmEnde() throws {
        let s = try sitzung("a")
        s.selectionChanged(NSRange(location: 0, length: 0))
        s.insert("\n- b", at: .end)
        XCTAssertEqual(s.note.body, "a\n- b")
    }

    /// Ein gemeldeter Cursor hinter dem Textende (Text wurde inzwischen kürzer) wird geklemmt.
    func testCursorWirdGeklemmt() throws {
        let s = try sitzung("ab")
        s.selectionChanged(NSRange(location: 99, length: 0))
        s.insert("c", at: .cursor)
        XCTAssertEqual(s.note.body, "ab c")
    }

    func testMitEditorGehtEsAnDenEditor() throws {
        let s = try sitzung("Text")
        let editor = FakeEditor()
        editor.sitzung = s
        s.attach(editor: editor)
        XCTAssertTrue(s.insert("neu", at: .cursor))
        XCTAssertEqual(editor.aufrufe.count, 1)
        XCTAssertEqual(editor.aufrufe.first?.0, "neu")
        XCTAssertEqual(s.note.body, "Textneu")             // der Editor meldet die Änderung selbst über edit
        XCTAssertTrue(s.lastEditSource === editor)
        XCTAssertEqual(s.externalRevision, 0)              // er hat seinen Text schon, kein Neuladen
    }

    /// Sagt der Editor „angenommen“, meldet aber nichts, fügt die Sitzung selbst ein — nichts geht verloren.
    func testEditorMeldetNichtDannSelbst() throws {
        let s = try sitzung("Text")
        let editor = FakeEditor()
        editor.meldet = false
        s.attach(editor: editor)
        s.selectionChanged(NSRange(location: 4, length: 0))
        XCTAssertTrue(s.insert("neu", at: .cursor))
        XCTAssertEqual(s.note.body, "Text neu")
        XCTAssertEqual(s.externalRevision, 1)
    }

    /// Der Editor hat die Einfügung nicht gesehen: Er lädt neu, sonst überschriebe seine nächste Eingabe sie.
    func testSelbstEinfuegenMitEditorLaedtDenEditorNeu() throws {
        let s = try sitzung("Text")
        let editor = FakeEditor()
        editor.nimmtAn = false
        s.attach(editor: editor)
        s.insert("neu", at: .end)
        XCTAssertEqual(s.externalRevision, 1)
        XCTAssertEqual(s.note.body, "Textneu")
    }

    func testSelbstEinfuegenOhneEditorLaedtNichtNeu() throws {
        let s = try sitzung("Text")
        s.insert("neu", at: .end)
        XCTAssertEqual(s.externalRevision, 0)
    }

    /// Kann der Editor nicht annehmen, fügt die Sitzung selbst ein — nichts geht verloren.
    func testEditorNimmtNichtAnDannSelbst() throws {
        let s = try sitzung("Text")
        let editor = FakeEditor()
        editor.nimmtAn = false
        s.attach(editor: editor)
        s.selectionChanged(NSRange(location: 4, length: 0))
        s.insert("neu", at: .cursor)
        XCTAssertEqual(s.note.body, "Text neu")
    }

    func testAbgehaengterEditorBekommtNichts() throws {
        let s = try sitzung("Text")
        let editor = FakeEditor()
        s.attach(editor: editor)
        s.detach(editor: editor)
        s.insert("neu", at: .end)
        XCTAssertTrue(editor.aufrufe.isEmpty)
        XCTAssertEqual(s.note.body, "Textneu")
    }

    func testEingabeMerktSichDieQuelle() throws {
        let s = try sitzung("a")
        let quelle = FakeEditor()
        s.edit("ab", from: quelle)
        XCTAssertTrue(s.lastEditSource === quelle)
        XCTAssertEqual(s.editRevision, 1)
    }

    func testPlatzhalterNimmtNichts() throws {
        try u.schreibe(".Fern.md.icloud", "")
        let s = u.store()
        let sitzung = NoteEditorSession(note: s.notes[0], store: s)
        XCTAssertFalse(sitzung.insert("x", at: .end))
        XCTAssertEqual(sitzung.note.body, "")
    }

    /// Fehlt die Datei, wird eingefügt und als ungesichert festgehalten.
    /// (Nicht über `edit` + `flush`: Das legt die fehlende Datei gleich neu an.)
    func testBeiFehlenderDateiUngesichert() throws {
        try u.schreibe("X.md", "a")
        let store = u.store()
        let s = NoteEditorSession(note: store.notes[0], store: store, saveDelay: 60)
        try FileManager.default.removeItem(at: u.ordner.appendingPathComponent("X.md"))
        store.reload()
        XCTAssertEqual(s.status, .missing)
        XCTAssertFalse(s.hasUnsavedText)
        XCTAssertTrue(s.insert("c", at: .end))
        XCTAssertEqual(s.status, .missing)
        XCTAssertTrue(s.hasUnsavedText)
        XCTAssertEqual(s.note.body, "ac")
        XCTAssertEqual(u.dateien(), [])       // nichts ins Leere gesichert
        s.flush()                             // flush legt sie mit dem Text neu an
        XCTAssertEqual(u.text("X.md"), "ac")
    }

    func testLeererTextNimmtNichts() throws {
        let s = try sitzung("a")
        XCTAssertFalse(s.insert("", at: .cursor))
        XCTAssertFalse(s.insert("", at: .end))
        XCTAssertEqual(s.note.body, "a")
        XCTAssertEqual(s.editRevision, 0)
    }

    /// Ein veralteter Cursor mitten in einem Emoji reißt es nicht auseinander.
    func testCursorMitteImEmojiZerreisstEsNicht() throws {
        let s = try sitzung("a👍b")
        s.selectionChanged(NSRange(location: 2, length: 0))   // zwischen den UTF-16-Hälften
        XCTAssertTrue(s.insert("x", at: .cursor))
        XCTAssertEqual(s.note.body, "a x👍b")
    }

    /// `NSNotFound` (keine Auswahl bekannt) wird wie „hinter dem Ende“ behandelt.
    func testCursorNSNotFoundHaengtAn() throws {
        let s = try sitzung("ab")
        s.selectionChanged(NSRange(location: NSNotFound, length: 0))
        s.insert("c", at: .cursor)
        XCTAssertEqual(s.note.body, "ab c")
    }

    /// Eine Auswahl wird nicht überschrieben: Der Text kommt an ihren Anfang, nichts geht verloren.
    func testAuswahlWirdNichtErsetzt() throws {
        let s = try sitzung("Hallo Welt")
        s.selectionChanged(NSRange(location: 6, length: 4))
        s.insert("liebe", at: .cursor)
        XCTAssertEqual(s.note.body, "Hallo liebeWelt")
    }
}
