import AppKit
import UniformTypeIdentifiers

/// Bilder in Notizen: Sie liegen als PNG in `Anhänge/` neben den Notizen, im
/// Text steht nur der Link — so liest Obsidian sie genauso.
enum NoteAttachments {

    /// Fest, nicht übersetzt: Der Ordner steht in den Links der Dateien.
    static let folderName = "Anhänge"
    static let maxBytes = 10 * 1024 * 1024

    enum Failure: Error, Equatable {
        case tooLarge
        case unreadable
        case writeFailed
    }

    enum Source: Equatable {
        case file(URL)
        case data(Data)
    }

    /// Was auf der Zwischenablage oder im Drag liegt: zuerst Bilddateien (Finder),
    /// dann Bilddaten — aber nur, wenn kein Text dabei ist (aus dem Browser
    /// kopierter Text bringt oft ein Bild mit; dann ist der Text gemeint).
    static func source(from pasteboard: NSPasteboard) -> Source? {
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self],
                                             options: [.urlReadingFileURLsOnly: true]) as? [URL],
           let bild = urls.first(where: isImageFile) {
            return .file(bild)
        }
        guard pasteboard.string(forType: .string) == nil else { return nil }
        for typ in [NSPasteboard.PasteboardType.png, .tiff] {
            if let daten = pasteboard.data(forType: typ) { return .data(daten) }
        }
        return nil
    }

    static func isImageFile(_ url: URL) -> Bool {
        UTType(filenameExtension: url.pathExtension)?.conforms(to: .image) ?? false
    }

    /// „2026-10-05-143210.png“, bei Gleichheit „…-2.png“.
    static func fileName(at date: Date, timeZone: TimeZone = .current, isTaken: (String) -> Bool) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = timeZone
        f.dateFormat = "yyyy-MM-dd-HHmmss"
        let stamm = f.string(from: date)
        var name = "\(stamm).png"
        var zahl = 2
        while isTaken(name) {
            name = "\(stamm)-\(zahl).png"
            zahl += 1
        }
        return name
    }

    /// PNG bleibt, wie es ist; alles andere wird PNG. `nil`, wenn es kein Bild ist.
    static func pngData(from data: Data) -> Data? {
        if data.starts(with: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) { return data }
        let rep = NSBitmapImageRep(data: data)
            ?? NSImage(data: data)?.tiffRepresentation.flatMap { NSBitmapImageRep(data: $0) }
        return rep?.representation(using: .png, properties: [:])
    }

    /// Legt das Bild ab und gibt den Pfad für den Link zurück („Anhänge/…png“).
    static func store(_ source: Source, in noteFolder: URL, now: Date = Date(),
                      fileManager: FileManager = .default) -> Result<String, Failure> {
        let roh: Data
        switch source {
        case .data(let daten):
            roh = daten
        case .file(let url):
            let groesse = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            guard groesse <= maxBytes else { return .failure(.tooLarge) }
            guard let daten = try? Data(contentsOf: url) else { return .failure(.unreadable) }
            roh = daten
        }
        guard roh.count <= maxBytes else { return .failure(.tooLarge) }
        guard let png = pngData(from: roh) else { return .failure(.unreadable) }
        let ordner = noteFolder.appendingPathComponent(folderName, isDirectory: true)
        do {
            try fileManager.createDirectory(at: ordner, withIntermediateDirectories: true)
            let name = fileName(at: now) { fileManager.fileExists(atPath: ordner.appendingPathComponent($0).path) }
            try png.write(to: ordner.appendingPathComponent(name), options: .withoutOverwriting)
            return .success("\(folderName)/\(name)")
        } catch {
            NSLog("shout: Bild nicht gesichert: \(error)")
            return .failure(.writeFailed)
        }
    }

    static func markdown(for path: String) -> String { "![](\(path))" }

    /// Der Link in einer eigenen Zeile.
    static func insertion(for path: String, after vorher: Character?, before nachher: Character?) -> String {
        var text = markdown(for: path)
        if let vorher, vorher != "\n" { text = "\n" + text }
        if nachher != "\n" { text += "\n" }
        return text
    }

    /// Ein Bildpfad aus dem Text — nur relativ und nur innerhalb des Notizordners.
    static func resolve(_ path: String, in noteFolder: URL) -> URL? {
        let pfad = path.removingPercentEncoding ?? path
        guard !pfad.isEmpty, !pfad.hasPrefix("/"), !pfad.contains("://") else { return nil }
        let basis = noteFolder.standardizedFileURL
        let ziel = basis.appendingPathComponent(pfad).standardizedFileURL
        guard ziel.path.hasPrefix(basis.path + "/") else { return nil }
        return ziel
    }
}
