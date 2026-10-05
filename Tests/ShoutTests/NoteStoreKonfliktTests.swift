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
    /// Frontmatter ist Sache der Datei, nicht des Editors: Ein veralteter
    /// `pinned`-Wert unserer Fassung darf die Platte nicht überstimmen — das
    /// Anheften läuft über `setPinned`, das bei neuem mtime vorher neu liest.
    func testGleicherInhaltIstKeinKonflikt() throws {
        try u.schreibe("X.md", "gleich", zeit: Date().addingTimeInterval(-60))
        let s = u.store()
        var n = s.notes[0]
        try u.schreibe("X.md", "gleich", zeit: Date())
        n.pinned = true
        guard case .saved(let gesichert) = s.save(n) else { return XCTFail("nicht gesichert") }
        XCTAssertEqual(u.dateien(), ["X.md"])
        XCTAssertFalse(gesichert.pinned, "der Wert von außen gilt, nicht der veraltete aus dem Editor")
        XCTAssertEqual(u.text("X.md"), "gleich")
    }

    /// Nur das Frontmatter wurde von außen geändert (Obsidian ergänzt Tags, ein
    /// anderer Mac heftet an): Der Text ist gleich, also kein Konflikt — aber das
    /// Frontmatter von der Platte darf beim Sichern nicht verloren gehen.
    func testFremdesFrontmatterBleibtErhalten() throws {
        try u.schreibe("X.md", "gleich", zeit: Date().addingTimeInterval(-60))
        let s = u.store()
        let n = s.notes[0]
        try u.schreibe("X.md", "---\ncreated: 2020-01-02T03:04:05Z\ntags: [neu]\npinned: true\n---\ngleich",
                       zeit: Date())

        guard case .saved(let gesichert) = s.save(n) else { return XCTFail("nicht gesichert") }
        let datei = try XCTUnwrap(u.lies("X.md"))
        XCTAssertTrue(datei.contains("tags: [neu]"), datei)
        XCTAssertTrue(datei.contains("pinned: true"), datei)
        XCTAssertTrue(gesichert.pinned)
        XCTAssertEqual(gesichert.extraFrontmatter, ["tags: [neu]"])
        XCTAssertEqual(gesichert.created, NoteFile.date(from: "2020-01-02T03:04:05Z"))
        XCTAssertEqual(u.dateien(), ["X.md"])
    }

    /// Von außen geändert, aber nicht lesbar (hier Latin-1 statt UTF-8): Nichts
    /// wird geschrieben — die Fremddatei bleibt Byte für Byte, unser Text bleibt
    /// beim Aufrufer ungesichert.
    func testUnlesbareFremdaenderungWirdNichtUeberschrieben() throws {
        try u.schreibe("X.md", "alt", zeit: Date().addingTimeInterval(-60))
        let s = u.store()
        var n = s.notes[0]
        let latin1 = Data([0x47, 0xFC, 0x6E])
        let url = u.ordner.appendingPathComponent("X.md")
        try latin1.write(to: url)
        try FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: url.path)
        n.body = "von innen"

        XCTAssertEqual(s.save(n), .failed)
        XCTAssertEqual(try Data(contentsOf: url), latin1)
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
        let ordnerPfad = u.ordner.path
        addTeardownBlock {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: ordnerPfad)
        }
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
