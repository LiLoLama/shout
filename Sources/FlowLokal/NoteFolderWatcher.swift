import Foundation
import CoreServices

/// Meldet Änderungen im Notizordner über FSEvents — auch Bearbeitungen an Ort
/// und Stelle, die ein `DispatchSource` auf den Ordner nicht sähe. Die Meldungen
/// kommen gebündelt (`latency`) auf der Hauptwarteschlange, mit den geänderten
/// Pfaden; ob sie die Notizliste betreffen, prüft `concernsFolder`. Der Store
/// liest dann einfach neu ein.
final class NoteFolderWatcher {

    /// Zwischenstück zwischen Strom und Watcher. Der Strom besitzt den Kasten
    /// (retain/release im Kontext), der Kasten kennt den Watcher nur schwach:
    /// Ein Rückruf, der nach `deinit` noch auf der Hauptwarteschlange wartet,
    /// findet dann `nil` statt eines freigegebenen Objekts — und es gibt keinen
    /// Retain-Zyklus mit `self`.
    private final class Kasten {
        weak var watcher: NoteFolderWatcher?
    }

    private var stream: FSEventStreamRef?
    private let onChange: ([String]) -> Void

    init?(url: URL, latency: TimeInterval = 0.5, onPaths: @escaping ([String]) -> Void) {
        self.onChange = onPaths

        // Besitz: `kasten` lebt durch die lokale starke Referenz bis zum Ende des
        // Initialisierers. Weil der Kontext `retain` setzt, ruft FSEventStreamCreate
        // es selbst einmal auf; deshalb wird hier `passUnretained` übergeben — ein
        // zusätzliches `passRetained` würde den Kasten dauerhaft leaken. Der Strom
        // hält den Kasten ab dann selbst und gibt ihn beim Release wieder frei.
        let kasten = Kasten()
        kasten.watcher = self
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(kasten).toOpaque(),
            retain: { info in
                guard let info else { return nil }
                _ = Unmanaged<Kasten>.fromOpaque(info).retain()
                return info
            },
            release: { info in
                guard let info else { return }
                Unmanaged<Kasten>.fromOpaque(info).release()
            },
            copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, _, eventPaths, _, _ in
            guard let info else { return }
            // Mit `UseCFTypes` kommen die Pfade als `CFArray` von `CFString`.
            let pfade = (Unmanaged<CFArray>.fromOpaque(eventPaths).takeUnretainedValue() as NSArray) as? [String] ?? []
            Unmanaged<Kasten>.fromOpaque(info).takeUnretainedValue().watcher?.onChange(pfade)
        }
        // Echte Pfade: Temp-Ordner liegen hinter dem Symlink /var → /private/var.
        let pfad = url.resolvingSymlinksInPath().path
        guard let stream = FSEventStreamCreate(
            nil, callback, &context, [pfad] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow), latency,
            UInt32(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes)) else { return nil }
        FSEventStreamSetDispatchQueue(stream, .main)
        guard FSEventStreamStart(stream) else {
            // Nie gestartet: Strom abbauen (gibt auch den Kasten wieder frei).
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            return nil
        }
        self.stream = stream
    }

    /// Für Aufrufer ohne Pfade.
    convenience init?(url: URL, latency: TimeInterval = 0.5, onChange: @escaping () -> Void) {
        self.init(url: url, latency: latency, onPaths: { _ in onChange() })
    }

    /// Betreffen die gemeldeten Pfade die Notizliste? Nur Dateien direkt im
    /// Ordner (oder der Ordner selbst). Unterordner (`.obsidian/`, `Anhänge/`)
    /// und versteckte Dateien nicht — ausgelagerte iCloud-Notizen (`.X.md.icloud`)
    /// schon. Ohne Pfade sicherheitshalber ja.
    static func concernsFolder(_ paths: [String], folder: URL) -> Bool {
        guard !paths.isEmpty else { return true }
        let ordner = folder.resolvingSymlinksInPath().standardizedFileURL.path
        return paths.contains { pfad in
            let datei = URL(fileURLWithPath: pfad).standardizedFileURL
            if datei.path == ordner { return true }
            guard datei.deletingLastPathComponent().path == ordner else { return false }
            let name = datei.lastPathComponent
            return !name.hasPrefix(".") || NoteFile.placeholderTarget(name) != nil
        }
    }

    deinit {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
    }
}
