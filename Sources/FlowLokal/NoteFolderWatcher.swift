import Foundation
import CoreServices

/// Meldet Änderungen im Notizordner über FSEvents — auch Bearbeitungen an Ort
/// und Stelle, die ein `DispatchSource` auf den Ordner nicht sähe. Die Meldungen
/// kommen gebündelt (`latency`) auf der Hauptwarteschlange; was sich geändert
/// hat, sagt der Watcher nicht — der Store liest dann einfach neu ein.
final class NoteFolderWatcher {

    private var stream: FSEventStreamRef?
    private let onChange: () -> Void

    init?(url: URL, latency: TimeInterval = 0.5, onChange: @escaping () -> Void) {
        self.onChange = onChange
        var context = FSEventStreamContext(version: 0, info: nil, retain: nil,
                                           release: nil, copyDescription: nil)
        context.info = Unmanaged.passUnretained(self).toOpaque()
        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            Unmanaged<NoteFolderWatcher>.fromOpaque(info).takeUnretainedValue().onChange()
        }
        // Echte Pfade: Temp-Ordner liegen hinter dem Symlink /var → /private/var.
        let pfad = url.resolvingSymlinksInPath().path
        guard let stream = FSEventStreamCreate(
            nil, callback, &context, [pfad] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow), latency,
            UInt32(kFSEventStreamCreateFlagFileEvents)) else { return nil }
        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, .main)
        FSEventStreamStart(stream)
    }

    deinit {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
    }
}
