import AppKit

// Einstiegspunkt. Wir bauen eine reine Menu-Bar-App (kein Dock-Icon),
// die per Delegate hochfährt. LSUIElement in der Info.plist sorgt zusätzlich
// dafür, dass kein Dock-Icon erscheint; .accessory ist der Laufzeit-Riegel.
//
// Top-Level-Code läuft beim Start bereits auf dem Main-Thread; assumeIsolated
// stellt das dem Compiler gegenüber sicher, damit wir den @MainActor-Delegate
// direkt erzeugen dürfen.
MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
