import XCTest
import AppKit
import Carbon.HIToolbox

@MainActor
final class HotkeyTests: XCTestCase {

    // MARK: - Tippen oder Halten

    func testKurzesDrueckenIstTippen() {
        var k = HotkeyPressClassifier()
        k.press(at: 0)
        XCTAssertNil(k.tick(at: 0.1))
        XCTAssertEqual(k.release(at: 0.2), .tap)
    }

    func testHaltenBeginntUndEndet() {
        var k = HotkeyPressClassifier()
        k.press(at: 0)
        XCTAssertEqual(k.tick(at: 0.35), .holdBegan)
        XCTAssertNil(k.tick(at: 0.5))                 // nur einmal
        XCTAssertEqual(k.release(at: 2), .holdEnded)
    }

    /// Ein zweites Drücken bei schon gedrückter Taste (Auto-Repeat, verlorenes Loslassen)
    /// darf `.holdBegan` nicht ein zweites Mal auslösen.
    func testZweitesDrueckenWaehrendHaltenIgnoriert() {
        var k = HotkeyPressClassifier()
        k.press(at: 0)
        XCTAssertEqual(k.tick(at: 0.4), .holdBegan)
        k.press(at: 0.5)
        XCTAssertNil(k.tick(at: 1.0))
        XCTAssertEqual(k.release(at: 1.5), .holdEnded)
        // Nach dem Loslassen zählt ein neues Drücken wieder.
        k.press(at: 2)
        XCTAssertEqual(k.tick(at: 2.4), .holdBegan)
    }

    func testLoslassenOhneDrueckenIstNichts() {
        var k = HotkeyPressClassifier()
        XCTAssertNil(k.release(at: 1))
    }

    /// Kam der Zeitgeber zu spät (Hauptstrang beschäftigt), gilt das Loslassen als Tippen.
    func testLangesDrueckenOhneZeitgeberIstTippen() {
        var k = HotkeyPressClassifier()
        k.press(at: 0)
        XCTAssertEqual(k.release(at: 1), .tap)
    }

    // MARK: - Kombination

    func testCarbonModifier() {
        let c = HotkeyCombo(keyCode: 45, flags: [.control, .option, .function])
        XCTAssertEqual(c.flags, [.control, .option])
        XCTAssertEqual(c.carbonModifiers, UInt32(controlKey) | UInt32(optionKey))
    }

    func testVorgabenUndAnzeige() {
        XCTAssertEqual(HotkeyCombo.scratchpadDefault.display, "⌃⌥N")
        XCTAssertEqual(HotkeyCombo.inboxDefault.display, "⌃⌥I")
    }

    // MARK: - Ziel

    func testZielFuerDieDiktiertaste() {
        let id = UUID()
        XCTAssertEqual(DictationTarget.forDictationKey(panelIsKey: true, activeNote: id, frontBundleID: "com.apple.mail"),
                       .scratchpad(noteID: id))
        XCTAssertEqual(DictationTarget.forDictationKey(panelIsKey: false, activeNote: id, frontBundleID: "com.apple.mail"),
                       .frontApp(bundleID: "com.apple.mail"))
        XCTAssertEqual(DictationTarget.forDictationKey(panelIsKey: true, activeNote: nil, frontBundleID: nil),
                       .frontApp(bundleID: nil))
    }

    func testFormatierungNurFuerFremdeApp() {
        XCTAssertEqual(DictationTarget.frontApp(bundleID: "x").formatterBundleID, "x")
        XCTAssertNil(DictationTarget.inbox.formatterBundleID)
        XCTAssertNil(DictationTarget.scratchpad(noteID: UUID()).formatterBundleID)
        XCTAssertTrue(DictationTarget.frontApp(bundleID: nil).isFrontApp)
        XCTAssertFalse(DictationTarget.inbox.isFrontApp)
    }

    // MARK: - Einstellungen

