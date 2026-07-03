import AppKit

/// Fügt Text an der aktuellen Cursor-Position ein.
///
/// Ablauf: Text in die Zwischenablage → kurz warten (damit sie sicher bereit
/// ist) → synthetisches ⌘V → danach die vorherige Zwischenablage
/// wiederherstellen, damit shout. sie nicht dauerhaft überschreibt.
/// Braucht die Bedienungshilfen-Freigabe (für ⌘V).
final class TextInjector {

    private let virtualKeyV: CGKeyCode = 0x09  // "v"

    /// Markierung für selbst erzeugte ⌘V-Events, damit die eigenen Hotkey-Monitore
    /// sie ignorieren können ("SHOU").
    static let syntheticEventTag: Int64 = 0x53_48_4F_55

    // Standard-Marker, an denen kooperierende Clipboard-Manager (Maccy, Paste,
    // Alfred …) erkennen, dass sie den Inhalt NICHT in die Historie aufnehmen sollen.
    private let concealedType = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")
    private let transientType = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")

    func paste(_ text: String) {
        let pasteboard = NSPasteboard.general
        let previous = pasteboard.string(forType: .string)

        pasteboard.clearContents()
        pasteboard.declareTypes([.string, concealedType, transientType], owner: nil)
        pasteboard.setString(text, forType: .string)
        // Diktatinhalt als vertraulich/transient kennzeichnen → kein Leak in Clipboard-Historien.
        pasteboard.setData(Data("1".utf8), forType: concealedType)
        pasteboard.setData(Data("1".utf8), forType: transientType)

        // Kurze Pause, damit die Zwischenablage sicher übernommen ist, bevor ⌘V kommt
        // (behebt das gelegentliche „Einfügen kommt nicht an").
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) { [weak self] in
            self?.postCommandV()
            // Nach dem Einfügen die vorherige Zwischenablage zurückschreiben.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                let pb = NSPasteboard.general
                pb.clearContents()
                if let previous { pb.setString(previous, forType: .string) }
            }
        }
    }

    private func postCommandV() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: virtualKeyV, keyDown: true)
        keyDown?.flags = .maskCommand
        keyDown?.setIntegerValueField(.eventSourceUserData, value: Self.syntheticEventTag)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: virtualKeyV, keyDown: false)
        keyUp?.flags = .maskCommand
        keyUp?.setIntegerValueField(.eventSourceUserData, value: Self.syntheticEventTag)
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }
}
