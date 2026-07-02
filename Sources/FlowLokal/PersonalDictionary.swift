import Foundation
import Combine

/// Persönliches Wörterbuch für shout.
///
/// Zwei Bestandteile:
///  - `terms`: Eigennamen/Fachbegriffe. Werden dem Formatting-LLM als „exakt so
///    schreiben"-Hinweis mitgegeben (und später als Whisper-Bias).
///  - `corrections`: gelernte Paare falsch→richtig. Werden nach dem Transkript
///    automatisch ersetzt (wortgenau, Groß-/Kleinschreibung egal).
///
/// Persistenz als JSON in ~/Library/Application Support/shout/dictionary.json.
@MainActor
final class PersonalDictionary: ObservableObject {

    struct Correction: Codable, Equatable, Identifiable {
        var id: String { "\(wrong)→\(right)" }
        var wrong: String
        var right: String
    }

    struct Contents: Codable {
        var terms: [String] = []
        var corrections: [Correction] = []
    }

    @Published private(set) var contents = Contents()

    private let fileURL: URL

    init() {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("shout", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("dictionary.json")
        load()
    }

    // MARK: - Persistenz

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode(Contents.self, from: data) else { return }
        contents = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(contents) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    // MARK: - Begriffe

    func addTerm(_ term: String) {
        let t = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty,
              !contents.terms.contains(where: { $0.caseInsensitiveCompare(t) == .orderedSame }) else { return }
        contents.terms.append(t)
        save()
    }

    func removeTerm(_ term: String) {
        contents.terms.removeAll { $0 == term }
        save()
    }

    // MARK: - Korrekturen

    /// Fügt eine Korrektur hinzu (bzw. aktualisiert sie) und hinterlegt die
    /// richtige Schreibweise gleich als Begriff.
    func addCorrection(wrong: String, right: String) {
        let w = wrong.trimmingCharacters(in: .whitespacesAndNewlines)
        let r = right.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !w.isEmpty, !r.isEmpty, w.caseInsensitiveCompare(r) != .orderedSame else { return }
        contents.corrections.removeAll { $0.wrong.caseInsensitiveCompare(w) == .orderedSame }
        contents.corrections.append(Correction(wrong: w, right: r))
        addTerm(r)   // ruft save()
    }

    func removeCorrection(_ correction: Correction) {
        contents.corrections.removeAll { $0 == correction }
        save()
    }

    // MARK: - Anwendung

    /// Ersetzt bekannte Falsch-Schreibungen wortgenau (case-insensitive) durch die
    /// korrekte Form. Wird auf den fertigen Text angewendet.
    func applyCorrections(to text: String) -> String {
        var result = text
        for c in contents.corrections {
            let pattern = "\\b\(NSRegularExpression.escapedPattern(for: c.wrong))\\b"
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(
                in: result, options: [], range: range,
                withTemplate: NSRegularExpression.escapedTemplate(for: c.right)
            )
        }
        return result
    }

    /// Begriffe als Hinweis-Zeile für den Formatting-Prompt (oder nil, wenn leer).
    var termHint: String? {
        contents.terms.isEmpty ? nil : contents.terms.joined(separator: ", ")
    }
}
