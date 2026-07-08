import AppKit
import SwiftUI

/// Schwebende Pille unten am Bildschirm. Drei Modi:
///  - `.idle`      — nur sichtbar, wenn „Pille immer anzeigen" aktiv ist; klickbar zum Starten.
///  - `.recording` — pegel-reaktive Wellenform, flankiert von X (abbrechen) und ✓ (absenden).
///  - `.processing`— animierte Welle, bis der fertige Text eingefügt ist.
///
/// Das Panel ist `nonactivating` + akzeptiert den ersten Mausklick, damit Klicks
/// den Tastaturfokus NICHT vom Zielfenster wegnehmen (sonst würde der Text falsch
/// eingefügt).
@MainActor
final class RecordingIndicator {
    enum Mode { case idle, recording, processing }

    final class PillModel: ObservableObject {
        @Published var level: Float = 0
        @Published var mode: Mode = .idle
        var onStart: () -> Void = {}
        var onCancel: () -> Void = {}
        var onSubmit: () -> Void = {}
    }

    private let model = PillModel()
    private var panel: NSPanel?
    private var persistent = false

    /// Aktionen der klickbaren Elemente (vom AppDelegate gesetzt).
    func setActions(start: @escaping () -> Void, cancel: @escaping () -> Void, submit: @escaping () -> Void) {
        model.onStart = start
        model.onCancel = cancel
        model.onSubmit = submit
    }

    // MARK: - Modus-Steuerung

    /// Aufnahme läuft: Wellenform + X/✓.
    func show() { model.level = 0; ensurePanel(); setMode(.recording) }

    /// Verarbeiten: animierte Welle, bis eingefügt.
    func showProcessing() { ensurePanel(); setMode(.processing) }

    /// Ruhezustand: nur bei „immer anzeigen" sichtbar (klickbarer Mic-Button).
    func showIdle() { ensurePanel(); setMode(.idle) }

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
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.2
            panel.animator().alphaValue = 0
        }, completionHandler: { panel.orderOut(nil) })
    }

    // MARK: - Panel

    private func setMode(_ mode: Mode) {
        model.mode = mode
        applyLayout(for: mode)
    }

    private func size(for mode: Mode) -> NSSize {
        switch mode {
        case .idle:       return NSSize(width: 46, height: 30)
        case .recording:  return NSSize(width: 150, height: 34)
        case .processing: return NSSize(width: 84, height: 28)
        }
    }

    private func applyLayout(for mode: Mode) {
        guard let panel else { return }
        let s = size(for: mode)
        panel.setContentSize(s)
        panel.contentView?.frame = NSRect(origin: .zero, size: s)
        panel.setFrameOrigin(targetOrigin(size: s))
        // Im Verarbeiten-Modus keine Buttons → Klicks durchreichen.
        panel.ignoresMouseEvents = (mode == .processing)
    }

    /// Reagiert auf eine geänderte Positions-Voreinstellung (aus den Einstellungen).
    func reposition() {
        guard let panel else { return }
        panel.setFrameOrigin(targetOrigin(size: panel.frame.size))
    }

    // MARK: - Position (Voreinstellung oder frei gezogen)

    private static let margin: CGFloat = 14

    /// Ziel-Ursprung für die aktuelle Größe: frei gezogener Punkt (Mitte) oder Anker.
    private func targetOrigin(size s: NSSize) -> NSPoint {
        let d = UserDefaults.standard
        if d.bool(forKey: "pillCustom") {
            let center = NSPoint(x: d.double(forKey: "pillCustomX"), y: d.double(forKey: "pillCustomY"))
            let vf = (NSScreen.screens.first { $0.frame.contains(center) } ?? NSScreen.main)?.visibleFrame ?? .zero
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
        guard let window else { super.mouseDragged(with: event); return }
        window.performDrag(with: event)   // OS-nativer Drag-Loop bis zum Loslassen
        // Danach: auf den sichtbaren Bereich klemmen und die Position (Mitte) sichern.
        let clamped = RecordingIndicator.clampToScreen(window.frame)
        if clamped != window.frame { window.setFrame(clamped, display: true) }
        let d = UserDefaults.standard
        d.set(true, forKey: "pillCustom")
        d.set(Double(clamped.midX), forKey: "pillCustomX")
        d.set(Double(clamped.midY), forKey: "pillCustomY")
    }
}

/// Die schwebende Pille (drei Layouts, textlos).
private struct RecordingPill: View {
    @ObservedObject var model: RecordingIndicator.PillModel

    private let weights: [CGFloat] = [0.55, 0.78, 0.93, 1.0, 0.93, 0.78, 0.55]
    private let minH: CGFloat = 2
    private let maxH: CGFloat = 20

    var body: some View {
        Group {
            switch model.mode {
            case .idle:       idlePill
            case .recording:  recordingPill
            case .processing: processingPill
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        .help("Aufnahme starten")
    }

    // Aufnahme: X · Wellenform · ✓.
    private var recordingPill: some View {
        HStack(spacing: 8) {
            circleButton(system: "xmark", tint: Color(white: 0.75), action: model.onCancel)
                .help("Abbrechen")
            HStack(spacing: 2.5) {
                ForEach(weights.indices, id: \.self) { i in
                    Capsule().fill(Color.shoutLive)
                        .frame(width: 2.8, height: barHeight(i))
                        .animation(.easeOut(duration: 0.1), value: model.level)
                }
            }
            circleButton(system: "checkmark", tint: Color.shoutLive, filled: true, action: model.onSubmit)
                .help("Einfügen")
        }
        .padding(.horizontal, 8)
        .frame(height: 34)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.08)))
    }

    // Verarbeiten: durchlaufende Welle.
    private var processingPill: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            HStack(spacing: 2.5) {
                ForEach(weights.indices, id: \.self) { i in
                    let phase = sin(t * 5.5 - Double(i) * 0.7)
                    let norm = CGFloat((phase + 1) / 2)
                    Capsule().fill(Color.shoutLive.opacity(0.35 + 0.65 * norm))
                        .frame(width: 2.8, height: minH + (maxH * 0.72 - minH) * norm)
                }
            }
        }
        .frame(width: 84, height: 28)
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
