import XCTest

/// Wegwerf-Umgebung für die Notiz-Tests: Notizordner, Puffer und ein eigener
/// Papierkorb unter einem Temp-Verzeichnis. Der echte Papierkorb bleibt sauber.
@MainActor
final class NotizUmgebung {
    let wurzel: URL
    let ordner: URL
    let puffer: URL
    let papierkorb: URL

    init() throws {
        wurzel = FileManager.default.temporaryDirectory
            .appendingPathComponent("shout-notizen-\(UUID().uuidString)", isDirectory: true)
        ordner = wurzel.appendingPathComponent("Notizen", isDirectory: true)
        puffer = wurzel.appendingPathComponent("Puffer", isDirectory: true)
        papierkorb = wurzel.appendingPathComponent("Papierkorb", isDirectory: true)
        for o in [ordner, papierkorb] {
            try FileManager.default.createDirectory(at: o, withIntermediateDirectories: true)
        }
    }

    /// Eingehängtes Disk-Image, solange ein Test eines braucht.
    private var eingehaengt: URL?

    func aufraeumen() {
        if let eingehaengt {
            _ = try? Self.hdiutil(["detach", "-force", eingehaengt.path])
        }
        try? FileManager.default.removeItem(at: wurzel)
    }

    /// Ein eigenes Volume (Disk-Image) — so liegen Notizordner und Puffer auf
    /// verschiedenen Laufwerken wie bei einem USB-Stick. Kann das System keines
    /// einhängen, wird der Test übersprungen.
    func laufwerk() throws -> URL {
        if let eingehaengt { return eingehaengt }
        let bild = wurzel.appendingPathComponent("stick.dmg")
        let punkt = wurzel.appendingPathComponent("Stick", isDirectory: true)
        try FileManager.default.createDirectory(at: punkt, withIntermediateDirectories: true)
        do {
            try Self.hdiutil(["create", "-size", "8m", "-fs", "APFS", "-volname", "ShoutStick", bild.path])
            try Self.hdiutil(["attach", "-nobrowse", "-noverify", "-mountpoint", punkt.path, bild.path])
        } catch {
            throw XCTSkip("Disk-Image nicht einhängbar: \(error)")
        }
        eingehaengt = punkt
        return punkt
    }

    private static func hdiutil(_ argumente: [String]) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        p.arguments = argumente
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try p.run()
        p.waitUntilExit()
        if p.terminationStatus != 0 { throw CocoaError(.fileWriteUnknown) }
    }

    func store(ordner anderer: URL? = nil, puffer anderer2: URL? = nil,
               createIfMissing: Bool = false) -> NoteStore {
        let korb = papierkorb
        return NoteStore(folder: anderer ?? ordner, bufferFolder: anderer2 ?? puffer, watch: false,
                         createIfMissing: createIfMissing) { url in
            let ziel = korb.appendingPathComponent(UUID().uuidString + "-" + url.lastPathComponent)
            try FileManager.default.moveItem(at: url, to: ziel)
            return ziel
        }
    }

    /// Schreibt eine Datei wie ein fremdes Programm. `zeit` setzt das mtime —
    /// so sind Änderungen „von außen“ sicher von der eigenen unterscheidbar.
    func schreibe(_ name: String, _ inhalt: String, zeit: Date? = nil) throws {
        let url = ordner.appendingPathComponent(name)
        try Data(inhalt.utf8).write(to: url)
        if let zeit {
            try FileManager.default.setAttributes([.modificationDate: zeit], ofItemAtPath: url.path)
        }
    }

    func lies(_ name: String) -> String? {
        try? String(contentsOf: ordner.appendingPathComponent(name), encoding: .utf8)
    }

    /// Nur der Text, ohne Frontmatter.
    func text(_ name: String) -> String? { lies(name).map { NoteFile.parse($0).body } }

    func dateien() -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: ordner.path)) ?? []).sorted()
    }
}
