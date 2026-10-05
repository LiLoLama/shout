import XCTest

/// Das Dateiformat einer Notiz: Frontmatter oben, Markdown darunter.
/// Obsidian liest dieselben Dateien — fremde Felder dürfen nie verloren gehen.
final class NoteFileTests: XCTestCase {

    private let berlin = TimeZone(identifier: "Europe/Berlin")!
    private let utc = TimeZone(identifier: "UTC")!

    private func datum(_ text: String) -> Date { NoteFile.date(from: text)! }

    func testOhneFrontmatterIstAllesText() {
        let gelesen = NoteFile.parse("Einfach nur Text\nZweite Zeile")
        XCTAssertEqual(gelesen, .init(body: "Einfach nur Text\nZweite Zeile",
                                      created: nil, pinned: false, extraFrontmatter: []))
    }

    func testFrontmatterWirdGelesen() {
        let gelesen = NoteFile.parse("---\ncreated: 2026-10-05T14:32:00+02:00\npinned: true\n---\nText")
        XCTAssertEqual(gelesen.body, "Text")
        XCTAssertEqual(gelesen.created, datum("2026-10-05T12:32:00Z"))
        XCTAssertTrue(gelesen.pinned)
        XCTAssertEqual(gelesen.extraFrontmatter, [])
    }

    /// Kernregel für Obsidian: `tags`, `aliases` & Co. bleiben wörtlich und in
    /// ihrer Reihenfolge stehen — auch mehrzeilige Listen.
    func testUnbekannteFelderBleibenErhalten() {
        let roh = "---\ntags:\n  - idee\n  - shout\ncreated: 2026-10-05T14:32:00+02:00\naliases: [NL]\n---\nText"
        let gelesen = NoteFile.parse(roh)
        XCTAssertEqual(gelesen.extraFrontmatter, ["tags:", "  - idee", "  - shout", "aliases: [NL]"])

        let neu = NoteFile.serialize(body: gelesen.body, created: gelesen.created!, pinned: false,
                                     extraFrontmatter: gelesen.extraFrontmatter, timeZone: berlin)
        XCTAssertEqual(neu, "---\ncreated: 2026-10-05T14:32:00+02:00\ntags:\n  - idee\n  - shout\naliases: [NL]\n---\nText")
    }

    func testRundlauf() {
        let erstellt = datum("2026-10-05T14:32:00+02:00")
        let text = NoteFile.serialize(body: "# Titel\n\nText\n", created: erstellt, pinned: true,
                                      extraFrontmatter: ["tags: [a]"], timeZone: berlin)
        XCTAssertEqual(NoteFile.parse(text),
                       .init(body: "# Titel\n\nText\n", created: erstellt,
                             createdRaw: "2026-10-05T14:32:00+02:00", pinned: true,
                             extraFrontmatter: ["tags: [a]"]))
    }

    /// Unter Windows bearbeitete Dateien kommen mit CRLF. Gelesen wird beides,
    /// geschrieben wird LF.
    func testCRLFWirdGelesen() {
        let gelesen = NoteFile.parse("---\r\npinned: true\r\n---\r\nA\r\nB")
        XCTAssertTrue(gelesen.pinned)
        XCTAssertEqual(gelesen.body, "A\nB")
    }

    func testPinnedFalseUndFehlend() {
        XCTAssertFalse(NoteFile.parse("---\npinned: false\n---\nx").pinned)
        XCTAssertFalse(NoteFile.parse("---\ncreated: 2026-10-05\n---\nx").pinned)
    }

    /// Obsidian schreibt Datumsfelder oft ohne Uhrzeit.
    func testNurDatumWieInObsidian() {
        XCTAssertNotNil(NoteFile.parse("---\ncreated: 2026-10-05\n---\nx").created)
    }

    /// Obsidian und andere Programme schreiben Uhrzeiten auch ohne Sekunden
    /// oder mit Leerzeichen statt „T“. Die Uhrzeit gilt in der lokalen Zeitzone.
    func testUhrzeitOhneSekundenUndMitLeerzeichen() throws {
        for wert in ["2026-10-05T14:32", "2026-10-05 14:32", "2026-10-05 14:32:07"] {
            let d = try XCTUnwrap(NoteFile.date(from: wert), wert)
            let k = Calendar.current.dateComponents(in: .current, from: d)
            XCTAssertEqual([k.year, k.month, k.day, k.hour, k.minute], [2026, 10, 5, 14, 32], wert)
        }
    }

