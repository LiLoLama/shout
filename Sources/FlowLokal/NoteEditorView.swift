import SwiftUI
import AppKit

/// Ein Fenster, das sich mit Esc ausblenden lässt (das Panel). Im Editor öffnet
/// Esc sonst die Wortvervollständigung.
@MainActor
protocol HidesOnEscape: AnyObject {
    func hideOnEscape()
}

/// Der Editor einer Notiz: ein `NSTextView`, weil SwiftUIs `TextEditor` die
/// Cursorposition erst ab macOS 15 herausgibt — und das Diktat genau dorthin
/// muss. Klartext, Markdown nur in der Darstellung.
struct NoteEditorView: NSViewRepresentable {
    @ObservedObject var session: NoteEditorSession
    /// Neue, leere Notiz: sofort hineinschreiben können.
    var autofocus = false
    /// Steigt, wenn die Seite den Fokus in den Editor holen will (⏎ in der Liste).
    var focusRequest = 0

    func makeCoordinator() -> Coordinator { Coordinator(session: session) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        let textView = scroll.documentView as! NSTextView
        Self.configure(textView)
        textView.delegate = context.coordinator
        // `NSTextStorage.delegate` ist schwach; der Coordinator hält die Hervorhebung.
        let highlighter = context.coordinator.highlighter
        // Während markierter Text entsteht (Option+U …), nicht neu gestalten.
        highlighter.shouldSkip = { [weak textView] in
            MainActor.assumeIsolated { textView?.hasMarkedText() ?? false }
        }
        textView.textStorage?.delegate = highlighter
        textView.string = session.note.body
        textView.isEditable = session.status != .placeholder

        let c = context.coordinator
        c.textView = textView
        c.revision = session.externalRevision
        c.editRevision = session.editRevision
        c.focusRequest = focusRequest
        // Den zuletzt gemeldeten Cursor übernehmen (geklemmt) — ein neuer Editor
        // derselben Notiz setzt dort fort.
        let laenge = (textView.string as NSString).length
        c.setztSelbst = true
        textView.setSelectedRange(NSRange(location: min(session.lastSelection.location, laenge), length: 0))
        c.setztSelbst = false
        session.attach(editor: c)
        if autofocus {
            DispatchQueue.main.async { textView.window?.makeFirstResponder(textView) }
        }
        return scroll
    }

    static func dismantleNSView(_ nsView: NSScrollView, coordinator: Coordinator) {
        coordinator.session.detach(editor: coordinator)
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        let c = context.coordinator
        guard let textView = c.textView else { return }
        // Erst freigeben, dann ersetzen: Kommt eine Notiz aus iCloud an, wechseln
        // Text und Sperre im selben Durchlauf — ein gesperrter Editor nähme den
        // Text sonst nicht an.
        textView.isEditable = session.status != .placeholder
        if c.revision != session.externalRevision {
            c.revision = session.externalRevision
            c.editRevision = session.editRevision
            c.replaceText(with: session.note.body)
        } else if c.editRevision != session.editRevision {
            c.editRevision = session.editRevision
            // Die Eingabe kam aus einem anderen Editor (oder ohne Editor): angleichen.
            if session.lastEditSource !== c { c.mirror(session.note.body) }
        }
        if c.focusRequest != focusRequest {
            c.focusRequest = focusRequest
            DispatchQueue.main.async { textView.window?.makeFirstResponder(textView) }
        }
    }

