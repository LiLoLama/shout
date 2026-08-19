import AppKit
import SwiftUI

extension Notification.Name {
    /// Die Pille wurde gezogen — die Einstellungen zeigen die Position an und
    /// müssen davon erfahren.
    static let shoutPillMoved = Notification.Name("shout.pillMoved")
}

/// Schwebende Pille unten am Bildschirm. Vier Modi:
///  - `.idle`      — nur sichtbar, wenn „Pille immer anzeigen" aktiv ist; klickbar zum Starten.
///  - `.armed`     — nur im Doppeltipp-Modus: der erste Tipp ist da, ein pulsierender
///                   Punkt wartet auf den zweiten. Nimmt keine Klicks an.
///  - `.recording` — pegel-reaktive Wellenform, flankiert von X (abbrechen) und ✓ (absenden).
///  - `.processing`— animierte Welle, bis der fertige Text eingefügt ist.
///
/// Das Panel ist `nonactivating` + akzeptiert den ersten Mausklick, damit Klicks
/// den Tastaturfokus NICHT vom Zielfenster wegnehmen (sonst würde der Text falsch
/// eingefügt).
@MainActor
final class RecordingIndicator {
    enum Mode: Equatable { case idle, armed, recording, processing }

    final class PillModel: ObservableObject {
        @Published var level: Float = 0
        @Published var mode: Mode = .idle
        /// Senkrecht statt waagerecht — hängt davon ab, wo die Pille steht.
        @Published var vertical = false
        /// Wo die Kapsel im Panel klebt. Zählt nur, während das Panel für eine
        /// Bewegung größer ist als die Kapsel: an einer Ecke muss sie an der Ecke
        /// bleiben und in den freien Raum wachsen, statt in die Mitte zu springen.
        @Published var align: Alignment = .center
        /// Fährt die Kapsel zusammen, während das Panel ausblendet.
        @Published var collapsed = false
        /// Kurzer Anlauf: der Körper staucht, bevor er sich dehnt.
        @Published var squash = false
        /// „Bewegung reduzieren" in den Systemeinstellungen — dann ohne Federn,
        /// ohne Puls, nur mit klaren kurzen Übergängen.
        @Published var motionReduced = false

        /// Läuft gerade etwas von sich aus? Nur dann braucht die Pille einen
        /// Taktgeber; im Ruhezustand und bei Aufnahme genügen die Datenänderungen.
        var beating: Bool { (mode == .armed || mode == .processing) && !motionReduced }
        var onStart: () -> Void = {}
        var onCancel: () -> Void = {}
        var onSubmit: () -> Void = {}
    }

    private let model = PillModel()
    private var panel: NSPanel?
    private var persistent = false

