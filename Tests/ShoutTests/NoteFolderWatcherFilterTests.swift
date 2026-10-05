import XCTest

/// Obsidian schreibt ständig in `.obsidian/`, Bilder liegen in `Anhänge/` — beides
/// betrifft die Notizliste nicht und soll kein Neueinlesen auslösen.
final class NoteFolderWatcherFilterTests: XCTestCase {

    private let ordner = URL(fileURLWithPath: "/tmp/notizen-filter", isDirectory: true)

    func testDateiDirektImOrdner() {
        XCTAssertTrue(NoteFolderWatcher.concernsFolder(["/tmp/notizen-filter/Idee.md"], folder: ordner))
    }

    func testDerOrdnerSelbst() {
        XCTAssertTrue(NoteFolderWatcher.concernsFolder(["/tmp/notizen-filter"], folder: ordner))
    }

    func testUnterordnerNicht() {
        XCTAssertFalse(NoteFolderWatcher.concernsFolder(["/tmp/notizen-filter/.obsidian/workspace.json"], folder: ordner))
        XCTAssertFalse(NoteFolderWatcher.concernsFolder(["/tmp/notizen-filter/Anhänge/bild.png"], folder: ordner))
    }

    func testVersteckteDateiNicht() {
        XCTAssertFalse(NoteFolderWatcher.concernsFolder(["/tmp/notizen-filter/.DS_Store"], folder: ordner))
    }

    /// Ausgelagerte iCloud-Dateien beginnen mit einem Punkt, betreffen die Liste aber sehr wohl.
    func testICloudPlatzhalterSchon() {
        XCTAssertTrue(NoteFolderWatcher.concernsFolder(["/tmp/notizen-filter/.Idee.md.icloud"], folder: ordner))
    }

    /// Ohne Pfade (zusammengefasste Meldung) lieber neu einlesen.
    func testOhnePfadeSicherheitshalberJa() {
        XCTAssertTrue(NoteFolderWatcher.concernsFolder([], folder: ordner))
    }

    func testMehrerePfadeEinTrefferReicht() {
        XCTAssertTrue(NoteFolderWatcher.concernsFolder(
            ["/tmp/notizen-filter/.obsidian/a.json", "/tmp/notizen-filter/B.md"], folder: ordner))
    }

    /// Mit dem echten FSEvents-Strom: Die Pfade kommen an, die Datei im Ordner
    /// betrifft ihn, eine Datei in einem Unterordner nicht.
    func testEchterStromLiefertPfade() throws {
        let echt = FileManager.default.temporaryDirectory
            .appendingPathComponent("shout-watcher-pfade-\(UUID().uuidString)", isDirectory: true)
        let unter = echt.appendingPathComponent(".obsidian", isDirectory: true)
        try FileManager.default.createDirectory(at: unter, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: echt) }

        var pfade: [String] = []
        let gemeldet = expectation(description: "Pfade gemeldet")
        gemeldet.assertForOverFulfill = false
        let watcher = try XCTUnwrap(NoteFolderWatcher(url: echt, latency: 0.1, onPaths: { neu in
            pfade += neu
            if neu.contains(where: { $0.hasSuffix("/B.md") }) { gemeldet.fulfill() }
        }))
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            try? Data("x".utf8).write(to: unter.appendingPathComponent("a.json"))
            try? Data("x".utf8).write(to: echt.appendingPathComponent("B.md"))
        }
        wait(for: [gemeldet], timeout: 5)
        withExtendedLifetime(watcher) {}
        XCTAssertTrue(NoteFolderWatcher.concernsFolder(pfade.filter { $0.hasSuffix("/B.md") }, folder: echt))
        XCTAssertFalse(NoteFolderWatcher.concernsFolder(pfade.filter { $0.hasSuffix("/a.json") }, folder: echt))
    }
}
