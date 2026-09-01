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
    /// „local" oder „remote", je Verarbeitungsschritt.
    @AppStorage("asrEngine") private var asrEngine = "local"
    @AppStorage("formatEngine") private var formatEngine = "local"
    /// Oberflächensprache — unabhängig von der Diktier-Sprache oben.
    @AppStorage(Loc.storageKey) private var uiLanguage = "system"
    @State private var formattingOn = false

    @State private var importing = false
    @State private var pendingImportURL: URL?
    @State private var confirmImport = false
    @State private var shareURL: URL?
    @State private var dataMessage: String?

    private var ram: Int { Hardware.physicalMemoryGB }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    NavigationLink { dictationPage } label: {
                        settingsLink(icon: "waveform", title: Loc.t("Diktieren & Sprache"),
                                     detail: Loc.t("Sprache, Aufbereitung, Befehle und Auto-Stopp"))
                    }
                    NavigationLink { modelPage } label: {
                        settingsLink(icon: "cpu", title: Loc.t("Sprachmodelle"),
                                     detail: ModelCatalog.asrName(asrModel))
                    }
                    NavigationLink { keyboardPage } label: {
                        settingsLink(icon: "keyboard", title: Loc.t("shout.-Tastatur"),
                                     detail: Loc.t("Einrichten und Vollzugriff verstehen"))
                    }
                    NavigationLink { dataPage } label: {
                        settingsLink(icon: "externaldrive", title: Loc.t("Backup & Übertragung"),
                                     detail: Loc.t("Daten zwischen Mac und iPhone übertragen"))
                    }
                }
                statsSection
                supportSection
            }
            .navigationTitle(Loc.t("Einstellungen"))
            .onAppear { formattingOn = engine.formattingEnabled }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
                switch result {
                case .success(let url):
                    pendingImportURL = url
                    confirmImport = true
                case .failure(let error): dataMessage = error.localizedDescription
                }
            }
            .confirmationDialog(Loc.t("Backup importieren?"),
                                isPresented: $confirmImport, titleVisibility: .visible) {
                Button(Loc.t("Daten ersetzen und importieren"), role: .destructive) {
                    if let url = pendingImportURL { dataMessage = engine.importBundle(from: url) }
                    pendingImportURL = nil
                }
                Button(Loc.t("Abbrechen"), role: .cancel) { pendingImportURL = nil }
            } message: {
                Text(Loc.f("Das Backup ersetzt %d Wörterbuch-Einträge, %d Diktate, Statistiken und geteilte Einstellungen. Vorher wird automatisch eine lokale Sicherheitskopie erstellt.",
                           engine.dictionary.contents.terms.count + engine.dictionary.contents.corrections.count,
                           engine.history.entries.count))
            }
            .sheet(item: $shareURL) { url in ShareSheet(items: [url]) }
        }
    }

    private var dictationPage: some View {
        Form { dictationSection }
            .navigationTitle(Loc.t("Diktieren & Sprache"))
            .navigationBarTitleDisplayMode(.inline)
    }

    private var modelPage: some View {
        Form { modelSection }
            .navigationTitle(Loc.t("Sprachmodelle"))
            .navigationBarTitleDisplayMode(.inline)
    }

    private var keyboardPage: some View {
        Form {
            Section {
                Label(Loc.t("1. Einstellungen → Allgemein → Tastatur → Tastaturen öffnen"),
                      systemImage: "1.circle.fill")
                Label(Loc.t("2. shout. auswählen und „Vollen Zugriff erlauben“ aktivieren"),
                      systemImage: "2.circle.fill")
                Label(Loc.t("3. In einem Textfeld über die Globe-Taste zu shout. wechseln"),
                      systemImage: "3.circle.fill")
            } header: {
                Text(Loc.t("Einrichten"))
            } footer: {
                Text(Loc.t("Vollzugriff wird nur benötigt, damit App und Tastatur das fertige Diktat über den gemeinsamen lokalen Speicher austauschen können. shout. überträgt keine Tastatureingaben und keine Diktate ins Internet."))
            }
            Section {
                LabeledContent(Loc.t("Ablauf"), value: Loc.t("Aufnehmen → zurückkehren → einfügen"))
                Text(Loc.t("Die Aufnahme findet in shout. statt, weil iOS Tastatur-Erweiterungen keinen Mikrofonzugriff erlaubt."))
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle(Loc.t("shout.-Tastatur"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private var dataPage: some View {
        Form { dataSection }
            .navigationTitle(Loc.t("Backup & Übertragung"))
            .navigationBarTitleDisplayMode(.inline)
    }

    private func settingsLink(icon: String, title: String, detail: String) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).foregroundStyle(.primary)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: icon)
                .foregroundStyle(Color.shoutLive)
                .frame(width: 28)
        }
        .padding(.vertical, 2)
    }

    // MARK: - Diktat

    private var dictationSection: some View {
        Section(Loc.t("Diktat")) {
            Picker(Loc.t("Sprache"), selection: $language) {
                Text(Loc.t("Deutsch")).tag("de")
                Text(Loc.t("English")).tag("en")
                Text(Loc.t("Automatisch")).tag("auto")
            }
            // Die Oberflächensprache ist unabhängig von der Diktier-Sprache oben.
            Picker(Loc.t("Oberfläche"), selection: Binding(
                get: { uiLanguage },
                set: { Loc.shared.apply($0) }
            )) {
                ForEach(Loc.languageOptions, id: \.key) { option in
                    Text(option.label).tag(option.key)
                }
            }
            Toggle(Loc.t("Text automatisch aufräumen"), isOn: $formattingOn)
                .onChange(of: formattingOn) { _, on in engine.formattingEnabled = on }
            if formattingOn, let p = engine.formatProgress, p > 0.001, p < 0.999 {
                ProgressView(value: p) { Text(Loc.f("Aufbereitungs-Modell lädt … %d %%", Int(p * 100))).font(.caption) }
            }
            Toggle(Loc.t("Sprachbefehle („Komma“, „neue Zeile“ …)"), isOn: $speechCommands)
            Toggle(Loc.t("Klang-Signale"), isOn: $soundCues)
            Toggle(Loc.t("Auto-Stopp bei Sprechpause"), isOn: $autoStop)
            if autoStop {
                HStack {
                    Text(Loc.t("Pause bis Stopp"))
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
                LabeledContent(Loc.t("Gerät"), value: "\(Hardware.chip) · \(ram) GB RAM")
                if let note = engine.modelNote {
                    Label(note, systemImage: "info.circle")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } header: {
                Text(Loc.t("Modelle"))
            } footer: {
                Text(Loc.t("★ = Empfehlung für dein Gerät. Tippe „Laden“, um ein Modell herunterzuladen und zu aktivieren — einmalig, danach läuft alles offline."))
            }

            Section {
                engineSwitch(for: .audio, selection: $asrEngine)
            }

            if asrEngine == "remote" {
                MobileProviderSection(purpose: .audio) {
                    await engine.reloadEngine(for: .audio)
                }
            } else {
                Section(Loc.t("Transkription (Sprache → Text)")) {
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
            }

            if formattingOn {
                Section {
                    engineSwitch(for: .text, selection: $formatEngine)
                }

                if formatEngine == "remote" {
                    MobileProviderSection(purpose: .text) {
                        await engine.reloadEngine(for: .text)
                    }
                } else {
                    Section(Loc.t("Aufbereitung (KI-Textmodell)")) {
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
    }

    /// Umschalter „auf diesem Gerät" / „Anbieter" für einen Verarbeitungsschritt.
    private func engineSwitch(for purpose: EnginePurpose,
                              selection: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker(Loc.t("Verarbeitung"), selection: Binding(
                get: { selection.wrappedValue },
                set: { neu in
                    guard neu != selection.wrappedValue else { return }
                    selection.wrappedValue = neu
                    Task { await engine.reloadEngine(for: purpose) }
                })) {
                Text(Loc.t("Auf diesem Gerät")).tag("local")
                Text(Loc.t("Anbieter")).tag("remote")
            }
            .pickerStyle(.segmented)

            Text(selection.wrappedValue == "remote"
                 ? Loc.t("Läuft bei einem Anbieter deiner Wahl. Standard ist dein Gerät.")
                 : Loc.t("Läuft vollständig auf diesem Gerät. Nichts verlässt es."))
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    /// Eine Modell-Zeile: Name + Größe/Hinweis + Badges, rechts Status oder „Laden".
    private func modelRow(_ o: ModelCatalog.Option, active: Bool, recommended: Bool,
                          loading: Bool, progress: Double?, action: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(modelProfile(o)).font(.subheadline.weight(.semibold))
                        if recommended {
                            Text(Loc.t("★ Empfohlen")).font(.caption2.weight(.semibold))
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Capsule().fill(Color.shoutLive.opacity(0.15)))
                                .foregroundStyle(.primary)
                        }
                        if ram < o.minRAMGB {
                            Text(Loc.t("Viel RAM nötig")).font(.caption2)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Capsule().fill(Color.secondary.opacity(0.15)))
                                .foregroundStyle(.secondary)
                        }
                    }
                    Text("\(o.name) · \(Loc.t(o.note))")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if active && !loading {
                    Label(Loc.t("Aktiv"), systemImage: "checkmark.circle.fill")
                        .font(.caption.weight(.medium)).foregroundStyle(.green)
                        .labelStyle(.titleAndIcon)
                } else if loading {
                    ProgressView().controlSize(.small)
                } else {
                    Button(Loc.t("Laden"), action: action)
                        .buttonStyle(.bordered).controlSize(.regular)
                        .frame(minHeight: 44)
                        .disabled(anyModelLoading)
                }
            }
            if loading, let p = progress, p > 0.001, p < 0.999 {
                ProgressView(value: p) {
                    Text(Loc.f("Wird geladen … %d %%", Int(p * 100))).font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func modelProfile(_ option: ModelCatalog.Option) -> String {
        if let index = ModelCatalog.asr.firstIndex(of: option) {
            switch index {
            case 0: return Loc.t("Schnell")
            case 1: return Loc.t("Ausgewogen")
            case 2: return Loc.t("Sehr genau")
            default: return Loc.t("Maximale Genauigkeit")
            }
        }
        if let index = ModelCatalog.formatting.firstIndex(of: option) {
            switch index {
            case 0: return Loc.t("Schnell")
            case 1: return Loc.t("Ausgewogen")
            default: return Loc.t("Beste Aufbereitung")
            }
        }
        return option.name
    }

    // MARK: - Daten (Mac ↔ iPhone)

    private var dataSection: some View {
        Section {
            Button {
                shareURL = engine.exportBundleURL()
            } label: {
                Label(Loc.t("Backup exportieren (teilen)"), systemImage: "square.and.arrow.up")
            }
            Button {
                importing = true
            } label: {
                Label(Loc.t("Backup importieren"), systemImage: "square.and.arrow.down")
            }
            if let safetyBackup = engine.latestSafetyBackupURL() {
                Button {
                    shareURL = safetyBackup
                } label: {
                    Label(Loc.t("Letzte Sicherheitskopie teilen"), systemImage: "clock.arrow.circlepath")
                }
            }
            if let m = dataMessage {
                Text(m).font(.caption).foregroundStyle(.secondary)
            }
        } header: {
            Text(Loc.t("Daten (Mac ↔ iPhone)"))
        } footer: {
            Text(Loc.t("Import ersetzt Wörterbuch, Verlauf, Statistiken und geteilte Einstellungen. Direkt davor legt shout. automatisch eine lokale Sicherheitskopie an."))
        }
    }

    // MARK: - Statistiken

    private var statsSection: some View {
        Section(Loc.t("Statistiken")) {
            LabeledContent(Loc.t("Wörter diktiert"), value: "\(engine.stats.data.totalWords)")
            LabeledContent(Loc.t("Diktate"), value: "\(engine.stats.data.totalDictations)")
            LabeledContent(Loc.t("Serie"), value: Loc.f("%d Tage", engine.stats.currentStreak))
        }
    }

    // MARK: - Support

    private var supportSection: some View {
        Section {
            Link(destination: URL(string: "https://ko-fi.com/lilolama")!) {
                Label(Loc.t("Entwicklung unterstützen"), systemImage: "cup.and.saucer.fill")
            }
            Link(destination: URL(string: "https://github.com/LiLoLama/shout")!) {
                Label(Loc.t("Quellcode auf GitHub"), systemImage: "chevron.left.forwardslash.chevron.right")
            }
        } header: {
            Text("Open Source")
        } footer: {
            Text(Loc.t("shout. ist frei und quelloffen (GPL-3.0). Ich bemühe mich, die App aktuell zu halten und zu erweitern — Unterstützung ist freiwillig und hilft sehr. ❤️"))
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
