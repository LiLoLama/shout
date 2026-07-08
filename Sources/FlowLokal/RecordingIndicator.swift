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
        if let screen = NSScreen.main {
            let vf = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: vf.midX - s.width / 2, y: vf.minY + 12))
        }
        // Im Verarbeiten-Modus keine Buttons → Klicks durchreichen.
        panel.ignoresMouseEvents = (mode == .processing)
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

/// NSHostingView, das den ersten Mausklick akzeptiert — nötig, damit Buttons in
/// einem nicht-aktivierenden Panel schon beim ersten Klick reagieren.
private final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
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
