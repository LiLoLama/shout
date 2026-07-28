import AppKit
import SwiftUI

/// Kleines, kurz eingeblendetes Panel oben rechts: „Gelernt: falsch → richtig"
/// mit einem Rückgängig-Button. Verschwindet nach ein paar Sekunden von selbst.
@MainActor
final class LearnedToast {

    private var panel: NSPanel?
    private var dismissTimer: Timer?

    func show(wrong: String, right: String, onUndo: @escaping () -> Void) {
        dismiss()

        let view = LearnedToastView(
            wrong: wrong,
            right: right,
            onUndo: { [weak self] in onUndo(); self?.dismiss() }
        )
        let hosting = NSHostingView(rootView: view)
        let size = hosting.fittingSize

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.contentView = hosting

        if let screen = NSScreen.main {
            let vf = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: vf.maxX - size.width - 16, y: vf.maxY - size.height - 16))
        }
        panel.orderFrontRegardless()
        self.panel = panel

        dismissTimer = Timer.scheduledTimer(withTimeInterval: 6, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.dismiss() }
        }
    }

    func dismiss() {
        dismissTimer?.invalidate()
        dismissTimer = nil
        panel?.orderOut(nil)
        panel = nil
    }
}

private struct LearnedToastView: View {
    let wrong: String
    let right: String
    let onUndo: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text(Loc.t("Ins Wörterbuch gelernt"))
                    .font(.caption).foregroundStyle(.secondary)
                Text("\(wrong)  →  \(right)")
                    .font(.callout).fontWeight(.semibold)
                    .lineLimit(1)
            }
            Button(Loc.t("Rückgängig"), action: onUndo)
                .buttonStyle(.borderless)
                .foregroundStyle(.blue)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: 360)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}
