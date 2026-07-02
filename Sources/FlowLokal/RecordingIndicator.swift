import AppKit
import SwiftUI

/// Minimaler, textloser Aufnahme-Hinweis: eine kleine, halbtransparente
/// Wellenform unten am Bildschirm, die auf den Mikrofon-Pegel reagiert —
/// nur sichtbar, während aufgenommen wird.
@MainActor
final class RecordingIndicator {

    /// Pegelmodell, an das die schwebende Pille gebunden ist.
    final class LevelModel: ObservableObject {
        @Published var level: Float = 0
    }

    private let model = LevelModel()
    private var panel: NSPanel?
    private let size = NSSize(width: 78, height: 32)

    func show() {
        guard panel == nil else { return }
        model.level = 0

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
    private let weights: [CGFloat] = [0.5, 0.75, 0.92, 1.0, 0.92, 0.75, 0.5]
    private let minH: CGFloat = 3
    private let maxH: CGFloat = 24

    var body: some View {
        HStack(spacing: 3) {
            ForEach(weights.indices, id: \.self) { i in
                Capsule()
                    .fill(Color.shoutLive)
                    .frame(width: 3.2, height: height(i))
                    .animation(.easeOut(duration: 0.1), value: model.level)
            }
        }
        .frame(width: 78, height: 32)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.08)))
    }

    private func height(_ i: Int) -> CGFloat {
        let l = CGFloat(model.level)
        return minH + (maxH - minH) * min(1, l * weights[i])
    }
}
