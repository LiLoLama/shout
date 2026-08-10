import Foundation

/// Baut die Dateinamen, die im Sichern-Dialog vorgeschlagen werden.
///
/// Eigener Typ, weil der Zusatz für den Rohtext leicht falsch zu machen ist: Ohne
/// ihn schlägt der Dialog für beide Fassungen denselben Namen vor, und das zweite
/// Sichern überschreibt stillschweigend das erste.
enum TranscriptExport {

    /// `Interview.m4a` + „-roh" + „txt" → `Interview-roh.txt`.
    ///
    /// Die Endung der Quelldatei fällt weg (nur die letzte — „Mein.Interview.v2.mp4"
    /// behält seine Punkte). Hat die Quelle keinen brauchbaren Namen, springt
    /// „Transkript" ein, damit nie eine Datei namens „.txt" vorgeschlagen wird.
    static func fileName(for source: URL, suffix: String, extension ext: String) -> String {
        var base = source.deletingPathExtension().lastPathComponent
        if base.isEmpty || base == "/" { base = "Transkript" }
        return base + suffix + "." + ext
    }
}
