import XCTest

final class TranscriptLayoutTests: XCTestCase {

    // MARK: - Steuermarken

    /// Genau der Fall aus einer echten Datei-Transkription: Whisper dekodiert
    /// Start-, Sprach- und Zeitmarken in den Segmenttext hinein.
    func testEntferntSteuermarkenAmAnfang() {
        let roh = "<|startoftranscript|><|de|><|transcribe|><|0.00|> Ich spür's, da guß da kommt.<|4.00|>"
        XCTAssertEqual(TranscriptLayout.stripSpecialTokens(roh), "Ich spür's, da guß da kommt.")
    }

    func testSegmentAusReinenSteuermarkenWirdLeer() {
        let roh = "<|startoftranscript|><|de|><|transcribe|><|0.00|><|endoftext|>"
        XCTAssertEqual(TranscriptLayout.stripSpecialTokens(roh), "")
    }

    func testTextZwischenMarkenBleibtVollstaendig() {
        let roh = "<|0.00|> Erster Teil.<|4.00|> <|4.00|> Zweiter Teil.<|8.00|>"
        XCTAssertEqual(TranscriptLayout.stripSpecialTokens(roh), "Erster Teil. Zweiter Teil.")
    }

    func testNormalerTextBleibtUnveraendert() {
        let text = "Ein ganz normaler Satz ohne Marken."
        XCTAssertEqual(TranscriptLayout.stripSpecialTokens(text), text)
    }

    /// Nach dem Entfernen bleiben sonst doppelte Leerzeichen stehen.
    func testMehrfacheLeerzeichenWerdenZusammengezogen() {
        XCTAssertEqual(TranscriptLayout.stripSpecialTokens("Eins <|1.00|>  <|2.00|> Zwei"), "Eins Zwei")
    }

    // MARK: - Gliederung

    private func seg(_ text: String, _ start: Double, _ end: Double) -> TranscriptSegment {
        TranscriptSegment(text: text, start: start, end: end)
    }

    func testJedesSegmentEigeneZeile() {
        let segments = [seg("Erste Zeile", 0, 4), seg("Zweite Zeile", 4, 8)]
        XCTAssertEqual(TranscriptLayout.rawText(from: segments), "Erste Zeile\nZweite Zeile")
    }

    /// Eine längere Sprechpause trennt Absätze — so bekommt ein Transkript die
    /// Gliederung, die das Gesprochene ohnehin hatte.
    func testLaengerePauseErzeugtAbsatz() {
        let segments = [seg("Vor der Pause", 0, 4), seg("Nach der Pause", 9, 12)]
        XCTAssertEqual(TranscriptLayout.rawText(from: segments), "Vor der Pause\n\nNach der Pause")
    }

    func testKurzePauseErzeugtKeinenAbsatz() {
        let segments = [seg("Eins", 0, 4), seg("Zwei", 4.5, 8)]
        XCTAssertEqual(TranscriptLayout.rawText(from: segments), "Eins\nZwei")
    }

    func testLeereSegmenteFliegenRaus() {
        let segments = [seg("Eins", 0, 4), seg("   ", 4, 5), seg("Zwei", 5, 8)]
        XCTAssertEqual(TranscriptLayout.rawText(from: segments), "Eins\nZwei")
    }

    /// Ein leeres Segment darf keinen Absatz erzwingen, nur weil danach die
    /// Zeitlücke rechnerisch groß wirkt.
    func testKeineSegmenteGibtLeerenText() {
        XCTAssertEqual(TranscriptLayout.rawText(from: []), "")
        XCTAssertEqual(TranscriptLayout.rawText(from: [seg("  ", 0, 1)]), "")
    }

    func testSteuermarkenWerdenBeimGliedernEntfernt() {
        let segments = [seg("<|0.00|> Mit Marke<|4.00|>", 0, 4), seg("Ohne", 4, 8)]
        XCTAssertEqual(TranscriptLayout.rawText(from: segments), "Mit Marke\nOhne")
    }

