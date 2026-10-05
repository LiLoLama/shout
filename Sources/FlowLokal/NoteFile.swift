import Foundation

/// Reine Funktionen rund um die Notizdatei. Kein Zustand, kein Dateizugriff
/// außer beim Suchen eines freien Namens.
enum NoteFile {

    static let fileExtension = "md"

    struct Parsed: Equatable {
        var body: String
        var created: Date?
        /// `created` so, wie es in der Datei stand (z. B. „2026-10-05“ aus
        /// Obsidian). Wird beim Schreiben wörtlich übernommen; `nil`, wenn das
        /// Feld fehlte oder unlesbar war.
        var createdRaw: String? = nil
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
                // Lesbar: Der Wert bleibt wörtlich, samt Anführungszeichen — ein
                // reines Datum wird beim Sichern nicht zu einer Uhrzeit.
                parsed.created = date(from: value)
                if parsed.created != nil {
                    parsed.createdRaw = line.dropFirst("created:".count).trimmingCharacters(in: .whitespaces)
                }
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
    /// `createdRaw` ist der Wert aus der Datei und wird wörtlich geschrieben; nur
    /// ohne ihn (neue Notiz, Feld fehlte oder war unlesbar) steht `created` als ISO 8601 da.
    static func serialize(body: String, created: Date, createdRaw: String? = nil, pinned: Bool,
                          extraFrontmatter: [String], timeZone: TimeZone = .current) -> String {
        let wert = createdRaw.flatMap { $0.isEmpty ? nil : $0 } ?? string(from: created, timeZone: timeZone)
        var lines = ["---", "created: " + wert]
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

    /// ISO 8601 mit Zeitzone oder Sekundenbruchteilen; ohne Zeitzone mit „T“ oder
    /// Leerzeichen, mit oder ohne Sekunden; oder als reines Datum — so, wie
    /// Obsidian und andere Programme es schreiben. Ohne Zeitzone gilt die lokale.
    static func date(from value: String) -> Date? {
        let varianten: [ISO8601DateFormatter.Options] = [
            [.withInternetDateTime],
            [.withInternetDateTime, .withFractionalSeconds],
        ]
        for optionen in varianten {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = optionen
            formatter.timeZone = .current
            if let date = formatter.date(from: value) { return date }
        }
        // `ISO8601DateFormatter` mit `.withFullDate` nimmt auch „2026-10-05T14:32“
        // an und macht Mitternacht daraus. `DateFormatter` verlangt den ganzen Text.
        for format in localFormats {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = .current
            formatter.dateFormat = format
            if let date = formatter.date(from: value) { return date }
        }
        return nil
    }

    private static let localFormats = [
        "yyyy-MM-dd'T'HH:mm:ss",
        "yyyy-MM-dd'T'HH:mm",
        "yyyy-MM-dd HH:mm:ss",
        "yyyy-MM-dd HH:mm",
        "yyyy-MM-dd",
    ]

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
        // `isNewline` erkennt auch „\r\n“, das Swift als ein einzelnes Zeichen sieht.
        let erste = body.split(whereSeparator: \.isNewline)
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
        text = trimEdges(text)
        // Der Schnitt bei 60 Zeichen kann wieder Leerzeichen oder Punkte an den Rand legen.
        text = trimEdges(String(text.prefix(maxTitleLength)))
        return text.isEmpty ? nil : text
    }

    /// Leerraum und Punkte am Anfang und Ende, so lange bis nichts mehr wegfällt:
    /// Aus „Hallo Welt ..." wird „Hallo Welt", aus „. Idee" wird „Idee".
    private static func trimEdges(_ text: String) -> String {
        var result = text
        var vorher: String
        repeat {
            vorher = result
            result = result.trimmingCharacters(in: .whitespaces)
            while result.hasPrefix(".") { result.removeFirst() }
            while result.hasSuffix(".") { result.removeLast() }
        } while result != vorher
        return result
    }

    /// Wörter mit mindestens einem Buchstaben oder einer Ziffer. Die Kästchen
    /// „- [ ]“, „- [x]“ und „- [X]“ zählen nicht.
    static func wordCount(_ body: String) -> Int {
        body.split(whereSeparator: \.isWhitespace)
            .filter { $0.lowercased() != "[x]" }
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
        let ownLower = current?.lowercased()
        let istBelegt: (String) -> Bool

        if let namen = try? fileManager.contentsOfDirectory(atPath: folder.path) {
            var belegt = Set<String>()
            for name in namen {
                belegt.insert(name.lowercased())
                if let echt = placeholderTarget(name) { belegt.insert(echt.lowercased()) }
            }
            if let ownLower { belegt.remove(ownLower) }
            istBelegt = { belegt.contains($0.lowercased()) }
        } else {
            // Ordner nicht lesbar: nicht als leer behandeln (sonst würde eine
            // vorhandene Notiz überschrieben), sondern jeden Kandidaten einzeln prüfen.
            istBelegt = { kandidat in
                if kandidat.lowercased() == ownLower { return false }
                return fileManager.fileExists(atPath: folder.appendingPathComponent(kandidat).path)
                    || fileManager.fileExists(atPath: folder.appendingPathComponent(".\(kandidat).icloud").path)
            }
        }

        var kandidat = "\(title).\(fileExtension)"
        var zahl = 2
        while istBelegt(kandidat) {
            kandidat = "\(title) \(zahl).\(fileExtension)"
            zahl += 1
        }
        return kandidat
    }
}
