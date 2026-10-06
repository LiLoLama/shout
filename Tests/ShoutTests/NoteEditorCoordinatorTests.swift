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

    /// Tippt jemand in einen Editor, der noch nicht angeglichen ist, wird der
    /// Anschlag abgelehnt und der Editor gleicht an. Sonst meldete er seinen
    /// alten Text plus Anschlag, und die Eingabe des anderen Editors wäre weg.
    func testTippenInVeraltetenEditorUeberschreibtNichts() throws {
        let s = try sitzung("a")
        let (a, aTV) = editor(s)
        let (b, bTV) = editor(s)
        aTV.setSelectedRange(NSRange(location: 1, length: 0))
        aTV.insertText("b", replacementRange: aTV.selectedRange())
        XCTAssertEqual(s.note.body, "ab")
        // B tippt, ohne dazwischen angeglichen worden zu sein.
        bTV.setSelectedRange(NSRange(location: 1, length: 0))
        bTV.insertText("x", replacementRange: bTV.selectedRange())
        XCTAssertTrue(s.note.body.contains("b"), "die Eingabe von A muss bleiben")
        XCTAssertEqual(bTV.string, s.note.body)
        withExtendedLifetime((a, b)) {}
    }

    /// Ein Diktat schreibt eine offene Komposition (Option+U …) erst fest.
    func testDiktatSchreibtOffeneKompositionFest() throws {
        let s = try sitzung("a")
        let (c, tv) = editor(s)
        tv.setSelectedRange(NSRange(location: 1, length: 0))
        tv.setMarkedText("¨", selectedRange: NSRange(location: 1, length: 0),
                         replacementRange: NSRange(location: NSNotFound, length: 0))
        XCTAssertTrue(tv.hasMarkedText())
        // NSTextView meldet eine offene Komposition erst, wenn sie festgeschrieben ist.
        XCTAssertEqual(s.note.body, "a")
        XCTAssertTrue(s.insert("b", at: .end))
        XCTAssertFalse(tv.hasMarkedText())
        XCTAssertEqual(tv.string, s.note.body)
        XCTAssertTrue(s.note.body.hasSuffix("b"))
        withExtendedLifetime(c) {}
    }

    /// Angleichen schreibt eine offene Komposition erst fest und verliert dabei
    /// nichts aus der Sitzung.
    func testAngleichenSchreibtOffeneKompositionFest() throws {
        let s = try sitzung("a")
        let (a, aTV) = editor(s)
        let (b, bTV) = editor(s)
        bTV.setSelectedRange(NSRange(location: 1, length: 0))
        bTV.setMarkedText("¨", selectedRange: NSRange(location: 1, length: 0),
                          replacementRange: NSRange(location: NSNotFound, length: 0))
        XCTAssertTrue(bTV.hasMarkedText())
        a.mirror(s.note.body)
        XCTAssertEqual(aTV.string, s.note.body)
        aTV.setSelectedRange(NSRange(location: (aTV.string as NSString).length, length: 0))
        aTV.insertText("b", replacementRange: aTV.selectedRange())
        let erwartet = s.note.body
        XCTAssertTrue(erwartet.hasSuffix("b"))
        b.mirror(s.note.body)
        XCTAssertFalse(bTV.hasMarkedText())
        XCTAssertEqual(bTV.string, erwartet)
        XCTAssertEqual(s.note.body, erwartet)
    }

    /// Option+U, dann u: Die offene Komposition zählt nicht als veralteter Text.
    /// Sonst lehnte der Editor jeden Umlaut ab.
    func testKompositionGiltNichtAlsVeraltet() throws {
        let s = try sitzung("a")
        let (c, tv) = editor(s)
        tv.setSelectedRange(NSRange(location: 1, length: 0))
        tv.setMarkedText("¨", selectedRange: NSRange(location: 1, length: 0),
                         replacementRange: NSRange(location: NSNotFound, length: 0))
        tv.insertText("ü", replacementRange: NSRange(location: NSNotFound, length: 0))
        XCTAssertEqual(tv.string, "aü")
        XCTAssertEqual(s.note.body, "aü")
        withExtendedLifetime(c) {}
    }

    /// Meldet eine Eingabemethode ihre Komposition doch an die Sitzung, gilt der
    /// Editor trotzdem als aktuell — sonst lehnte er jeden Anschlag ab.
    func testGemeldeteKompositionGiltAlsAktuell() throws {
        let s = try sitzung("a")
        let (c, tv) = editor(s)
        tv.setSelectedRange(NSRange(location: 1, length: 0))
        tv.setMarkedText("¨", selectedRange: NSRange(location: 1, length: 0),
                         replacementRange: NSRange(location: NSNotFound, length: 0))
        // Wie eine Eingabemethode, die markierten Text meldet.
        s.edit(tv.string, from: c)
        XCTAssertEqual(s.note.body, "a¨")
        tv.insertText("ü", replacementRange: NSRange(location: NSNotFound, length: 0))
        XCTAssertEqual(tv.string, "aü")
        XCTAssertEqual(s.note.body, "aü")
    }

    /// Festschreiben einer Komposition in einem veralteten Editor: Der Anschlag
    /// gleicht mitten im Einfügen an (wiedereintretend) und lehnt ab.
    func testFestschreibenImVeraltetenEditor() throws {
        let s = try sitzung("a")
        let (a, aTV) = editor(s)
        let (b, bTV) = editor(s)
        bTV.setSelectedRange(NSRange(location: 1, length: 0))
        bTV.setMarkedText("¨", selectedRange: NSRange(location: 1, length: 0),
                          replacementRange: NSRange(location: NSNotFound, length: 0))
        aTV.setSelectedRange(NSRange(location: 1, length: 0))
        aTV.insertText("b", replacementRange: aTV.selectedRange())
        XCTAssertEqual(s.note.body, "ab")
        bTV.insertText("ü", replacementRange: NSRange(location: NSNotFound, length: 0))
        XCTAssertTrue(s.note.body.contains("b"), "die Eingabe von A muss bleiben")
        XCTAssertEqual(bTV.string, s.note.body)
        withExtendedLifetime((a, b)) {}
    }

    func testJederEditorHatEigenesRueckgaengig() throws {
        let s = try sitzung("a")
        let (eins, tv1) = editor(s)
        let (zwei, _) = editor(s)
        XCTAssertFalse(eins.undo === zwei.undo)
        XCTAssertTrue(tv1.undoManager === eins.undo)
    }

    func testErsetzenUeberDenEditorIstEinRueckgaengigSchritt() throws {
        let s = try sitzung("eins zwei drei")
        let (c, tv) = editor(s)
        XCTAssertTrue(s.replace(NSRange(location: 5, length: 4), with: "ZWEI"))
        XCTAssertEqual(tv.string, "eins ZWEI drei")
        XCTAssertEqual(s.note.body, "eins ZWEI drei")
        c.undo.undo()
        XCTAssertEqual(tv.string, "eins zwei drei")
    }

    func testErsetzenGehtAuchImGesperrtenEditorUndLaesstIhnGesperrt() throws {
        let s = try sitzung("alt")
        let (_, tv) = editor(s)
        s.beginTransform("…") {}
        tv.isEditable = false
        XCTAssertTrue(s.replace(NSRange(location: 0, length: 3), with: "neu"))
        XCTAssertEqual(tv.string, "neu")
        XCTAssertFalse(tv.isEditable)
    }
}
