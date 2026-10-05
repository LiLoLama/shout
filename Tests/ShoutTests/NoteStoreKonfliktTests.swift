import XCTest

/// Zwei Seiten ändern dieselbe Notiz — hier im Editor, draußen in Obsidian oder
/// auf einem zweiten Mac über iCloud. Keine Fassung darf still gewinnen.
@MainActor
final class NoteStoreKonfliktTests: XCTestCase {

    private var u: NotizUmgebung!

    override func setUpWithError() throws {
        Loc.shared.apply("de")
        u = try NotizUmgebung()
    }

    override func tearDown() {
        // Ein Test kann den Ordner schreibgeschützt zurücklassen.
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: u.ordner.path)
        u.aufraeumen()
        Loc.shared.apply("system")
        super.tearDown()
    }

    func testGleichzeitigeAenderungGibtKonfliktdatei() throws {
        try u.schreibe("X.md", "alt", zeit: Date().addingTimeInterval(-60))
        let s = u.store()
        var n = s.notes[0]
        try u.schreibe("X.md", "von außen", zeit: Date())
        n.body = "von innen"

        guard case .conflict(let extern, let name) = s.save(n) else { return XCTFail("kein Konflikt") }
        XCTAssertEqual(extern.body, "von außen")
        XCTAssertEqual(extern.id, n.id)
        XCTAssertEqual(name, "X (Konflikt).md")
        XCTAssertEqual(u.text("X.md"), "von außen")
        XCTAssertEqual(u.text("X (Konflikt).md"), "von innen")
        XCTAssertEqual(Set(s.notes.map(\.title)), ["X", "X (Konflikt)"])
    }

    /// Anderes mtime, aber derselbe Text (z. B. nur „berührt“): kein Konflikt.
    func testGleicherInhaltIstKeinKonflikt() throws {
        try u.schreibe("X.md", "gleich", zeit: Date().addingTimeInterval(-60))
        let s = u.store()
        var n = s.notes[0]
        try u.schreibe("X.md", "gleich", zeit: Date())
        n.pinned = true
        guard case .saved = s.save(n) else { return XCTFail("nicht gesichert") }
        XCTAssertEqual(u.dateien(), ["X.md"])
    }

    /// Von außen gelöscht: Der Store legt die Datei nicht stillschweigend neu
    /// an — die Sitzung zeigt „Nicht mehr im Ordner“ und bietet „Wieder sichern“.
    func testVonAussenGeloeschtMeldetFehlend() throws {
        try u.schreibe("X.md", "a")
        let s = u.store()
        var n = s.notes[0]
        try FileManager.default.removeItem(at: u.ordner.appendingPathComponent("X.md"))
        n.body = "b"
        XCTAssertEqual(s.save(n), .missing)
        XCTAssertEqual(u.dateien(), [])
    }

    /// Die eigene Sicherung zählt nicht als Änderung von außen.
    func testZweimalSichernIstKeinKonflikt() throws {
        let s = u.store()
        var n = Note.blank()
        n.body = "Erster Stand hier"
        guard case .saved(var a) = s.save(n) else { return XCTFail() }
        a.body = "Zweiter Stand hier"
        guard case .saved = s.save(a) else { return XCTFail("eigene Sicherung als Konflikt erkannt") }
    }

    /// Die Konfliktdatei überschreibt nie etwas: Liegt „X (Konflikt).md“ schon
    /// da, bekommt die eigene Fassung einen freien Namen.
    func testKonfliktdateiUeberschreibtNichts() throws {
        try u.schreibe("X.md", "alt", zeit: Date().addingTimeInterval(-60))
        try u.schreibe("X (Konflikt).md", "frühere Konfliktfassung")
        let s = u.store()
        var n = try XCTUnwrap(s.notes.first { $0.fileName == "X.md" })
        try u.schreibe("X.md", "von außen", zeit: Date())
        n.body = "von innen"

        guard case .conflict(_, let name) = s.save(n) else { return XCTFail("kein Konflikt") }
        XCTAssertNotEqual(name, "X (Konflikt).md")
        XCTAssertEqual(u.text("X (Konflikt).md"), "frühere Konfliktfassung")
        XCTAssertEqual(u.text(name), "von innen")
        XCTAssertEqual(u.text("X.md"), "von außen")
    }

    /// Lässt sich die Konfliktdatei nicht schreiben, existiert unser Text sonst
    /// nirgends — das Ergebnis muss `.failed` sein, damit er ungesichert bleibt.
    func testKonfliktdateiNichtSchreibbarMeldetFehlgeschlagen() throws {
        try u.schreibe("X.md", "alt", zeit: Date().addingTimeInterval(-60))
        let s = u.store()
        var n = s.notes[0]
        try u.schreibe("X.md", "von außen", zeit: Date())
        n.body = "von innen"

        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: u.ordner.path)
        // Als root (oder bei Ausnahmen) hält der Schreibschutz nicht — dann überspringen.
        let probe = u.ordner.appendingPathComponent(".probe")
        if (try? Data("x".utf8).write(to: probe)) != nil {
            try? FileManager.default.removeItem(at: probe)
            throw XCTSkip("Ordner lässt sich trotz Schreibschutz beschreiben")
        }

        XCTAssertEqual(s.save(n), .failed)

        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: u.ordner.path)
        XCTAssertEqual(u.dateien(), ["X.md"])
        XCTAssertEqual(u.text("X.md"), "von außen")
    }
}
