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
        let s = markiert("![](a.png)\n", groesse: CGSize(width: 100, height: 50))
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
        s.replaceCharacters(in: NSRange(location: 0, length: 0), with: "Text\n![](b.png)\n")
        XCTAssertNotNil(marke(s, bei: 5))
        s.replaceCharacters(in: NSRange(location: 4, length: 0), with: " mehr")   // anderer Absatz
        XCTAssertNotNil(marke(s, bei: 10), "Marke überlebt die Neugestaltung")
    }

    func testLetzteZeileOhneZeilenumbruchOhneVorschau() {
        let ohne = markiert("Text\n![](a.png)", groesse: CGSize(width: 10, height: 10))
        XCTAssertNil(marke(ohne, bei: 5), "ohne Abschlusszeichen gibt TextKit keinen Absatzabstand")
        let mit = markiert("Text\n![](a.png)\n", groesse: CGSize(width: 10, height: 10))
        XCTAssertNotNil(marke(mit, bei: 5))
    }

    func testHoechstbreiteBegrenztDieVorschau() throws {
        let s = NSTextStorage(string: "![](a.png)\n")
        MarkdownHighlighter.apply(to: s)
        MarkdownHighlighter.markImages(in: s, range: NSRange(location: 0, length: s.length), maxWidth: 200) { _ in
            CGSize(width: 640, height: 480)
        }
        XCTAssertEqual(marke(s, bei: 0)?.size, CGSize(width: 200, height: 150))
    }

    func testNeuBemessenErsetztMarkeUndAbstand() throws {
        let s = NSTextStorage(string: "![](a.png)\nrest\n")
        MarkdownHighlighter.apply(to: s)
        let ganz = NSRange(location: 0, length: s.length)
        MarkdownHighlighter.markImages(in: s, range: ganz, maxWidth: 320) { _ in CGSize(width: 640, height: 480) }
        MarkdownHighlighter.markImages(in: s, range: ganz, maxWidth: 160) { _ in CGSize(width: 640, height: 480) }
        XCTAssertEqual(marke(s, bei: 0)?.size, CGSize(width: 160, height: 120))
        let stil = try XCTUnwrap(s.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)
        XCTAssertEqual(stil.paragraphSpacing, 130)
        // Ohne Größe verschwinden Marke und Abstand wieder.
        MarkdownHighlighter.markImages(in: s, range: ganz, size: { _ in nil })
        XCTAssertNil(marke(s, bei: 0))
        let zurueck = try XCTUnwrap(s.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)
        XCTAssertEqual(zurueck.paragraphSpacing, MarkdownHighlighter.Style.paragraph.paragraphSpacing)
    }

    func testBildImCodeblockOhneVorschau() {
        let s = markiert("```\n![](a.png)\n```\n", groesse: CGSize(width: 10, height: 10))
        XCTAssertNil(marke(s, bei: 4))
    }
}