    // MARK: - Zeitmarken

    func testZeitmarkeStehtAmAbsatzanfang() {
        let segments = [seg("Erste Zeile", 0, 4), seg("Zweite Zeile", 4, 8)]
        XCTAssertEqual(TranscriptLayout.rawText(from: segments, timestamps: true),
                       "[0:00] Erste Zeile\nZweite Zeile")
    }

    /// Jeder Absatz bekommt seine eigene Zeit — das ist der Sinn der Sache: eine
    /// Stelle im Text wiederfinden zu können.
    func testJederAbsatzBekommtEineZeitmarke() {
        let segments = [seg("Vor der Pause", 0, 4), seg("Nach der Pause", 124, 128)]
        XCTAssertEqual(TranscriptLayout.rawText(from: segments, timestamps: true),
                       "[0:00] Vor der Pause\n\n[2:04] Nach der Pause")
    }

    func testZeitmarkeUeberEineStunde() {
        let segments = [seg("Spät dran", 3725, 3729)]
        XCTAssertEqual(TranscriptLayout.rawText(from: segments, timestamps: true),
                       "[1:02:05] Spät dran")
    }

    /// Der Eingang fürs Sprachmodell braucht keine Zeitmarken — die würden dort nur
    /// Kontext kosten und im Protokoll wieder auftauchen.
    func testOhneZeitmarkenUnveraendert() {
        let segments = [seg("Eins", 0, 4), seg("Zwei", 4, 8)]
        XCTAssertEqual(TranscriptLayout.rawText(from: segments, timestamps: false), "Eins\nZwei")
    }

    // MARK: - Sprecher

    private func seg(_ text: String, _ start: Double, _ end: Double, _ speaker: Int?) -> TranscriptSegment {
        TranscriptSegment(text: text, start: start, end: end, speaker: speaker)
    }

    /// Ein Sprecherwechsel beginnt einen neuen Absatz, auch ohne Pause — sonst
    /// klebt die Antwort an der Frage.
    func testSprecherwechselBeginntNeuenAbsatz() {
        let segments = [seg("Frage?", 0, 4, 1), seg("Antwort.", 4, 8, 2)]
        XCTAssertEqual(TranscriptLayout.rawText(from: segments, speakerLabel: { "Sprecher \($0)" }),
                       "Sprecher 1: Frage?\n\nSprecher 2: Antwort.")
    }

    func testGleicherSprecherBleibtImAbsatz() {
        let segments = [seg("Erst das", 0, 4, 1), seg("dann das", 4, 8, 1)]
        XCTAssertEqual(TranscriptLayout.rawText(from: segments, speakerLabel: { "Sprecher \($0)" }),
                       "Sprecher 1: Erst das\ndann das")
    }

    func testSprecherUndZeitmarkeZusammen() {
        let segments = [seg("Hallo", 65, 68, 2)]
        XCTAssertEqual(TranscriptLayout.rawText(from: segments, timestamps: true,
                                                speakerLabel: { "Sprecher \($0)" }),
                       "[1:05] Sprecher 2: Hallo")
    }

    /// Ohne erkannten Sprecher steht einfach kein Name davor.
    func testOhneSprecherKeinLabel() {
        let segments = [seg("Anonym", 0, 4, nil)]
        XCTAssertEqual(TranscriptLayout.rawText(from: segments, speakerLabel: { "Sprecher \($0)" }),
                       "Anonym")
    }

    /// Ohne Label-Funktion bleibt alles wie bisher — der Eingang fürs Sprachmodell
    /// soll die Namen aber bekommen, deshalb ist sie dort gesetzt.
    func testOhneLabelFunktionKeineSprecher() {
        let segments = [seg("Frage?", 0, 4, 1), seg("Antwort.", 4, 8, 2)]
        XCTAssertEqual(TranscriptLayout.rawText(from: segments), "Frage?\nAntwort.")
    }
}