    init() {
        // Bildschirm abgesteckt oder Auflösung geändert: neu setzen. Ohne das
        // bliebe die Pille an einer Stelle, die es nicht mehr gibt.
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.reposition() }
        }
        // Nach dem Ziehen kann sich die Ausrichtung ändern (Seitenkante ↔ oben/unten).
        NotificationCenter.default.addObserver(
            forName: .shoutPillMoved, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.reposition() }
        }
    }

    /// Aktionen der klickbaren Elemente (vom AppDelegate gesetzt).
    func setActions(start: @escaping () -> Void, cancel: @escaping () -> Void, submit: @escaping () -> Void) {
        model.onStart = start
        model.onCancel = cancel
        model.onSubmit = submit
    }

    // MARK: - Modus-Steuerung

    /// Aufnahme läuft: Wellenform + X/✓.
    func show() { model.level = 0; present(.recording) }

    /// Verarbeiten: animierte Welle, bis eingefügt.
    func showProcessing() { present(.processing) }

    /// Ruhezustand: nur bei „immer anzeigen" sichtbar (klickbarer Mic-Button).
    func showIdle() { present(.idle) }

    /// Erster Tipp im Doppeltipp-Modus: wartender Punkt.
    func showArmed() { present(.armed) }

    /// Zeigt einen Zustand — immer in Bewegung. Entsteht die Pille gerade erst,
    /// startet sie klein und poppt auf; stand sie schon da, formt sie sich um.
    private func present(_ mode: Mode) {
        model.motionReduced = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if panel == nil { model.collapsed = true }
        ensurePanel()
        setMode(mode)
    }

    /// Nach Abschluss/Abbruch: idle-Pille zeigen (wenn dauerhaft) oder ausblenden.
    func finish() { persistent ? showIdle() : hide() }

    /// Schaltet den Dauer-Modus um.
    func setPersistent(_ on: Bool) {
        persistent = on
        if on {
            if panel == nil { showIdle() }          // aus dem Nichts einblenden
        } else if model.mode == .idle {
            hide()                                    // nur die reine Idle-Pille ausblenden
        }
    }

    /// Neuen Pegel (0…1) einspeisen — geglättet.
    func updateLevel(_ level: Float) {
        model.level = model.level * 0.5 + level * 0.5
    }

    func hide() {
        guard let panel else { return }
        self.panel = nil
        model.collapsed = true            // die Kapsel fährt zusammen (Sache der View)
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.2
            panel.animator().alphaValue = 0
        }, completionHandler: { panel.orderOut(nil) })
    }

    // MARK: - Panel

    /// Setzt den Zustand. Wie sich der Körper dabei bewegt, entscheidet die View
    /// anhand der Werte im Modell — hier wird nur die Abfolge getaktet.
    private func setMode(_ mode: Mode) {
        // Reihenfolge ist wichtig: erst das Panel auf die Größe bringen, in der
        // die Bewegung stattfindet, dann den Zustand umschalten. Andernfalls
        // beschneidet das noch kleine Fenster die wachsende Kapsel — genau das
        // ließ sie „fertig erscheinen" statt sich aufzubauen.
        applyLayout(for: mode, from: model.mode)
        let generation = layoutGeneration
        model.collapsed = false

        // Der Start der Aufnahme ist der Moment, der Betonung verdient: kurzer
        // Anlauf, dann dehnt sich der Körper. Alle anderen Wechsel gehen direkt.
        let anticipate = (mode == .recording && model.mode != .recording
                          && panel != nil && !model.motionReduced)
        guard anticipate else { model.mode = mode; return }

        model.squash = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.09) { [weak self] in
            guard let self, self.layoutGeneration == generation else { return }
            self.model.squash = false
            self.model.mode = mode
        }
    }

    private func size(for mode: Mode) -> NSSize {
        let base = baseSize(for: mode)
        // Senkrecht ist dieselbe Pille, nur gekippt.
        return model.vertical ? NSSize(width: base.height, height: base.width) : base
    }

    private func baseSize(for mode: Mode) -> NSSize {
        switch mode {
        case .idle:       return NSSize(width: 46, height: 30)
        case .armed:      return NSSize(width: 34, height: 30)
        case .recording:  return NSSize(width: 150, height: 34)
        case .processing: return NSSize(width: 84, height: 28)
        }
    }

    /// Zählt Moduswechsel, damit das verspätete Nachziehen der Panel-Größe nicht
    /// in einen neueren Wechsel hineinredet.
    private var layoutGeneration = 0

    private func applyLayout(for mode: Mode, from previous: Mode? = nil) {
        guard let panel else { return }
        model.vertical = Self.wantsVertical()
        model.align = Self.alignment()
        let target = size(for: mode)
        layoutGeneration += 1
        let generation = layoutGeneration

        if let previous {
            // Während der Bewegung ist das Panel so groß wie der größere der zwei
            // Zustände — die Bühne für beide. Das Panel ist durchsichtig, das sieht
            // niemand; sichtbar ist nur die Kapsel, die SwiftUI umformt.
            let old = size(for: previous)
            setPanelFrame(NSSize(width: max(old.width, target.width),
                                 height: max(old.height, target.height)))
            // Danach auf die Zielgröße nachziehen: ein zu großes Panel bliebe als
            // unsichtbarer Klickfänger neben der Pille liegen.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
                guard let self, self.panel != nil, self.layoutGeneration == generation else { return }
                self.setPanelFrame(self.size(for: self.model.mode))
            }
        } else {
            setPanelFrame(target)
        }
        // Ohne Buttons (Verarbeiten, Warten auf den zweiten Tipp) → Klicks durchreichen.
        panel.ignoresMouseEvents = (mode == .processing || mode == .armed)
    }

    private func setPanelFrame(_ s: NSSize) {
        guard let panel else { return }
        panel.setContentSize(s)
        panel.contentView?.frame = NSRect(origin: .zero, size: s)
        panel.setFrameOrigin(targetOrigin(size: s))
    }

    /// Wohin die Kapsel im Panel gehört — abgeleitet aus der eingestellten Ecke.
    private static func alignment() -> Alignment {
        let d = UserDefaults.standard
        guard !d.bool(forKey: "pillCustom") else { return .center }
        switch d.string(forKey: "pillAnchor") ?? "bottomCenter" {
        case "bottomLeft":  return .bottomLeading
        case "bottomRight": return .bottomTrailing
        case "topLeft":     return .topLeading
        case "topRight":    return .topTrailing
        case "topCenter":   return .top
        default:            return .bottom
        }
    }

    /// Reagiert auf eine geänderte Positions-Voreinstellung (aus den Einstellungen).
    func reposition() {
        guard panel != nil else { return }
        applyLayout(for: model.mode)
    }

    // MARK: - Position (Voreinstellung oder frei gezogen)

    private static let margin: CGFloat = 14

    /// Ziel-Ursprung für die aktuelle Größe: frei gezogener Punkt oder Anker.
    ///
    /// Die freie Position steht **relativ zum Bildschirm** (Anteil 0…1 seiner
    /// sichtbaren Fläche) und nicht als absoluter Punkt. Absolut gespeichert
    /// wanderte die Pille beim Abstecken eines breiten Monitors an den rechten
    /// Rand: „Mitte" eines 3440 Punkt breiten Schirms liegt bei x ≈ 1720, und
    /// diesen Punkt gibt es auf dem eingebauten Display nicht mehr — der Code fand
    /// keinen passenden Bildschirm und klemmte auf den Rand.
    private func targetOrigin(size s: NSSize) -> NSPoint {
        let d = UserDefaults.standard
        if d.bool(forKey: "pillCustom") {
            let spot = Self.customSpot()
            let vf = spot.screen.visibleFrame
            let center = PillPlacement.center(for: spot.fraction, in: vf)
            let x = min(max(center.x - s.width / 2, vf.minX), vf.maxX - s.width)
            let y = min(max(center.y - s.height / 2, vf.minY), vf.maxY - s.height)
            return NSPoint(x: x, y: y)
        }
        let vf = NSScreen.main?.visibleFrame ?? .zero
        let m = Self.margin
        let anchor = d.string(forKey: "pillAnchor") ?? "bottomCenter"
        let x: CGFloat
        switch anchor {
        case "bottomLeft", "topLeft":   x = vf.minX + m
        case "bottomRight", "topRight": x = vf.maxX - s.width - m
        default:                         x = vf.midX - s.width / 2
        }
        let y = anchor.hasPrefix("top") ? (vf.maxY - s.height - m) : (vf.minY + m)
        return NSPoint(x: x, y: y)
    }

    /// Gemerkte freie Position: Bildschirm und Anteil darin.
    static func customSpot() -> (screen: NSScreen, fraction: CGPoint) {
        let d = UserDefaults.standard
        let screen = screen(withID: d.string(forKey: "pillScreen")) ?? NSScreen.main ?? NSScreen.screens[0]
        var fraction = CGPoint(x: d.double(forKey: "pillFracX"), y: d.double(forKey: "pillFracY"))

        // Übergang von den alten, absolut gespeicherten Werten: einmalig umrechnen.
        if d.object(forKey: "pillFracX") == nil, d.object(forKey: "pillCustomX") != nil {
            let old = NSPoint(x: d.double(forKey: "pillCustomX"), y: d.double(forKey: "pillCustomY"))
            let host = NSScreen.screens.first { $0.frame.contains(old) } ?? screen
            fraction = PillPlacement.fraction(of: old, in: host.visibleFrame)
            d.set(Double(fraction.x), forKey: "pillFracX")
            d.set(Double(fraction.y), forKey: "pillFracY")
            d.set(id(of: host), forKey: "pillScreen")
        }
        return (screen, PillPlacement.clamped(fraction))
    }

    /// Merkt sich die Position eines Fensters relativ zu seinem Bildschirm.
    static func rememberSpot(of frame: NSRect) {
        let center = NSPoint(x: frame.midX, y: frame.midY)
        let host = NSScreen.screens.first { $0.frame.contains(center) } ?? NSScreen.main
        guard let host else { return }
        let fraction = PillPlacement.fraction(of: center, in: host.visibleFrame)
        let d = UserDefaults.standard
        d.set(true, forKey: "pillCustom")
        d.set(Double(fraction.x), forKey: "pillFracX")
        d.set(Double(fraction.y), forKey: "pillFracY")
        d.set(id(of: host), forKey: "pillScreen")
    }

    /// Soll die Pille senkrecht stehen? An einer Seitenkante ja, oben oder unten
    /// nein — dort, wo sie am wenigsten Platz wegnimmt.
    static func wantsVertical() -> Bool {
        switch UserDefaults.standard.string(forKey: "pillOrientation") ?? "auto" {
        case "vertical": return true
        case "horizontal": return false
        default: break
        }
        // Feste Anker sitzen alle oben oder unten.
        guard UserDefaults.standard.bool(forKey: "pillCustom") else { return false }
        return PillPlacement.prefersVertical(at: customSpot().fraction)
    }

    private static func id(of screen: NSScreen) -> String {
        String(describing: screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] ?? "")
    }

    private static func screen(withID stored: String?) -> NSScreen? {
        guard let stored, !stored.isEmpty else { return nil }
        return NSScreen.screens.first { id(of: $0) == stored }
    }

    /// Klemmt einen Fenster-Frame auf den sichtbaren Bereich seines Bildschirms.
    static func clampToScreen(_ frame: NSRect) -> NSRect {
        let center = NSPoint(x: frame.midX, y: frame.midY)
        let vf = (NSScreen.screens.first { $0.frame.contains(center) } ?? NSScreen.main)?.visibleFrame ?? frame
        var f = frame
        f.origin.x = min(max(f.origin.x, vf.minX), vf.maxX - f.width)
        f.origin.y = min(max(f.origin.y, vf.minY), vf.maxY - f.height)
        return f
    }

    private func ensurePanel() {
        guard panel == nil else { return }
        let s = size(for: model.mode)

        let hosting = FirstMouseHostingView(rootView: RecordingPill(model: model))
        hosting.frame = NSRect(origin: .zero, size: s)
        hosting.autoresizingMask = [.width, .height]

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: s),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        panel.contentView = hosting

        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            panel.animator().alphaValue = 0.95
        }
        self.panel = panel
        applyLayout(for: model.mode)
    }
}

