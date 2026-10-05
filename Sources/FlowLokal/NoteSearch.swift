import Foundation

/// Suche und Reihenfolge der Notizliste. Rein: dieselben Notizen und dieselbe
/// Suche ergeben immer dasselbe — im Panel (Plan 2) wie auf der Seite.
enum NoteSearch {

    struct Snippet: Equatable {
        let before: String
        let match: String
        let after: String
    }

    struct Result: Equatable, Identifiable {
        let note: Note
        let snippet: Snippet?
        var id: UUID { note.id }
    }

    static let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
    /// Zeichen Kontext vor und nach dem Treffer.
    static let context = 40

    /// Angeheftete zuerst, dann die zuletzt geänderte, bei Gleichstand nach Titel.
    static func sorted(_ notes: [Note]) -> [Note] {
        notes.sorted { a, b in
            if a.pinned != b.pinned { return a.pinned }
            if a.modified != b.modified { return a.modified > b.modified }
            return a.title.localizedStandardCompare(b.title) == .orderedAscending
        }
    }

    /// Treffer im Text bekommen einen Ausschnitt; Treffer nur im Titel nicht.
    static func filter(_ notes: [Note], query raw: String) -> [Result] {
        let query = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let ordered = sorted(notes)
        guard !query.isEmpty else { return ordered.map { Result(note: $0, snippet: nil) } }
        return ordered.compactMap { note in
            if let range = note.body.range(of: query, options: options) {
                return Result(note: note, snippet: snippet(in: note.body, around: range))
            }
            if note.title.range(of: query, options: options) != nil {
                return Result(note: note, snippet: nil)
            }
            return nil
        }
    }

    static func snippet(in text: String, around range: Range<String.Index>) -> Snippet {
        let start = text.index(range.lowerBound, offsetBy: -context, limitedBy: text.startIndex) ?? text.startIndex
        let end = text.index(range.upperBound, offsetBy: context, limitedBy: text.endIndex) ?? text.endIndex
        func flach(_ teil: Substring) -> String {
            String(teil).replacingOccurrences(of: "\n", with: " ")
                        .replacingOccurrences(of: "\r", with: " ")
        }
        return Snippet(
            before: (start > text.startIndex ? "…" : "") + flach(text[start..<range.lowerBound]),
            match: String(text[range]),
            after: flach(text[range.upperBound..<end]) + (end < text.endIndex ? "…" : ""))
    }

    /// Zeilen ohne Markdown-Zeichen, hintereinander, höchstens 120 Zeichen.
    static func preview(_ body: String) -> String {
        let text = body.split(whereSeparator: \.isNewline)
            .map(NoteFile.cleanLine)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return String(text.prefix(120))
    }
}
