import XCTest

@MainActor
final class ScratchpadSettingsBackupTests: XCTestCase {

    private var namen: [String] = []

    private func defaults() -> UserDefaults {
        let name = "shout-scratchpad-backup-\(UUID().uuidString)"
        namen.append(name)
        return UserDefaults(suiteName: name)!
    }

    override func tearDown() {
        for name in namen { UserDefaults().removePersistentDomain(forName: name) }
        super.tearDown()
    }

    func testRundlauf() {
        let da = defaults(), db = defaults()
        let a = ScratchpadSettings(defaults: da)
        a.isEnabled = false
        a.openBehavior = .lastPinned
        a.setCombo(nil, for: .inbox)
        a.setCombo(HotkeyCombo(keyCode: 45, flags: [.control, .option, .shift]), for: .scratchpad)

        let b = ScratchpadSettings(defaults: db)
        var geaendert = 0
        b.onChange = { geaendert += 1 }
        b.apply(a.backupFields)

        XCTAssertEqual(b.backupFields, a.backupFields)
        XCTAssertFalse(b.isEnabled)
        XCTAssertEqual(b.openBehavior, .lastPinned)
        XCTAssertNil(b.combo(for: .inbox))
        XCTAssertGreaterThan(geaendert, 0, "Tasten werden neu angemeldet")
        XCTAssertEqual(ScratchpadSettings(defaults: db).backupFields, a.backupFields, "gesichert")
    }

    func testUnbekanntesBleibtWieEsIst() {
        let b = ScratchpadSettings(defaults: defaults())
        b.apply(.init(enabled: true, openBehavior: "quatsch", keys: ["scratchpad": Data("x".utf8)]))
        XCTAssertEqual(b.openBehavior, .resume)
        XCTAssertEqual(b.combo(for: .scratchpad), .scratchpadDefault)
        XCTAssertEqual(b.combo(for: .inbox), .inboxDefault)
    }

    private func daten(_ kombi: HotkeyCombo) -> Data { try! JSONEncoder().encode(kombi) }

    func testAbgelehnteTastenBehaltenDieJetzigeBelegung() {
        let b = ScratchpadSettings(defaults: defaults())
        let diktat = HotkeyCombo(keyCode: 40, flags: [.control, .option])
        let ohneModifikator = HotkeyCombo(keyCode: 45, flags: [.command])
        let abgelehnt = b.apply(.init(enabled: true, openBehavior: "resume",
                                      keys: ["scratchpad": daten(diktat), "inbox": daten(ohneModifikator)]),
                                dictationKey: (keyCode: 40, modifiers: diktat.modifiers, isModifierOnly: false))
        XCTAssertEqual(Set(abgelehnt), [.scratchpad, .inbox])
        XCTAssertEqual(b.combo(for: .scratchpad), .scratchpadDefault)
        XCTAssertEqual(b.combo(for: .inbox), .inboxDefault)
    }

    func testVertauschteTastenWerdenAngenommen() {
        let b = ScratchpadSettings(defaults: defaults())
        let abgelehnt = b.apply(.init(enabled: true, openBehavior: "resume",
                                      keys: ["scratchpad": daten(.inboxDefault), "inbox": daten(.scratchpadDefault)]))
        XCTAssertTrue(abgelehnt.isEmpty)
        XCTAssertEqual(b.combo(for: .scratchpad), .inboxDefault)
        XCTAssertEqual(b.combo(for: .inbox), .scratchpadDefault)
    }

    func testGleicheTasteFuerBeideRollenNimmtNurDieErsteAn() {
        let b = ScratchpadSettings(defaults: defaults())
        let kombi = HotkeyCombo(keyCode: 12, flags: [.control, .option])
        let abgelehnt = b.apply(.init(enabled: true, openBehavior: "resume",
                                      keys: ["scratchpad": daten(kombi), "inbox": daten(kombi)]))
        XCTAssertEqual(abgelehnt, [.inbox])
        XCTAssertEqual(b.combo(for: .scratchpad), kombi)
        XCTAssertEqual(b.combo(for: .inbox), .inboxDefault)
    }
}
