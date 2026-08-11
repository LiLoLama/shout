import SwiftUI
import UniformTypeIdentifiers

/// „Dateien" auf dem iPhone: Audio- oder Videodatei aus der Dateien-App wählen,
/// lokal transkribieren, Ergebnis lesen und teilen.
///
/// Bewusst schlanker als am Mac: kein Ergebnisfenster (auf dem Telefon gibt es
/// keine zweiten Fenster) und keine Sprechertrennung — die bräuchte die ganze
/// Datei im Speicher, und iOS beendet Apps, die zu viel belegen, ohne Vorwarnung.
struct MobileFilesView: View {
    @ObservedObject var engine: MobileEngine
    @ObservedObject var queue: FileTranscriptionQueue

    @AppStorage("fileFormattingEnabled") private var minutesEnabled = true
    @AppStorage("fileSpeechCommandsEnabled") private var speechCommands = false
    @State private var picking = false
    @State private var pickerError: String?
    @State private var recording = false

    var body: some View {
        NavigationStack {
            List {
                if engine.transcriberReady {
                    meetingSection
                    optionsSection
                    filesSection
                    if !queue.jobs.isEmpty { jobsSection }
                } else {
                    Section {
                        Text(Loc.t("Zum Transkribieren wird das Sprachmodell gebraucht. Lade es in den Einstellungen — danach geht es hier weiter."))
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }

                Section {
                    Text(Loc.t("Die Datei wird auf diesem Gerät gelesen — nichts wird hochgeladen. Lange Dateien dauern auf dem Telefon deutlich länger als am Rechner."))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle(Loc.t("Dateien"))
            .fileImporter(isPresented: $picking,
                          allowedContentTypes: [.audio, .movie],
                          allowsMultipleSelection: true) { result in
                switch result {
                case .success(let urls): queue.add(urls)
                case .failure(let error): pickerError = error.localizedDescription
                }
            }
            .fullScreenCover(isPresented: $recording) {
                MeetingRecordView(recorder: engine.meetingRecorder) { url in
                    queue.add([url])
                }
            }
            .alert(Loc.t("Datei konnte nicht geöffnet werden"),
                   isPresented: .init(get: { pickerError != nil },
                                      set: { if !$0 { pickerError = nil } })) {
                Button(Loc.t("OK"), role: .cancel) { pickerError = nil }
            } message: {
                Text(pickerError ?? "")
            }
        }
    }

    // MARK: - Abschnitte

    /// Aufnehmen steht oben: Es ist der Weg, bei dem das Transkript erst entsteht,
    /// waehrend die Dateiauswahl schon vorhandenes Material verarbeitet.
    private var meetingSection: some View {
        Section {
            Button {
                recording = true
            } label: {
                Label(Loc.t("Meeting aufnehmen"), systemImage: "record.circle")
            }
            .tint(Color.shoutLive)
        } footer: {
            Text(Loc.t("Handy auf den Tisch legen und aufnehmen. Die Aufnahme läuft weiter, wenn der Bildschirm aus ist, und wird danach automatisch transkribiert."))
        }
    }

    private var filesSection: some View {
        Section {
            Button {
                picking = true
            } label: {
                Label(Loc.t("Datei auswählen …"), systemImage: "waveform.badge.plus")
            }
        } footer: {
            Text(Loc.t("MP3, M4A, WAV, MP4, MOV und alles, was iOS abspielen kann"))
        }
    }

    private var optionsSection: some View {
        Section(Loc.t("Verarbeitung")) {
            Toggle(Loc.t("Protokoll erstellen"), isOn: $minutesEnabled)
                .disabled(!engine.formatterReady)
            if !engine.formatterReady {
                Text(Loc.t("Das Modell zum Aufbereiten ist noch nicht geladen. Bis dahin kommt das Rohtranskript."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Toggle(Loc.t("Sprachbefehle anwenden"), isOn: $speechCommands)
        }
    }

    private var jobsSection: some View {
        Section(Loc.t("Aufträge")) {
            ForEach(queue.jobs) { job in
                MobileJobRow(job: job, onCancel: { queue.cancel(job) })
            }
            .onDelete { indexSet in
                for index in indexSet where index < queue.jobs.count {
                    queue.remove(queue.jobs[index])
                }
            }
        }
    }
}

/// Eine Zeile der Auftragsliste; fertige Aufträge führen aufs Ergebnis.
private struct MobileJobRow: View {
    @ObservedObject var job: FileTranscriptionJob
    let onCancel: () -> Void

    var body: some View {
        if case .done = job.state {
            NavigationLink { MobileTranscriptView(job: job) } label: { label }
        } else {
            HStack {
                label
                Spacer()
                if !job.isFinished {
                    Button(role: .destructive, action: onCancel) {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var label: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(job.name).font(.body).lineLimit(1).truncationMode(.middle)
            Text(subtitle).font(.caption).foregroundStyle(.secondary)
            if let fraction = progress {
                ProgressView(value: fraction).tint(Color.shoutLive)
            }
        }
    }

    private var progress: Double? {
        switch job.state {
        case .transcribing(let p), .formatting(let p): return p
        default: return nil
        }
    }

    private var subtitle: String {
        let state: String
        switch job.state {
        case .queued: state = Loc.t("Wartet")
        case .transcribing: state = Loc.t("Wird transkribiert …")
        case .separatingSpeakers: state = Loc.t("Sprecher werden getrennt …")
        case .formatting: state = Loc.t("Protokoll wird erstellt …")
        case .done: state = Loc.f("Fertig · %d Wörter", job.wordCount)
        case .failed(let reason): return reason
        case .cancelled: state = Loc.t("Abgebrochen")
        }
        guard job.duration > 0 else { return state }
        return "\(TranscriptLayout.timecode(job.duration)) · \(state)"
    }
}

/// Ergebnis eines Auftrags: Umschalter zwischen Protokoll und Rohtext, Teilen.
///
/// Kein zweites Fenster wie am Mac und keine Vergleichsspalte — auf einem Telefon
/// wäre beides unbedienbar. Bearbeiten ebenfalls nicht: Ein Textfeld über ein
/// einstündiges Transkript ist auf dem iPhone eher Falle als Hilfe.
private struct MobileTranscriptView: View {
    @ObservedObject var job: FileTranscriptionJob

    private enum Fassung: Hashable { case protokoll, roh }
    @State private var active: Fassung = .protokoll

    private var hasBoth: Bool { !job.formattedText.isEmpty && !job.rawText.isEmpty }
    private var text: String {
        (active == .protokoll && !job.formattedText.isEmpty) ? job.formattedText : job.rawText
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if hasBoth {
                    Picker("", selection: $active) {
                        Text(Loc.t("Protokoll")).tag(Fassung.protokoll)
                        Text(Loc.t("Rohtext")).tag(Fassung.roh)
                    }
                    .pickerStyle(.segmented)
                }

                if text.isEmpty {
                    Text(Loc.t("Kein gesprochener Inhalt erkannt."))
                        .font(.footnote).foregroundStyle(.secondary)
                } else {
                    Text(text).font(.callout).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding()
        }
        .navigationTitle(job.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    UIPasteboard.general.string = text
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .disabled(text.isEmpty)

                if let file = exportFile() {
                    ShareLink(item: file) { Image(systemName: "square.and.arrow.up") }
                }
            }
        }
    }

    /// Schreibt die aktive Fassung in eine temporäre Datei, damit das Teilen-Menü
    /// sie als Anhang statt als Textschnipsel weiterreicht.
    private func exportFile() -> URL? {
        guard !text.isEmpty else { return nil }
        let suffix = (hasBoth && active == .roh) ? (Loc.isGerman ? "-roh" : "-raw") : ""
        let name = TranscriptExport.fileName(for: job.url, suffix: suffix, extension: "txt")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }
}
