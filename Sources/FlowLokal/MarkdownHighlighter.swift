import AppKit

/// Hebt Markdown im Editor hervor, ohne den Text zu verändern: Die Datei bleibt
/// Klartext, nur die Darstellung bekommt Größen, Fett, Kursiv und gedimmte
/// Markierungszeichen. Als Delegate eines `NSTextStorage` gestaltet es nach
/// jeder Zeichenänderung den Absatz um die Änderung neu — mit einem Codeblock-Zaun im
/// Text (oder wenn gerade einer verschwand) den ganzen Text, damit
/// Codeblöcke über mehrere Zeilen nie halb erkannt werden.
final class MarkdownHighlighter: NSObject, NSTextStorageDelegate {

    enum Style {
        static let bodySize: CGFloat = 14
        static let headingSizes: [CGFloat] = [22, 19, 17, 15.5, 14.5, 14]
        static let text = NSColor(white: 0.90, alpha: 1)
        static let dim = NSColor(white: 0.42, alpha: 1)
        /// Wie `Color.shoutLive`.
        static let accent = NSColor(red: 1.0, green: 0.29, blue: 0.04, alpha: 1)
        static let codeBackground = NSColor(white: 1, alpha: 0.06)
        static let body = NSFont.systemFont(ofSize: bodySize)
        static let mono = NSFont.monospacedSystemFont(ofSize: bodySize - 1, weight: .regular)
        static let paragraph: NSParagraphStyle = {
            let stil = NSMutableParagraphStyle()
            stil.lineSpacing = 3
            stil.paragraphSpacing = 4
            return stil
        }()
        static var baseAttributes: [NSAttributedString.Key: Any] {
            [.font: body, .foregroundColor: text, .paragraphStyle: paragraph]
        }
    }

    /// Gibt `true` zurück, solange nicht neu gestaltet werden darf — im Editor,
    /// während markierter Text entsteht (Option+U für Umlaute). Das Neugestalten
    /// löschte sonst dessen Attribute. Das Übernehmen ist wieder eine
    /// Zeichenänderung, danach wird von selbst neu gestaltet.
    var shouldSkip: (() -> Bool)?

    /// Stand vor der letzten Änderung: Gab es einen Codeblock-Zaun? Verschwindet
    /// er, muss der ganze Text neu, sonst blieben frühere Blockzeilen monospace.
    private var hatteZaun = false

    func textStorage(_ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions,
                     range editedRange: NSRange, changeInLength delta: Int) {
        guard editedMask.contains(.editedCharacters), shouldSkip?() != true else { return }
        let ns = textStorage.string as NSString
        let hatZaun = ns.range(of: "```").location != NSNotFound
        defer { hatteZaun = hatZaun }
        // Ein Zaun verändert die Darstellung bis zum nächsten — dann alles.
        if hatZaun || hatteZaun {
            Self.apply(to: textStorage)
            markiereBilder(textStorage, in: NSRange(location: 0, length: ns.length))
            return
        }
        // Ein einzelnes \r trennt für `paragraphRange` Absätze, Kursiv (`[^\n]`)
        // greift aber über es hinweg. Nur ein \r ohne folgendes \n löst den ganzen
        // Text aus, damit CRLF-Text (ein Zeilenumbruch aus \r\n) absatzweise bleibt.
        if ns.length > 0, alleinstehendesCR.firstMatch(in: textStorage.string, range: NSRange(location: 0, length: ns.length)) != nil {
            Self.apply(to: textStorage)
            markiereBilder(textStorage, in: NSRange(location: 0, length: ns.length))
            return
        }
        let start = min(editedRange.location, ns.length)
        let ende = min(NSMaxRange(editedRange), ns.length)
        // Der Absatz am Ende der Änderung gehört dazu: Endet sie auf einem
        // Zeilenumbruch (Enter mitten in einer Zeile), liegt der Rest der Zeile
        // sonst außerhalb von `paragraphRange(for: editedRange)`.
        let vorn = ns.paragraphRange(for: NSRange(location: start, length: ende - start))
        let hinten = ns.paragraphRange(for: NSRange(location: ende, length: 0))
        let bereich = NSUnionRange(vorn, hinten)
        Self.apply(to: textStorage, in: bereich)
        markiereBilder(textStorage, in: bereich)
    }

