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
}