/// NSHostingView, das (a) den ersten Mausklick akzeptiert (Buttons reagieren im
/// nicht-aktivierenden Panel sofort) und (b) beim Ziehen das Fenster NATIV
/// verschiebt (`performDrag`) — flüssiges Echtzeit-Tracking ohne key/aktives
/// Fenster. Ein reiner Klick (ohne Ziehen) löst `mouseDragged` nicht aus und
/// bleibt damit den SwiftUI-Buttons (Start/✕/✓) vorbehalten.
private final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDragged(with event: NSEvent) {
        // Fixiert: Das Fenster bleibt liegen. Sonst verschiebt ein Klick daneben
        // die Pille ungewollt — wer sie einmal platziert hat, will das nicht.
        guard !UserDefaults.standard.bool(forKey: "pillLocked"), let window else {
            super.mouseDragged(with: event)
            return
        }
        window.performDrag(with: event)   // OS-nativer Drag-Loop bis zum Loslassen
        // Danach: auf den sichtbaren Bereich klemmen und die Position sichern.
        let clamped = RecordingIndicator.clampToScreen(window.frame)
        if clamped != window.frame { window.setFrame(clamped, display: true) }
        RecordingIndicator.rememberSpot(of: clamped)
        NotificationCenter.default.post(name: .shoutPillMoved, object: nil)
    }
}