    /// Setzt die Bildmarken im Bereich (neu). Ohne `imageSize` passiert nichts.
    func markiereBilder(_ storage: NSTextStorage, in bereich: NSRange) {
        guard let imageSize else { return }
        Self.markImages(in: storage, range: bereich, maxWidth: imageMaxWidth?() ?? Self.imagePreviewMaxWidth,
                        size: imageSize)
    }

    /// Größe eines Bildes zum Pfad aus dem Text; `nil` — keine Vorschau. Vom Editor gesetzt.
    var imageSize: ((String) -> CGSize?)?

    /// Höchstbreite der Vorschau im Moment — der Editor kennt die Textbreite.
    /// Ohne Angabe gilt `imagePreviewMaxWidth`.
    var imageMaxWidth: (() -> CGFloat)?

    static let imagePreviewMaxWidth: CGFloat = 320
    private static let imageLine = muster("^!\\[[^\\]\\n]*\\]\\(([^)\\n]+)\\)[ \\t]*$")

    /// Markiert Zeilen, die nur aus einem Bild-Link bestehen, und hält unter
    /// ihnen Platz für die Vorschau frei. Läuft nach `apply`, das alle Attribute
    /// des Bereichs zurücksetzt; alte Marken im Bereich werden vorher entfernt
    /// (auch bei Aufrufen ohne `apply`, etwa nach einer Breitenänderung).
    /// Nur Zeilen mit Zeilenumbruch dahinter: TextKit gibt dem letzten Absatz
    /// ohne Abschlusszeichen keinen Absatzabstand. Bilder in Codeblöcken bleiben
    /// Text.
    static func markImages(in storage: NSTextStorage, range bereich: NSRange,
                           maxWidth: CGFloat = imagePreviewMaxWidth, size: (String) -> CGSize?) {
        let ns = storage.string as NSString
        let start = min(bereich.location, ns.length)
        let absaetze = ns.paragraphRange(for: NSRange(location: start, length: min(bereich.length, ns.length - start)))
        // Alte Marken weg, Absatzstil zurück.
        var alte: [NSRange] = []
        storage.enumerateAttribute(.notizBild, in: absaetze) { wert, r, _ in
            if wert != nil { alte.append(r) }
        }
        for r in alte {
            storage.removeAttribute(.notizBild, range: r)
            storage.addAttribute(.paragraphStyle, value: Style.paragraph, range: ns.paragraphRange(for: r))
        }
        let bloecke = fence.matches(in: storage.string, range: absaetze).map(\.range)
        imageLine.enumerateMatches(in: storage.string, options: [], range: absaetze) { treffer, _, _ in
            guard let treffer else { return }
            let absatz = ns.paragraphRange(for: treffer.range)
            guard NSMaxRange(absatz) > NSMaxRange(treffer.range) else { return }
            guard !bloecke.contains(where: { NSIntersectionRange($0, treffer.range).length > 0 }) else { return }
            let pfad = ns.substring(with: treffer.range(at: 1))
            guard let original = size(pfad), original.width > 0, original.height > 0 else { return }
            let breite = min(original.width, maxWidth)
            let hoehe = (original.height * breite / original.width).rounded()
            storage.addAttribute(.notizBild, value: NoteImageMark(path: pfad, size: CGSize(width: breite, height: hoehe)),
                                 range: treffer.range)
            let stil = (Style.paragraph.mutableCopy() as? NSMutableParagraphStyle) ?? NSMutableParagraphStyle()
            stil.paragraphSpacing = hoehe + 10
            storage.addAttribute(.paragraphStyle, value: stil, range: absatz)
        }
    }

    private let alleinstehendesCR = try! NSRegularExpression(pattern: "\\r(?!\\n)")

    // MARK: - Regeln

    private static func muster(_ p: String) -> NSRegularExpression {
        try! NSRegularExpression(pattern: p, options: [.anchorsMatchLines])
    }

    private static let fence = muster("^```[^\\n]*\\n[\\s\\S]*?^```[^\\n]*$")
    private static let heading = muster("^(#{1,6})[ \\t]+\\S.*$")
    private static let bold = muster("(\\*\\*|__)(?=\\S)(.+?)(?<=\\S)\\1")
    private static let italic = muster("(?<![\\*\\w])([\\*_])(?=[^\\s\\*_])([^\\n]+?)(?<=[^\\s\\*_])\\1(?![\\*\\w])")
    private static let code = muster("`[^`\\n]+`")
    private static let listMarker = muster("^[ \\t]*([-*+]|\\d+[.)])[ \\t]")
    private static let checkbox = muster("^[ \\t]*[-*+][ \\t](\\[[ xX]\\])[ \\t]?(.*)$")
    private static let quote = muster("^>[ \\t]?.*$")
    private static let link = muster("!?\\[([^\\]\\n]*)\\]\\(([^)\\n]*)\\)")

