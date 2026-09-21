#if os(macOS)
import AppKit
import SwiftUI

/// Die Karte, die auftaucht, wenn ein Meeting erkannt wurde: „Zoom-Meeting läuft
/// — mitschneiden?". Nach dem Ja wird aus derselben Karte die Laufanzeige mit
/// Zeit, Pegel und „Stoppen"; das Dashboard muss dafür nicht offen sein.
///
/// Dasselbe Panel-Muster wie die Pille (`RecordingIndicator`): `nonactivating`,
/// damit der Tastaturfokus im Meeting-Fenster bleibt, `.statusBar` und
/// `fullScreenAuxiliary`, damit die Karte auch über einem Zoom-Vollbild steht.
/// Größer als die Pille, weil hier eine Frage steht, die man lesen muss.
@MainActor
final class MeetingPrompt {

    enum State: Equatable { case ask, recording, done }

    final class Model: ObservableObject {
        @Published var appName = "Zoom"
        @Published var icon: NSImage?
        @Published var state: State = .ask
        @Published var duration: TimeInterval = 0
        @Published var level: Float = 0
        @Published var note: String?
        /// Klein und durchsichtig, bevor die Karte aufklappt.
        @Published var collapsed = true
        @Published var motionReduced = false

        var onAccept: () -> Void = {}
        var onDecline: () -> Void = {}
        var onMute: () -> Void = {}
        var onStop: () -> Void = {}
        var onOpen: () -> Void = {}
    }

    private let model = Model()
    private var panel: NSPanel?
    private var dismissTimer: Timer?

    /// So lange steht die Frage, dann verschwindet sie von selbst. Ein Fenster,
    /// das wartet, bis man es wegklickt, ist im Meeting eine Zumutung.
    private static let askSeconds: TimeInterval = 20

    private static let askSize = NSSize(width: 384, height: 140)
    private static let recordingSize = NSSize(width: 384, height: 80)
    private static let doneSize = NSSize(width: 384, height: 80)
    /// So lange steht die Bestätigung nach dem Stoppen.
    private static let doneSeconds: TimeInterval = 7

    var isVisible: Bool { panel != nil }
    var state: State { model.state }

    // MARK: - Zeigen

    /// Fragt, ob mitgeschnitten werden soll.
    func ask(appName: String, icon: NSImage?,
             onAccept: @escaping () -> Void,
             onDecline: @escaping () -> Void,
             onMute: @escaping () -> Void) {
        model.appName = appName
        model.icon = icon
        model.note = nil
        model.onAccept = { [weak self] in self?.stopDismissTimer(); onAccept() }
        model.onDecline = { [weak self] in self?.dismiss(); onDecline() }
        model.onMute = { [weak self] in self?.dismiss(); onMute() }
        present(.ask)

        dismissTimer = Timer.scheduledTimer(withTimeInterval: Self.askSeconds, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.model.state == .ask else { return }
                self.dismiss()
                self.model.onDecline()
            }
        }
    }

    /// Zeigt die Laufanzeige — entweder nach dem Ja oder direkt, wenn die
    /// Einstellung auf „automatisch" steht.
    func showRecording(appName: String, icon: NSImage?, onStop: @escaping () -> Void) {
        stopDismissTimer()
        model.appName = appName
        model.icon = icon
        model.duration = 0
        model.level = 0
        model.note = nil
        model.onStop = onStop
        present(.recording)
    }

    /// Nach dem Stoppen: kurze Bestätigung, wohin der Mitschnitt gegangen ist.
    /// Ohne sie wäre die Karte einfach weg und der Mitschnitt unauffindbar für
    /// jemanden, der das Dashboard gar nicht offen hatte.
    func showDone(appName: String, icon: NSImage?, message: String, onOpen: @escaping () -> Void) {
        stopDismissTimer()
        model.appName = appName
        model.icon = icon
        model.note = message
        model.onOpen = { [weak self] in self?.dismiss(); onOpen() }
        present(.done)

        dismissTimer = Timer.scheduledTimer(withTimeInterval: Self.doneSeconds, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.dismiss() }
        }
    }

    func update(duration: TimeInterval, level: Float, note: String?) {
        model.duration = duration
        model.level = level
        model.note = note
    }

    func dismiss() {
        stopDismissTimer()
        guard let panel else { return }
        self.panel = nil
        model.collapsed = true
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.18
            panel.animator().alphaValue = 0
        }, completionHandler: { panel.orderOut(nil) })
    }

    private func stopDismissTimer() {
        dismissTimer?.invalidate()
        dismissTimer = nil
    }

    // MARK: - Panel

    private func present(_ state: State) {
        model.motionReduced = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion

        // Der Zustand muss stehen, BEVOR das Panel vorne ist — sonst blitzt für
        // ein Bild der alte auf. Dasselbe Problem hatte die Pille.
        var instantly = Transaction()
        instantly.disablesAnimations = true
        withTransaction(instantly) {
            model.state = state
            if panel == nil { model.collapsed = true }
        }

        if panel == nil {
            build()
        }
        layout(for: state)

        // Erst im nächsten Durchlauf aufklappen: Im selben Aufruf fielen „klein"
        // und „groß" zu einem Wert zusammen und die Bewegung fiele aus.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.panel != nil else { return }
            self.model.collapsed = false
        }
    }

    private func build() {
        let hosting = FirstMouseHosting(rootView: MeetingPromptCard(model: model))
        hosting.frame = NSRect(origin: .zero, size: Self.askSize)
        hosting.autoresizingMask = [.width, .height]

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: Self.askSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false        // der Schatten kommt aus der SwiftUI-Karte
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        panel.contentView = hosting

        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            panel.animator().alphaValue = 1
        }
        self.panel = panel
    }

    private func layout(for state: State) {
        guard let panel else { return }
        let size: NSSize
        switch state {
        case .ask:       size = Self.askSize
        case .recording: size = Self.recordingSize
        case .done:      size = Self.doneSize
        }
        panel.setContentSize(size)
        panel.contentView?.frame = NSRect(origin: .zero, size: size)
        panel.setFrameOrigin(Self.origin(for: size))
    }

    /// Oben mittig. Steht die Pille oben, weicht die Karte nach unten aus — zwei
    /// Dinge an derselben Kante überlagern sich sonst.
    private static func origin(for size: NSSize) -> NSPoint {
        let visible = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame ?? .zero
        let margin: CGFloat = 18
        let x = visible.midX - size.width / 2
        let anchor = UserDefaults.standard.string(forKey: "pillAnchor") ?? "bottomCenter"
        let pillOnTop = !UserDefaults.standard.bool(forKey: "pillCustom") && anchor.hasPrefix("top")
        let y = pillOnTop ? visible.minY + margin : visible.maxY - size.height - margin
        return NSPoint(x: x, y: y)
    }
}

