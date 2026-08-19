import XCTest

final class TranscriptPlausibilityTests: XCTestCase {

    // MARK: - Verschluckter Anfang
    //
    // Die Samples kommen getrimmt bei Whisper an: `trimSilence` schneidet auf
    // 300 ms vor dem ersten Sprach-Fenster. Beginnt Whispers erster Abschnitt
    // deutlich später, hat es also Audio übersprungen, in dem gesprochen wurde.

    func testAbschnittAbSekundeNullIstInOrdnung() {
        XCTAssertFalse(TranscriptPlausibility.swallowedStart(firstSegmentStart: 0, audioSeconds: 20))
    }

    func testKleinerVersatzIstNochDerSicherheitsrand() {
        XCTAssertFalse(TranscriptPlausibility.swallowedStart(firstSegmentStart: 0.4, audioSeconds: 20),
                       "300 ms Rand plus Zeitmarken-Raster darf keinen Verdacht auslösen")
    }

    func testSpaeterBeginnIstVerdaechtig() {
        XCTAssertTrue(TranscriptPlausibility.swallowedStart(firstSegmentStart: 4.0, audioSeconds: 20),
                      "4 s übersprungen bei 20 s Audio — genau der gemeldete Fehler")
    }

    /// Der Fall aus dem Verlauf: ein Drittel fehlt. Textlänge allein hätte das
    /// nie gemeldet, der Beginn des ersten Abschnitts schon.
    func testFehlendesDrittelWirdErkannt() {
        XCTAssertTrue(TranscriptPlausibility.swallowedStart(firstSegmentStart: 6.2, audioSeconds: 18))
    }

    func testAuchBeiKurzemDiktat() {
        XCTAssertTrue(TranscriptPlausibility.swallowedStart(firstSegmentStart: 1.5, audioSeconds: 3))
    }

    func testGrenzeSelbstLoestNichtAus() {
        XCTAssertFalse(TranscriptPlausibility.swallowedStart(firstSegmentStart: 1.0, audioSeconds: 20))
        XCTAssertTrue(TranscriptPlausibility.swallowedStart(firstSegmentStart: 1.2, audioSeconds: 20))
    }

    func testOhneAbschnitteKeinUrteil() {
        XCTAssertFalse(TranscriptPlausibility.swallowedStart(firstSegmentStart: nil, audioSeconds: 20),
                       "gar kein Abschnitt heißt leeres Ergebnis — das prüft die Leer-Regel")
    }

    /// Winzige Schnipsel nicht bewerten: dort ist eine Sekunde Versatz Rauschen
    /// im Zeitmarken-Raster, kein verlorener Satz.
    func testSehrKurzesAudioWirdNichtBewertet() {
        XCTAssertFalse(TranscriptPlausibility.swallowedStart(firstSegmentStart: 1.1, audioSeconds: 1.2))
    }

    // MARK: - Zu wenig Text für die Länge

    func testDeutlichZuWenigTextIstVerdaechtig() {
        XCTAssertTrue(TranscriptPlausibility.tooLittleText(characters: 25, audioSeconds: 10))
    }

    func testNormaleDichteIstUnverdaechtig() {
        // Gemessen an echten Diktaten: 13–14 Zeichen je Sekunde.
        XCTAssertFalse(TranscriptPlausibility.tooLittleText(characters: 130, audioSeconds: 10))
    }

    func testKurzeDiktateWerdenNichtBewertet() {
        XCTAssertFalse(TranscriptPlausibility.tooLittleText(characters: 5, audioSeconds: 4),
                       "unter 5 s ist ein knappes Ergebnis normal (‚ja', ‚Punkt')")
    }
}
