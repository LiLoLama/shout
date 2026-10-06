import XCTest

@MainActor
final class NoteEditorSessionToolTests: XCTestCase {

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

    private func sitzung(_ text: String) throws -> NoteEditorSession {
        try u.schreibe("X.md", text)
        let s = u.store()
        return NoteEditorSession(note: s.notes[0], store: s, saveDelay: 60)
    }

    func testErsetzenOhneEditor() throws {
        let s = try sitzung("eins zwei drei")
        XCTAssertTrue(s.replace(NSRange(location: 5, length: 4), with: "ZWEI"))
        XCTAssertEqual(s.note.body, "eins ZWEI drei")
        XCTAssertEqual(s.lastSelection, NSRange(location: 5, length: 4))
    }

    func testErsetzenAusserhalbDesTextesScheitert() throws {
        let s = try sitzung("kurz")
        XCTAssertFalse(s.replace(NSRange(location: 3, length: 9), with: "x"))
        XCTAssertEqual(s.note.body, "kurz")
    }

    func testGesperrtNimmtKeinDiktatAn() throws {
        let s = try sitzung("Text")
        s.beginTransform("…") {}
        XCTAssertTrue(s.isTransforming)
        XCTAssertFalse(s.insert("mehr", at: .end))
        XCTAssertEqual(s.note.body, "Text")
    }

    func testAbbrechenRuftDenAbbruchUndEntsperrt() throws {
        let s = try sitzung("Text")
        var abgebrochen = false
        s.beginTransform("…") { abgebrochen = true }
        XCTAssertTrue(s.cancelTransformIfRunning())
        XCTAssertTrue(abgebrochen)
        XCTAssertFalse(s.isTransforming)
        XCTAssertNil(s.toolNotice)
        XCTAssertFalse(s.cancelTransformIfRunning())
    }

    func testRueckgaengigNurSolangeUnveraendert() throws {
        let s = try sitzung("vorher")
        s.replace(NSRange(location: 0, length: 6), with: "nachher")
        s.showToolNotice(.done("Fertig", undo: NoteEditorSession.ToolUndo(before: "vorher", after: "nachher")))
        XCTAssertTrue(s.canUndoTool)
        s.undoTool()
        XCTAssertEqual(s.note.body, "vorher")
        XCTAssertNil(s.toolNotice)

        s.replace(NSRange(location: 0, length: 6), with: "nachher")
        s.showToolNotice(.done("Fertig", undo: NoteEditorSession.ToolUndo(before: "vorher", after: "nachher")))
        s.edit("selbst geändert")
        XCTAssertFalse(s.canUndoTool)
        s.undoTool()
        XCTAssertEqual(s.note.body, "selbst geändert")
    }

    func testOrdnerDerSitzung() throws {
        let s = try sitzung("x")
        XCTAssertEqual(s.folderURL.standardizedFileURL, u.ordner.standardizedFileURL)
    }
}
