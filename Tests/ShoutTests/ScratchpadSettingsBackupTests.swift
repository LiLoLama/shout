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
}
