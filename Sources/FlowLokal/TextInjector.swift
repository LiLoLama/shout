import AppKit

/// Fügt Text an der aktuellen Cursor-Position ein.
///
/// v0-Ansatz: Text ins Pasteboard schreiben und ein synthetisches ⌘V posten.
/// Robust und app-übergreifend, braucht aber die Accessibility-Berechtigung.
/// (Direktes Tippen via CGEvent-Keystrokes wäre eine spätere Alternative,
/// verliert aber bei Sonderzeichen/Umlauten schnell an Zuverlässigkeit.)
final class TextInjector {

    private let virtualKeyV: CGKeyCode = 0x09  // "v"

    func insert(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        let source = CGEventSource(stateID: .combinedSessionState)

        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: virtualKeyV, keyDown: true)
        keyDown?.flags = .maskCommand
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: virtualKeyV, keyDown: false)
        keyUp?.flags = .maskCommand

        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }
}
