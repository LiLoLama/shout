import AppKit

/// Markdown für die Zwischenablage: Klartext (das Markdown unverändert) und RTF
/// mit echter Formatierung. Mail, Pages und Notion nehmen das RTF und zeigen
/// Überschriften, Listen und Fettes; das Terminal nimmt den Klartext.
/// Bild-Links bleiben Text.
enum MarkdownPasteboard {

    static let bodySize: CGFloat = 13
    private static let indent: CGFloat = 18
    private static let headingSizes: [CGFloat] = [20, 17, 15, 14, 13, 13]

    /// Schreibt Klartext und RTF. `extraTypes` bekommen den Wert "1" — für die
    /// Marker, an denen Zwischenablage-Verläufe erkennen, dass sie den Inhalt
    /// nicht aufnehmen sollen.
    static func write(_ markdown: String, to pasteboard: NSPasteboard,
                      extraTypes: [NSPasteboard.PasteboardType] = []) {
        pasteboard.clearContents()
        let rtf = rtf(from: markdown)
        let typen: [NSPasteboard.PasteboardType] = [.string] + (rtf != nil ? [.rtf] : []) + extraTypes
        pasteboard.declareTypes(typen, owner: nil)
        pasteboard.setString(markdown, forType: .string)
        if let rtf = rtf { pasteboard.setData(rtf, forType: .rtf) }
        for typ in extraTypes { pasteboard.setData(Data("1".utf8), forType: typ) }
    }

