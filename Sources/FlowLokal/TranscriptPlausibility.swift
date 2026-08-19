import Foundation

/// Prüft, ob ein Whisper-Ergebnis plausibel zur Aufnahme passt — ohne WhisperKit,
/// damit die Entscheidung für sich testbar ist.
///
/// Hintergrund: Der Wörterbuch-Prompt (`promptTokens`) macht Whisper bei
/// Eigennamen treffsicherer, kann es aber auch dazu bringen, Audio zu
/// überspringen — im Extremfall alles, häufiger nur den Anfang. Erkennen wir das,
/// läuft ein zweiter Durchgang ohne Prompt und das längere Ergebnis gewinnt.
enum TranscriptPlausibility {

    /// Hat Whisper den Anfang verschluckt?
    ///
    /// Die Samples erreichen Whisper getrimmt: `AudioRecorder.trimSilence`
    /// schneidet auf 300 ms vor dem ersten Fenster mit Sprachenergie. Im Audio
    /// wird also ab etwa Sekunde 0,3 gesprochen. Beginnt Whispers erster
    /// Abschnitt trotzdem deutlich später, hat es diesen Teil übersprungen —
    /// und genau das ist als fehlendes erstes Drittel zu lesen.
    ///
    /// Anders als eine Textlängen-Regel hängt das an keiner Sprechgeschwindigkeit:
    /// ein Versatz von Sekunden ist ein Versatz, egal wie dicht gesprochen wurde.
    static func swallowedStart(firstSegmentStart: Double?, audioSeconds: Double) -> Bool {
        // Winzige Schnipsel nicht bewerten: dort ist eine Sekunde Versatz das
        // Zeitmarken-Raster, kein verlorener Satz.
        guard audioSeconds >= 1.5, let start = firstSegmentStart else { return false }
        // 300 ms Sicherheitsrand aus dem Trimmen, Whispers Zeitmarken laufen in
        // 20-ms-Schritten und die erste Marke sitzt gern etwas hinter dem Einsatz.
        // Über einer Sekunde ist davon nichts mehr zu erklären.
        return start > 1.0
    }

    /// Deutlich zu wenig Text für die Audiolänge — der Fall, in dem Whisper nicht
    /// nur den Anfang, sondern fast alles ausgelassen hat.
    ///
    /// Echte Diktate liegen bei 13–14 Zeichen je Sekunde. Die Grenze steht mit
    /// Absicht sehr tief bei 3: Sie soll den Totalausfall fangen, ohne bei
    /// langsamem Sprechen oder langen Denkpausen unnötig einen zweiten Durchgang
    /// auszulösen. Den teilweisen Verlust erkennt `swallowedStart`.
    static func tooLittleText(characters: Int, audioSeconds: Double) -> Bool {
        guard audioSeconds > 5 else { return false }
        return Double(characters) < audioSeconds * 3
    }
}
