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
}