    static func rtf(from markdown: String) -> Data? {
        let text = attributed(from: markdown)
        return text.rtf(from: NSRange(location: 0, length: text.length),
                        documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
    }

    /// Zeilenweise: Überschriften, Listen, Checkboxen, Zitate und Codeblöcke
    /// selbst, alles innerhalb einer Zeile (fett, kursiv, Code, Links) über
    /// `AttributedString(markdown:)`.
    static func attributed(from markdown: String) -> NSAttributedString {
        let ergebnis = NSMutableAttributedString()
        let zeilen = markdown.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        var imCode = false
        for (index, zeile) in zeilen.enumerated() {
            let ende = index < zeilen.count - 1 ? "\n" : ""
            let trimmed = zeile.trimmingCharacters(in: .whitespaces)
            // Zaun nur, wenn die Zeile mit ``` beginnt und kein weiteres ``` danach hat
            if trimmed.hasPrefix("```") {
                let afterOpen = trimmed.dropFirst(3)
                if !afterOpen.contains("```") {
                    imCode.toggle()
                    continue
                }
            }
            if imCode {
                ergebnis.append(NSAttributedString(string: zeile + ende,
                                                   attributes: [.font: mono, .paragraphStyle: absatz(einzug: 0)]))
                continue
            }
            ergebnis.append(block(zeile, ende: ende))
        }
        return ergebnis
    }

    // MARK: - Blöcke

    private static func block(_ zeile: String, ende: String) -> NSAttributedString {
        let einzugZeichen = zeile.prefix(while: { $0 == " " || $0 == "\t" })
        let ebene = einzugZeichen.reduce(0) { $0 + ($1 == "\t" ? 2 : 1) } / 2
        let rest = String(zeile.dropFirst(einzugZeichen.count))

        let rauten = rest.prefix(while: { $0 == "#" }).count
        if (1...6).contains(rauten), rest.dropFirst(rauten).first == " " {
            let titel = String(rest.dropFirst(rauten + 1))
            return inline(titel, basis: bold(NSFont.systemFont(ofSize: headingSizes[rauten - 1])),
                          absatz: absatz(einzug: 0), ende: ende)
        }
        let kaestchen: [(String, String)] = [("- [ ] ", "☐"), ("- [x] ", "☑"), ("- [X] ", "☑"),
                                             ("* [ ] ", "☐"), ("* [x] ", "☑"), ("* [X] ", "☑")]
        for (marke, zeichen) in kaestchen where rest.hasPrefix(marke) {
            return listItem(zeichen, String(rest.dropFirst(marke.count)), ebene: ebene, ende: ende)
        }
        for marke in ["- ", "* ", "+ "] where rest.hasPrefix(marke) {
            return listItem("•", String(rest.dropFirst(marke.count)), ebene: ebene, ende: ende)
        }
        let ziffern = rest.prefix(while: { $0.isASCII && $0.isNumber })
        if !ziffern.isEmpty {
            let danach = rest.dropFirst(ziffern.count)
            if danach.hasPrefix(". ") || danach.hasPrefix(") ") {
                return listItem(String(ziffern) + ".", String(danach.dropFirst(2)), ebene: ebene, ende: ende)
            }
        }
        if rest.hasPrefix(">") {
            var inhalt = rest.dropFirst()
            if inhalt.first == " " { inhalt = inhalt.dropFirst() }
            return inline(String(inhalt), basis: body, absatz: absatz(einzug: indent), ende: ende, farbe: .gray)
        }
        return inline(zeile, basis: body, absatz: absatz(einzug: 0), ende: ende)
    }

    private static func listItem(_ marke: String, _ text: String, ebene: Int, ende: String) -> NSAttributedString {
        let links = CGFloat(ebene) * indent
        let stil = absatz(einzug: links + indent, erste: links)
        let zeile = NSMutableAttributedString(string: marke + "\t", attributes: [.font: body, .paragraphStyle: stil])
        zeile.append(inline(text, basis: body, absatz: stil, ende: ende))
        return zeile
    }

    private static func absatz(einzug: CGFloat, erste: CGFloat? = nil) -> NSParagraphStyle {
        let stil = NSMutableParagraphStyle()
        stil.headIndent = einzug
        stil.firstLineHeadIndent = erste ?? einzug
        if einzug > 0 { stil.tabStops = [NSTextTab(textAlignment: .left, location: einzug)] }
        stil.defaultTabInterval = indent
        return stil
    }

    // MARK: - Innerhalb einer Zeile

    private static func inline(_ text: String, basis: NSFont, absatz: NSParagraphStyle,
                               ende: String, farbe: NSColor? = nil) -> NSAttributedString {
        var grund: [NSAttributedString.Key: Any] = [.font: basis, .paragraphStyle: absatz]
        if let farbe { grund[.foregroundColor] = farbe }
        // Bild-Links bleiben Text — der Parser machte sonst nur den Alt-Text daraus.
        // Inline-Dreifach-Backticks bleiben Text — sie sollen nicht als Codeblock-Zaun gelten.
        guard !text.contains("!["), !text.contains("```"),
              let geparst = try? AttributedString(
                markdown: text,
                options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) else {
            return NSAttributedString(string: text + ende, attributes: grund)
        }
        let ergebnis = NSMutableAttributedString()
        for lauf in geparst.runs {
            var attribute = grund
            var schrift = basis
            if let absicht = lauf.inlinePresentationIntent {
                if absicht.contains(.code) { schrift = monoFont(basedOn: schrift) }
                if absicht.contains(.stronglyEmphasized) { schrift = bold(schrift) }
                if absicht.contains(.emphasized) { schrift = italic(schrift) }
                if absicht.contains(.strikethrough) {
                    attribute[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
                }
            }
            attribute[.font] = schrift
            if let link = lauf.link { attribute[.link] = link }
            ergebnis.append(NSAttributedString(string: String(geparst[lauf.range].characters),
                                               attributes: attribute))
        }
        ergebnis.append(NSAttributedString(string: ende, attributes: grund))
        return ergebnis
    }

    private static var body: NSFont { NSFont.systemFont(ofSize: bodySize) }
    private static var mono: NSFont { NSFont.monospacedSystemFont(ofSize: bodySize - 1, weight: .regular) }
    private static func monoFont(basedOn schrift: NSFont) -> NSFont {
        NSFont.monospacedSystemFont(ofSize: schrift.pointSize, weight: .regular)
    }
    private static func bold(_ f: NSFont) -> NSFont { NSFontManager.shared.convert(f, toHaveTrait: .boldFontMask) }
    private static func italic(_ f: NSFont) -> NSFont { NSFontManager.shared.convert(f, toHaveTrait: .italicFontMask) }
}
