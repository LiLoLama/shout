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
        fileURL = StoreIO.directory().appendingPathComponent("dictionary.json")
        if let decoded = StoreIO.load(Contents.self, from: fileURL) { contents = decoded }
    }

    // MARK: - Persistenz

    private func save() {
        StoreIO.save(contents, to: fileURL)
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

    /// Ersetzt den kompletten Inhalt (für Import).
    func replaceContents(_ newContents: Contents) {
        contents = newContents
        save()
    }

    // MARK: - Anwendung

    /// Ersetzt bekannte Falsch-Schreibungen wortgenau (case-insensitive) durch die
    /// korrekte Form. Wird auf den fertigen Text angewendet.
    func applyCorrections(to text: String) -> String {
        var result = text
        for c in contents.corrections {
            // \b nur dort ansetzen, wo der Begriff mit einem Wortzeichen beginnt/endet.
            // Sonst (z. B. „C#", „.NET", „§14") würde \b nie matchen und die Korrektur
            // liefe stillschweigend ins Leere.
            func isWordChar(_ ch: Character?) -> Bool {
                guard let ch else { return false }
                return ch.isLetter || ch.isNumber || ch == "_"
            }
            let lead = isWordChar(c.wrong.first) ? "\\b" : ""
            let trail = isWordChar(c.wrong.last) ? "\\b" : ""
            let pattern = "\(lead)\(NSRegularExpression.escapedPattern(for: c.wrong))\(trail)"
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
