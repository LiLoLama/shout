import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Einstellungen: Diktat-Optionen, Modelle (mit Geräte-Empfehlung), Daten, Statistiken, Support.
struct MobileSettingsView: View {
    @ObservedObject var engine: MobileEngine

    @AppStorage("transcriptionLanguage") private var language = "de"
    @AppStorage("speechCommandsEnabled") private var speechCommands = false
    @AppStorage("soundCuesEnabled") private var soundCues = true
    @AppStorage("autoStopEnabled") private var autoStop = false
    @AppStorage("silenceSeconds") private var silenceSeconds = 1.5
    @AppStorage("asrModel") private var asrModel = ModelCatalog.defaultASR
    @AppStorage("formatModel") private var formatModel = ModelCatalog.defaultFormatting
    @State private var formattingOn = false

    @State private var importing = false
    @State private var shareURL: URL?
    @State private var dataMessage: String?

    private var ram: Int { Hardware.physicalMemoryGB }

    var body: some View {
        NavigationStack {
            Form {
                dictationSection
                modelSection
                dataSection
                statsSection
                supportSection
            }
            .navigationTitle("Einstellungen")
            .onAppear { formattingOn = engine.formattingEnabled }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
                switch result {
                case .success(let url): dataMessage = engine.importBundle(from: url)
                case .failure(let error): dataMessage = error.localizedDescription
                }
            }
            .sheet(item: $shareURL) { url in ShareSheet(items: [url]) }
        }
    }

    // MARK: - Diktat

    private var dictationSection: some View {
        Section("Diktat") {
            Picker("Sprache", selection: $language) {
                Text("Deutsch").tag("de")
                Text("English").tag("en")
                Text("Automatisch").tag("auto")
            }
            Toggle("Text automatisch aufräumen", isOn: $formattingOn)
                .onChange(of: formattingOn) { _, on in engine.formattingEnabled = on }
            if formattingOn, let p = engine.formatProgress, p > 0.001, p < 0.999 {
                ProgressView(value: p) { Text("Aufbereitungs-Modell lädt … \(Int(p * 100)) %").font(.caption) }
            }
            Toggle("Sprachbefehle („Komma“, „neue Zeile“ …)", isOn: $speechCommands)
            Toggle("Klang-Signale", isOn: $soundCues)
            Toggle("Auto-Stopp bei Sprechpause", isOn: $autoStop)
            if autoStop {
                HStack {
                    Text("Pause bis Stopp")
                    Slider(value: $silenceSeconds, in: 0.5...3.0, step: 0.1)
                    Text(String(format: "%.1f s", silenceSeconds)).font(.caption).monospacedDigit()
                }
            }
        }
    }

    // MARK: - Modelle

    private var anyModelLoading: Bool { engine.asrLoadingID != nil || engine.formatLoadingID != nil }

    private var modelSection: some View {
        Group {
            Section {
                LabeledContent("Gerät", value: "\(Hardware.chip) · \(ram) GB RAM")
                if let note = engine.modelNote {
                    Text(note).font(.caption).foregroundStyle(Color.shoutLive)
                }
            } header: {
                Text("Modelle")
            } footer: {
                Text("★ = Empfehlung für dein Gerät. Tippe „Laden“, um ein Modell herunterzuladen und zu aktivieren — einmalig, danach läuft alles offline.")
            }

            Section("Transkription (Sprache → Text)") {
                ForEach(ModelCatalog.asr) { o in
                    modelRow(o,
                             active: asrModel == o.id,
                             recommended: o.id == ModelCatalog.recommendedASR(ramGB: ram).id,
                             loading: engine.asrLoadingID == o.id,
                             progress: engine.asrProgress) {
                        Task { await engine.switchASRModel(to: o.id) }
                    }
                }
            }

            if formattingOn {
                Section("Aufbereitung (KI-Textmodell)") {
                    ForEach(ModelCatalog.formatting) { o in
                        modelRow(o,
                                 active: formatModel == o.id,
                                 recommended: o.id == ModelCatalog.recommendedFormatting(ramGB: ram).id,
                                 loading: engine.formatLoadingID == o.id,
                                 progress: engine.formatProgress) {
                            Task { await engine.switchFormatModel(to: o.id) }
                        }
                    }
                }
            }
        }
    }

    /// Eine Modell-Zeile: Name + Größe/Hinweis + Badges, rechts Status oder „Laden".
    private func modelRow(_ o: ModelCatalog.Option, active: Bool, recommended: Bool,
                          loading: Bool, progress: Double?, action: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(o.name).font(.subheadline.weight(.medium))
                        if recommended {
                            Text("★ Empfohlen").font(.caption2.weight(.semibold))
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Capsule().fill(Color.shoutLive.opacity(0.15)))
                                .foregroundStyle(Color.shoutLive)
                        }
                        if ram < o.minRAMGB {
                            Text("Viel RAM nötig").font(.caption2)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Capsule().fill(Color.secondary.opacity(0.15)))
                                .foregroundStyle(.secondary)
                        }
                    }
                    Text(o.note).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if active && !loading {
                    Label("Aktiv", systemImage: "checkmark.circle.fill")
                        .font(.caption.weight(.medium)).foregroundStyle(.green)
                        .labelStyle(.titleAndIcon)
                } else if loading {
                    ProgressView().controlSize(.small)
                } else {
                    Button("Laden", action: action)
                        .buttonStyle(.bordered).controlSize(.small)
                        .disabled(anyModelLoading)
                }
            }
            if loading, let p = progress, p > 0.001, p < 0.999 {
                ProgressView(value: p) {
                    Text("Wird geladen … \(Int(p * 100)) %").font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Daten (Mac ↔ iPhone)

    private var dataSection: some View {
        Section {
            Button {
                shareURL = engine.exportBundleURL()
            } label: {
                Label("Backup exportieren (teilen)", systemImage: "square.and.arrow.up")
            }
            Button {
                importing = true
            } label: {
                Label("Backup importieren", systemImage: "square.and.arrow.down")
            }
            if let m = dataMessage {
                Text(m).font(.caption).foregroundStyle(.secondary)
            }
        } header: {
            Text("Daten (Mac ↔ iPhone)")
        } footer: {
            Text("Am Mac unter „Sync & Geräte“ exportieren, per AirDrop aufs iPhone senden und hier importieren — übernimmt Wörterbuch, Verlauf, Statistiken und Einstellungen. Achtung: Import ersetzt die aktuellen Daten.")
        }
    }

    // MARK: - Statistiken

    private var statsSection: some View {
        Section("Statistiken") {
            LabeledContent("Wörter diktiert", value: "\(engine.stats.data.totalWords)")
            LabeledContent("Diktate", value: "\(engine.stats.data.totalDictations)")
            LabeledContent("Serie", value: "\(engine.stats.currentStreak) Tage")
        }
    }

    // MARK: - Support

    private var supportSection: some View {
        Section {
            Link(destination: URL(string: "https://ko-fi.com/lilolama")!) {
                Label("Entwicklung unterstützen", systemImage: "cup.and.saucer.fill")
            }
            Link(destination: URL(string: "https://github.com/LiLoLama/shout")!) {
                Label("Quellcode auf GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
            }
        } header: {
            Text("Open Source")
        } footer: {
            Text("shout. ist frei und quelloffen (GPL-3.0). Ich bemühe mich, die App aktuell zu halten und zu erweitern — Unterstützung ist freiwillig und hilft sehr. ❤️")
        }
    }
}

/// Erlaubt `.sheet(item:)` mit einer URL.
extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}

/// Dünner Wrapper um das System-Teilen-Blatt (UIActivityViewController).
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
