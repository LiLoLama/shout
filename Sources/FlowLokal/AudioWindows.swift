import Foundation

/// Teilt eine lange Aufnahme in Fenster, die einzeln zu einem
/// Transkriptions-Endpunkt passen.
///
/// **Warum das nötig ist:** Die Endpunkte begrenzen die Dateigröße (bei OpenAI
/// 25 MB). WAV mit 16 kHz, Mono, 16 bit sind 32.000 Byte je Sekunde — die Grenze
/// liegt damit bei rund 13 Minuten. Fürs Diktat ist das folgenlos, für die
/// Datei-Transkription nicht: Dort sind Aufnahmen von einer Stunde der Normalfall.
///
/// **Geschnitten wird an der leisesten Stelle** innerhalb der letzten Sekunden
/// des Fensters, nicht stur nach der Uhr. Ein Schnitt in einer Sprechpause
/// kostet nichts; ein Schnitt mitten im Wort kostet das Wort.
///
/// **Bewusst ohne Überlappung.** Eine Überlappung würde die Sekunden am Übergang
/// zweimal transkribieren, und dann müsste eine Heuristik die Doppelung wieder
/// entfernen — die kann echten Inhalt verwerfen, und das ist der eine Fehler,
/// den dieses Programm nicht machen darf. Der Preis: Findet sich im Suchbereich
/// gar keine Pause (durchgehendes Sprechen über zehn Minuten), kann ein einzelnes
/// Wort am Übergang verstümmelt werden. Das ist selten und sichtbar, während
/// stiller Inhaltsverlust weder das eine noch das andere ist.
enum AudioWindows {

    struct Window: Equatable {
        /// Bereich im Sample-Puffer.
        let range: Range<Int>
        /// Zeitversatz des Fensters im Gesamtaudio, in Sekunden. Die Zeitmarken
        /// der Segmente aus diesem Fenster werden darum verschoben.
        let offsetSeconds: Double
    }

    /// Rahmenlänge der Lautstärkemessung: 20 ms, dasselbe Raster, in dem
    /// Whisper seine Zeitmarken setzt.
    private static let frameSeconds = 0.02

    /// - Parameters:
    ///   - maxSeconds: Höchstlänge eines Fensters. Voreinstellung 10 Minuten —
    ///     mit Sicherheitsabstand unter den ~13 Minuten der 25-MB-Grenze.
    ///   - searchSeconds: Wie weit vom Fensterende aus nach einer Pause gesucht wird.
    static func split(_ samples: [Float],
                      sampleRate: Int = 16_000,
                      maxSeconds: Double = 600,
                      searchSeconds: Double = 15) -> [Window] {
        guard !samples.isEmpty else { return [] }

        let maxLength = Int(maxSeconds * Double(sampleRate))
        guard maxLength > 0, samples.count > maxLength else {
            return [Window(range: 0..<samples.count, offsetSeconds: 0)]
        }

        var fenster: [Window] = []
        var start = 0
        while start < samples.count {
            let rest = samples.count - start
            if rest <= maxLength {
                fenster.append(Window(range: start..<samples.count,
                                      offsetSeconds: Double(start) / Double(sampleRate)))
                break
            }
            let hartesEnde = start + maxLength
            let suchBeginn = max(start + 1, hartesEnde - Int(searchSeconds * Double(sampleRate)))
            let schnitt = quietestPoint(in: samples, from: suchBeginn, to: hartesEnde,
                                        sampleRate: sampleRate)
            fenster.append(Window(range: start..<schnitt,
                                  offsetSeconds: Double(start) / Double(sampleRate)))
            start = schnitt
        }
        return fenster
    }

    /// Mitte des leisesten 20-ms-Rahmens im Bereich. Bei Gleichstand gewinnt der
    /// spätere Rahmen — so werden die Fenster nicht unnötig kurz.
    private static func quietestPoint(in samples: [Float], from: Int, to: Int,
                                      sampleRate: Int) -> Int {
        let frame = max(1, Int(frameSeconds * Double(sampleRate)))
        guard to - from > frame else { return to }

        var bestesEnergie = Float.greatestFiniteMagnitude
        var besterIndex = to

        var i = from
        while i + frame <= to {
            var energie: Float = 0
            for j in i..<(i + frame) { energie += samples[j] * samples[j] }
            if energie <= bestesEnergie {
                bestesEnergie = energie
                besterIndex = i + frame / 2
            }
            i += frame
        }
        return besterIndex
    }
}
