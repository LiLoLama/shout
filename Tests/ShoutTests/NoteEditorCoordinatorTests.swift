import XCTest
import AppKit

/// Der Coordinator mit einem echten NSTextView, ohne SwiftUI drumherum.
@MainActor
final class NoteEditorCoordinatorTests: XCTestCase {

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

    private func editor(_ session: NoteEditorSession) -> (NoteEditorView.Coordinator, NSTextView) {
        let c = NoteEditorView.Coordinator(session: session)
        let tv = NSTextView(frame: NSRect(x: 0, y: 0, width: 300, height: 200))
        tv.isRichText = false
        tv.allowsUndo = true
        tv.delegate = c
        tv.string = session.note.body
        c.textView = tv
        c.editRevision = session.editRevision
        session.attach(editor: c)
        return (c, tv)
    }

    private func sitzung(_ text: String) throws -> NoteEditorSession {
        try u.schreibe("X.md", text)
        let s = u.store()
        return NoteEditorSession(note: s.notes[0], store: s, saveDelay: 60)
    }

    func testDiktatAmCursorUndEinSchrittZurueck() throws {
        let s = try sitzung("Hallo Welt")
        let (c, tv) = editor(s)
        tv.setSelectedRange(NSRange(location: 5, length: 0))
        XCTAssertTrue(s.insert("schöne", at: .cursor))
        XCTAssertEqual(tv.string, "Hallo schöne Welt")
        XCTAssertEqual(s.note.body, "Hallo schöne Welt")
        XCTAssertEqual(tv.selectedRange(), NSRange(location: 12, length: 0))
        // Gruppen schließt der UndoManager am Ende eines Laufschleifen-Durchgangs.
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        c.undo.undo()
        XCTAssertEqual(tv.string, "Hallo Welt")
    }

    func testAnhaengenLaesstDenCursorStehen() throws {
        let s = try sitzung("a")
        let (_, tv) = editor(s)
        tv.setSelectedRange(NSRange(location: 0, length: 0))
        s.insert("\nb", at: .end)
        XCTAssertEqual(tv.string, "a\nb")
        XCTAssertEqual(tv.selectedRange(), NSRange(location: 0, length: 0))
    }

    func testGesperrterEditorNimmtNichtsAn() throws {
        let s = try sitzung("a")
        let (c, tv) = editor(s)
        tv.isEditable = false
        XCTAssertFalse(c.insertText("x", at: .end))
    }

    /// Zwei Editoren auf derselben Sitzung: Der zweite gleicht an, ohne dem
    /// ersten das Diktat-Ziel wegzunehmen.
    func testAngleichenStiehltNichtDasDiktatZiel() throws {
        let s = try sitzung("a")
        // Beide Coordinators festhalten: `NSTextView.delegate` ist schwach.
        let (zweiter, zweiterTV) = editor(s)
        let (erster, ersterTV) = editor(s)     // zuletzt angehängt
        ersterTV.setSelectedRange(NSRange(location: 1, length: 0))
        XCTAssertTrue(s.editor === erster)
        ersterTV.insertText("b", replacementRange: ersterTV.selectedRange())
        XCTAssertEqual(s.note.body, "ab")
        XCTAssertTrue(s.lastEditSource === erster)
        zweiter.mirror(s.note.body)
        XCTAssertEqual(zweiterTV.string, "ab")
        XCTAssertTrue(s.editor === erster)
    }

    /// Ist der Diktat-Editor noch nicht angeglichen (ein anderer hat geschrieben,
    /// SwiftUI hat noch nicht aktualisiert), lehnt er ab. Sonst meldete er seinen
    /// alten Text als neuen und die Eingabe des anderen ginge verloren.
    func testVeralteterEditorLehntAbUndNichtsGehtVerloren() throws {
        let s = try sitzung("a")
        let (zweiter, zweiterTV) = editor(s)
        let (erster, ersterTV) = editor(s)
        ersterTV.setSelectedRange(NSRange(location: 1, length: 0))
        ersterTV.insertText("b", replacementRange: ersterTV.selectedRange())
        XCTAssertEqual(s.note.body, "ab")
        zweiterTV.setSelectedRange(NSRange(location: 1, length: 0))
        XCTAssertTrue(s.editor === zweiter)
        let extern = s.externalRevision
        XCTAssertTrue(s.insert("c", at: .end))
        XCTAssertEqual(s.note.body, "abc")
        XCTAssertEqual(zweiterTV.string, "a", "abgelehnt heißt: nichts geändert")
        XCTAssertEqual(s.externalRevision, extern + 1, "der Editor lädt neu")
        withExtendedLifetime(erster) {}
    }

    func testJederEditorHatEigenesRueckgaengig() throws {
        let s = try sitzung("a")
        let (eins, tv1) = editor(s)
        let (zwei, _) = editor(s)
        XCTAssertFalse(eins.undo === zwei.undo)
        XCTAssertTrue(tv1.undoManager === eins.undo)
    }
}
