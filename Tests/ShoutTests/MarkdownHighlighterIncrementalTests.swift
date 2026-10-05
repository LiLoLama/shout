import XCTest
import AppKit

/// Absatzweise gestaltet muss genau dasselbe herauskommen wie ganz gestaltet.
final class MarkdownHighlighterIncrementalTests: XCTestCase {

    /// Vergleicht die Attribute Zeichen für Zeichen.
    private func gleicheAttribute(_ a: NSTextStorage, _ b: NSTextStorage) -> Bool {
        guard a.string == b.string else { return false }
        for i in 0..<a.length {
            let x = a.attributes(at: i, effectiveRange: nil) as NSDictionary
            let y = b.attributes(at: i, effectiveRange: nil) as NSDictionary
            if x != y { return false }
        }
        return true
    }

    private func pruefe(_ s: NSTextStorage, _ hinweis: String, file: StaticString = #filePath, line: UInt = #line) {
        let vergleich = NSTextStorage(string: s.string)
        MarkdownHighlighter.apply(to: vergleich)
        XCTAssertTrue(gleicheAttribute(s, vergleich), "\(hinweis): \(s.string.debugDescription)", file: file, line: line)
    }

    func testBearbeitungenWieGanzGestaltet() {
        let hervorhebung = MarkdownHighlighter()
        let s = NSTextStorage(string: "# Titel\nText mit **fett** und *kursiv*\n- [ ] offen\n- [x] erledigt\n> Zitat\n[Link](https://x.de)\n")
        s.delegate = hervorhebung
        MarkdownHighlighter.apply(to: s)

        // (Anteil der Länge als Ort, Länge des ersetzten Bereichs, neuer Text)
        let bearbeitungen: [(Double, Int, String)] = [
            (0.3, 0, "Neu "),
            (0.0, 2, ""),
            (0.5, 3, "\n## Zwei\n"),
            (0.8, 0, "**x**"),
            (0.2, 5, "`code` "),
            (0.6, 1, ""),
            (1.0, 0, "\n```\nblock **nicht fett**\n```\n"),
            (0.97, 0, "nach dem Block"),
        ]
        for (anteil, laenge, text) in bearbeitungen {
            let ort = Int(Double(s.length) * anteil)
            s.replaceCharacters(in: NSRange(location: ort, length: min(laenge, s.length - ort)), with: text)
            pruefe(s, "nach Bearbeitung bei \(ort)")
        }
    }

    /// Verschwindet der letzte Zaun, muss der frühere Codeblock wieder normal aussehen.
    func testEntfernterZaunGestaltetAllesNeu() {
        let hervorhebung = MarkdownHighlighter()
        let s = NSTextStorage(string: "Vorher\n```\n**fett?**\n```\nNachher")
        s.delegate = hervorhebung
        MarkdownHighlighter.apply(to: s)
        let zaun = (s.string as NSString).range(of: "```")
        s.replaceCharacters(in: zaun, with: "")
        pruefe(s, "nach Entfernen des Zauns")
    }

    /// Der Text kommt wie im Editor über den Delegate herein; fällt der letzte
    /// Zaun weg, muss auch der Rest des früheren Blocks wieder normal werden.
    func testLetzterZaunWegNachGeladenemText() {
        let hervorhebung = MarkdownHighlighter()
        let s = NSTextStorage()
        s.delegate = hervorhebung
        s.replaceCharacters(in: NSRange(location: 0, length: 0), with: "Vorher\n```\n**fett?**\n```\nNachher\n")
        pruefe(s, "nach dem Laden")
        for _ in 0..<2 {
            let zaun = (s.string as NSString).range(of: "```")
            s.replaceCharacters(in: zaun, with: "")
            pruefe(s, "nach Entfernen eines Zauns")
        }
        XCTAssertFalse(s.string.contains("```"))
    }

    func testBereichGestaltetNurDiesenAbsatz() {
        let s = NSTextStorage(string: "**eins**\n**zwei**")
        let zweite = (s.string as NSString).range(of: "**zwei**")
        MarkdownHighlighter.apply(to: s, in: zweite)
        let fett = { (i: Int) in NSFontManager.shared.traits(of: s.attribute(.font, at: i, effectiveRange: nil) as! NSFont).contains(.boldFontMask) }
        XCTAssertTrue(fett(zweite.location + 3))
        XCTAssertFalse(fett(3))
    }
}
