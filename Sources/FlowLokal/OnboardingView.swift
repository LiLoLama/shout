import SwiftUI
import AppKit
import AVFoundation
import ApplicationServices

/// Erststart-Assistent: führt durch Mikrofon- und Bedienungshilfen-Freigabe,
/// zeigt den Modell-Download und lässt ein Probediktat machen.
struct OnboardingView: View {
    @ObservedObject var dashboard: DashboardModel
    @ObservedObject var settings: RecordingSettings
    let onFinish: () -> Void

    @State private var step = 0
    @State private var micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
    @State private var axTrusted = AXIsProcessTrusted()
    @State private var testText = ""

    private let stepCount = 5
    private let poll = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Color.white.opacity(0.06))
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 40).padding(.vertical, 30)
            footer
        }
        .frame(width: 560, height: 520)
        .background(Color.shoutWindow)
        .preferredColorScheme(.dark)
        .tint(Color.shoutLive)
        .onReceive(poll) { _ in
            micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
            axTrusted = AXIsProcessTrusted()
        }
    }

    // MARK: - Kopf

    private var header: some View {
        HStack(spacing: 10) {
            HStack(spacing: 0) {
                Text("shout").font(.system(size: 20, weight: .bold))
                Text(".").font(.system(size: 20, weight: .bold)).foregroundStyle(Color.shoutLive)
            }
            Spacer()
            HStack(spacing: 6) {
                ForEach(0..<stepCount, id: \.self) { i in
                    Capsule()
                        .fill(i == step ? Color.shoutLive : Color.white.opacity(i < step ? 0.35 : 0.14))
                        .frame(width: i == step ? 18 : 7, height: 7)
                        .animation(.easeInOut(duration: 0.2), value: step)
                }
            }
        }
        .padding(.horizontal, 22).padding(.vertical, 16)
    }

    // MARK: - Inhalt

    @ViewBuilder private var content: some View {
        switch step {
        case 0: welcomeStep
        case 1: micStep
        case 2: accessibilityStep
        case 3: modelStep
        default: testStep
        }
    }

    private var welcomeStep: some View {
        stepBody(icon: "mic.fill", title: "Willkommen bei shout.",
                 text: "Diktieren in jede App — komplett lokal auf deinem Mac. Keine Cloud, keine Konten. In vier kurzen Schritten ist alles startklar.") {
            EmptyView()
        }
    }

    private var micStep: some View {
        let granted = micStatus == .authorized
        return stepBody(icon: granted ? "checkmark.circle.fill" : "mic.circle.fill",
                        iconColor: granted ? .green : Color.shoutLive,
                        title: "Mikrofon",
                        text: granted
                            ? "Perfekt — shout. darf dein Mikrofon nutzen."
                            : "shout. braucht Zugriff auf dein Mikrofon, um deine Sprache lokal in Text umzuwandeln.") {
            if !granted {
                if micStatus == .denied || micStatus == .restricted {
                    Button("In Systemeinstellungen öffnen") {
                        openSettings("Privacy_Microphone")
                    }.buttonStyle(PrimaryOnboardButton())
                } else {
                    Button("Mikrofon erlauben") {
                        AVCaptureDevice.requestAccess(for: .audio) { ok in
                            DispatchQueue.main.async { micStatus = ok ? .authorized : .denied }
                        }
                    }.buttonStyle(PrimaryOnboardButton())
                }
            }
        }
    }

    private var accessibilityStep: some View {
        stepBody(icon: axTrusted ? "checkmark.circle.fill" : "hand.raised.circle.fill",
                 iconColor: axTrusted ? .green : Color.shoutLive,
                 title: "Bedienungshilfen",
                 text: axTrusted
                    ? "Alles bereit — shout. kann Text an der Cursor-Position einfügen."
                    : "Damit shout. den fertigen Text an der Cursor-Position einfügen kann, aktiviere es unter „Bedienungshilfen“. Danach erkennt shout. die Freigabe automatisch.") {
            if !axTrusted {
                Button("Bedienungshilfen öffnen") {
                    let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
                    _ = AXIsProcessTrustedWithOptions(opts)
                    openSettings("Privacy_Accessibility")
                }.buttonStyle(PrimaryOnboardButton())
            }
        }
    }

    private var modelStep: some View {
        let ready = dashboard.transcriberReady
        return stepBody(icon: ready ? "checkmark.circle.fill" : "arrow.down.circle.fill",
                        iconColor: ready ? .green : Color.shoutLive,
                        title: "Sprachmodell",
                        text: ready
                            ? "Das Sprachmodell ist geladen und liegt lokal auf deinem Mac."
                            : "Beim ersten Start lädt shout. das Sprachmodell einmalig herunter (danach läuft alles offline). Das kann je nach Verbindung ein paar Minuten dauern.") {
            if !ready {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small).tint(Color.shoutLive)
                    Text("Modell wird geladen …").font(.system(size: 12)).foregroundStyle(Color(white: 0.6))
                }
            }
        }
    }

    private var testStep: some View {
        stepBody(icon: "keyboard.fill", title: "Probier es aus",
                 text: "Klick ins Feld, halte \(settings.hotkeyDescription) und sprich einen Satz. Dein Text erscheint direkt hier.") {
            VStack(alignment: .leading, spacing: 8) {
                TextEditor(text: $testText)
                    .font(.system(size: 13))
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .frame(height: 90)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color(white: 0.11)))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.white.opacity(0.08)))
                Text("Tipp: Aufnahme-Art und Taste kannst du später unter „Aufnahme & Text“ ändern.")
                    .font(.system(size: 11)).foregroundStyle(Color(white: 0.45))
            }
        }
    }

    // MARK: - Fuß

    private var footer: some View {
        HStack {
            if step > 0 {
                Button("Zurück") { step -= 1 }.buttonStyle(ConsoleButtonStyle())
            }
            Spacer()
            if step < stepCount - 1 {
                Button("Weiter") { step += 1 }.buttonStyle(PrimaryOnboardButton())
            } else {
                Button("Los geht's") { onFinish() }.buttonStyle(PrimaryOnboardButton())
            }
        }
        .padding(.horizontal, 22).padding(.vertical, 16)
    }

    // MARK: - Helfer

    @ViewBuilder
    private func stepBody<Extra: View>(icon: String, iconColor: Color = Color.shoutLive,
                                       title: String, text: String,
                                       @ViewBuilder extra: () -> Extra) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Image(systemName: icon).font(.system(size: 44)).foregroundStyle(iconColor)
            VStack(alignment: .leading, spacing: 10) {
                Text(title).font(.system(size: 22, weight: .semibold)).foregroundStyle(Color(white: 0.95))
                Text(text).font(.system(size: 14)).foregroundStyle(Color(white: 0.62))
                    .fixedSize(horizontal: false, vertical: true).lineSpacing(3)
            }
            extra()
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func openSettings(_ anchor: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") {
            NSWorkspace.shared.open(url)
        }
    }
}

/// Hervorgehobener Onboarding-Knopf in der Signalfarbe.
private struct PrimaryOnboardButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
            .padding(.horizontal, 18).padding(.vertical, 9)
            .background(RoundedRectangle(cornerRadius: 9).fill(Color.shoutLive))
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}