    private func einstellungen() -> (ScratchpadSettings, UserDefaults, String) {
        let suite = "shout-hotkeys-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        return (ScratchpadSettings(defaults: d), d, suite)
    }

    func testVorgabenOhneGespeichertes() {
        let (s, d, suite) = einstellungen()
        defer { d.removePersistentDomain(forName: suite) }
        XCTAssertTrue(s.isEnabled)
        XCTAssertEqual(s.openBehavior, .resume)
        XCTAssertEqual(s.combo(for: .scratchpad), .scratchpadDefault)
        XCTAssertEqual(s.combo(for: .inbox), .inboxDefault)
    }

    func testGespeichertUndGeleert() {
        let (s, d, suite) = einstellungen()
        defer { d.removePersistentDomain(forName: suite) }
        let neu = HotkeyCombo(keyCode: 1, flags: [.control, .option])     // ⌃⌥S
        s.setCombo(neu, for: .scratchpad)
        s.setCombo(nil, for: .inbox)
        let wieder = ScratchpadSettings(defaults: d)
        XCTAssertEqual(wieder.combo(for: .scratchpad), neu)
        XCTAssertNil(wieder.combo(for: .inbox))      // bewusst „Keine“, nicht die Vorgabe
    }

    func testBeschaedigteBelegungFaelltAufVorgabeZurueck() {
        let (s, d, suite) = einstellungen()
        defer { d.removePersistentDomain(forName: suite) }
        _ = s
        d.set(Data("kaputt".utf8), forKey: "scratchpad.combo.scratchpad")
        d.set(Data("kaputt".utf8), forKey: "scratchpad.combo.inbox")
        let wieder = ScratchpadSettings(defaults: d)
        XCTAssertEqual(wieder.combo(for: .scratchpad), .scratchpadDefault)
        XCTAssertEqual(wieder.combo(for: .inbox), .inboxDefault)
    }

    func testAenderungWirdGemeldet() {
        let (s, d, suite) = einstellungen()
        defer { d.removePersistentDomain(forName: suite) }
        var gemeldet = 0
        s.onChange = { gemeldet += 1 }
        s.setCombo(nil, for: .inbox)
        s.isEnabled = false
        XCTAssertEqual(gemeldet, 2)
    }

    func testPruefungDerKombination() {
        let (s, d, suite) = einstellungen()
        defer { d.removePersistentDomain(forName: suite) }
        let diktat: (keyCode: UInt16, modifiers: UInt, isModifierOnly: Bool) = (61, 0, true)
        // Ohne ⌃ oder ⌥ würde die Taste Kürzel anderer Apps abfangen.
        XCTAssertNotNil(s.rejection(for: HotkeyCombo(keyCode: 45, flags: [.command]), role: .scratchpad, dictationKey: diktat))
        // Feste Kürzel von shout.
        XCTAssertNotNil(s.rejection(for: HotkeyCombo(keyCode: 8, flags: [.command, .option]), role: .scratchpad, dictationKey: diktat))
        // Schon von der anderen Rolle belegt.
        XCTAssertNotNil(s.rejection(for: .inboxDefault, role: .scratchpad, dictationKey: diktat))
        // Die Diktiertaste selbst.
        let diktatKombi: (keyCode: UInt16, modifiers: UInt, isModifierOnly: Bool) =
            (1, NSEvent.ModifierFlags([.control, .option]).rawValue, false)
        XCTAssertNotNil(s.rejection(for: HotkeyCombo(keyCode: 1, flags: [.control, .option]), role: .scratchpad, dictationKey: diktatKombi))
        // Gültig.
        XCTAssertNil(s.rejection(for: HotkeyCombo(keyCode: 1, flags: [.control, .option]), role: .scratchpad, dictationKey: diktat))
        // Die eigene, unveränderte Belegung ist kein Konflikt mit sich selbst.
        XCTAssertNil(s.rejection(for: .scratchpadDefault, role: .scratchpad, dictationKey: diktat))
    }
}
