import XCTest

/// Whisper hängt an Diktate gern ein „Vielen Dank." an, das nie gesagt wurde —
/// eine Untertitel-Floskel aus seinen Trainingsdaten, erfunden in der Stille am
/// Ende der Aufnahme. Im Verlauf stand das in 21 von 300 Diktaten im ROHTEXT.
/// Gestrichen wird nur, wenn im Zeitraum der Floskel kaum Sprache zu hören ist:
/// Ein gesprochenes „Vielen Dank" muss bleiben.
final class PhantomClosingTests: XCTestCase {

    private let rate = 16_000

    /// Audio aus Abschnitten: `true` = Sprache (lauter Ton), `false` = Stille
    /// mit leichtem Grundrauschen. Dauer jeweils in Sekunden.
    private func audio(_ parts: [(Bool, Double)]) -> [Float] {
        var out: [Float] = []
        for (speech, seconds) in parts {
            let n = Int(seconds * Double(rate))
            for i in 0..<n {
                if speech {
                    out.append(0.2 * sinf(Float(i) * 2 * .pi * 220 / Float(rate)))
                } else {
                    // Grundrauschen deutlich unter der Sprachschwelle.
                    out.append(i % 2 == 0 ? 0.001 : -0.001)
                }
            }
        }
        return out
    }

    private func seg(_ text: String, _ start: Double, _ end: Double) -> TranscriptSegment {
        TranscriptSegment(text: text, start: start, end: end)
    }

    // MARK: - Streichen

    func testErfundeneFloskelInDerStilleWirdGestrichen() {
        let samples = audio([(true, 8), (false, 2)])
        let text = "Kannst du da nochmal schauen? Vielen Dank."
        let segments = [seg(" Kannst du da nochmal schauen?", 0, 8), seg(" Vielen Dank.", 8.1, 10)]
        XCTAssertEqual(TranscriptPlausibility.withoutPhantomClosing(text: text, segments: segments, samples: samples),
                       "Kannst du da nochmal schauen?")
    }

    /// Ohne Punkt davor — so stand es mehrfach im Verlauf („…selber machen Vielen Dank").
    func testFloskelAlsEigenesFensterOhnePunktDavor() {
        let samples = audio([(true, 8), (false, 2)])
        let text = "Das kann ich komplett selber machen Vielen Dank"
        let segments = [seg("Das kann ich komplett selber machen", 0, 8), seg("Vielen Dank", 8.2, 9.8)]
        XCTAssertEqual(TranscriptPlausibility.withoutPhantomClosing(text: text, segments: segments, samples: samples),
                       "Das kann ich komplett selber machen")
    }

    /// Whisper setzt die erfundene Floskel gern in das aufgefüllte Fenster HINTER
    /// das Ende der Aufnahme — dort ist per Definition nichts gesprochen.
    func testFloskelHinterDemAudioendeWirdGestrichen() {
        let samples = audio([(true, 6)])
        let text = "Das passt so. Bis zum nächsten Mal."
        let segments = [seg("Das passt so.", 0, 5.9), seg("Bis zum nächsten Mal.", 6.0, 8.0)]
        XCTAssertEqual(TranscriptPlausibility.withoutPhantomClosing(text: text, segments: segments, samples: samples),
                       "Das passt so.")
    }

    func testUntertitelZeileWirdGestrichen() {
        let samples = audio([(true, 5), (false, 3)])
        let text = "Termin ist am Montag. Untertitel im Auftrag des ZDF, 2020"
        let segments = [seg("Termin ist am Montag.", 0, 5), seg("Untertitel im Auftrag des ZDF, 2020", 5.2, 8)]
        XCTAssertEqual(TranscriptPlausibility.withoutPhantomClosing(text: text, segments: segments, samples: samples),
                       "Termin ist am Montag.")
    }

    // MARK: - Stehen lassen

    func testGesprochenesVielenDankBleibt() {
        let samples = audio([(true, 8), (false, 0.3), (true, 0.8), (false, 0.5)])
        let text = "Kannst du da nochmal schauen? Vielen Dank."
        let segments = [seg("Kannst du da nochmal schauen?", 0, 8), seg("Vielen Dank.", 8.3, 9.2)]
        XCTAssertEqual(TranscriptPlausibility.withoutPhantomClosing(text: text, segments: segments, samples: samples),
                       text)
    }

    /// Steckt die Floskel im selben Abschnitt wie echter Text, lässt sich ihr
    /// Zeitraum nicht abgrenzen — dann lieber nichts anfassen.
    func testFloskelImSelbenAbschnittBleibt() {
        let samples = audio([(true, 8), (false, 2)])
        let text = "Kannst du da nochmal schauen? Vielen Dank."
        let segments = [seg("Kannst du da nochmal schauen? Vielen Dank.", 0, 10)]
        XCTAssertEqual(TranscriptPlausibility.withoutPhantomClosing(text: text, segments: segments, samples: samples),
                       text)
    }

    func testAndererSchlusssatzInDerStilleBleibt() {
        let samples = audio([(true, 8), (false, 2)])
        let text = "Das ist der Plan. Das ist der Gedanke dahinter."
        let segments = [seg("Das ist der Plan.", 0, 8), seg("Das ist der Gedanke dahinter.", 8.1, 10)]
        XCTAssertEqual(TranscriptPlausibility.withoutPhantomClosing(text: text, segments: segments, samples: samples),
                       text, "Nur bekannte Floskeln — echter Text wird nie anhand der Lautstärke gestrichen")
    }

    func testOhneAbschnitteUnveraendert() {
        let samples = audio([(true, 8), (false, 2)])
        XCTAssertEqual(TranscriptPlausibility.withoutPhantomClosing(text: "Hallo. Vielen Dank.", segments: [], samples: samples),
                       "Hallo. Vielen Dank.")
    }

    /// Passt das Textende nicht zum letzten Abschnitt, wäre das Abschneiden ein
    /// Raten — der Text bleibt.
    func testTextendePasstNichtZumAbschnitt() {
        let samples = audio([(true, 8), (false, 2)])
        let text = "Kannst du da nochmal schauen?"
        let segments = [seg("Kannst du da nochmal schauen?", 0, 8), seg("Vielen Dank.", 8.1, 10)]
        XCTAssertEqual(TranscriptPlausibility.withoutPhantomClosing(text: text, segments: segments, samples: samples),
                       text)
    }
}
