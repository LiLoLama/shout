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

    /// Gesicherter Original-Inhalt der Zwischenablage (ALLE Typen, nicht nur Text)
    /// und die geplante Wiederherstellung. Nur auf dem Main-Thread benutzt.
    private var savedItems: [NSPasteboardItem]?
    private var restoreWorkItem: DispatchWorkItem?
    private var restorePending = false

    func paste(_ text: String) {
        let pasteboard = NSPasteboard.general

        if !restorePending {
            // Erstes Einfügen einer Serie → den ECHTEN Nutzer-Inhalt vollständig sichern
            // (Text, Bild, RTF …). Tiefe Kopie, da Pasteboard-Items flüchtig sind.
            savedItems = pasteboard.pasteboardItems?.map { item in
                let copy = NSPasteboardItem()
                for type in item.types {
                    if let data = item.data(forType: type) { copy.setData(data, forType: type) }
                }
                return copy
            }
        } else {
            // Serie läuft (schnell hintereinander diktiert): geplante Wiederherstellung
            // abbrechen und den ursprünglichen Snapshot behalten — sonst würde das
            // zweite Diktat den Text des ersten als „Original" sichern und wiederherstellen.
            restoreWorkItem?.cancel()
            restoreWorkItem = nil
        }
        restorePending = true

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
        }

        // Restore-WorkItem SOFORT erzeugen und referenzieren (nicht erst im 0,06-s-Block)
        // — sonst kann ein Folge-paste() im Fenster davor es nicht canceln, beide Restores
        // laufen, und der zweite schreibt eine bereits geleerte Zwischenablage zurück.
        let restore = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let pb = NSPasteboard.general
            pb.clearContents()
            if let items = self.savedItems, !items.isEmpty { pb.writeObjects(items) }
            self.savedItems = nil
            self.restorePending = false
            self.restoreWorkItem = nil
        }
        restoreWorkItem = restore
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.41, execute: restore)
    }

    /// Schreibt Text als vertraulich/transient in die Zwischenablage (mit den
    /// Concealed/Transient-Markern), OHNE ⌘V — für den Fall, dass kein Ziel-Fenster
    /// bekannt ist. So landet Diktattext nicht in Clipboard-Historien.
    func copyConcealed(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.declareTypes([.string, concealedType, transientType], owner: nil)
        pb.setString(text, forType: .string)
        pb.setData(Data("1".utf8), forType: concealedType)
        pb.setData(Data("1".utf8), forType: transientType)
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
