import Foundation

/// Bringt Whisper-Segmente in eine Form, die man lesen mag.
///
/// Zwei Aufgaben, die beide aus derselben Beobachtung entstanden sind: Der
/// Segmenttext von WhisperKit ist NICHT der saubere Text, den `TranscriptionResult.text`
/// liefert. Er enthält die Steuermarken des Modells (`<|de|>`, `<|0.00|>`,
/// `<|endoftext|>` …), und aneinandergehängt ergibt er eine einzige Textwurst.
enum TranscriptLayout {

    /// Pause zwischen zwei Segmenten, ab der ein neuer Absatz beginnt.
    static let paragraphGap: Double = 1.5

    /// Entfernt Whisper-Steuermarken der Form `<|…|>`.
    ///
    /// `DecodingOptions.skipSpecialTokens` steht schon auf `true` — das hier ist der
    /// Gürtel zum Hosenträger: Die Marken sind für einen Nutzer schlicht Müll, und
    /// sie landen sonst nicht nur im Text, sondern auch in den Untertiteln.
    static func stripSpecialTokens(_ text: String) -> String {
        let withoutTokens = text.replacingOccurrences(
            of: "<\\|.*?\\|>", with: " ", options: .regularExpression)
        // Nach dem Entfernen bleiben Leerzeichen-Nester zurück.
        return withoutTokens
            .replacingOccurrences(of: "[ \\t]+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Baut das Rohtranskript: eine Zeile je Segment, Leerzeile bei einer längeren
    /// Sprechpause.
    ///
    /// Alles in einen Absatz zu hängen ist die naheliegende, aber schlechteste
    /// Variante — bei einer Stunde Audio steht dann eine Wand aus Text da. Die
    /// Segmentgrenzen sind ohnehin da, und die Pausen im Gesprochenen sind die
    /// ehrlichste verfügbare Gliederung.
    static func rawText(from segments: [TranscriptSegment], paragraphGap: Double = paragraphGap) -> String {
        var lines: [String] = []
        var previousEnd: Double?

        for segment in segments {
            let text = stripSpecialTokens(segment.text)
            guard !text.isEmpty else { continue }
            // Absatz nur zwischen zwei ECHTEN Zeilen — der Vergleich läuft gegen das
            // letzte übernommene Segment, nicht gegen ein übersprungenes leeres.
            if let end = previousEnd, segment.start - end >= paragraphGap {
                lines.append("")
            }
            lines.append(text)
            previousEnd = segment.end
        }
        return lines.joined(separator: "\n")
    }
}
