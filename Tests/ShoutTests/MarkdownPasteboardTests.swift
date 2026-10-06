import XCTest
import AppKit

final class MarkdownPasteboardTests: XCTestCase {

    private func text(_ md: String) -> String { MarkdownPasteboard.attributed(from: md).string }

    private func schrift(_ md: String, bei index: Int) -> NSFont? {
        MarkdownPasteboard.attributed(from: md).attribute(.font, at: index, effectiveRange: nil) as? NSFont
    }

    private func istFett(_ schrift: NSFont?) -> Bool {
        guard let schrift else { return false }
        return NSFontManager.shared.traits(of: schrift).contains(.boldFontMask)
    }

    func testUeberschriftIstFettUndGroesser() {
        XCTAssertEqual(text("# Titel"), "Titel")
        let f = schrift("# Titel", bei: 0)
        XCTAssertTrue(istFett(f))
        XCTAssertGreaterThan(f?.pointSize ?? 0, MarkdownPasteboard.bodySize)
    }

    func testFettImSatz() {
        let md = "ein **wichtiges** Wort"
        XCTAssertEqual(text(md), "ein wichtiges Wort")
        XCTAssertTrue(istFett(schrift(md, bei: 4)))
        XCTAssertFalse(istFett(schrift(md, bei: 0)))
    }

    func testListeBekommtPunkt() {
        XCTAssertEqual(text("- eins\n- zwei"), "•\teins\n•\tzwei")
    }

    func testCheckboxen() {
        XCTAssertEqual(text("- [ ] offen\n- [x] erledigt"), "☐\toffen\n☑\terledigt")
    }

    func testNummerierteListe() {
        XCTAssertEqual(text("1. a\n2. b"), "1.\ta\n2.\tb")
    }

    func testBildLinkBleibtText() {
        XCTAssertEqual(text("![](Anhänge/a.png)"), "![](Anhänge/a.png)")
    }

    func testCodeblockOhneZaeuneInMonospace() {
        let md = "```\nlet x = 1\n```"
        XCTAssertEqual(text(md), "let x = 1\n")
        XCTAssertTrue(schrift(md, bei: 0)?.isFixedPitch ?? false)
    }

    func testAbsaetzeBleiben() {
        XCTAssertEqual(text("eins\n\nzwei"), "eins\n\nzwei")
    }

    func testRTFEnthaeltDenText() throws {
        let data = try XCTUnwrap(MarkdownPasteboard.rtf(from: "# Hallo\n- Punkt"))
        let zurueck = try NSAttributedString(data: data,
                                             options: [.documentType: NSAttributedString.DocumentType.rtf],
                                             documentAttributes: nil)
        XCTAssertTrue(zurueck.string.contains("Hallo"))
        XCTAssertTrue(zurueck.string.contains("•"))
    }

    func testZwischenablageHatKlartextUnveraendertUndRTF() {
        let pb = NSPasteboard(name: NSPasteboard.Name("shout-test-\(UUID().uuidString)"))
        defer { pb.releaseGlobally() }
        let marke = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")
        let md = "# Titel\n- [ ] **fett**"
        MarkdownPasteboard.write(md, to: pb, extraTypes: [marke])
        XCTAssertEqual(pb.string(forType: .string), md)
        XCTAssertNotNil(pb.data(forType: .rtf))
        XCTAssertEqual(pb.data(forType: marke), Data("1".utf8))
    }

    func testZaunInDersebenZeileBleibtTextKeinMonospace() {
        // Inline-Backticks sollten nicht als Zaun gelten
        let md = "```inline``` danach\nnormal"
        XCTAssertEqual(text(md), "```inline``` danach\nnormal")
        XCTAssertFalse(schrift(md, bei: 0)?.isFixedPitch ?? false)
    }

    func testRTFNurAngekuendigt() {
        // Wenn RTF nicht gesetzt wird, sollte es auch nicht in der Typenliste deklariert sein
        let pb = NSPasteboard(name: NSPasteboard.Name("shout-test-\(UUID().uuidString)"))
        defer { pb.releaseGlobally() }
        let md = "Test"
        MarkdownPasteboard.write(md, to: pb, extraTypes: [])
        XCTAssertEqual(pb.string(forType: .string), md)
        // Wenn RTF generiert wurde, ist es da; wenn nicht (Fehler), ist es nicht deklariert
        let typen = pb.types ?? []
        if pb.data(forType: .rtf) == nil {
            XCTAssertFalse(typen.contains(.rtf))
        } else {
            XCTAssertTrue(typen.contains(.rtf))
        }
    }
}
