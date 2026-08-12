import XCTest

final class TranscriptStoreTests: XCTestCase {

    /// Eigener Ordner je Testlauf — die Ablage arbeitet auf echten Dateien.
    private var ordner: URL!
    private var audio: URL!

    override func setUpWithError() throws {
        ordner = FileManager.default.temporaryDirectory
            .appendingPathComponent("shout-store-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: ordner, withIntermediateDirectories: true)
        audio = ordner.appendingPathComponent("Meeting 2026-08-12 09-15.m4a")
        try Data().write(to: audio)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: ordner)
    }

    private var beispiel: StoredTranscript {
        StoredTranscript(
            rawText: "[00:00] Sprecher 1: Guten Morgen.",
            formattedText: "## Zusammenfassung\nKurzes Treffen.",
            segments: [TranscriptSegment(text: "Guten Morgen.", start: 0, end: 1.5, speaker: 1)],
            duration: 1.5,
            speakerNote: nil)
    }

    /// Die Ablage liegt neben der Aufnahme und ersetzt nur die Endung — sonst
    /// fände `existingRecordings()` sie als zweiten Mitschnitt.
    func testAblageLiegtNebenDerAufnahme() {
        let sidecar = TranscriptStore.sidecar(for: audio)
        XCTAssertEqual(sidecar.lastPathComponent, "Meeting 2026-08-12 09-15.json")
        XCTAssertEqual(sidecar.deletingLastPathComponent(), audio.deletingLastPathComponent())
    }

    func testSichernUndLaden() {
        TranscriptStore.save(beispiel, for: audio)
        XCTAssertEqual(TranscriptStore.load(for: audio), beispiel)
    }

    /// Der wichtigste Teil: Zeitmarken und Sprechernummer müssen die Runde durch
    /// JSON überstehen, sonst wären Untertitel nach einem Neustart wertlos.
    func testSegmenteUeberlebenDasSichern() throws {
        TranscriptStore.save(beispiel, for: audio)
        let geladen = try XCTUnwrap(TranscriptStore.load(for: audio))
        XCTAssertEqual(geladen.segments.count, 1)
        XCTAssertEqual(geladen.segments[0].start, 0)
        XCTAssertEqual(geladen.segments[0].end, 1.5)
        XCTAssertEqual(geladen.segments[0].speaker, 1)
    }

    func testOhneAblageKommtNichts() {
        XCTAssertNil(TranscriptStore.load(for: audio))
    }

    func testEntfernenLoeschtDieAblage() {
        TranscriptStore.save(beispiel, for: audio)
        TranscriptStore.remove(for: audio)
        XCTAssertNil(TranscriptStore.load(for: audio))
        XCTAssertFalse(FileManager.default.fileExists(atPath: TranscriptStore.sidecar(for: audio).path))
    }

    /// Beschädigte Datei: lieber nichts zurückgeben als abstürzen — der Auftrag
    /// steht dann wieder als „noch nicht verarbeitet" da.
    func testKaputteAblageWirdIgnoriert() throws {
        try "kein JSON".write(to: TranscriptStore.sidecar(for: audio), atomically: true, encoding: .utf8)
        XCTAssertNil(TranscriptStore.load(for: audio))
    }
}
