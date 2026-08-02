import Foundation

/// Ein Abschnitt eines Transkripts mit Zeitmarken in Sekunden ab Dateibeginn.
///
/// Bewusst ein eigener Typ statt WhisperKits `TranscriptionSegment`: So kommen
/// `SubtitleWriter` und die Tests ohne den Modell-Stack aus, und die Zeitmarken
/// lassen sich beim blockweisen Lesen verschieben, ohne WhisperKit-Typen zu kopieren.
struct TranscriptSegment: Sendable, Equatable {
    let text: String
    let start: Double
    let end: Double

    /// Verschiebt die Zeitmarken um den Startzeitpunkt des Blocks, aus dem das
    /// Segment stammt — aus „Sekunde 3 im Block" wird „Sekunde 123 in der Datei".
    func offset(by seconds: Double) -> TranscriptSegment {
        TranscriptSegment(text: text, start: start + seconds, end: end + seconds)
    }
}
