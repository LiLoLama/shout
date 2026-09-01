import SwiftUI
import AVFoundation
import UIKit

/// Erststart: kurze Erklärung, Mikrofon-Freigabe, Modell-Download-Status.
struct MobileOnboardingView: View {
    @ObservedObject var engine: MobileEngine
    let onFinish: () -> Void

    @State private var micPermission = AVAudioApplication.shared.recordPermission

    private var micGranted: Bool { micPermission == .granted }
    private var micDenied: Bool { micPermission == .denied }

    /// Zeigt, welches (für dieses Gerät empfohlene) Modell geladen wird — inkl. Größe.
    private var modelSubtitle: String {
        let id = UserDefaults.standard.string(forKey: "asrModel") ?? ModelCatalog.defaultASR
        if let option = ModelCatalog.asr.first(where: { $0.id == id }) {
            return Loc.f("%@ · %@ — einmalig, danach offline.", option.name, Loc.t(option.note))
        }
        return Loc.t("Einmalig — danach läuft alles offline.")
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 26) {
                Image(systemName: "mic.fill")
                    .font(.system(size: 52))
                    .foregroundStyle(Color.shoutLive)
                    .accessibilityHidden(true)

                VStack(spacing: 10) {
                    Text(Loc.t("Willkommen bei shout."))
                        .font(.title2.bold())
                    Text(Loc.t("Diktieren direkt auf deinem Gerät — die Spracherkennung läuft komplett lokal. Keine Cloud, keine Konten, nichts verlässt dein Gerät."))
                        .font(.subheadline).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                VStack(spacing: 14) {
                    stepRow(
                        done: micGranted,
                        title: micGranted
                            ? Loc.t("Mikrofon erlaubt")
                            : (micDenied ? Loc.t("Mikrofon noch nicht erlaubt") : Loc.t("Mikrofon erlauben")),
                        subtitle: micDenied
                            ? Loc.t("Du kannst shout. ansehen und den Zugriff später beim ersten Diktat erlauben.")
                            : Loc.t("Für die Aufnahme deiner Diktate. Du kannst das auch später entscheiden."),
                        actionTitle: micDenied ? Loc.t("Einstellungen öffnen") : Loc.t("Erlauben")
                    ) {
                        if micDenied {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        } else {
                            AVAudioApplication.requestRecordPermission { granted in
                                Task { @MainActor in
                                    micPermission = granted ? .granted : .denied
                                }
                            }
                        }
                    }

                    stepRow(
                        done: engine.transcriberReady,
                        title: engine.transcriberReady ? Loc.t("Sprachmodell geladen") : Loc.t("Sprachmodell lädt …"),
                        subtitle: modelSubtitle,
                        actionTitle: nil,
                        action: nil
                    )
                    if !engine.transcriberReady {
                        if let p = engine.asrProgress, p > 0.001, p < 0.999 {
                            ProgressView(value: p) {
                                Text("\(Int(p * 100)) %").font(.caption).foregroundStyle(.secondary)
                            }
                            .accessibilityLabel(Loc.t("Sprachmodell lädt …"))
                            .padding(.horizontal, 16)
                        } else {
                            ProgressView()
                                .accessibilityLabel(Loc.t("Sprachmodell lädt …"))
                                .padding(.horizontal, 16)
                        }
                    }

                    // Am iPhone wiegt das Argument noch schwerer als am Mac:
                    // 4–8 GB RAM und harte Jetsam-Grenzen. Wer hier hängt, findet
                    // die Alternative ohne diesen Hinweis nicht.
                    Text(Loc.t("Gerät zu schwach? Du kannst beide Schritte stattdessen bei einem Anbieter deiner Wahl laufen lassen — später in den Einstellungen."))
                        .font(.caption).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                }
            }
            .frame(maxWidth: 560)
            .padding(.horizontal, 24)
            .padding(.top, 48)
            .padding(.bottom, 24)
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 8) {
                Button(action: onFinish) {
                    Text(micGranted ? Loc.t("Los geht’s") : Loc.t("App ansehen"))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                if !micGranted {
                    Text(Loc.t("Mikrofonzugriff wird erst benötigt, wenn du wirklich aufnimmst."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(.bar)
        }
        .tint(Color.shoutLive)
    }

    private func stepRow(done: Bool, title: String, subtitle: String,
                         actionTitle: String?, action: (() -> Void)?) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(done ? .green : Color.shoutLive)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.medium))
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if !done, let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))
        .accessibilityElement(children: action == nil ? .combine : .contain)
    }
}