/// Buttons sollen im nicht aktivierenden Panel schon beim ersten Klick
/// reagieren, ohne dass das Panel den Fokus an sich zieht.
private final class FirstMouseHosting<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

// MARK: - Karte

private struct MeetingPromptCard: View {
    @ObservedObject var model: MeetingPrompt.Model

    private var spring: Animation {
        model.motionReduced ? .easeOut(duration: 0.12) : .spring(response: 0.36, dampingFraction: 0.68)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            switch model.state {
            case .ask:       askBody
            case .recording: recordingBody
            case .done:      doneBody
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.35), radius: 18, y: 6)
        .scaleEffect(model.collapsed ? 0.94 : 1, anchor: .top)
        .opacity(model.collapsed ? 0 : 1)
        .offset(y: model.collapsed ? -10 : 0)
        .animation(spring, value: model.collapsed)
        .animation(spring, value: model.state)
        .padding(6)          // Platz für den Schatten
    }

    // MARK: Frage

    private var askBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                icon
                VStack(alignment: .leading, spacing: 2) {
                    Text(Loc.f("%@-Meeting läuft", model.appName))
                        .font(.system(size: 13, weight: .semibold))
                    Text(Loc.t("Mitschneiden und daraus ein Protokoll machen?"))
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 8) {
                Button(Loc.t("Mitschneiden"), action: model.onAccept)
                    .buttonStyle(PromptButtonStyle(filled: true))
                Button(Loc.t("Nicht jetzt"), action: model.onDecline)
                    .buttonStyle(PromptButtonStyle(filled: false))
                Spacer(minLength: 0)
                Button(Loc.f("Nie bei %@", model.appName), action: model.onMute)
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Text(Loc.t("Bitte vorher die anderen Beteiligten fragen."))
                .font(.system(size: 10)).foregroundStyle(.tertiary)
        }
    }

    // MARK: Laufanzeige

    private var recordingBody: some View {
        HStack(spacing: 12) {
            icon
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Circle().fill(Color.shoutLive).frame(width: 7, height: 7)
                    Text(Loc.f("%@ wird mitgeschnitten", model.appName))
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1).truncationMode(.tail)
                    Spacer(minLength: 6)
                    Text(Self.clock(model.duration))
                        .font(.system(size: 12).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                if let note = model.note {
                    Text(note)
                        .font(.system(size: 10))
                        .foregroundStyle(Color(red: 0.95, green: 0.7, blue: 0.2))
                        .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                } else {
                    meter
                }
            }
            Button(Loc.t("Stoppen"), action: model.onStop)
                .buttonStyle(PromptButtonStyle(filled: false))
                .layoutPriority(1)
        }
    }

    // MARK: Bestätigung

    private var doneBody: some View {
        HStack(spacing: 12) {
            icon
            VStack(alignment: .leading, spacing: 3) {
                Text(Loc.t("Mitschnitt gesichert"))
                    .font(.system(size: 12, weight: .semibold))
                Text(model.note ?? "")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Button(Loc.t("Öffnen"), action: model.onOpen)
                .buttonStyle(PromptButtonStyle(filled: false))
        }
    }

    private var meter: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.1))
                Capsule().fill(Color.shoutLive.opacity(0.85))
                    .frame(width: max(2, geo.size.width * CGFloat(min(1, model.level))))
                    .animation(.linear(duration: 0.1), value: model.level)
            }
        }
        .frame(height: 4)
    }

    /// Eigene Knöpfe statt `.borderedProminent`: Die Karte sitzt in einem
    /// `nonactivating`-Panel, ihre App ist also NIE die aktive — und ein
    /// hervorgehobener System-Knopf wird dann grau gezeichnet. Der wichtigste
    /// Knopf sähe aus wie der unwichtigste.
    private struct PromptButtonStyle: ButtonStyle {
        let filled: Bool

        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(filled ? Color.white : Color(white: 0.92))
                .padding(.horizontal, 12).padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(filled ? Color.shoutLive : Color.white.opacity(0.10))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(Color.white.opacity(filled ? 0 : 0.10))
                )
                .opacity(configuration.isPressed ? 0.75 : 1)
        }
    }

    private var icon: some View {
        Group {
            if let image = model.icon {
                Image(nsImage: image).resizable().interpolation(.high)
            } else {
                Image(systemName: "person.wave.2.fill")
                    .resizable().scaledToFit().foregroundStyle(Color.shoutLive)
            }
        }
        .frame(width: 30, height: 30)
    }

    private static func clock(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        return total >= 3600
            ? String(format: "%d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
            : String(format: "%d:%02d", total / 60, total % 60)
    }
}
#endif
