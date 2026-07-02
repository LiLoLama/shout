import AppKit

/// Fügt Text an der aktuellen Cursor-Position ein.
///
/// Ablauf: Text in die Zwischenablage → kurz warten (damit sie sicher bereit
/// ist) → synthetisches ⌘V → danach die vorherige Zwischenablage
/// wiederherstellen, damit shout. sie nicht dauerhaft überschreibt.
/// Braucht die Bedienungshilfen-Freigabe (für ⌘V).
final class TextInjector {

    private let virtualKeyV: CGKeyCode = 0x09  // "v"

    func paste(_ text: String) {
        let pasteboard = NSPasteboard.general
        let previous = pasteboard.string(forType: .string)

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

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
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: virtualKeyV, keyDown: false)
        keyUp?.flags = .maskCommand
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }
}
