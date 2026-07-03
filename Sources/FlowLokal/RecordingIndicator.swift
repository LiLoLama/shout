import AppKit
import SwiftUI

/// Minimaler, textloser Aufnahme-Hinweis: eine kleine, halbtransparente
/// Wellenform unten am Bildschirm, die auf den Mikrofon-Pegel reagiert —
/// nur sichtbar, während aufgenommen wird.
@MainActor
final class RecordingIndicator {

    enum Mode { case recording, processing }

    /// Pegel-/Zustandsmodell, an das die schwebende Pille gebunden ist.
    final class LevelModel: ObservableObject {
        @Published var level: Float = 0
        @Published var mode: Mode = .recording
    }

    private let model = LevelModel()
    private var panel: NSPanel?
    private let size = NSSize(width: 72, height: 26)

    /// Zeigt die Pille im Aufnahme-Modus (pegel-reaktive Wellenform).
    func show() {
        model.level = 0
        model.mode = .recording
        ensurePanel()
    }

    /// Wechselt in den Verarbeiten-Modus (animierte, indeterminierte Welle) —
    /// bleibt sichtbar, bis der fertige Text eingefügt ist.
    func showProcessing() {
        model.mode = .processing
        ensurePanel()
    }

    private func ensurePanel() {
        guard panel == nil else { return }

        let hosting = NSHostingView(rootView: RecordingPill(model: model))
        hosting.frame = NSRect(origin: .zero, size: size)

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        panel.contentView = hosting

        if let screen = NSScreen.main {
            let vf = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: vf.midX - size.width / 2, y: vf.minY + 12))
        }

        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.22
            panel.animator().alphaValue = 0.9   // etwas durchsichtig
        }
        self.panel = panel
    }

    /// Neuen Pegel (0…1) einspeisen — geglättet.
    func updateLevel(_ level: Float) {
        model.level = model.level * 0.5 + level * 0.5
    }

    func hide() {
        guard let panel else { return }
        self.panel = nil
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.22
            panel.animator().alphaValue = 0
        }, completionHandler: {
            panel.orderOut(nil)
        })
    }
}

/// Die schwebende Pille: Wellenform, deren Balken auf den Pegel reagieren.
/// Kein Text. Bei Stille schrumpfen die Balken auf ein kleines Minimum.
private struct RecordingPill: View {
    @ObservedObject var model: RecordingIndicator.LevelModel

    // Gewichtung je Balken (Mitte höher) für die Wellenform-Form.
    private let weights: [CGFloat] = [0.55, 0.78, 0.93, 1.0, 0.93, 0.78, 0.55]
    private let minH: CGFloat = 2
    private let maxH: CGFloat = 21

    var body: some View {
        Group {
            if model.mode == .processing {
                processingBars
            } else {
                recordingBars
            }
        }
        .frame(width: 72, height: 26)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.08)))
    }

    /// Aufnahme: Balken reagieren auf den Mikrofon-Pegel.
    private var recordingBars: some View {
        HStack(spacing: 2.5) {
            ForEach(weights.indices, id: \.self) { i in
                Capsule()
                    .fill(Color.shoutLive)
                    .frame(width: 2.8, height: recordingHeight(i))
                    .animation(.easeOut(duration: 0.1), value: model.level)
            }
        }
    }

    /// Verarbeiten: eine durchlaufende Welle (indeterminiert), selbstlaufend.
    private var processingBars: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            HStack(spacing: 2.5) {
                ForEach(weights.indices, id: \.self) { i in
                    let phase = sin(t * 5.5 - Double(i) * 0.7)       // -1…1, wandert
                    let norm = CGFloat((phase + 1) / 2)               // 0…1
                    Capsule()
                        .fill(Color.shoutLive.opacity(0.35 + 0.65 * norm))
                        .frame(width: 2.8, height: minH + (maxH * 0.72 - minH) * norm)
                }
            }
        }
    }

    private func recordingHeight(_ i: Int) -> CGFloat {
        let l = CGFloat(model.level)
        return minH + (maxH - minH) * min(1, l * weights[i])
    }
}