    /// Jede gelesene Schreibweise kommt beim Schreiben wörtlich zurück.
    func testRundlaufBehaeltCreatedWoertlich() throws {
        let werte = ["2026-10-05", "2026-10-05T14:32", "2026-10-05 14:32", "2026-10-05 14:32:07",
                     "2026-10-05T14:32:07", "2026-10-05T14:32:07+02:00", "2026-10-05T12:32:07.250Z",
                     "\"2026-10-05\"", "'2026-10-05 14:32'"]
        for wert in werte {
            let roh = "---\ncreated: \(wert)\ntags: [a]\n---\nText"
            let gelesen = NoteFile.parse(roh)
            XCTAssertEqual(gelesen.createdRaw, wert)
            let geschrieben = NoteFile.serialize(body: gelesen.body, created: try XCTUnwrap(gelesen.created, wert),
                                                 createdRaw: gelesen.createdRaw, pinned: gelesen.pinned,
                                                 extraFrontmatter: gelesen.extraFrontmatter, timeZone: utc)
            XCTAssertEqual(geschrieben, roh)
        }
    }

    /// Ein reines Datum bleibt ein reines Datum — keine Uhrzeit dazuerfunden.
    func testNurDatumWirdAlsNurDatumGeschrieben() {
        let gelesen = NoteFile.parse("---\ncreated: 2026-10-05\n---\nx")
        let text = NoteFile.serialize(body: gelesen.body, created: gelesen.created!,
                                      createdRaw: gelesen.createdRaw, pinned: false, extraFrontmatter: [])
        XCTAssertEqual(text, "---\ncreated: 2026-10-05\n---\nx")
    }

    /// Ohne Wert aus der Datei (neue Notiz, unlesbares Feld) schreibt shout ISO 8601.
    func testOhneRohwertSchreibtISO() {
        XCTAssertNil(NoteFile.parse("---\ncreated: gestern\n---\nx").createdRaw)
        let text = NoteFile.serialize(body: "x", created: datum("2026-10-05T12:00:00Z"), createdRaw: nil,
                                      pinned: false, extraFrontmatter: [], timeZone: utc)
        XCTAssertEqual(text, "---\ncreated: 2026-10-05T12:00:00Z\n---\nx")
    }

    /// Ein Datum mit Anhang ist kein Datum — nicht still auf Mitternacht kürzen.
    func testDatumMitAnhangIstUnlesbar() {
        XCTAssertNil(NoteFile.date(from: "2026-10-05 gestern"))
    }

    /// Ein unlesbares Datum fällt weg und wird beim nächsten Speichern neu
    /// geschrieben — sonst stünde `created` danach doppelt in der Datei.
    func testKaputtesDatumFaelltWeg() {
        let gelesen = NoteFile.parse("---\ncreated: gestern\n---\nx")
        XCTAssertNil(gelesen.created)
        XCTAssertEqual(gelesen.extraFrontmatter, [])
    }

    /// Eine Trennlinie ohne Gegenstück ist kein Frontmatter, sondern Text.
    func testOhneSchlusslinieKeinFrontmatter() {
        let roh = "---\nNur eine Trennlinie am Anfang"
        XCTAssertEqual(NoteFile.parse(roh).body, roh)
    }

    func testNichtAngeheftetSchreibtKeinPinned() {
        let text = NoteFile.serialize(body: "x", created: datum("2026-10-05T12:00:00Z"),
                                      pinned: false, extraFrontmatter: [], timeZone: utc)
        XCTAssertEqual(text, "---\ncreated: 2026-10-05T12:00:00Z\n---\nx")
    }

    func testNeueNotizIstLeerUndNeu() {
        let notiz = Note.blank()
        XCTAssertTrue(notiz.isNew)
        XCTAssertEqual(notiz.title, "")
        var benannt = notiz
        benannt.fileName = "Idee 2.md"
        XCTAssertEqual(benannt.title, "Idee 2")
        XCTAssertFalse(benannt.isNew)
    }
}
