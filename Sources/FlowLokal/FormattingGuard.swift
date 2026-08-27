import Foundation

/// Prüft, ob die Ausgabe der Aufbereitung wirklich eine Formatierung der Eingabe
/// ist — ohne MLX, damit die Entscheidung für sich testbar ist.
///
/// Hintergrund: Ein Diktat, das wie eine Bitte klingt („Könntest du bitte das
/// suchen und einfügen?"), wird von einem kleinen Modell gelegentlich als Auftrag
/// an sich selbst gelesen. Es antwortet dann („Bitte gib mir den Text, den ich
/// formatieren soll") statt zu formatieren, und diese Antwort landet im Dokument.
/// Gegen die Ursache steht der Prompt (Transkript in Markierungen, ausdrücklich
/// als Daten); das hier ist das Netz dahinter.
enum FormattingGuard {

    enum Verdict: Equatable {
        case ok
        /// Die Ausgabe besteht überwiegend aus Wörtern, die nie diktiert wurden:
        /// Das Modell hat geantwortet, statt zu formatieren.
        case unrelated(inputSharePercent: Int)
        /// Inhaltlich passend, aber drastisch gekürzt — Ende verschluckt.
        case truncated(inWords: Int, outWords: Int)
    }

    /// Anteil der AUSGABE-Wörter, die aus dem Diktat stammen müssen.
    ///
    /// Bewusst diese Richtung: Bereinigen darf Wörter WEGLASSEN (Füllwörter, und
    /// bei kurzen Diktaten schnell die Hälfte), aber keine erfinden. Deshalb ist
    /// „wie viel der Ausgabe stammt aus der Eingabe" der belastbare Maßstab, nicht
    /// „wie viel der Eingabe steht noch in der Ausgabe" — letzteres fällt bei
    /// „also äh das ist gut ja wirklich gut" → „Das ist gut." legitim auf 43 %.
    ///
    /// Eine Antwort des Modells liegt fast vollständig daneben (bei den vier
    /// echten Fehlfällen im Verlauf: 0–27 % gemeinsame Wörter). Listen-Umbau
    /// kostet ein paar Prozent, weil „1." und „2." neue Wörter sind.
    private static let minInputShare = 0.50
    /// Erst ab dieser Wortzahl im Diktat ist der Vergleich aussagekräftig.
    private static let minWordsForShare = 5
    /// Kürzungs-Prüfung erst ab hier — bei kürzeren Diktaten ist die halbe
    /// Wortzahl schnell erreicht, ohne dass Inhalt fehlt.
    private static let minWordsForLength = 30

    static func check(input: String, output: String) -> Verdict {
        let inTokens = tokens(of: input)
        guard inTokens.count >= minWordsForShare else { return .ok }

        let outTokens = tokens(of: output)
        guard !outTokens.isEmpty else { return .unrelated(inputSharePercent: 0) }

        let share = Double(outTokens.intersection(inTokens).count) / Double(outTokens.count)
        if share < minInputShare {
            return .unrelated(inputSharePercent: Int((share * 100).rounded()))
        }

        // Wortzahlen, nicht Token-Mengen: Wiederholungen zählen hier mit.
        let inWords = input.split(whereSeparator: \.isWhitespace).count
        let outWords = output.split(whereSeparator: \.isWhitespace).count
        if inWords >= minWordsForLength, outWords * 100 < inWords * 55 {
            return .truncated(inWords: inWords, outWords: outWords)
        }
        return .ok
    }

    /// Wörter in Kleinschreibung, ohne Satzzeichen — Interpunktion und
    /// Groß-/Kleinschreibung setzt die Aufbereitung ja gerade neu und darf nicht
    /// gegen sie zählen.
    private static func tokens(of s: String) -> Set<String> {
        Set(s.lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
            .filter { !$0.isEmpty })
    }
}
