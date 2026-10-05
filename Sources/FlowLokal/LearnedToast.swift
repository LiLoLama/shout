import AppKit
import SwiftUI

/// Kleines, kurz eingeblendetes Panel oben rechts: „Gelernt: falsch → richtig"
/// mit Rückgängig, oder ein schlichter Hinweis mit einer Aktion. Verschwindet
/// nach ein paar Sekunden von selbst.
@MainActor
final class LearnedToast {

    private var panel: NSPanel?
    private var dismissTimer: Timer?

    func show(wrong: String, right: String, onUndo: @escaping () -> Void) {
        dismiss()
        present(NSHostingView(rootView: LearnedToastView(
            wrong: wrong,
            right: right,
            onUndo: { [weak self] in onUndo(); self?.dismiss() }
        )))
    }

    /// Ein Hinweis (z. B. „Im Eingang notiert“), optional mit einem Knopf.
    func showInfo(_ message: String, actionTitle: String? = nil, action: (() -> Void)? = nil) {
        dismiss()
        present(NSHostingView(rootView: InfoToastView(
            message: message,
            actionTitle: actionTitle,
            onAction: { [weak self] in action?(); self?.dismiss() }
        )))
    }

    func dismiss() {
        dismissTimer?.invalidate()
        dismissTimer = nil
        panel?.orderOut(nil)
        panel = nil
    }

    private func present<V: View>(_ hosting: NSHostingView<V>) {
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

        // Nur diesen Toast schließen: Eine schon eingereihte Task eines alten
        // Zeitgebers darf nicht den inzwischen gezeigten nächsten wegnehmen.
        dismissTimer = Timer.scheduledTimer(withTimeInterval: 6, repeats: false) { [weak self, weak panel] _ in
            Task { @MainActor in
                guard let self, let panel, self.panel === panel else { return }
                self.dismiss()
            }
        }
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

private struct InfoToastView: View {
    let message: String
    let actionTitle: String?
    let onAction: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "note.text")
                .foregroundStyle(Color.shoutLive)
                .font(.title3)
            Text(message)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            if let actionTitle {
                Button(actionTitle, action: onAction)
                    .buttonStyle(.borderless)
                    .foregroundStyle(.blue)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: 360)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}
