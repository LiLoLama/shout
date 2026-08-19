import XCTest

final class DoubleTapDetectorTests: XCTestCase {

    private var detector = DoubleTapDetector()

    override func setUp() {
        super.setUp()
        detector = DoubleTapDetector()   // window 0.4 s, Sperrfrist 0.25 s
    }

    // MARK: - Starten

    /// Zwei Anschläge im Zeitfenster → Aufnahme startet beim zweiten.
    func testZweiSchnelleTippsStarten() {
        XCTAssertEqual(detector.handleDown(at: 10.0, isRecording: false), .none,
                       "der erste Tipp darf noch nichts tun")
        XCTAssertEqual(detector.handleDown(at: 10.2, isRecording: false), .start)
    }

    /// Knapp innerhalb des Fensters zählt noch, knapp darüber nicht mehr.
    /// (Auf der Grenze selbst wird nicht geprüft — 10.4 - 10.0 ist in Double
    /// minimal größer als 0.4, das wäre ein Test über Fließkomma-Rundung.)
    func testFensterrand() {
        _ = detector.handleDown(at: 10.0, isRecording: false)
        XCTAssertEqual(detector.handleDown(at: 10.39, isRecording: false), .start)

        var zweiter = DoubleTapDetector()
        _ = zweiter.handleDown(at: 10.0, isRecording: false)
        XCTAssertEqual(zweiter.handleDown(at: 10.41, isRecording: false), .none)
    }

    /// Zu langsam getippt → keine Aufnahme. Genau das schützt vor Versehen.
    func testZweiLangsameTippsStartenNicht() {
        XCTAssertEqual(detector.handleDown(at: 10.0, isRecording: false), .none)
        XCTAssertEqual(detector.handleDown(at: 10.6, isRecording: false), .none)
    }

    /// Der zu langsame zweite Tipp ist der neue erste — direkt danach kann
    /// wieder ein Doppeltipp entstehen, ohne extra Pause.
    func testLangsamerTippWirdNeuerErsterTipp() {
        _ = detector.handleDown(at: 10.0, isRecording: false)
        _ = detector.handleDown(at: 11.0, isRecording: false)
        XCTAssertEqual(detector.handleDown(at: 11.2, isRecording: false), .start)
    }

    // MARK: - Stoppen

    /// Ein einzelner Tipp beendet die laufende Aufnahme.
    func testEinzelnerTippStoppt() {
        _ = detector.handleDown(at: 10.0, isRecording: false)
        XCTAssertEqual(detector.handleDown(at: 10.2, isRecording: false), .start)
        XCTAssertEqual(detector.handleDown(at: 12.0, isRecording: true), .stop)
    }

    /// Der gemeine Fall: dreimal statt zweimal getippt. Der dritte Tipp fällt in
    /// die Sperrfrist und darf die gerade begonnene Aufnahme nicht abwürgen.
    func testDritterTippInDerSperrfristStopptNicht() {
        _ = detector.handleDown(at: 10.0, isRecording: false)
        XCTAssertEqual(detector.handleDown(at: 10.2, isRecording: false), .start)
        XCTAssertEqual(detector.handleDown(at: 10.35, isRecording: true), .none)
    }

    /// Nach der Sperrfrist stoppt der nächste Tipp wieder normal.
    func testNachDerSperrfristStopptDerNaechsteTipp() {
        _ = detector.handleDown(at: 10.0, isRecording: false)
        _ = detector.handleDown(at: 10.2, isRecording: false)
        XCTAssertEqual(detector.handleDown(at: 10.46, isRecording: true), .stop)
    }

    /// Aufnahme anderswo gestartet (Pille, Menü): der erste Tipp stoppt sofort,
    /// ohne Sperrfrist — es gibt ja keinen Doppeltipp, zu dem er gehören könnte.
    func testFremdGestarteteAufnahmeStopptSofort() {
        XCTAssertEqual(detector.handleDown(at: 10.0, isRecording: true), .stop)
    }

    /// Nach dem Stopp ist der Detektor leer: ein einzelner Tipp startet nichts.
    func testNachDemStoppBrauchtEsWiederZweiTipps() {
        _ = detector.handleDown(at: 10.0, isRecording: false)
        _ = detector.handleDown(at: 10.2, isRecording: false)
        _ = detector.handleDown(at: 12.0, isRecording: true)
        XCTAssertEqual(detector.handleDown(at: 12.1, isRecording: false), .none,
                       "der Tipp nach dem Stopp darf nicht als zweiter Tipp gelten")
        XCTAssertEqual(detector.handleDown(at: 12.3, isRecording: false), .start)
    }
}
