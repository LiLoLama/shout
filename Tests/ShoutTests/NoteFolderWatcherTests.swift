import XCTest

/// FSEvents statt `DispatchSource` auf den Ordner: Bearbeitet Obsidian oder vim
/// eine Datei an Ort und Stelle, ändert sich der Ordner selbst nicht — nur die
/// Datei darin. Genau das muss trotzdem gemeldet werden.
final class NoteFolderWatcherTests: XCTestCase {

    private var ordner: URL!

    override func setUpWithError() throws {
        ordner = FileManager.default.temporaryDirectory
            .appendingPathComponent("shout-watcher-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: ordner, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: ordner)
    }

    func testMeldetNeueDatei() throws {
        let gemeldet = expectation(description: "Änderung gemeldet")
        gemeldet.assertForOverFulfill = false
        let watcher = try XCTUnwrap(NoteFolderWatcher(url: ordner, latency: 0.1) { gemeldet.fulfill() })
        // FSEvents braucht einen Moment, bis der Strom läuft.
        let ziel = ordner.appendingPathComponent("a.md")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            try? Data("x".utf8).write(to: ziel)
        }
        wait(for: [gemeldet], timeout: 5)
        withExtendedLifetime(watcher) {}
    }

    func testMeldetAenderungAnOrtUndStelle() throws {
        // Die Startdatei muss vor dem Watcher liegen und ihre Ereignisse müssen
        // verklungen sein — sonst würde der Test das Anlegen statt der
        // Bearbeitung an Ort und Stelle messen.
        let ziel = ordner.appendingPathComponent("a.md")
        try Data("alt".utf8).write(to: ziel)
        let abgewartet = expectation(description: "Startdatei abgeklungen")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { abgewartet.fulfill() }
        wait(for: [abgewartet], timeout: 5)

        var meldungen = 0
        let gemeldet = expectation(description: "Änderung gemeldet")
        gemeldet.assertForOverFulfill = false
        let watcher = try XCTUnwrap(NoteFolderWatcher(url: ordner, latency: 0.1) {
            meldungen += 1
            gemeldet.fulfill()
        })
        // Der Strom startet mit „seit jetzt“; vor dem Anhängen kurz warten und
        // sicherstellen, dass bis dahin nichts gemeldet wurde.
        let bereit = expectation(description: "Strom läuft")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { bereit.fulfill() }
        wait(for: [bereit], timeout: 5)
        XCTAssertEqual(meldungen, 0, "Vor der Bearbeitung darf nichts gemeldet werden")

        let handle = try FileHandle(forWritingTo: ziel)
        handle.seekToEndOfFile()
        handle.write(Data(" neu".utf8))
        try handle.close()

        wait(for: [gemeldet], timeout: 5)
        XCTAssertGreaterThanOrEqual(meldungen, 1)
        withExtendedLifetime(watcher) {}
    }

    /// Nach dem Freigeben darf kein Rückruf mehr kommen — auch keiner, der schon
    /// auf der Hauptwarteschlange eingereiht war.
    func testStopptNachFreigabe() throws {
        let gemeldet = expectation(description: "Nach Freigabe gemeldet")
        gemeldet.isInverted = true
        var watcher: NoteFolderWatcher? = NoteFolderWatcher(url: ordner, latency: 0.1) {
            gemeldet.fulfill()
        }
        XCTAssertNotNil(watcher)
        watcher = nil
        try Data("x".utf8).write(to: ordner.appendingPathComponent("b.md"))
        wait(for: [gemeldet], timeout: 1.5)
    }
}
