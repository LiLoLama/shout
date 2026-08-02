import XCTest

final class SubtitleWriterTests: XCTestCase {

    // MARK: - Zeitmarken

    func testZeitmarkeAmAnfang() {
        XCTAssertEqual(SubtitleWriter.timecode(0), "00:00:00,000")
    }

    func testZeitmarkeMitMillisekunden() {
        XCTAssertEqual(SubtitleWriter.timecode(83.456), "00:01:23,456")
    }

    func testZeitmarkeUeberEineStunde() {
        XCTAssertEqual(SubtitleWriter.timecode(3661.5), "01:01:01,500")
    }

    /// Negative Werte dürfen kein „-00:00:01" erzeugen — das liest kein Abspieler.
    func testZeitmarkeNegativWirdAufNullGeklemmt() {
        XCTAssertEqual(SubtitleWriter.timecode(-2), "00:00:00,000")
    }

    // MARK: - SRT

    func testSrtNummeriertUndTrenntMitLeerzeile() {
        let segments = [
            TranscriptSegment(text: "Erster Satz.", start: 0, end: 1.5),
            TranscriptSegment(text: "Zweiter Satz.", start: 1.5, end: 3),
        ]
        let expected = """
        1
        00:00:00,000 --> 00:00:01,500
        Erster Satz.

        2
        00:00:01,500 --> 00:00:03,000
        Zweiter Satz.


        """
        XCTAssertEqual(SubtitleWriter.srt(from: segments), expected)
    }

    /// Leere Segmente kommen von Whisper regelmäßig (Stille). Sie fliegen raus,
    /// die Nummerierung bleibt trotzdem lückenlos.
    func testSrtUeberspringtLeereSegmenteOhneLuecke() {
        let segments = [
            TranscriptSegment(text: "Eins", start: 0, end: 1),
            TranscriptSegment(text: "   ", start: 1, end: 2),
            TranscriptSegment(text: "Zwei", start: 2, end: 3),
        ]
        let srt = SubtitleWriter.srt(from: segments)
        XCTAssertTrue(srt.contains("1\n00:00:00,000 --> 00:00:01,000\nEins"))
        XCTAssertTrue(srt.contains("2\n00:00:02,000 --> 00:00:03,000\nZwei"))
        // Genau zwei Einträge — das leere Segment darf keine Nummer verbrauchen.
        let entries = srt.components(separatedBy: "\n\n").filter { !$0.isEmpty }
        XCTAssertEqual(entries.count, 2)
    }

    func testSrtOhneSegmenteIstLeer() {
        XCTAssertEqual(SubtitleWriter.srt(from: []), "")
    }

    /// Whisper liefert gelegentlich ein Ende vor dem Anfang. Ein rückwärts
    /// laufender Zeitbereich bringt Abspieler durcheinander.
    func testSrtKlemmtEndeAufMindestensStart() {
        let segments = [TranscriptSegment(text: "Kaputt", start: 5, end: 3)]
        XCTAssertTrue(SubtitleWriter.srt(from: segments).contains("00:00:05,000 --> 00:00:05,000"))
    }

    // MARK: - Zeitversatz

    func testOffsetVerschiebtBeideZeitmarken() {
        let segment = TranscriptSegment(text: "Text", start: 1, end: 2).offset(by: 120)
        XCTAssertEqual(segment, TranscriptSegment(text: "Text", start: 121, end: 122))
    }
}