/// HStack oder VStack, je nach Ausrichtung. Ohne das stünde jedes Layout zweimal
/// im Code, einmal je Richtung.
private struct Stack<Content: View>: View {
    let vertical: Bool
    let spacing: CGFloat
    @ViewBuilder let content: () -> Content

    var body: some View {
        if vertical { VStack(spacing: spacing) { content() } }
        else { HStack(spacing: spacing) { content() } }
    }
}

/// Die schwebende Pille: **ein** Körper, textlos. Kein Zustand ersetzt einen
/// anderen — die Kapsel ändert Breite, Höhe und Inhalt, und der Punkt des
/// Wartezustands ist derselbe Balken, der später in der Mitte der Wellenform
/// steht. Deshalb muss beim Start nichts entstehen und nichts vergehen.
private struct RecordingPill: View {
    @ObservedObject var model: RecordingIndicator.PillModel

    private let weights: [CGFloat] = [0.55, 0.78, 0.93, 1.0, 0.93, 0.78, 0.55]
    private var mid: Int { weights.count / 2 }

    private let barW: CGFloat = 2.8       // Dicke eines Balkens
    private let dotW: CGFloat = 8         // Der wartende Punkt ist ein dicker, kurzer Balken
    private let minH: CGFloat = 2
    private let maxH: CGFloat = 20