    /// Gestaltet den ganzen Text.
    static func apply(to storage: NSTextStorage) {
        apply(to: storage, in: NSRange(location: 0, length: (storage.string as NSString).length))
    }

    /// Gestaltet nur `bereich`. Der Bereich muss an Absatzgrenzen beginnen und
    /// enden — alle Regeln außer dem Zaun sind zeilengebunden.
    static func apply(to storage: NSTextStorage, in bereich: NSRange) {
        let ns = storage.string as NSString
        let ganz = NSIntersectionRange(bereich, NSRange(location: 0, length: ns.length))
        storage.setAttributes(Style.baseAttributes, range: ganz)
        guard ganz.length > 0 else { return }
        let text = storage.string

        let bloecke = fence.matches(in: text, range: ganz).map(\.range)
        func ausserhalbCode(_ r: NSRange) -> Bool {
            !bloecke.contains { NSIntersectionRange($0, r).length > 0 }
        }
        func jeder(_ re: NSRegularExpression, _ tu: (NSTextCheckingResult) -> Void) {
            for treffer in re.matches(in: text, range: ganz) where ausserhalbCode(treffer.range) { tu(treffer) }
        }
        func dimmen(_ r: NSRange) { storage.addAttribute(.foregroundColor, value: Style.dim, range: r) }

        jeder(heading) { t in
            let ebene = t.range(at: 1).length
            storage.addAttribute(.font, value: NSFont.boldSystemFont(ofSize: Style.headingSizes[ebene - 1]), range: t.range)
            dimmen(t.range(at: 1))
        }
        jeder(quote) { t in
            dimmen(t.range)
            addTrait(.italicFontMask, in: t.range, of: storage)
        }
        jeder(listMarker) { t in
            storage.addAttribute(.foregroundColor, value: Style.accent, range: t.range(at: 1))
        }
        jeder(checkbox) { t in
            dimmen(t.range(at: 1))
            if ns.substring(with: t.range(at: 1)).lowercased() == "[x]" {
                storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: t.range(at: 2))
                dimmen(t.range(at: 2))
            }
        }
        jeder(bold) { t in
            addTrait(.boldFontMask, in: t.range(at: 2), of: storage)
            let n = t.range(at: 1).length
            dimmen(NSRange(location: t.range.location, length: n))
            dimmen(NSRange(location: NSMaxRange(t.range) - n, length: n))
        }
        jeder(italic) { t in
            addTrait(.italicFontMask, in: t.range(at: 2), of: storage)
            dimmen(NSRange(location: t.range.location, length: 1))
            dimmen(NSRange(location: NSMaxRange(t.range) - 1, length: 1))
        }
        jeder(link) { t in
            dimmen(t.range)
            storage.addAttribute(.foregroundColor, value: Style.accent, range: t.range(at: 1))
        }
        jeder(code) { t in
            storage.addAttributes([.font: Style.mono, .backgroundColor: Style.codeBackground], range: t.range)
        }
        for block in bloecke {
            storage.addAttributes([.font: Style.mono, .backgroundColor: Style.codeBackground,
                                   .foregroundColor: Style.text], range: block)
        }
    }

    /// Fügt Fett oder Kursiv hinzu, ohne Größe und vorhandene Merkmale zu verlieren
    /// (fett in einer Überschrift bleibt groß).
    private static func addTrait(_ trait: NSFontTraitMask, in range: NSRange, of storage: NSTextStorage) {
        guard range.length > 0 else { return }
        storage.enumerateAttribute(.font, in: range) { wert, teil, _ in
            let schrift = wert as? NSFont ?? Style.body
            var neu = NSFontManager.shared.convert(schrift, toHaveTrait: trait)
            if !NSFontManager.shared.traits(of: neu).contains(trait) {
                let merkmal: NSFontDescriptor.SymbolicTraits = trait == .boldFontMask ? .bold : .italic
                let beschreibung = schrift.fontDescriptor.withSymbolicTraits(
                    schrift.fontDescriptor.symbolicTraits.union(merkmal))
                neu = NSFont(descriptor: beschreibung, size: schrift.pointSize) ?? schrift
            }
            storage.addAttribute(.font, value: neu, range: teil)
        }
    }
}
