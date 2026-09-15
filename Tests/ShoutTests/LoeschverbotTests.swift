import XCTest

/// Der Wächter für die Zusage der Modellverzeichnis-Erweiterung: **Sie löscht
/// nichts.**
///
/// Die Ordner, in denen sie sucht, gehören jemand anderem — LM Studio, ein
/// eigenes Archiv, eine externe Platte. Ein Aufräumen wäre dort nicht bloß ein
/// Fehler, sondern ein Datenverlust, den niemand angefordert hat. Diese Zusage
/// steht an mehreren Stellen im Code als Kommentar; hier steht sie als Test.
///
/// Geprüft wird der Quelltext selbst, nicht das Verhalten: Ein Verhaltenstest
/// könnte nur zeigen, dass ein bestimmter Weg nichts löscht, nie dass es
/// keinen solchen Weg gibt.
final class LoeschverbotTests: XCTestCase {

    /// Die Dateien der Erweiterung, die auf dem Dateisystem arbeiten.
    private let dateien = ["ModelStore.swift", "ModelScan.swift", "ModelPaths.swift"]

    /// `removeObject(forKey:)` steht bewusst NICHT dabei: Das räumt eine
    /// Einstellung ab, keine Datei — `ModelPaths.sichern(in:)` braucht es, um
    /// eine zurückgenommene Ordnerwahl auch wirklich zurückzunehmen.
    private let verbotene = [
        "removeItem", "trashItem", "unlinkItem", "replaceItem",
        "remove(atPath", "unlink(", "rmdir", "truncate", "createFile",
    ]

    func testModellverzeichnisLoeschtNichts() throws {
        let quellordner = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // Tests/ShoutTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // Projektwurzel
            .appendingPathComponent("Sources", isDirectory: true)
            .appendingPathComponent("FlowLokal", isDirectory: true)

        for datei in dateien {
            let pfad = quellordner.appendingPathComponent(datei)
            // Ohne diese Prüfung ginge der Wächter still durch, sobald eine
            // Datei umzieht — und bewachte dann gar nichts mehr.
            XCTAssertTrue(FileManager.default.fileExists(atPath: pfad.path),
                          "Quelldatei nicht gefunden: \(pfad.path)")
            let text = try String(contentsOf: pfad, encoding: .utf8)
            for aufruf in verbotene {
                XCTAssertFalse(text.contains(aufruf),
                               "\(datei) enthält „\(aufruf)“ — die Erweiterung darf nichts löschen oder überschreiben.")
            }
        }
    }
}
