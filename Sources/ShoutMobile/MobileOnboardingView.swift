import SwiftUI
import AVFoundation

/// Erststart: kurze Erklärung, Mikrofon-Freigabe, Modell-Download-Status.
struct MobileOnboardingView: View {
    @ObservedObject var engine: MobileEngine
    let onFinish: () -> Void

    @State private var micGranted = AVAudioApplication.shared.recordPermission == .granted

    var body: some View {
        VStack(spacing: 26) {
            Spacer()

            Image(systemName: "mic.fill")
                .font(.system(size: 52)).foregroundStyle(Color.shoutLive)

            VStack(spacing: 10) {
                Text("Willkommen bei shout.")
                    .font(.title2.bold())
                Text("Diktieren direkt auf deinem iPhone — die Spracherkennung läuft komplett lokal. Keine Cloud, keine Konten, nichts verlässt dein Gerät.")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 28)

            VStack(spacing: 14) {
                stepRow(done: micGranted,
                        title: micGranted ? "Mikrofon erlaubt" : "Mikrofon erlauben",
                        subtitle: "Für die Aufnahme deiner Diktate.") {
                    AVAudioApplication.requestRecordPermission { granted in
                        Task { @MainActor in micGranted = granted }
                    }
                }

                stepRow(done: engine.transcriberReady,
                        title: engine.transcriberReady ? "Sprachmodell geladen" : "Sprachmodell lädt …",
                        subtitle: "Einmalig — danach läuft alles offline.",
                        action: nil)
                if let p = engine.asrProgress, p > 0.001, p < 0.999 {
                    ProgressView(value: p).padding(.horizontal, 32)
                }
            }
            .padding(.horizontal, 16)

            Spacer()

            Button {
                onFinish()
            } label: {
                Text("Los geht’s")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!micGranted)
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
        }
        .tint(Color.shoutLive)
    }

    private func stepRow(done: Bool, title: String, subtitle: String, action: (() -> Void)?) -> some View {
        HStack(spacing: 12) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(done ? .green : Color.shoutLive)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.medium))
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if !done, let action {
                Button("Erlauben", action: action).buttonStyle(.bordered).controlSize(.small)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))
    }
}
