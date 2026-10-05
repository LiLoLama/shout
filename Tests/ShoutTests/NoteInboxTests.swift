import XCTest

/// Die Eingangs-Notiz: unten anhängen, eine Überschrift pro Tag.
final class NoteInboxTests: XCTestCase {

    private let de = Locale(identifier: "de_DE")
    private let en = Locale(identifier: "en_US")
    private let berlin = TimeZone(identifier: "Europe/Berlin")!

    /// UTC-Zeitpunkt; in Berlin (Sommerzeit) zwei Stunden später.
    private func utc(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }

    func testUeberschriftDeutsch() {
        XCTAssertEqual(NoteInbox.dayHeading(for: utc("2026-10-05T12:32:00Z"), locale: de, timeZone: berlin),
                       "## Montag, 5. Oktober 2026")
    }

    func testUeberschriftEnglisch() {
        XCTAssertEqual(NoteInbox.dayHeading(for: utc("2026-10-05T12:32:00Z"), locale: en, timeZone: berlin),
                       "## Monday, October 5, 2026")
    }

    func testLeererEingang() {
        let anhang = NoteInbox.appendix(to: "", text: "Milch kaufen", date: utc("2026-10-05T12:32:00Z"),
                                        locale: de, timeZone: berlin)
        XCTAssertEqual(anhang, "## Montag, 5. Oktober 2026\n- **14:32** Milch kaufen\n")
    }

    func testGleicherTagOhneNeueUeberschrift() {
        let body = "## Montag, 5. Oktober 2026\n- **14:32** Milch kaufen\n"
        let anhang = NoteInbox.appendix(to: body, text: "Brot", date: utc("2026-10-05T13:10:00Z"),
                                        locale: de, timeZone: berlin)
        XCTAssertEqual(anhang, "- **15:10** Brot\n")
    }

    func testNeuerTagMitLeerzeileDavor() {
        let body = "## Montag, 5. Oktober 2026\n- **14:32** Milch kaufen\n"
        let anhang = NoteInbox.appendix(to: body, text: "Termin", date: utc("2026-10-06T07:00:00Z"),
                                        locale: de, timeZone: berlin)
        XCTAssertEqual(anhang, "\n## Dienstag, 6. Oktober 2026\n- **09:00** Termin\n")
    }

    func testTextOhneZeilenendeAmSchluss() {
        let anhang = NoteInbox.appendix(to: "Notiz", text: "x", date: utc("2026-10-05T12:32:00Z"),
                                        locale: de, timeZone: berlin)
        XCTAssertEqual(anhang, "\n\n## Montag, 5. Oktober 2026\n- **14:32** x\n")
    }

    func testMehrzeiligEingerueckt() {
        let anhang = NoteInbox.appendix(to: "", text: "Erste Zeile\nzweite Zeile", date: utc("2026-10-05T12:32:00Z"),
                                        locale: de, timeZone: berlin)
        XCTAssertEqual(anhang, "## Montag, 5. Oktober 2026\n- **14:32** Erste Zeile\n  zweite Zeile\n")
    }

    func testLetzteUeberschrift() {
        XCTAssertEqual(NoteInbox.lastHeading(in: "# Titel\n## A\ntext\n## B\n"), "## B")
        XCTAssertNil(NoteInbox.lastHeading(in: "nur Text"))
    }
}
