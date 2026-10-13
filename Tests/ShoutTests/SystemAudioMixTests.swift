import CoreAudio
import XCTest

/// Mischung im Systemton-Abgriff: Der Tap ist der letzte Puffer, davor liegen die
/// Eingänge der Sub-Geräte (Mikrofon). Der Mikrofon-Pegel wird getrennt gemessen —
/// sonst verdeckt der Ton der anderen ein stummes Mikrofon.
@available(macOS 14.2, *)
final class SystemAudioMixTests: XCTestCase {

    /// Baut eine AudioBufferList aus Puffern mit je einem Kanal.
    private func withList<T>(_ buffers: [[Float]],
                             _ body: (UnsafeMutableAudioBufferListPointer) -> T) -> T {
        let list = AudioBufferList.allocate(maximumBuffers: buffers.count)
        defer { free(list.unsafeMutablePointer) }
        var storage = buffers.map { samples -> UnsafeMutablePointer<Float> in
            let pointer = UnsafeMutablePointer<Float>.allocate(capacity: samples.count)
            pointer.initialize(from: samples, count: samples.count)
            return pointer
        }
        defer { storage.forEach { $0.deallocate() }; storage.removeAll() }
        for (index, samples) in buffers.enumerated() {
            list[index] = AudioBuffer(mNumberChannels: 1,
                                      mDataByteSize: UInt32(samples.count * MemoryLayout<Float>.size),
                                      mData: UnsafeMutableRawPointer(storage[index]))
        }
        return body(list)
    }

    func testNurSystemtonNimmtNurDenTap() {
        let result = withList([[0.9, 0.9], [0.2, -0.2]]) {
            SystemAudioTap.mix($0, includeSubDevices: false)
        }
        XCTAssertEqual(result.samples, [0.2, -0.2])
        XCTAssertNil(result.microphonePeak)
    }

    func testBeidesMischtUndMisstMikrofonGetrennt() {
        // Zweierpotenzen, damit die Halbierung exakt bleibt.
        let result = withList([[0.5, 0.0], [0.25, -0.25]]) {
            SystemAudioTap.mix($0, includeSubDevices: true)
        }
        XCTAssertEqual(result.samples, [0.375, -0.125])
        XCTAssertEqual(result.microphonePeak, 0.5)
    }

    /// Der Fall aus dem Teams-Meeting: Das Mikrofon liefert Nullen, der Ton der
    /// anderen kommt an. Die Mischung ist laut — das Mikrofon trotzdem stumm.
    func testStummesMikrofonFaelltAuchBeiLautemTapAuf() {
        let result = withList([[0, 0, 0], [0.5, -0.5, 0.5]]) {
            SystemAudioTap.mix($0, includeSubDevices: true)
        }
        XCTAssertEqual(result.microphonePeak, 0)
    }

    /// Ohne Puffer vor dem Tap ist gar kein Mikrofon im Aggregat — auch das ist stumm.
    func testFehlendesMikrofonZaehltAlsStumm() {
        let result = withList([[0.5, -0.5]]) {
            SystemAudioTap.mix($0, includeSubDevices: true)
        }
        XCTAssertEqual(result.samples, [0.5, -0.5])
        XCTAssertEqual(result.microphonePeak, 0)
    }
}
