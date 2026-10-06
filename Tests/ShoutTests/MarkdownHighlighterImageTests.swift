import XCTest
import AppKit

final class MarkdownHighlighterImageTests: XCTestCase {

    private func markiert(_ text: String, groesse: CGSize?) -> NSTextStorage {
        let speicher = NSTextStorage(string: text)
        MarkdownHighlighter.apply(to: speicher)
        MarkdownHighlighter.markImages(in: speicher, range: NSRange(location: 0, length: speicher.length)) { _ in groesse }
        return speicher
    }

    private func marke(_ s: NSTextStorage, bei index: Int) -> NoteImageMark? {
        s.attribute(.notizBild, at: index, effectiveRange: nil) as? NoteImageMark
    }

    func testBildzeileBekommtMarkeUndAbstand() throws {
        let s = markiert("Text\n![](Anhänge/a.png)\nmehr", groesse: CGSize(width: 640, height: 480))
        let m = try XCTUnwrap(marke(s, bei: 5))
        XCTAssertEqual(m.path, "Anhänge/a.png")
        XCTAssertEqual(m.size, CGSize(width: 320, height: 240))
        let stil = try XCTUnwrap(s.attribute(.paragraphStyle, at: 5, effectiveRange: nil) as? NSParagraphStyle)
        XCTAssertGreaterThanOrEqual(stil.paragraphSpacing, 240)
        XCTAssertNil(marke(s, bei: 0))
    }

    func testKleinesBildBleibtKlein() throws {
        let s = markiert("![](a.png)", groesse: CGSize(width: 100, height: 50))
        XCTAssertEqual(marke(s, bei: 0)?.size, CGSize(width: 100, height: 50))
    }

    func testBildMitteImSatzOhneVorschau() {
        let s = markiert("siehe ![](a.png) hier", groesse: CGSize(width: 10, height: 10))
        XCTAssertNil(marke(s, bei: 6))
    }

    func testOhneBekannteGroesseOhneVorschau() {
        let s = markiert("![](fehlt.png)", groesse: nil)
        XCTAssertNil(marke(s, bei: 0))
    }

    func testDieHervorhebungMarkiertBeimTippen() {
        let h = MarkdownHighlighter()
        h.imageSize = { _ in CGSize(width: 50, height: 20) }
        let s = NSTextStorage()
        s.delegate = h
        s.replaceCharacters(in: NSRange(location: 0, length: 0), with: "Text\n![](b.png)")
        XCTAssertNotNil(marke(s, bei: 5))
        s.replaceCharacters(in: NSRange(location: 4, length: 0), with: " mehr")   // anderer Absatz
        XCTAssertNotNil(marke(s, bei: 10), "Marke überlebt die Neugestaltung")
    }
}
