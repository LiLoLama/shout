import XCTest

/// Welches Mikrofon der Mitschnitt nimmt. Es muss dasselbe sein wie beim Diktat:
/// Steht in macOS ein virtuelles Gerät (Loopback, Teams Audio) als Standard-Eingang,
/// fehlt sonst die eigene Stimme im Meeting — die Aufnahme sieht trotzdem gesund
/// aus, weil der Ton der anderen ankommt.
@MainActor
final class MeetingMicrophoneTests: XCTestCase {

    private let vorhanden = ["BuiltInMicrophoneDevice", "LoopbackAudio", "MSTeamsAudioDevice"]

    func testGewaehltesMikrofonGewinnt() {
        XCTAssertEqual(MeetingRecorder.microphoneUID(preferred: "BuiltInMicrophoneDevice",
                                                     available: vorhanden),
                       "BuiltInMicrophoneDevice")
    }

    /// „Systemstandard" ist im Einstellungs-Menü der leere Text.
    func testSystemstandardGibtNichts() {
        XCTAssertNil(MeetingRecorder.microphoneUID(preferred: "", available: vorhanden))
        XCTAssertNil(MeetingRecorder.microphoneUID(preferred: nil, available: vorhanden))
    }

    /// Abgestecktes Headset: lieber der Standard-Eingang als gar kein Mitschnitt.
    func testFehlendesGeraetFaelltAufStandardZurueck() {
        XCTAssertNil(MeetingRecorder.microphoneUID(preferred: "AirPodsPro", available: vorhanden))
    }

    // MARK: - Stummes Mikrofon erkennen

    /// Ein echtes Mikrofon rauscht immer ein wenig. Exakte Nullen liefert nur ein
    /// falsches oder virtuelles Gerät — genau das soll auffallen.
    func testDigitaleStilleIstStumm() {
        XCTAssertFalse(MeetingRecorder.isMicrophoneSignal(0))
        XCTAssertFalse(MeetingRecorder.isMicrophoneSignal(0.000_01))
    }

    /// Rauschboden eines eingebauten Mikrofons in einem ruhigen Raum (≈ −66 dBFS):
    /// Wer gerade nur zuhört, darf keinen Hinweis bekommen.
    func testRauschenEinesEchtenMikrofonsZaehlt() {
        XCTAssertTrue(MeetingRecorder.isMicrophoneSignal(0.0005))
    }
}
