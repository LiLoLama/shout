import XCTest

final class SpeakerAssignmentTests: XCTestCase {

    private func seg(_ text: String, _ start: Double, _ end: Double) -> TranscriptSegment {
        TranscriptSegment(text: text, start: start, end: end)
    }

    private func range(_ speaker: Int, _ start: Double, _ end: Double) -> SpeakerRange {
        SpeakerRange(speaker: speaker, start: start, end: end)
    }

    func testSegmentBekommtDenUeberlappendenSprecher() {
        let segments = [seg("Hallo", 0, 4)]
        let ranges = [range(1, 0, 10)]
        XCTAssertEqual(SpeakerAssignment.assign(ranges, to: segments).first?.speaker, 1)
    }

    /// Die Grenzen von Whisper und Pyannote fallen nie exakt zusammen. Entscheidend
    /// ist, wer im Segment am längsten spricht — nicht, wer zufällig zuerst dran ist.
    func testGroesserAnteilGewinnt() {
        let segments = [seg("Gemischt", 0, 10)]
        let ranges = [range(1, 0, 3), range(2, 3, 10)]
        // Ohne Umnummerierung, sonst würde der Gewinner ohnehin zur Nummer 1 —
        // hier geht es um die Auswahl, nicht um die Anzeige.
        XCTAssertEqual(SpeakerAssignment.assign(ranges, to: segments, renumber: false).first?.speaker, 2)
    }

    func testMehrereSegmenteVerschiedeneSprecher() {
        let segments = [seg("Erst A", 0, 4), seg("Dann B", 5, 9)]
        let ranges = [range(1, 0, 4.5), range(2, 4.5, 10)]
        let result = SpeakerAssignment.assign(ranges, to: segments)
        XCTAssertEqual(result.map(\.speaker), [1, 2])
    }

    /// Findet sich keine Überlappung, bleibt der Sprecher offen — lieber kein Label
    /// als ein falsches.
    func testOhneUeberlappungKeinSprecher() {
        let segments = [seg("Allein", 20, 24)]
        let ranges = [range(1, 0, 10)]
        XCTAssertNil(SpeakerAssignment.assign(ranges, to: segments).first?.speaker)
    }

    func testOhneSprecherbereicheBleibtAllesUnveraendert() {
        let segments = [seg("Eins", 0, 4), seg("Zwei", 4, 8)]
        let result = SpeakerAssignment.assign([], to: segments)
        XCTAssertEqual(result.map(\.text), ["Eins", "Zwei"])
        XCTAssertTrue(result.allSatisfy { $0.speaker == nil })
    }

    /// Text und Zeitmarken dürfen bei der Zuordnung nicht verlorengehen.
    func testTextUndZeitenBleibenErhalten() {
        let segments = [seg("Wichtig", 1, 5)]
        let result = SpeakerAssignment.assign([range(3, 0, 10)], to: segments)
        XCTAssertEqual(result.first?.text, "Wichtig")
        XCTAssertEqual(result.first?.start, 1)
        XCTAssertEqual(result.first?.end, 5)
    }

    /// Pyannote nummeriert seine Cluster beliebig (0, 4, 7 …). Für die Anzeige
    /// sollen daraus „Sprecher 1, 2, 3" in der Reihenfolge des ersten Auftretens werden.
    func testSprechernummernWerdenNachAuftretenVergeben() {
        let segments = [seg("A", 0, 2), seg("B", 2, 4), seg("C", 4, 6)]
        let ranges = [range(7, 0, 2), range(4, 2, 4), range(7, 4, 6)]
        let result = SpeakerAssignment.assign(ranges, to: segments, renumber: true)
        XCTAssertEqual(result.map(\.speaker), [1, 2, 1])
    }

    func testOhneUmnummerierungBleibenDieOriginalnummern() {
        let segments = [seg("A", 0, 2)]
        let result = SpeakerAssignment.assign([range(7, 0, 2)], to: segments, renumber: false)
        XCTAssertEqual(result.first?.speaker, 7)
    }
}
