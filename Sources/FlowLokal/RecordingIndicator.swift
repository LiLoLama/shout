import AppKit
import SwiftUI

/// Minimaler, textloser Aufnahme-Hinweis: eine kleine schwebende Wellenform
/// unten mittig am Bildschirm — nur sichtbar, während aufgenommen wird.
@MainActor
final class RecordingIndicator {

    private var panel: NSPanel?
    private let size = NSSize(width: 96, height: 34)

    func show() {
        guard panel == nil else { return }

        let hosting = NSHostingView(rootView: RecordingPill())
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
            panel.setFrameOrigin(NSPoint(x: vf.midX - size.width / 2, y: vf.minY + 26))
        }

        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.22
            panel.animator().alphaValue = 1
        }
        self.panel = panel
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

/// Die schwebende Pille: nur eine pulsierende Wellenform, kein Text.
private struct RecordingPill: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animating = false

    private let heights: [CGFloat] = [7, 15, 11, 19, 9, 14, 8]

    var body: some View {
        HStack(spacing: 3.5) {
            ForEach(heights.indices, id: \.self) { i in
                Capsule()
                    .fill(Color.shoutLive)
                    .frame(width: 3.5, height: heights[i])
                    .scaleEffect(y: (animating && !reduceMotion) ? 1.0 : 0.5, anchor: .center)
                    .animation(
                        reduceMotion ? nil :
                            .easeInOut(duration: 0.55).repeatForever().delay(Double(i) * 0.07),
                        value: animating
                    )
            }
        }
        .frame(width: 96, height: 34)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.10)))
        .onAppear { animating = true }
    }
}
