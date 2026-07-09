import SwiftUI

/// Einstellungen: Diktat-Optionen, Modelle (mit Geräte-Empfehlung), Statistiken, Support.
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

    private var ram: Int { Hardware.physicalMemoryGB }

    var body: some View {
        NavigationStack {
            Form {
                dictationSection
                modelSection
                statsSection
                supportSection
            }
            .navigationTitle("Einstellungen")
            .onAppear { formattingOn = engine.formattingEnabled }
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

    private var modelSection: some View {
        Section {
            LabeledContent("Gerät", value: "\(Hardware.chip) · \(ram) GB RAM")

            Picker("Transkription", selection: $asrModel) {
                ForEach(ModelCatalog.asr) { o in
                    Text(o.id == ModelCatalog.recommendedASR(ramGB: ram).id ? "\(o.name) ★" : o.name)
                        .tag(o.id)
                }
            }
            .onChange(of: asrModel) { _, id in Task { await engine.switchASRModel(to: id) } }
            if let p = engine.asrProgress, p > 0.001, p < 0.999 {
                ProgressView(value: p) { Text("Sprachmodell lädt … \(Int(p * 100)) %").font(.caption) }
            }

            if formattingOn {
                Picker("Aufbereitung", selection: $formatModel) {
                    ForEach(ModelCatalog.formatting) { o in
                        Text(o.id == ModelCatalog.recommendedFormatting(ramGB: ram).id ? "\(o.name) ★" : o.name)
                            .tag(o.id)
                    }
                }
                .onChange(of: formatModel) { _, id in Task { await engine.switchFormatModel(to: id) } }
            }

            if let note = engine.modelNote {
                Text(note).font(.caption).foregroundStyle(Color.shoutLive)
            }
        } header: {
            Text("Modelle")
        } footer: {
            Text("★ = Empfehlung für dein Gerät. Modelle werden einmalig geladen und laufen danach komplett offline.")
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
