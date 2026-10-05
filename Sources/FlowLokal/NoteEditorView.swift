import SwiftUI
import AppKit

/// Der Editor einer Notiz: ein `NSTextView`, weil SwiftUIs `TextEditor` die
/// Cursorposition erst ab macOS 15 herausgibt — und das Diktat (Plan 2) genau
/// dorthin muss. Klartext, Markdown nur in der Darstellung.
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
        c.focusRequest = focusRequest
        if autofocus {
            DispatchQueue.main.async { textView.window?.makeFirstResponder(textView) }
        }
        return scroll
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
            c.replaceText(with: session.note.body)
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
    final class Coordinator: NSObject, NSTextViewDelegate {
        let session: NoteEditorSession
        let highlighter = MarkdownHighlighter()
        weak var textView: NSTextView?
        var revision = 0
        var focusRequest = 0

        init(session: NoteEditorSession) { self.session = session }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            session.edit(tv.string)
        }

        /// Übernimmt eine Fassung von außen als normale Bearbeitung — so holt ⌘Z
        /// die eigene Fassung zurück. Der Cursor bleibt, so gut es geht, stehen.
        func replaceText(with text: String) {
            guard let tv = textView, tv.string != text else { return }
            let ganz = NSRange(location: 0, length: (tv.string as NSString).length)
            let auswahl = tv.selectedRange()
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
    }
}
