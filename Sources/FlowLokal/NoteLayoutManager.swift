import AppKit

extension NSAttributedString.Key {
    /// Eine Zeile, die nur aus einem Bild-Link besteht — mit Vorschau darunter.
    static let notizBild = NSAttributedString.Key("shout.notizBild")
}

/// Pfad und Vorschaugröße einer Bildzeile.
final class NoteImageMark: NSObject {
    let path: String
    let size: CGSize

    init(path: String, size: CGSize) {
        self.path = path
        self.size = size
    }

    override func isEqual(_ object: Any?) -> Bool {
        guard let andere = object as? NoteImageMark else { return false }
        return andere.path == path && andere.size == size
    }

    override var hash: Int { path.hashValue ^ Int(size.width) ^ Int(size.height) }
}

/// Zeichnet unter jeder Bildzeile die Vorschau — in den Absatzabstand, den die
/// Hervorhebung dafür freihält.
final class NoteLayoutManager: NSLayoutManager {

    /// Lädt ein Bild zum Pfad aus dem Text (relativ zum Notizordner).
    var loadImage: ((String) -> NSImage?)?

    override func drawGlyphs(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        super.drawGlyphs(forGlyphRange: glyphsToShow, at: origin)
        guard let speicher = textStorage, let loadImage else { return }
        let zeichen = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
        speicher.enumerateAttribute(.notizBild, in: zeichen) { wert, bereich, _ in
            guard let marke = wert as? NoteImageMark, let bild = loadImage(marke.path) else { return }
            let glyphen = glyphRange(forCharacterRange: bereich, actualCharacterRange: nil)
            guard glyphen.length > 0 else { return }
            let zeile = lineFragmentUsedRect(forGlyphAt: NSMaxRange(glyphen) - 1, effectiveRange: nil)
            // Auf der Höhe des Textes, nicht des Containerrands.
            let rand = textContainer(forGlyphAt: glyphen.location, effectiveRange: nil)?.lineFragmentPadding ?? 0
            let ziel = NSRect(x: origin.x + zeile.minX + rand, y: origin.y + zeile.maxY + 4,
                              width: marke.size.width, height: marke.size.height)
            bild.draw(in: ziel, from: .zero, operation: .sourceOver, fraction: 1,
                      respectFlipped: true, hints: nil)
        }
    }
}
