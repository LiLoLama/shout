import Foundation

/// Ein Zeitabschnitt, in dem laut Sprechertrennung eine bestimmte Person spricht.
///
/// Eigener Typ statt SpeakerKits `SpeakerSegment`, damit die Zuordnung eine reine
/// Funktion bleibt und ohne CoreML-Modelle testbar ist.
struct SpeakerRange: Sendable, Equatable {
    let speaker: Int
    let start: Double
    let end: Double
}

/// Ordnet den Transkript-Segmenten Sprecher zu.
///
/// Whisper und Pyannote schneiden unabhängig voneinander — ihre Grenzen fallen nie
/// exakt zusammen. Deshalb gewinnt pro Segment der Sprecher mit der größten
/// zeitlichen Überlappung, nicht der zufällig erste.
enum SpeakerAssignment {

    /// Weist jedem Segment den überlappungsstärksten Sprecher zu. Ohne Überlappung
    /// bleibt der Sprecher offen — ein falsches Label wäre schlimmer als keines.
    ///
    /// `renumber` vergibt fortlaufende Nummern in der Reihenfolge des ersten
    /// Auftretens: Pyannote nummeriert seine Cluster beliebig (0, 4, 7 …), in der
    /// Anzeige soll aber „Sprecher 1" der sein, der zuerst spricht.
    static func assign(_ ranges: [SpeakerRange], to segments: [TranscriptSegment],
                       renumber: Bool = true) -> [TranscriptSegment] {
        guard !ranges.isEmpty else { return segments }

        var mapping: [Int: Int] = [:]   // Cluster-Nummer → Anzeigenummer
        var next = 1

        return segments.map { segment in
            var best: (speaker: Int, overlap: Double)?
            for range in ranges {
                let overlap = min(segment.end, range.end) - max(segment.start, range.start)
                guard overlap > 0 else { continue }
                if best == nil || overlap > best!.overlap { best = (range.speaker, overlap) }
            }
            guard let winner = best?.speaker else { return segment }

            let number: Int
            if renumber {
                if let known = mapping[winner] {
                    number = known
                } else {
                    number = next
                    mapping[winner] = next
                    next += 1
                }
            } else {
                number = winner
            }
            return TranscriptSegment(text: segment.text, start: segment.start,
                                     end: segment.end, speaker: number)
        }
    }
}
