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
    /// Sprechpause, auf Wunsch eine Zeitmarke am Anfang jedes Absatzes.
    ///
    /// Alles in einen Absatz zu hängen ist die naheliegende, aber schlechteste
    /// Variante — bei einer Stunde Audio steht dann eine Wand aus Text da. Die
    /// Segmentgrenzen sind ohnehin da, und die Pausen im Gesprochenen sind die
    /// ehrlichste verfügbare Gliederung.
    ///
    /// `timestamps` ist beim Anzeigen an und für den Eingang ins Sprachmodell aus:
    /// Dort kosteten die Marken nur Kontext und tauchten am Ende im Protokoll wieder auf.
    /// `speakerLabel` baut aus der Sprechernummer die Anrede („Sprecher 1"). Als
    /// Funktion übergeben, damit diese Datei nichts von `Loc` wissen muss und rein
    /// testbar bleibt. Ohne sie erscheinen keine Sprecher.
    static func rawText(from segments: [TranscriptSegment],
                        paragraphGap: Double = paragraphGap,
                        timestamps: Bool = false,
                        speakerLabel: ((Int) -> String)? = nil) -> String {
        var lines: [String] = []
        var previousEnd: Double?
        var previousSpeaker: Int?

        for segment in segments {
            let text = stripSpecialTokens(segment.text)
            guard !text.isEmpty else { continue }
            let speaker = speakerLabel == nil ? nil : segment.speaker

            // Neuer Absatz bei längerer Pause ODER bei Sprecherwechsel — sonst klebt
            // die Antwort an der Frage. Der Vergleich läuft gegen das letzte
            // übernommene Segment, nicht gegen ein übersprungenes leeres.
            let pause = previousEnd.map { segment.start - $0 >= paragraphGap } ?? true
            let changed = previousEnd != nil && speaker != previousSpeaker
            let newParagraph = pause || changed
            if newParagraph, previousEnd != nil { lines.append("") }

            var line = text
            if newParagraph, let speaker, let speakerLabel {
                line = "\(speakerLabel(speaker)): \(line)"
            }
            if newParagraph, timestamps {
                line = "[\(timecode(segment.start))] \(line)"
            }
            lines.append(line)
            previousEnd = segment.end
            previousSpeaker = speaker
        }
        return lines.joined(separator: "\n")
    }

    /// „2:04" bzw. „1:02:05" — kurz genug, um vor jedem Absatz zu stehen.
    static func timecode(_ seconds: Double) -> String {
        let total = Int(max(0, seconds))
        return total >= 3600
            ? String(format: "%d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
            : String(format: "%d:%02d", total / 60, total % 60)
    }
}
