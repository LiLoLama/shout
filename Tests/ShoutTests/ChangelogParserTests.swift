import XCTest

final class ChangelogParserTests: XCTestCase {

    private let beispiel = """
    # shout. — Neuigkeiten

    Vorspann, wird ignoriert.

    ## 1.13.0 — 2026-10-07
    zeigen: ja
    video: scratchpad

    ### Deutsch
    **Neu: das Scratchpad.**
    - ⌃⌥N blendet ein.

    ### English
    **New: the Scratchpad.**
    - ⌃⌥N shows it.

    ## 1.12.0 - 2026-09-21
    zeigen: nein

    ### Deutsch
    Meeting-Erkennung.

    ### English
    Meeting detection.
    """

    func testZweiEintraegeNeuesteZuerst() throws {
        let e = ChangelogParser.parse(beispiel)
        XCTAssertEqual(e.map(\.version.description), ["1.13.0", "1.12.0"])
        let neu = try XCTUnwrap(e.first)
        XCTAssertTrue(neu.highlight)
        XCTAssertEqual(neu.video, "scratchpad")
        XCTAssertEqual(neu.date, "2026-10-07")
        XCTAssertEqual(neu.german, "**Neu: das Scratchpad.**\n- ⌃⌥N blendet ein.")
        XCTAssertEqual(neu.english, "**New: the Scratchpad.**\n- ⌃⌥N shows it.")
        XCTAssertFalse(e[1].highlight)
        XCTAssertNil(e[1].video)
        XCTAssertEqual(neu.text(german: false), neu.english)
    }

    func testFehlendesZeigenUeberspringtNurDiesenAbschnitt() {
        let text = beispiel.replacingOccurrences(of: "zeigen: nein\n", with: "")
        XCTAssertEqual(ChangelogParser.parse(text).map(\.version.description), ["1.13.0"])
    }

    func testFehlenderSprachblockUeberspringt() {
        let text = beispiel.replacingOccurrences(of: "### English\nMeeting detection.", with: "")
        XCTAssertEqual(ChangelogParser.parse(text).map(\.version.description), ["1.13.0"])
    }

    func testLeererSprachblockUeberspringt() {
        let text = beispiel.replacingOccurrences(of: "Meeting detection.", with: "   ")
        XCTAssertEqual(ChangelogParser.parse(text).count, 1)
    }

    func testKaputteKopfzeileUeberspringt() {
        let text = beispiel.replacingOccurrences(of: "## 1.12.0 - 2026-09-21", with: "## eins — gestern")
        XCTAssertEqual(ChangelogParser.parse(text).count, 1)
    }

    func testUnbekannterZeigenWertUeberspringt() {
        let text = beispiel.replacingOccurrences(of: "zeigen: nein", with: "zeigen: vielleicht")
        XCTAssertEqual(ChangelogParser.parse(text).count, 1)
    }

    func testVideonameNurBuchstabenZiffernBindestrich() {
        let text = beispiel.replacingOccurrences(of: "video: scratchpad", with: "video: ../geheim")
        XCTAssertEqual(ChangelogParser.parse(text).count, 1, "ungültiger Videoname → Abschnitt übersprungen")
    }

    func testDoppelteVersionDerErsteGewinnt() {
        let text = beispiel + "\n\n## 1.13.0 — 2026-10-08\nzeigen: nein\n\n### Deutsch\nx\n\n### English\ny\n"
        let e = ChangelogParser.parse(text)
        XCTAssertEqual(e.count, 2)
        XCTAssertTrue(e[0].highlight)
    }

    func testCRLF() {
        XCTAssertEqual(ChangelogParser.parse(beispiel.replacingOccurrences(of: "\n", with: "\r\n")).count, 2)
    }

    func testVersionen() throws {
        XCTAssertEqual(AppVersion("1.13"), AppVersion("1.13.0"))
        XCTAssertGreaterThan(try XCTUnwrap(AppVersion("1.13.10")), try XCTUnwrap(AppVersion("1.13.9")))
        XCTAssertLessThan(try XCTUnwrap(AppVersion("1.9")), try XCTUnwrap(AppVersion("1.12.0")))
        XCTAssertNil(AppVersion(""))
        XCTAssertNil(AppVersion("1.x"))
        XCTAssertNil(AppVersion("1..2"))
        XCTAssertEqual(Set([AppVersion("2")!, AppVersion("2.0.0")!]).count, 1)
        XCTAssertEqual(AppVersion("1.13.0")?.description, "1.13.0")
    }
}
