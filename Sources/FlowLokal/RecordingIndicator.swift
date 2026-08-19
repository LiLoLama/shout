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
        withAnimation(.easeOut(duration: 0.17)) { model.collapsed = true }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.2
            panel.animator().alphaValue = 0
        }, completionHandler: { panel.orderOut(nil) })
    }

    // MARK: - Panel

    /// Die eine Feder, die alle Wechsel trägt: Auftauchen, Umformen, Zusammenfahren.
    private static let motion = Animation.spring(response: 0.3, dampingFraction: 0.72)

    private func setMode(_ mode: Mode) {
        // Reihenfolge ist wichtig: erst das Panel auf die Größe bringen, in der
        // die Bewegung stattfindet, dann den Inhalt umschalten. Andernfalls
        // beschneidet das noch kleine Fenster die hereinwachsende Pille — genau
        // das ließ sie „fertig erscheinen" statt sich aufzubauen.
        applyLayout(for: mode, from: model.mode)
        withAnimation(Self.motion) {
            model.collapsed = false
            model.mode = mode
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

/// Die schwebende Pille (vier Layouts, textlos).
private struct RecordingPill: View {
    @ObservedObject var model: RecordingIndicator.PillModel

    private let weights: [CGFloat] = [0.55, 0.78, 0.93, 1.0, 0.93, 0.78, 0.55]
    private let minH: CGFloat = 2
    private let maxH: CGFloat = 20

    var body: some View {
        Group {
            switch model.mode {
            case .idle:       idlePill
            case .armed:      armedPill
            case .recording:  recordingPill
            case .processing: processingPill
            }
        }
        // Jeder Wechsel wächst herein und fährt zusammen heraus, statt fertig
        // aufzutauchen. Die Feder dazu setzt der Indicator (withAnimation).
        .transition(.scale(scale: 0.6).combined(with: .opacity))
        .scaleEffect(model.collapsed ? 0.72 : 1)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: model.align)
    }

    // Ruhezustand: klickbarer Mic-Knopf.
    private var idlePill: some View {
        Button(action: model.onStart) {
            Image(systemName: "mic.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.shoutLive)
                .frame(width: 40, height: 26)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.10)))
        }
        .buttonStyle(.plain)
        .help(Loc.t("Aufnahme starten"))
    }

    // Warten auf den zweiten Tipp: ein pulsierender Punkt, sonst nichts. Der Puls
    // läuft über TimelineView statt über @State-Animation — derselbe Weg wie beim
    // Verarbeiten und unabhängig davon, wie oft die Pille neu aufgebaut wird.
    private var armedPill: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let beat = (sin(t * 9.0) + 1) / 2                  // 0…1, ~1,4 Schläge/s
            Circle().fill(Color.shoutLive)
                .frame(width: 8, height: 8)
                .scaleEffect(1.0 + 0.45 * beat)
                .opacity(0.55 + 0.45 * (1 - beat))
                .frame(width: 26, height: 26)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.10)))
        }
    }

    // Aufnahme: X · Wellenform · ✓ — waagerecht oder senkrecht gestapelt.
    private var recordingPill: some View {
        Stack(vertical: model.vertical, spacing: 8) {
            circleButton(system: "xmark", tint: Color(white: 0.75), action: model.onCancel)
                .help(Loc.t("Abbrechen"))
            bars { barHeight($0) }
            circleButton(system: "checkmark", tint: Color.shoutLive, filled: true, action: model.onSubmit)
                .help(Loc.t("Einfügen"))
        }
        .padding(model.vertical ? .vertical : .horizontal, 8)
        .frame(width: model.vertical ? 34 : nil, height: model.vertical ? nil : 34)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.08)))
    }

    /// Die Balken der Wellenform. Senkrecht wachsen sie in die Breite statt in die
    /// Höhe — sonst stünde die Welle quer zur Pille.
    @ViewBuilder
    private func bars(_ length: @escaping (Int) -> CGFloat) -> some View {
        Stack(vertical: model.vertical, spacing: 2.5) {
            ForEach(weights.indices, id: \.self) { i in
                Capsule().fill(Color.shoutLive)
                    .frame(width: model.vertical ? length(i) : 2.8,
                           height: model.vertical ? 2.8 : length(i))
                    .animation(.easeOut(duration: 0.1), value: model.level)
            }
        }
    }

    // Verarbeiten: durchlaufende Welle.
    private var processingPill: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            Stack(vertical: model.vertical, spacing: 2.5) {
                ForEach(weights.indices, id: \.self) { i in
                    let phase = sin(t * 5.5 - Double(i) * 0.7)
                    let norm = CGFloat((phase + 1) / 2)
                    let length = minH + (maxH * 0.72 - minH) * norm
                    Capsule().fill(Color.shoutLive.opacity(0.35 + 0.65 * norm))
                        .frame(width: model.vertical ? length : 2.8,
                               height: model.vertical ? 2.8 : length)
                }
            }
        }
        .frame(width: model.vertical ? 28 : 84, height: model.vertical ? 84 : 28)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.08)))
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

    private func barHeight(_ i: Int) -> CGFloat {
        let l = CGFloat(model.level)
        return minH + (maxH - minH) * min(1, l * weights[i])
    }
}
