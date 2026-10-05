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
                       .init(body: "# Titel\n\nText\n", created: erstellt, pinned: true,
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
