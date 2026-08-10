import XCTest

final class TranscriptExportTests: XCTestCase {

    private let quelle = URL(fileURLWithPath: "/Users/test/Interview.m4a")

    func testNameOhneZusatz() {
        XCTAssertEqual(TranscriptExport.fileName(for: quelle, suffix: "", extension: "txt"),
                       "Interview.txt")
    }

    func testNameMitRohtextZusatz() {
        XCTAssertEqual(TranscriptExport.fileName(for: quelle, suffix: "-roh", extension: "txt"),
                       "Interview-roh.txt")
    }

    func testUntertitelEndung() {
        XCTAssertEqual(TranscriptExport.fileName(for: quelle, suffix: "", extension: "srt"),
                       "Interview.srt")
    }

    /// Nur die letzte Endung fliegt weg — „Mein.Interview.v2" bleibt vollständig.
    func testPunkteImNamenBleibenErhalten() {
        let url = URL(fileURLWithPath: "/Users/test/Mein.Interview.v2.mp4")
        XCTAssertEqual(TranscriptExport.fileName(for: url, suffix: "", extension: "txt"),
                       "Mein.Interview.v2.txt")
    }

    func testQuelleOhneEndung() {
        let url = URL(fileURLWithPath: "/Users/test/Aufnahme")
        XCTAssertEqual(TranscriptExport.fileName(for: url, suffix: "-raw", extension: "txt"),
                       "Aufnahme-raw.txt")
    }

    /// Ein leerer Name (etwa aus einem Pfad, der auf „/" endet) darf keine Datei
    /// erzeugen, die nur aus Punkt und Endung besteht.
    func testLeererNameFaelltAufTranskriptZurueck() {
        let url = URL(fileURLWithPath: "/")
        XCTAssertEqual(TranscriptExport.fileName(for: url, suffix: "", extension: "txt"),
                       "Transkript.txt")
    }
}