    private static func configure(_ tv: NSTextView) {
        typealias Style = MarkdownHighlighter.Style
        tv.isRichText = false
        tv.importsGraphics = false
        tv.allowsUndo = true
        // Markdown braucht gerade Anführungszeichen und echte Bindestriche.
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.isContinuousSpellCheckingEnabled = true
        tv.usesFindBar = true
        tv.isIncrementalSearchingEnabled = true
        tv.drawsBackground = false
        tv.font = Style.body
        tv.textColor = Style.text
        tv.typingAttributes = Style.baseAttributes
        tv.insertionPointColor = Style.accent
        tv.selectedTextAttributes = [.backgroundColor: Style.accent.withAlphaComponent(0.30)]
        tv.textContainerInset = NSSize(width: 18, height: 16)
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate, NoteTextEditing {
        let session: NoteEditorSession
        let highlighter = MarkdownHighlighter()
        /// Eigenes Rückgängig je Editor. Das Fenster teilt sonst eines für alle
        /// Tabs, und ⌘Z in einem Tab träfe Schritte eines anderen.
        let undo = UndoManager()
        weak var textView: NSTextView?
        var revision = 0
        var editRevision = 0
        var focusRequest = 0
        /// Während der Editor selbst Text oder Auswahl setzt (Angleichen, Ersetzen),
        /// ist eine Auswahländerung keine Handlung des Nutzers.
        var setztSelbst = false
        /// Während des Angleichens meldet der Editor keinen Text an die Sitzung:
        /// Was er dabei festschreibt (eine offene Komposition), ist veraltet.
        private var gleichtAn = false

        init(session: NoteEditorSession) { self.session = session }

        /// Der Text ohne offene Komposition (Option+U, Eingabemethoden). Die
        /// meldet `NSTextView` erst, wenn sie festgeschrieben ist; bis dahin
        /// kennt die Sitzung sie nicht.
        private func gemeldeterText(_ tv: NSTextView) -> String {
            guard tv.hasMarkedText() else { return tv.string }
            let ns = tv.string as NSString
            let markiert = tv.markedRange()
            guard markiert.location != NSNotFound, NSMaxRange(markiert) <= ns.length else { return tv.string }
            return ns.replacingCharacters(in: markiert, with: "")
        }

        func undoManager(for view: NSTextView) -> UndoManager? { undo }

        func textDidChange(_ notification: Notification) {
            guard !gleichtAn, let tv = notification.object as? NSTextView else { return }
            session.edit(tv.string, from: self)
            editRevision = session.editRevision
        }

        /// Zeigt der Editor eine ältere Fassung als die Sitzung (ein anderer Editor
        /// hat geschrieben, SwiftUI hat noch nicht angeglichen), meldete die
        /// Änderung seinen alten Text als neuen — die neuere Fassung wäre still
        /// weg. Dann gleicht er erst an und lehnt diesen Anschlag sichtbar ab.
        func textView(_ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange,
                      replacementString: String?) -> Bool {
            guard !setztSelbst, gemeldeterText(textView) != session.note.body else { return true }
            mirror(session.note.body)
            return false
        }

        /// Ein Klick oder Pfeil im Editor: Dorthin geht das nächste Diktat.
        func textViewDidChangeSelection(_ notification: Notification) {
            guard !setztSelbst, let tv = notification.object as? NSTextView else { return }
            session.selectionChanged(tv.selectedRange())
            session.attach(editor: self)
        }

        /// Esc im Panel blendet es aus, statt die Wortvervollständigung zu öffnen.
        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            guard commandSelector == #selector(NSResponder.cancelOperation(_:)),
                  let fenster = textView.window as? HidesOnEscape else { return false }
            fenster.hideOnEscape()
            return true
        }

        // MARK: NoteTextEditing

        /// Fügt als ein Rückgängig-Schritt ein. `.cursor` ersetzt die Auswahl und
        /// setzt den Cursor dahinter; `.end` hängt an und lässt den Cursor stehen.
        func insertText(_ text: String, at point: NoteEditorSession.InsertionPoint) -> Bool {
            guard let tv = textView, tv.isEditable else { return false }
            // Zeigt der Editor noch eine ältere Fassung (die Sitzung hat neu geladen
            // oder ein anderer Editor geschrieben, und SwiftUI hat noch nicht
            // angeglichen), meldete er beim Einfügen seinen alten Text als neuen —
            // und überschriebe damit die neuere Fassung. Dann lieber ablehnen: Die
            // Sitzung fügt selbst ein und lädt den Editor neu.
            guard gemeldeterText(tv) == session.note.body else { return false }
            // Eine offene Komposition zuerst festschreiben; sie wird dabei gemeldet.
            if tv.hasMarkedText() { tv.unmarkText() }
            let ns = tv.string as NSString
            let ziel = point == .end ? NSRange(location: ns.length, length: 0) : tv.selectedRange()
            let vorher: Character? = ziel.location > 0
                ? ns.substring(with: ns.rangeOfComposedCharacterSequence(at: ziel.location - 1)).last
                : nil
            let einfuegen = point == .end ? text : DictationInsertion.text(text, after: vorher)
            let auswahlVorher = tv.selectedRange()
            tv.breakUndoCoalescing()
            guard tv.shouldChangeText(in: ziel, replacementString: einfuegen) else { return false }
            tv.textStorage?.replaceCharacters(in: ziel, with: einfuegen)
            tv.didChangeText()
            tv.breakUndoCoalescing()
            if point == .cursor {
                let danach = NSRange(location: ziel.location + (einfuegen as NSString).length, length: 0)
                tv.setSelectedRange(danach)
                tv.scrollRangeToVisible(danach)
            } else {
                setztSelbst = true
                tv.setSelectedRange(auswahlVorher)
                setztSelbst = false
                // Hat das Anhängen die Auswahl unterwegs verschoben und gemeldet,
                // stimmt der gemerkte Cursor der Sitzung wieder.
                session.selectionChanged(auswahlVorher)
            }
            return true
        }

        /// Übernimmt eine Fassung von außen als normale Bearbeitung — so holt ⌘Z
        /// die eigene Fassung zurück. Der Cursor bleibt, so gut es geht, stehen.
        func replaceText(with text: String) {
            guard let tv = textView, tv.string != text else { return }
            let ganz = NSRange(location: 0, length: (tv.string as NSString).length)
            let auswahl = tv.selectedRange()
            setztSelbst = true
            defer { setztSelbst = false }
            if tv.shouldChangeText(in: ganz, replacementString: text) {
                tv.textStorage?.replaceCharacters(in: ganz, with: text)
                tv.didChangeText()
            } else {
                // Gesperrt (Platzhalter): ohne Rückgängig, aber der Editor zeigt,
                // was die Sitzung hält — sonst klafften beide still auseinander.
                tv.textStorage?.replaceCharacters(in: ganz, with: text)
            }
            let laenge = (text as NSString).length
            tv.setSelectedRange(NSRange(location: min(auswahl.location, laenge), length: 0))
        }

        /// Gleicht an einen anderen Editor derselben Notiz an: ohne Rückgängig-
        /// Schritt, und die eigenen Schritte passen danach nicht mehr zum Text.
        func mirror(_ text: String) {
            // Unterscheidet sich nur die offene Komposition, ist nichts anzugleichen.
            guard let tv = textView, gemeldeterText(tv) != text else { return }
            setztSelbst = true
            defer { setztSelbst = false }
            // Eine offene Komposition festschreiben, ohne sie zu melden: Sie hängt
            // am veralteten Text und wird gleich mit ersetzt.
            if tv.hasMarkedText() {
                gleichtAn = true
                tv.unmarkText()
                gleichtAn = false
            }
            let auswahl = tv.selectedRange()
            tv.textStorage?.replaceCharacters(in: NSRange(location: 0, length: (tv.string as NSString).length), with: text)
            tv.breakUndoCoalescing()
            undo.removeAllActions()
            let laenge = (text as NSString).length
            tv.setSelectedRange(NSRange(location: min(auswahl.location, laenge), length: 0))
        }
    }
}
