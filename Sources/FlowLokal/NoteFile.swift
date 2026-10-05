import Foundation

/// Reine Funktionen rund um die Notizdatei. Kein Zustand, kein Dateizugriff
/// außer beim Suchen eines freien Namens.
enum NoteFile {

    static let fileExtension = "md"

    struct Parsed: Equatable {
        var body: String
        var created: Date?
        var pinned: Bool
        var extraFrontmatter: [String]
    }

    // MARK: - Frontmatter

    /// Zerlegt eine Datei in Frontmatter und Text. Gelesen werden nur `created`
    /// und `pinned`; alle anderen Zeilen wandern unverändert nach
    /// `extraFrontmatter`, damit Obsidian-Felder beim Speichern erhalten bleiben.
    static func parse(_ raw: String) -> Parsed {
        var text = raw.replacingOccurrences(of: "\r\n", with: "\n")
        if text.hasPrefix("\u{FEFF}") { text.removeFirst() }
        let ohne = Parsed(body: text, created: nil, pinned: false, extraFrontmatter: [])
        guard text.hasPrefix("---\n") else { return ohne }

        let rest = text.dropFirst(4)
        var lines: [Substring] = []
        var bodyStart: String.Index?
        var cursor = rest.startIndex
        while cursor < rest.endIndex {
            let lineEnd = rest[cursor...].firstIndex(of: "\n") ?? rest.endIndex
            let line = rest[cursor..<lineEnd]
            let next = lineEnd < rest.endIndex ? rest.index(after: lineEnd) : rest.endIndex
            if line == "---" {
                bodyStart = next
                break
            }
            lines.append(line)
            cursor = next
        }
        // Keine Schlusslinie: Die Striche am Anfang sind Text, kein Frontmatter.
        guard let bodyStart else { return ohne }

        var parsed = Parsed(body: String(rest[bodyStart...]), created: nil,
                            pinned: false, extraFrontmatter: [])
        for line in lines {
            if let value = value(of: "created", in: line) {
                // Unlesbar: Die Zeile fällt weg und wird beim Speichern neu geschrieben.
                parsed.created = date(from: value)
            } else if let value = value(of: "pinned", in: line) {
                parsed.pinned = value.lowercased() == "true"
            } else {
                parsed.extraFrontmatter.append(String(line))
            }
        }
        return parsed
    }

    /// Schreibt Frontmatter und Text. `created` steht immer da, `pinned` nur,
    /// wenn die Notiz angeheftet ist; danach die fremden Felder in ihrer Reihenfolge.
    static func serialize(body: String, created: Date, pinned: Bool,
                          extraFrontmatter: [String], timeZone: TimeZone = .current) -> String {
        var lines = ["---", "created: " + string(from: created, timeZone: timeZone)]
        if pinned { lines.append("pinned: true") }
        lines += extraFrontmatter
        lines.append("---")
        return lines.joined(separator: "\n") + "\n" + body
    }

    /// Nur Felder am Zeilenanfang — eingerückte Zeilen gehören zu einer Liste darüber.
    private static func value(of key: String, in line: Substring) -> String? {
        guard line.hasPrefix(key + ":") else { return nil }
        return line.dropFirst(key.count + 1)
            .trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
    }

    // MARK: - Datum

    /// ISO 8601 mit Zeitzone, mit Sekundenbruchteilen, ohne Zeitzone oder als
    /// reines Datum — so, wie Obsidian und andere Programme es schreiben.
    static func date(from value: String) -> Date? {
        let varianten: [ISO8601DateFormatter.Options] = [
            [.withInternetDateTime],
            [.withInternetDateTime, .withFractionalSeconds],
            [.withFullDate, .withTime, .withColonSeparatorInTime, .withDashSeparatorInDate],
            [.withFullDate],
        ]
        for optionen in varianten {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = optionen
            formatter.timeZone = .current
            if let date = formatter.date(from: value) { return date }
        }
        return nil
    }

