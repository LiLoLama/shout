import XCTest

final class WAVEncoderTests: XCTestCase {

    private func lies32(_ data: Data, at offset: Int) -> UInt32 {
        data.subdata(in: offset..<(offset + 4)).withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
            .littleEndian
    }

    private func lies16(_ data: Data, at offset: Int) -> UInt16 {
        data.subdata(in: offset..<(offset + 2)).withUnsafeBytes { $0.loadUnaligned(as: UInt16.self) }
            .littleEndian
    }

    private func text(_ data: Data, at offset: Int) -> String {
        String(data: data.subdata(in: offset..<(offset + 4)), encoding: .ascii) ?? ""
    }

    func testKopfKennungen() {
        let wav = WAVEncoder.data(from: [0, 0.5, -0.5])
        XCTAssertEqual(text(wav, at: 0), "RIFF")
        XCTAssertEqual(text(wav, at: 8), "WAVE")
        XCTAssertEqual(text(wav, at: 12), "fmt ")
        XCTAssertEqual(text(wav, at: 36), "data")
    }

    /// 16 kHz, Mono, 16 bit — genau das, was aus `AudioRecorder` kommt und was
    /// die Endpunkte erwarten.
    func testFormatAngaben() {
        let wav = WAVEncoder.data(from: [0])
        XCTAssertEqual(lies16(wav, at: 20), 1, "PCM, unkomprimiert")
        XCTAssertEqual(lies16(wav, at: 22), 1, "Mono")
        XCTAssertEqual(lies32(wav, at: 24), 16_000)
        XCTAssertEqual(lies32(wav, at: 28), 32_000, "Byte je Sekunde")
        XCTAssertEqual(lies16(wav, at: 32), 2, "Byte je Rahmen")
        XCTAssertEqual(lies16(wav, at: 34), 16, "Bit je Sample")
    }

    func testLaengenAngaben() {
        let samples = [Float](repeating: 0, count: 100)
        let wav = WAVEncoder.data(from: samples)
        XCTAssertEqual(wav.count, 44 + 200)
        XCTAssertEqual(lies32(wav, at: 4), UInt32(36 + 200), "Restlänge ab Byte 8")
        XCTAssertEqual(lies32(wav, at: 40), 200, "Länge des Datenblocks")
    }

    func testAbweichenderTaktGehtInDenKopf() {
        let wav = WAVEncoder.data(from: [0], sampleRate: 48_000)
        XCTAssertEqual(lies32(wav, at: 24), 48_000)
        XCTAssertEqual(lies32(wav, at: 28), 96_000)
    }

    /// Ein übersteuertes Diktat darf nicht als Krachen ankommen: Werte über 1
    /// werden begrenzt, nicht in einen Überlauf gerechnet.
    func testUebersteuerteWerteWerdenBegrenzt() {
        let wav = WAVEncoder.data(from: [2.5, -2.5])
        XCTAssertEqual(Int16(bitPattern: lies16(wav, at: 44)), 32_767)
        XCTAssertEqual(Int16(bitPattern: lies16(wav, at: 46)), -32_767)
    }

    func testStilleErgibtNullen() {
        let wav = WAVEncoder.data(from: [0, 0])
        XCTAssertEqual(lies16(wav, at: 44), 0)
        XCTAssertEqual(lies16(wav, at: 46), 0)
    }

    func testLeereEingabeErgibtNurDenKopf() {
        XCTAssertEqual(WAVEncoder.data(from: []).count, 44)
    }

    /// Die Rechnung, auf der die Fensterung beruht: 25 MB sind rund 13 Minuten.
    func testSekundenRechnungFuerDieGroessengrenze() {
        let sekunden = WAVEncoder.seconds(fitting: 25 * 1_024 * 1_024)
        XCTAssertEqual(sekunden, 819.2, accuracy: 0.5)
        XCTAssertGreaterThan(sekunden / 60, 13)
        XCTAssertLessThan(sekunden / 60, 14)
    }
}
