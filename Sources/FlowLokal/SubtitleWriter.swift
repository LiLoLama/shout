import Foundation

/// Schreibt Transkript-Abschnitte als SubRip-Untertitel (.srt).
///
/// Die Untertitel entstehen IMMER aus dem Rohtranskript. Sobald das Formatierungs-
/// Modell Füllwörter entfernt und Sätze umbaut, passt der Wortlaut nicht mehr zu
/// den Zeitmarken — dann wären die Untertitel schlicht falsch.
enum SubtitleWriter {

    /// SRT-Text für die Segmente. Leere Segmente werden übersprungen; die
    /// Nummerierung bleibt trotzdem lückenlos, weil manche Abspieler bei Lücken
    /// die restliche Datei verwerfen.
    static func srt(from segments: [TranscriptSegment]) -> String {
        var out = ""
        var index = 1
        for segment in segments {
            let text = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            out += "\(index)\n"
            out += "\(timecode(segment.start)) --> \(timecode(max(segment.end, segment.start)))\n"
            out += "\(text)\n\n"
            index += 1
        }
        return out
    }

    /// „HH:MM:SS,mmm" — Millisekunden mit Komma, wie SubRip es verlangt (ein
    /// Punkt statt des Kommas ist der häufigste Grund, warum eine .srt stumm bleibt).
    static func timecode(_ seconds: Double) -> String {
        let totalMs = Int((max(0, seconds) * 1000).rounded())
        let ms = totalMs % 1000
        let total = totalMs / 1000
        return String(format: "%02d:%02d:%02d,%03d", total / 3600, (total % 3600) / 60, total % 60, ms)
    }
}