    static func string(from date: Date, timeZone: TimeZone = .current) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = timeZone
        return formatter.string(from: date)
    }

    // MARK: - Titel und Dateinamen

    static let maxTitleLength = 60
    static let titleWordLimit = 5
    /// Ab so vielen Wörtern steht der Dateiname einer neuen Notiz fest.
    static let fixedTitleWordCount = 3

    /// Titel aus den ersten Wörtern der ersten Zeile mit Inhalt. Bildzeilen
    /// zählen nicht — ein Dateiname „![](Anhänge-…" hilft niemandem.
    static func deriveTitle(from body: String) -> String? {
        let erste = body.split(separator: "\n")
            .map(cleanLine)
            .first { !$0.isEmpty && !$0.hasPrefix("![") }
        guard let erste else { return nil }
        let woerter = erste.split(whereSeparator: \.isWhitespace).prefix(titleWordLimit)
        return safeTitle(woerter.joined(separator: " "))
    }

    /// Markdown-Zeichen am Zeilenanfang und Hervorhebungen fallen weg: Aus
    /// „## **Wichtig**: Termin" wird „Wichtig: Termin".
    static func cleanLine(_ line: Substring) -> String {
        var text = line.trimmingCharacters(in: .whitespaces)
        let marker = ["[ ]", "[x]", "[X]", "#", "-", "*", "+", ">"]
        var weiter = true
        while weiter {
            weiter = false
            for zeichen in marker where text.hasPrefix(zeichen) {
                text = String(text.dropFirst(zeichen.count)).trimmingCharacters(in: .whitespaces)
                weiter = true
            }
        }
        text.removeAll { "*_`".contains($0) }
        return text
    }

    /// Ein Dateiname, der überall taugt: keine Pfadzeichen, nichts, was Windows
    /// oder Obsidian-Links ablehnen, kein führender Punkt (versteckte Datei),
    /// kein Punkt am Ende, höchstens 60 Zeichen.
    static func safeTitle(_ raw: String) -> String? {
        var text = raw.replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: "\\", with: "-")
        text.removeAll { ":*\"<>|?#^[]".contains($0) }
        text = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        while text.hasPrefix(".") { text.removeFirst() }
        text = String(text.prefix(maxTitleLength)).trimmingCharacters(in: .whitespaces)
        while text.hasSuffix(".") { text.removeLast() }
        return text.isEmpty ? nil : text
    }

    /// Wörter mit mindestens einem Buchstaben oder einer Ziffer. „- [ ]" zählt nicht.
    static func wordCount(_ body: String) -> Int {
        body.split(whereSeparator: \.isWhitespace)
            .filter { $0.contains { $0.isLetter || $0.isNumber } }
            .count
    }

    /// „Titel (Konflikt)" — gekürzt so, dass der Zusatz immer ganz dasteht.
    static func conflictTitle(_ title: String, suffix: String) -> String {
        let platz = max(maxTitleLength - suffix.count - 1, 1)
        return String(title.prefix(platz)).trimmingCharacters(in: .whitespaces) + " " + suffix
    }

    /// iCloud lagert „Idee.md" als „.Idee.md.icloud" aus. Gibt den echten Namen
    /// zurück, wenn es ein ausgelagerter Notizname ist.
    static func placeholderTarget(_ name: String) -> String? {
        guard name.hasPrefix("."), name.hasSuffix(".icloud") else { return nil }
        let innen = String(name.dropFirst().dropLast(".icloud".count))
        return (innen as NSString).pathExtension.lowercased() == fileExtension ? innen : nil
    }

    /// Freier Dateiname: „Titel.md", sonst „Titel 2.md", „Titel 3.md" …
    /// `current` ist die eigene Datei und zählt nicht als belegt. Verglichen wird
    /// ohne Groß-/Kleinschreibung, wie APFS es standardmäßig tut.
    static func freeFileName(for title: String, in folder: URL, current: String? = nil,
                             fileManager: FileManager = .default) -> String {
        let namen = (try? fileManager.contentsOfDirectory(atPath: folder.path)) ?? []
        var belegt = Set<String>()
        for name in namen {
            belegt.insert(name.lowercased())
            if let echt = placeholderTarget(name) { belegt.insert(echt.lowercased()) }
        }
        if let current { belegt.remove(current.lowercased()) }

        var kandidat = "\(title).\(fileExtension)"
        var zahl = 2
        while belegt.contains(kandidat.lowercased()) {
            kandidat = "\(title) \(zahl).\(fileExtension)"
            zahl += 1
        }
        return kandidat
    }
}
