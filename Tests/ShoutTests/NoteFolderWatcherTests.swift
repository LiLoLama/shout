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
        let ziel = ordner.appendingPathComponent("a.md")
        try Data("alt".utf8).write(to: ziel)
        let gemeldet = expectation(description: "Änderung gemeldet")
        gemeldet.assertForOverFulfill = false
        let watcher = try XCTUnwrap(NoteFolderWatcher(url: ordner, latency: 0.1) { gemeldet.fulfill() })
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            guard let handle = try? FileHandle(forWritingTo: ziel) else { return }
            handle.seekToEndOfFile()
            handle.write(Data(" neu".utf8))
            try? handle.close()
        }
        wait(for: [gemeldet], timeout: 5)
        withExtendedLifetime(watcher) {}
    }
}
