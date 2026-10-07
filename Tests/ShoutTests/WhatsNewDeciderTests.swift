import XCTest

final class WhatsNewDeciderTests: XCTestCase {

    private func e(_ v: String, _ zeigen: Bool) -> ChangelogEntry {
        ChangelogEntry(version: AppVersion(v)!, date: "2026-10-07", highlight: zeigen, video: nil, german: "d", english: "e")
    }

    private lazy var alle = [e("1.15.0", true), e("1.14.1", false), e("1.14.0", true), e("1.13.0", true), e("1.12.0", true)]

    private func zeige(_ lastSeen: String?, _ current: String, onboarding: Bool = true) -> [String] {
        WhatsNewDecider.entriesToShow(all: alle, lastSeen: lastSeen.flatMap(AppVersion.init),
                                      current: AppVersion(current)!, onboardingDone: onboarding)
            .map(\.version.description)
    }

    func testNeuinstallationZeigtNichts() {
        XCTAssertEqual(zeige(nil, "1.15.0", onboarding: false), [])
    }

    func testOhneGemerkteVersionGiltDieBasislinie() {
        XCTAssertEqual(WhatsNewDecider.baseline, AppVersion("1.12.0"))
        XCTAssertEqual(zeige(nil, "1.13.0"), ["1.13.0"])
    }

    func testUebersprungeneVersionenZusammen() {
        XCTAssertEqual(zeige("1.13.0", "1.15.0"), ["1.15.0", "1.14.0"])
    }

    func testNurMarkierteUndNichtsUeberDerLaufenden() {
        XCTAssertEqual(zeige("1.14.0", "1.14.1"), [])
        XCTAssertEqual(zeige("1.13.0", "1.14.1"), ["1.14.0"])
    }

    func testSchonGesehen() {
        XCTAssertEqual(zeige("1.15.0", "1.15.0"), [])
    }

    func testZustandMerktSich() {
        let name = "shout-whatsnew-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        defer { d.removePersistentDomain(forName: name) }
        let s = WhatsNewState(defaults: d)
        XCTAssertNil(s.lastSeen)
        s.markSeen(AppVersion("1.13.0")!)
        XCTAssertEqual(WhatsNewState(defaults: d).lastSeen, AppVersion("1.13.0"))
        d.set("kaputt", forKey: WhatsNewState.key)
        XCTAssertNil(WhatsNewState(defaults: d).lastSeen)
    }

    func testMarkSeenSenktDieMarkeNicht() {
        let name = "shout-whatsnew-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        defer { d.removePersistentDomain(forName: name) }
        let s = WhatsNewState(defaults: d)
        s.markSeen(AppVersion("1.15.0")!)
        s.markSeen(AppVersion("1.14.0")!)   // Downgrade
        XCTAssertEqual(s.lastSeen, AppVersion("1.15.0"))
        s.markSeen(AppVersion("1.15.0")!)
        XCTAssertEqual(s.lastSeen, AppVersion("1.15.0"))
        s.markSeen(AppVersion("1.16.0")!)
        XCTAssertEqual(s.lastSeen, AppVersion("1.16.0"))
    }
}
