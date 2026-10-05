import XCTest
import AppKit

/// Die Darstellung ändert nie den Text — die Datei bleibt Klartext.
final class MarkdownHighlighterTests: XCTestCase {

    private typealias Style = MarkdownHighlighter.Style

    private func gestaltet(_ text: String) -> NSTextStorage {
        let speicher = NSTextStorage(string: text)
        MarkdownHighlighter.apply(to: speicher)
        return speicher
    }

    private func schrift(_ s: NSTextStorage, _ i: Int) -> NSFont {
        s.attribute(.font, at: i, effectiveRange: nil) as! NSFont
    }

    private func farbe(_ s: NSTextStorage, _ i: Int) -> NSColor? {
        s.attribute(.foregroundColor, at: i, effectiveRange: nil) as? NSColor
    }

    private func fett(_ f: NSFont) -> Bool { NSFontManager.shared.traits(of: f).contains(.boldFontMask) }
    private func kursiv(_ f: NSFont) -> Bool { NSFontManager.shared.traits(of: f).contains(.italicFontMask) }
    private func mono(_ f: NSFont) -> Bool { f.fontDescriptor.symbolicTraits.contains(.monoSpace) }

    func testTextBleibtUnveraendert() {
        let text = "# Titel\n**fett** und *kursiv*\n- [x] erledigt\n`code`"
        XCTAssertEqual(gestaltet(text).string, text)
    }

    func testUeberschrift() {
        let s = gestaltet("# Titel\nText")
        XCTAssertTrue(fett(schrift(s, 3)))
        XCTAssertEqual(schrift(s, 3).pointSize, 22)
        XCTAssertEqual(farbe(s, 0), Style.dim)         // das # ist gedimmt
        XCTAssertFalse(fett(schrift(s, 9)))
        XCTAssertEqual(schrift(s, 9).pointSize, Style.bodySize)
    }

    func testUeberschriftEbeneDrei() {
        XCTAssertEqual(schrift(gestaltet("### Drei"), 5).pointSize, 17)
    }

    func testFett() {
        let s = gestaltet("**fett** normal")
        XCTAssertTrue(fett(schrift(s, 3)))
        XCTAssertEqual(farbe(s, 0), Style.dim)
        XCTAssertFalse(fett(schrift(s, 10)))
    }

    func testKursiv() {
        let s = gestaltet("ein *kursiv* Wort")
        XCTAssertTrue(kursiv(schrift(s, 6)))
        XCTAssertFalse(kursiv(schrift(s, 1)))
    }

    func testUnterstrichImWortIstKeinKursiv() {
        XCTAssertFalse(kursiv(schrift(gestaltet("snake_case_name"), 7)))
    }

    func testCode() {
        let s = gestaltet("nimm `make test` jetzt")
        XCTAssertTrue(mono(schrift(s, 7)))
        XCTAssertFalse(mono(schrift(s, 1)))
    }

    func testErledigteAufgabeDurchgestrichen() {
        XCTAssertNotNil(gestaltet("- [x] erledigt").attribute(.strikethroughStyle, at: 8, effectiveRange: nil))
        XCTAssertNil(gestaltet("- [ ] offen").attribute(.strikethroughStyle, at: 7, effectiveRange: nil))
    }

    func testListenzeichenInSignalfarbe() {
        XCTAssertEqual(farbe(gestaltet("- Punkt"), 0), Style.accent)
    }

    func testCodeblockOhneHervorhebung() {
        let s = gestaltet("```\n**nicht fett**\n```")
        XCTAssertFalse(fett(schrift(s, 7)))
        XCTAssertTrue(mono(schrift(s, 7)))
    }

    func testLeererText() {
        XCTAssertEqual(gestaltet("").length, 0)
    }

    /// Der Delegate gestaltet nach jeder Zeichenänderung neu (so läuft es im Editor).
    func testDelegateGestaltetNachTippenNeu() {
        let hervorhebung = MarkdownHighlighter()      // `delegate` ist schwach — Referenz halten
        let s = NSTextStorage(string: "")
        s.delegate = hervorhebung
        s.replaceCharacters(in: NSRange(location: 0, length: 0), with: "# Titel")
        XCTAssertEqual(s.string, "# Titel")
        XCTAssertEqual(schrift(s, 3).pointSize, 22)
        s.replaceCharacters(in: NSRange(location: 0, length: 2), with: "")
        XCTAssertEqual(s.string, "Titel")
        XCTAssertEqual(schrift(s, 2).pointSize, Style.bodySize)
        XCTAssertFalse(fett(schrift(s, 2)))
        withExtendedLifetime(hervorhebung) {}
    }

    func testFettInUeberschriftBleibtGross() {
        let s = gestaltet("## a **b** c")
        XCTAssertTrue(fett(schrift(s, 6)))
        XCTAssertEqual(schrift(s, 6).pointSize, 19)
    }
}
