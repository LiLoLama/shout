import SwiftUI

/// Haupt-Screen: großer Aufnahme-Knopf, Live-Pegel, Ergebnis mit Kopieren/Teilen.
struct HomeView: View {
    @ObservedObject var engine: MobileEngine
    @State private var copied = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer(minLength: 8)

                statusHeader

                recordButton
                    .padding(.vertical, 8)

                if case .recording = engine.state {
                    Button(role: .destructive) { engine.cancelRecording() } label: {
                        Label(Loc.t("Verwerfen"), systemImage: "xmark")
                    }
                    .buttonStyle(.bordered)
                }

                if case .failed(let message) = engine.state {
                    VStack(spacing: 10) {
                        Text(message)
                            .font(.footnote).foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Button(Loc.t("Erneut versuchen")) { engine.recover() }
                            .buttonStyle(.borderedProminent)
                    }
                    .padding(.horizontal, 24)
                }

                if engine.cameFromKeyboard, engine.lastResult != nil,
                   engine.state == .idle {
                    keyboardReturnHint
                }

                if let result = engine.lastResult, engine.state != .recording {
                    resultCard(result)
                }

                Spacer()
            }
            .padding()
            .navigationTitle("shout.")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: - Status

    private var statusHeader: some View {
        Group {
            switch engine.state {
            case .loadingModel:
                VStack(spacing: 6) {
                    if let p = engine.asrProgress, p > 0.001, p < 0.999 {
                        ProgressView(value: p) { Text(Loc.f("Sprachmodell wird geladen … %d %%", Int(p * 100))) }
                            .font(.footnote)
                    } else {
                        ProgressView { Text(Loc.t("Sprachmodell wird geladen …")).font(.footnote) }
                    }
                    Text(Loc.t("Einmalig — danach läuft alles offline."))
                        .font(.caption2).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 32)
            case .idle:
                Text(engine.lastResult == nil ? Loc.t("Tippe zum Diktieren") : Loc.t("Bereit"))
                    .font(.subheadline).foregroundStyle(.secondary)
            case .recording:
                Text(Loc.t("Ich höre zu …")).font(.subheadline).foregroundStyle(Color.shoutLive)
            case .working:
                Text(Loc.t("Verarbeite …")).font(.subheadline).foregroundStyle(.secondary)
            case .failed:
                Text(Loc.t("Problem")).font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Aufnahme-Knopf

    private var recordButton: some View {
        Button { engine.toggleRecording() } label: {
            ZStack {
                // Pegel-Ring während der Aufnahme
                if engine.state == .recording {
                    Circle()
                        .stroke(Color.shoutLive.opacity(0.35), lineWidth: 6)
                        .frame(width: 148, height: 148)
                        .scaleEffect(1 + CGFloat(engine.level) * 0.35)
                        .animation(.easeOut(duration: 0.1), value: engine.level)
                }
                Circle()
                    .fill(engine.state == .recording ? Color.shoutLive : Color.shoutLive.opacity(0.92))
                    .frame(width: 128, height: 128)
                    .shadow(color: Color.shoutLive.opacity(0.35), radius: 18, y: 6)
                Group {
                    switch engine.state {
                    case .recording:
                        Image(systemName: "stop.fill").font(.system(size: 40, weight: .bold))
                    case .working:
                        ProgressView().controlSize(.large).tint(.white)
                    default:
                        Image(systemName: "mic.fill").font(.system(size: 44, weight: .semibold))
                    }
                }
                .foregroundStyle(.white)
            }
        }
        .buttonStyle(.plain)
        .disabled(engine.state == .loadingModel || engine.state == .working || isFailed)
        .accessibilityLabel(engine.state == .recording ? Loc.t("Aufnahme stoppen") : Loc.t("Aufnahme starten"))
    }

    private var isFailed: Bool { if case .failed = engine.state { return true }; return false }

    // MARK: - Tastatur-Rückkehr

    private var keyboardReturnHint: some View {
        HStack(spacing: 10) {
            Image(systemName: "keyboard.badge.ellipsis")
                .font(.title3).foregroundStyle(Color.shoutLive)
            VStack(alignment: .leading, spacing: 2) {
                Text(Loc.t("Fertig — zurück zu deiner App wischen"))
                    .font(.subheadline.weight(.semibold))
                Text(Loc.t("Dann in der shout-Tastatur auf Einfügen tippen."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.shoutLive.opacity(0.12)))
        .padding(.horizontal, 4)
    }

    // MARK: - Ergebnis

    private func resultCard(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(Loc.t("In Zwischenablage kopiert"), systemImage: "doc.on.clipboard")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
            }
            ScrollView {
                Text(text)
                    .font(.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(maxHeight: 180)

            HStack(spacing: 12) {
                Button {
                    UIPasteboard.general.string = text
                    copied = true
                    Task { try? await Task.sleep(nanoseconds: 1_500_000_000); copied = false }
                } label: {
                    Label(copied ? Loc.t("Kopiert ✓") : Loc.t("Kopieren"), systemImage: "doc.on.doc")
                }
                .buttonStyle(.bordered)

                ShareLink(item: text) {
                    Label(Loc.t("Teilen"), systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemBackground)))
        .padding(.horizontal, 4)
    }
}
