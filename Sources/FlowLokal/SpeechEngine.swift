import Foundation

/// Ergebnis einer Spracherkennung.
///
/// `text` und `segments` sind absichtlich getrennt und **nicht** dasselbe:
/// WhisperKit filtert die Steuermarken (`<|de|>`, `<|0.00|>`, `<|endoftext|>`)
/// in `TranscriptionResult.text` anders als in den Segment-Texten, weshalb das
/// Diktat schon immer den einen und die Datei-Transkription den anderen Weg
/// nimmt. Bei Anbietern kommt hinzu, dass manche überhaupt keine Zeitmarken
/// liefern — dann gibt es ein Ersatzsegment über die Gesamtlänge, und `.srt`
/// wird unbrauchbar, während das Diktat weiter funktioniert.
struct SpeechResult: Sendable {
    /// Fertige Fassung, wie sie das Diktat einfügt.
    let text: String
    /// Abschnitte mit Zeitmarken — Grundlage für Untertitel.
    let segments: [TranscriptSegment]
}

/// Ein Spracherkenner. Lokal ist das WhisperKit im eigenen Prozess, extern ein
/// OpenAI-kompatibler `/v1/audio/transcriptions`-Endpunkt.
///
/// Alles, was nicht die Erkennung selbst ist, bleibt im Router `Transcriber`:
/// die Sprachwahl aus den Einstellungen und der Plausibilitäts-Wachhund. Damit
/// gelten beide für jeden Erkenner.
protocol SpeechEngine: Actor {

    var isReady: Bool { get }

    /// Für die Oberfläche, z. B. „Whisper Turbo" oder „whisper-large-v3 · Groq".
    var displayName: String { get }

    /// Lädt bzw. verbindet. `reset` erzwingt einen Neuaufbau (Modellwechsel zur
    /// Laufzeit). Wirft, damit der Aufrufer den Status korrekt setzen und
    /// gegebenenfalls zurückrollen kann — so war es schon vor der Extraktion.
    func prepare(reset: Bool, onProgress: (@Sendable (Double) -> Void)?) async throws

    /// „Aufwärmen", damit das erste echte Diktat nicht spürbar länger dauert.
    /// Die Sprache kommt vom Router mit, damit dasselbe aufgewärmt wird, was
    /// danach auch läuft (bei fester Sprache entfällt die Erkennungsstufe).
    /// Bei einem Anbieter absichtlich wirkungslos: Stille hochzuladen würde
    /// Geld kosten und nichts beschleunigen.
    func warmUp(language: String?) async

    /// `language`: ISO-Kürzel, oder `nil` für automatische Erkennung.
    func transcribe(samples: [Float], language: String?) async throws -> SpeechResult
}
