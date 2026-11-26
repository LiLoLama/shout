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

    // MARK: - Erfundene Schlussfloskel

    /// Streicht eine Schlussfloskel, die Whisper in der Stille am Ende erfunden hat.
    ///
    /// Whisper ist zu großen Teilen auf Video-Untertiteln trainiert, und die enden
    /// mit „Vielen Dank fürs Zuschauen" oder „Untertitel im Auftrag des ZDF". Bleibt
    /// am Ende der Aufnahme ein stiller Rest (Atemzug, Tastenklick beim Beenden,
    /// das auf 30 s aufgefüllte Fenster), schreibt es dort gern so eine Zeile hin.
    /// Im Verlauf stand am 26.11.2026 in 21 von 300 Diktaten ein nie gesagtes
    /// „Vielen Dank." schon im Rohtext.
    ///
    /// Gestrichen wird nur, wenn BEIDES zutrifft:
    /// - Der letzte Abschnitt besteht allein aus einer bekannten Floskel. Echter
    ///   Text wird nie wegen geringer Lautstärke angefasst.
    /// - In seinem Zeitraum ist kaum Sprache im Audio. Ein gesprochenes
    ///   „Vielen Dank" klingt rund eine Sekunde und bleibt damit stehen.
    ///
    /// Passt das Textende nicht genau zu diesem Abschnitt, bleibt der Text, wie er
    /// ist: Abschneiden auf Verdacht wäre schlimmer als die Floskel.
    static func withoutPhantomClosing(text: String,
                                      segments: [TranscriptSegment],
                                      samples: [Float],
                                      sampleRate: Double = 16_000) -> String {
        guard let last = segments.last else { return text }
        let floskel = last.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !floskel.isEmpty, isKnownClosing(floskel) else { return text }

        let gesprochen = speechSeconds(in: samples, from: last.start, to: last.end, sampleRate: sampleRate)
        guard gesprochen < maxPhantomSpeechSeconds else { return text }

        let ganz = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let range = ganz.range(of: floskel, options: [.caseInsensitive, .backwards, .anchored]) else {
            return text
        }
        return String(ganz[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Weniger Sprache als das im Floskel-Zeitraum heißt: nicht gesagt. Ein
    /// gesprochenes „Vielen Dank" bringt ~0,6–0,9 s Sprachenergie; Whispers
    /// Zeitmarken können den Abschnitt ein, zwei Zehntel in den letzten echten
    /// Satz ragen lassen — 0,3 s liegt sicher dazwischen.
    static let maxPhantomSpeechSeconds = 0.3

    /// Floskeln aus Untertiteln, die Whisper in Stille erfindet. Vergleich ohne
    /// Satzzeichen und Groß-/Kleinschreibung.
    private static let knownClosings: Set<String> = [
        "vielen dank", "vielen dank fürs zuschauen", "danke fürs zuschauen",
        "vielen dank für ihre aufmerksamkeit", "danke", "danke schön", "dankeschön",
        "bis zum nächsten mal", "tschüss", "thank you", "thanks for watching",
        "thank you for watching",
    ]

    static func isKnownClosing(_ text: String) -> Bool {
        let ohneZeichen = text.lowercased().unicodeScalars
            .map { CharacterSet.punctuationCharacters.contains($0) ? " " : String($0) }
            .joined()
        let norm = ohneZeichen.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        // „Untertitel im Auftrag des ZDF, 2020", „Untertitelung des ZDF",
        // „Untertitel der Amara.org-Community" — alle Varianten über den Anfang.
        return knownClosings.contains(norm) || norm.hasPrefix("untertitel")
    }

    /// Sekunden mit Sprachenergie im Zeitraum — dieselbe Schwelle wie
    /// `AudioRecorder.trimSilence` (10 % des Spitzenwerts, geklemmt auf
    /// 0,004–0,012), in 30-ms-Fenstern. Ein Zeitraum hinter dem Audioende
    /// (Whispers aufgefülltes Fenster) hat keine.
    static func speechSeconds(in samples: [Float], from start: Double, to end: Double,
                              sampleRate: Double = 16_000) -> Double {
        let window = Int(sampleRate * 0.03)
        guard window > 0, !samples.isEmpty else { return 0 }

        func rms(_ von: Int, _ bis: Int) -> Float {
            var sum: Float = 0
            for j in von..<bis { sum += samples[j] * samples[j] }
            return (sum / Float(bis - von)).squareRoot()
        }

        var peak: Float = 0
        var i = 0
        while i < samples.count {
            peak = max(peak, rms(i, min(i + window, samples.count)))
            i += window
        }
        let threshold = min(max(0.004, peak * 0.10), 0.012)

        let von = max(0, min(samples.count, Int(start * sampleRate)))
        let bis = max(von, min(samples.count, Int(end * sampleRate)))
        var aktiv = 0
        i = von
        while i < bis {
            let ende = min(i + window, bis)
            if rms(i, ende) > threshold { aktiv += ende - i }
            i += window
        }
        return Double(aktiv) / sampleRate
    }
}
