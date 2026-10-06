import XCTest

@MainActor
final class NoteTransformRunnerTests: XCTestCase {

    private var u: NotizUmgebung!
    private var defaults: UserDefaults!
    private var suite: String!

    override func setUpWithError() throws {
        Loc.shared.apply("de")
        u = try NotizUmgebung()
        suite = "shout-runner-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        u.aufraeumen()
        Loc.shared.apply("system")
        super.tearDown()
    }

    private func sitzung(_ text: String) throws -> NoteEditorSession {
        try u.schreibe("X.md", text)
        let s = u.store()
        return NoteEditorSession(note: s.notes[0], store: s, saveDelay: 60)
    }

    private func runner(versionen: @escaping (NoteEditorSession) -> Void = { _ in },
                        kopiert: @escaping (String) -> Void = { _ in },
                        _ antwort: @escaping (String, String) async throws -> String) -> NoteTransformRunner {
        NoteTransformRunner(defaults: defaults, saveVersion: versionen, copy: kopiert, transform: antwort)
    }

    func testOhneAuswahlDerGanzeText() async throws {
        let s = try sitzung("roh")
        let r = runner { text, _ in "fertig(\(text))" }
        let task = try XCTUnwrap(r.run(instruction: "x", working: "läuft", done: "Fertig", on: s))
        XCTAssertTrue(s.isTransforming)
        XCTAssertEqual(s.toolNotice, .working("läuft"))
        await task.value
        XCTAssertFalse(s.isTransforming)
        XCTAssertEqual(s.note.body, "fertig(roh)")
        XCTAssertEqual(s.toolNotice, .done("Fertig", undo: NoteEditorSession.ToolUndo(before: "roh", after: "fertig(roh)")))
    }

    func testNurDieAuswahl() async throws {
        let s = try sitzung("eins zwei drei")
        s.selectionChanged(NSRange(location: 5, length: 4))
        let r = runner { text, _ in text.uppercased() }
        await r.run(instruction: "x", working: "…", done: "ok", on: s)?.value
        XCTAssertEqual(s.note.body, "eins ZWEI drei")
    }

    func testAnweisungKommtAn() async throws {
        let s = try sitzung("Text")
        var anweisung = ""
        let r = runner { _, a in anweisung = a; return "neu" }
        await r.run(instruction: "Kürzer!", working: "…", done: "ok", on: s)?.value
        XCTAssertEqual(anweisung, "Kürzer!")
    }

    func testVorherEinStand() async throws {
        let s = try sitzung("roh")
        s.edit("roh, ungesichert")
        var gesichert: [String] = []
        let r = runner(versionen: { gesichert.append($0.note.body) }) { _, _ in "neu" }
        await r.run(instruction: "x", working: "…", done: "ok", on: s)?.value
        XCTAssertEqual(gesichert, ["roh, ungesichert"])
        XCTAssertEqual(u.text("X.md"), "roh, ungesichert", "vor dem Transform gesichert")
    }

    func testZuLangOhneAufruf() throws {
        let s = try sitzung(String(repeating: "a", count: TransformPrompt.maxLength + 1))
        var aufgerufen = false
        let r = runner { _, _ in aufgerufen = true; return "x" }
        XCTAssertNil(r.run(instruction: "x", working: "…", done: "ok", on: s))
        XCTAssertFalse(aufgerufen)
        XCTAssertEqual(s.toolNotice, .failed(NoteTransformRunner.message(for: TransformError.tooLong)))
    }

    func testLeererTextNichts() throws {
        let s = try sitzung("   ")
        let r = runner { _, _ in "x" }
        XCTAssertNil(r.run(instruction: "x", working: "…", done: "ok", on: s))
        XCTAssertEqual(s.toolNotice, .failed(Loc.t("Kein Text zum Bearbeiten.")))
    }

    func testAbbrechenLaesstDenTextStehen() async throws {
        let s = try sitzung("alt")
        let r = runner { _, _ in
            try? await Task.sleep(for: .milliseconds(200))
            return "neu"
        }
        let task = try XCTUnwrap(r.run(instruction: "x", working: "…", done: "ok", on: s))
        XCTAssertTrue(s.cancelTransformIfRunning())
        await task.value
        XCTAssertEqual(s.note.body, "alt")
        XCTAssertFalse(s.isTransforming)
        XCTAssertNil(s.toolNotice)
    }

    func testFehlerMitGrundTextBleibt() async throws {
        let s = try sitzung("alt")
        let r = runner { _, _ in throw TransformError.timedOut }
        await r.run(instruction: "x", working: "…", done: "ok", on: s)?.value
        XCTAssertEqual(s.note.body, "alt")
        XCTAssertFalse(s.isTransforming)
        XCTAssertEqual(s.toolNotice, .failed(NoteTransformRunner.message(for: TransformError.timedOut)))
    }

    func testWaehrendDesTransformsKeinDiktat() async throws {
        let s = try sitzung("alt")
        let r = runner { _, _ in
            try? await Task.sleep(for: .milliseconds(100))
            return "neu"
        }
        let task = r.run(instruction: "x", working: "…", done: "ok", on: s)
        XCTAssertFalse(s.insert(" mehr", at: .end))
        await task?.value
        XCTAssertEqual(s.note.body, "neu")
    }

    func testGesprocheneAnweisungWirdGemerkt() async throws {
        let s = try sitzung("Text")
        let r = runner { _, _ in "neu" }
        await r.runInstruction("  mach es kürzer \n", on: s)?.value
        XCTAssertEqual(r.lastInstruction, "mach es kürzer")
        XCTAssertEqual(runner { _, _ in "" }.lastInstruction, "mach es kürzer")
    }

    func testKurzform() {
        XCTAssertEqual(NoteTransformRunner.short("kurz"), "kurz")
        XCTAssertEqual(NoteTransformRunner.short(String(repeating: "x", count: 60)).count, 40)
    }
}
