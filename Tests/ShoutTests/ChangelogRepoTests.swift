import XCTest

/// Die echte `CHANGELOG.md` und das Release-Skript des Repos.
final class ChangelogRepoTests: XCTestCase {

    private var wurzel: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    private func text(_ datei: String) throws -> String {
        try String(contentsOf: wurzel.appendingPathComponent(datei), encoding: .utf8)
    }

    func testAlleAbschnitteGueltig() throws {
        let roh = try text("CHANGELOG.md")
        let abschnitte = roh.components(separatedBy: "\n").filter { $0.hasPrefix("## ") }.count
        XCTAssertEqual(ChangelogParser.parse(roh).count, abschnitte, "ein Abschnitt wurde übersprungen")
    }

    func testEintragFuerDieAktuelleVersion() throws {
        let yml = try text("project.yml")
        let zeile = try XCTUnwrap(yml.components(separatedBy: "\n").first { $0.contains("MARKETING_VERSION:") })
        let version = try XCTUnwrap(zeile.components(separatedBy: "\"").dropFirst().first)
        let eintraege = ChangelogParser.parse(try text("CHANGELOG.md"))
        XCTAssertTrue(eintraege.contains { $0.version == AppVersion(version) }, "kein Abschnitt für \(version)")
    }

    func testVideosGibtEsAuch() throws {
        for e in ChangelogParser.parse(try text("CHANGELOG.md")) {
            guard let v = e.video else { continue }
            XCTAssertTrue(FileManager.default.fileExists(atPath: wurzel.appendingPathComponent("Resources/Explainers/\(v).html").path),
                          "Animation \(v) fehlt")
        }
    }

    private func skript(_ args: [String], changelog: String? = nil) throws -> (code: Int32, out: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/bash")
        p.arguments = [wurzel.appendingPathComponent("Support/release-notes.sh").path] + args
        var env = ProcessInfo.processInfo.environment
        if let changelog { env["SHOUT_CHANGELOG"] = changelog }
        p.environment = env
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = Pipe()
        try p.run()
        p.waitUntilExit()
        return (p.terminationStatus, String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self))
    }

    func testReleaseNotesHabenBeideSprachenOhneSteuerzeilen() throws {
        let r = try skript(["1.13.0"])
        XCTAssertEqual(r.code, 0)
        XCTAssertTrue(r.out.hasPrefix("**Neu: das Scratchpad.**"))
        XCTAssertTrue(r.out.contains("\n---\n"))
        XCTAssertTrue(r.out.contains("**New: the Scratchpad.**"))
        XCTAssertFalse(r.out.contains("zeigen:"))
        XCTAssertFalse(r.out.contains("video:"))
        XCTAssertFalse(r.out.contains("### "))
    }

    func testPruefungScheitertOhneAbschnitt() throws {
        XCTAssertEqual(try skript(["--check", "1.13.0"]).code, 0)
        XCTAssertNotEqual(try skript(["--check", "9.9.9"]).code, 0)
        let kaputt = FileManager.default.temporaryDirectory.appendingPathComponent("shout-changelog-\(UUID().uuidString).md")
        try "## 2.0.0 — 2026-12-01\nzeigen: ja\n\n### Deutsch\nx\n".write(to: kaputt, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: kaputt) }
        XCTAssertNotEqual(try skript(["--check", "2.0.0"], changelog: kaputt.path).code, 0, "English fehlt")
    }
}
