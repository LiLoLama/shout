import AppKit
import SwiftUI

/// Ob gerade ins Panel diktiert wird — für den Mikrofon-Knopf.
@MainActor
final class ScratchpadMicState: ObservableObject {
    @Published var isRecording = false
}

/// Das schwebende Fenster. Nicht aktivierend: Es nimmt der App davor den Fokus
/// nicht; erst ein Klick in den Text macht es zum Key-Fenster — ohne dass
/// shout. aktiv wird (kein Dock-Symbol, „vorige App“ bleibt die App davor).
final class ScratchpadPanel: NSPanel, HidesOnEscape {
    var onHide: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func cancelOperation(_ sender: Any?) { onHide?() }
    func hideOnEscape() { onHide?() }

    /// Die Editoren verdeckter Tabs bleiben im Fenster (für ihr Rückgängig) und
    /// stehen damit in der Tab-Reihenfolge: ⇥ aus dem Suchfeld landete sonst im
    /// unsichtbaren Editor des ersten Tabs, und man tippte blind hinein. Ein
    /// unsichtbarer Kandidat wird deshalb auf den sichtbaren Editor umgelenkt.
    override func makeFirstResponder(_ responder: NSResponder?) -> Bool {
        guard let view = responder as? NSView, Self.unsichtbar(view) else {
            return super.makeFirstResponder(responder)
        }
        guard let sichtbar = contentView.flatMap(Self.sichtbarerEditor), sichtbar !== view else { return false }
        return super.makeFirstResponder(sichtbar)
    }

    /// SwiftUI setzt für `opacity(0)` den Alpha-Wert einer umgebenden Ansicht auf 0.
    private static func verborgen(_ view: NSView) -> Bool {
        view.isHidden || view.alphaValue == 0 || view.layer?.opacity == 0
    }

    private static func unsichtbar(_ view: NSView) -> Bool {
        var ansicht: NSView? = view
        while let v = ansicht {
            if verborgen(v) { return true }
            ansicht = v.superview
        }
        return false
    }

    private static func sichtbarerEditor(in view: NSView) -> NSTextView? {
        if verborgen(view) { return nil }
        if let text = view as? NSTextView, !text.isFieldEditor, text.acceptsFirstResponder { return text }
        for unter in view.subviews {
            if let treffer = sichtbarerEditor(in: unter) { return treffer }
        }
        return nil
    }
}

/// Ein- und Ausblenden, Rahmen merken. Beim Ausblenden wird gesichert.
@MainActor
final class ScratchpadPanelController: NSObject, NSWindowDelegate {

    static let minSize = CGSize(width: 360, height: 260)
    static let defaultSize = CGSize(width: 520, height: 420)
    private static let rahmenKey = "scratchpad.frame"

    private let model: ScratchpadModel
    private let settings: ScratchpadSettings
    private let mic: ScratchpadMicState
    private let defaults: UserDefaults
    private let onMic: () -> Void
    private var panel: ScratchpadPanel?

    init(model: ScratchpadModel, settings: ScratchpadSettings, mic: ScratchpadMicState,
         defaults: UserDefaults = .standard, onMic: @escaping () -> Void) {
        self.model = model
        self.settings = settings
        self.mic = mic
        self.defaults = defaults
        self.onMic = onMic
    }

    var isVisible: Bool { panel?.isVisible == true }
    /// Hat das Panel den Tastatur-Fokus? Dann schreibt die Diktiertaste hinein.
    var isKey: Bool { panel?.isKeyWindow == true }

    func toggle() {
        if isVisible { hide() } else { show(focus: false) }
    }

    /// Blendet ein, ohne den Fokus zu nehmen — außer `focus` (Klick auf den Toast).
    func show(focus: Bool) {
        let fenster = panel ?? baue()
        if !fenster.isVisible {
            model.prepareForShowing(behavior: settings.openBehavior)
            fenster.setFrame(gespeicherterRahmen(), display: false)
            fenster.orderFrontRegardless()
        }
        if focus { fenster.makeKey() }
    }

    func hide() {
        guard let fenster = panel, fenster.isVisible else { return }
        model.flushAll()
        merke(fenster)
        fenster.orderOut(nil)
    }

    // MARK: NSWindowDelegate

    /// Der Schließen-Knopf blendet aus (das Fenster bleibt bestehen).
    func windowWillClose(_ notification: Notification) {
        model.flushAll()
        if let fenster = panel { merke(fenster) }
    }

    func windowDidMove(_ notification: Notification) {
        if let fenster = panel { merke(fenster) }
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        if let fenster = panel { merke(fenster) }
    }

    // MARK: Intern

    private func baue() -> ScratchpadPanel {
        let fenster = ScratchpadPanel(
            contentRect: NSRect(origin: .zero, size: Self.defaultSize),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered, defer: false)
        fenster.titlebarAppearsTransparent = true
        fenster.titleVisibility = .hidden
        fenster.isFloatingPanel = true
        fenster.level = .floating
        fenster.hidesOnDeactivate = false
        fenster.becomesKeyOnlyIfNeeded = true
        fenster.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        fenster.minSize = NSSize(width: Self.minSize.width, height: Self.minSize.height)
        fenster.isReleasedWhenClosed = false
        fenster.appearance = NSAppearance(named: .darkAqua)
        fenster.backgroundColor = NSColor(Color.shoutWindow)
        fenster.delegate = self
        fenster.onHide = { [weak self] in self?.hide() }
        fenster.contentView = NSHostingView(rootView: ScratchpadView(model: model, store: model.store, mic: mic, onMic: onMic))
        panel = fenster
        return fenster
    }

    private static func kennung(_ bildschirm: NSScreen) -> String? {
        (bildschirm.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.stringValue
    }

    private func gesichert() -> PanelPlacement.Saved? {
        defaults.data(forKey: Self.rahmenKey).flatMap { try? JSONDecoder().decode(PanelPlacement.Saved.self, from: $0) }
    }

    /// Der gemerkte Bildschirm, sonst der mit dem Mauszeiger, sonst der Hauptbildschirm.
    private func bildschirm(fuer gemerkt: PanelPlacement.Saved?) -> NSScreen? {
        if let kennung = gemerkt?.screen,
           let treffer = NSScreen.screens.first(where: { Self.kennung($0) == kennung }) {
            return treffer
        }
        let maus = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(maus, $0.frame, false) } ?? NSScreen.main
    }

    private func gespeicherterRahmen() -> NSRect {
        let gemerkt = gesichert()
        guard let sichtbar = bildschirm(fuer: gemerkt)?.visibleFrame else {
            return NSRect(origin: .zero, size: Self.defaultSize)
        }
        if let gemerkt { return PanelPlacement.restore(gemerkt, in: sichtbar, minSize: Self.minSize) }
        return PanelPlacement.initial(in: sichtbar, size: Self.defaultSize)
    }

    private func merke(_ fenster: NSWindow) {
        guard let bildschirm = fenster.screen ?? NSScreen.main else { return }
        let stand = PanelPlacement.save(fenster.frame, in: bildschirm.visibleFrame, screen: Self.kennung(bildschirm))
        if let daten = try? JSONEncoder().encode(stand) { defaults.set(daten, forKey: Self.rahmenKey) }
    }
}