    var body: some View {
        Stack(vertical: model.vertical, spacing: 2.5) {
            ForEach(weights.indices, id: \.self) { i in bar(i) }
        }
        .frame(width: shell.width, height: shell.height)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.09)))
        .overlay(alignment: model.vertical ? .top : .leading) { cancelButton }
        .overlay(alignment: model.vertical ? .bottom : .trailing) { submitButton }
        .overlay { micButton }
        .scaleEffect(bodyScale)
        // Der Körper folgt dem Zustand: Anlauf (Stauchen), dann Dehnen mit
        // leichtem Überschwingen. Reduzierte Bewegung bekommt dieselbe Abfolge
        // ohne Federn — die Zustände bleiben unterscheidbar, es wippt nur nichts.
        .animation(model.motionReduced ? .easeOut(duration: 0.18)
                                       : .spring(response: 0.36, dampingFraction: 0.62),
                   value: model.mode)
        .animation(.easeIn(duration: 0.09), value: model.squash)
        .animation(.easeOut(duration: 0.17), value: model.collapsed)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: model.align)
    }

    // MARK: - Größe des Körpers

    /// Sichtbare Größe der Kapsel je Zustand, waagerecht gedacht und bei
    /// senkrechter Pille gekippt.
    private var shell: CGSize {
        let base: CGSize
        switch model.mode {
        case .idle:       base = CGSize(width: 40, height: 26)
        case .armed:      base = CGSize(width: 26, height: 26)
        case .recording:  base = CGSize(width: 111, height: 34)
        case .processing: base = CGSize(width: 84, height: 28)
        }
        return model.vertical ? CGSize(width: base.height, height: base.width) : base
    }

    /// Anlauf und Abgang. Beide bleiben unter 1, damit die Kapsel nie über den
    /// Rand des Panels hinauswächst — das Überschwingen steckt in der Breite.
    private var bodyScale: CGSize {
        if model.collapsed { return CGSize(width: 0.72, height: 0.72) }
        guard model.squash else { return CGSize(width: 1, height: 1) }
        return model.vertical ? CGSize(width: 0.86, height: 0.94)
                              : CGSize(width: 0.94, height: 0.86)
    }

    // MARK: - Die Balken (Punkt, Wellenform, Verarbeiten in einem)

    private func bar(_ i: Int) -> some View {
        // Ein Taktgeber für alles, was von sich aus läuft. Angehalten, sobald
        // nichts pulsiert oder wandert — sonst zeichnete die Dauer-Pille im
        // Ruhezustand für nichts 60 Bilder je Sekunde.
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: !model.beating)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let length = self.length(i, at: t)
            let thick = (i == mid && model.mode == .armed) ? dotW : barW
            Capsule().fill(Color.shoutLive)
                .frame(width: model.vertical ? length : thick,
                       height: model.vertical ? thick : length)
                .scaleEffect(pulse(i, at: t))
                .opacity(opacity(i, at: t))
        }
        // Aus der Mitte heraus: der Mittelbalken zuerst, die äußeren folgen.
        .animation(model.motionReduced
                    ? .easeOut(duration: 0.18)
                    : .spring(response: 0.34, dampingFraction: 0.7)
                        .delay(Double(abs(i - mid)) * 0.035),
                   value: model.mode)
        .animation(.easeOut(duration: 0.1), value: model.level)
    }

    /// Länge eines Balkens im aktuellen Zustand.
    private func length(_ i: Int, at t: TimeInterval) -> CGFloat {
        switch model.mode {
        case .idle:
            return 0
        case .armed:
            return i == mid ? dotW : 0          // nur der Punkt steht
        case .recording:
            let l = CGFloat(model.level)
            return minH + (maxH - minH) * min(1, l * weights[i])
        case .processing:
            return minH + (maxH * 0.72 - minH) * wave(i, at: t)
        }
    }

    /// Der Puls des Wartezustands — nur der Punkt schlägt, ~1,4-mal je Sekunde
    /// und damit genau einmal im Zeitfenster für den zweiten Tipp.
    private func pulse(_ i: Int, at t: TimeInterval) -> CGFloat {
        guard model.mode == .armed, i == mid, !model.motionReduced else { return 1 }
        return 1.0 + 0.45 * CGFloat((sin(t * 9.0) + 1) / 2)
    }

    private func opacity(_ i: Int, at t: TimeInterval) -> Double {
        switch model.mode {
        case .armed:
            guard i == mid, !model.motionReduced else { return 1 }
            return 0.55 + 0.45 * (1 - Double((sin(t * 9.0) + 1) / 2))
        case .processing:
            return 0.35 + 0.65 * Double(wave(i, at: t))
        default:
            return 1
        }
    }

    /// Durchlaufende Welle des Verarbeiten-Zustands, 0…1.
    private func wave(_ i: Int, at t: TimeInterval) -> CGFloat {
        CGFloat((sin(t * 5.5 - Double(i) * 0.7) + 1) / 2)
    }

    // MARK: - Knöpfe, die an den Rändern der Kapsel mitreiten

    private var cancelButton: some View {
        circleButton(system: "xmark", tint: Color(white: 0.75), action: model.onCancel)
            .help(Loc.t("Abbrechen"))
            .padding(model.vertical ? .top : .leading, 8)
            .modifier(OnlyWhileRecording(mode: model.mode))
    }

    private var submitButton: some View {
        circleButton(system: "checkmark", tint: Color.shoutLive, filled: true, action: model.onSubmit)
            .help(Loc.t("Einfügen"))
            .padding(model.vertical ? .bottom : .trailing, 8)
            .modifier(OnlyWhileRecording(mode: model.mode))
    }

    /// Ruhezustand: derselbe Körper, nur mit Mikrofon — und klickbar wie bisher.
    private var micButton: some View {
        Button(action: model.onStart) {
            Image(systemName: "mic.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.shoutLive)
                .frame(width: 40, height: 26)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(Loc.t("Aufnahme starten"))
        .opacity(model.mode == .idle ? 1 : 0)
        .allowsHitTesting(model.mode == .idle)
        .animation(.easeOut(duration: 0.14), value: model.mode)
    }

    private func circleButton(system: String, tint: Color, filled: Bool = false,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(filled ? Color.white : tint)
                .frame(width: 22, height: 22)
                .background(Circle().fill(filled ? tint : Color.white.opacity(0.14)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }
}

/// Zeigt einen Knopf nur während der Aufnahme: er kommt zuletzt, nachdem sich
/// die Kapsel gedehnt hat, und geht als Erstes wieder — hinaus schneller als
/// herein.
private struct OnlyWhileRecording: ViewModifier {
    let mode: RecordingIndicator.Mode

    func body(content: Content) -> some View {
        let on = (mode == .recording)
        return content
            .opacity(on ? 1 : 0)
            .scaleEffect(on ? 1 : 0.5)
            .allowsHitTesting(on)
            .animation(on ? .easeOut(duration: 0.16).delay(0.18)
                          : .easeOut(duration: 0.11), value: mode)
    }
}
