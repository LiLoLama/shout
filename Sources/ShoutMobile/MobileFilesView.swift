import SwiftUI
import UniformTypeIdentifiers

/// „Meetings" auf dem iPhone: aufnehmen oder eine vorhandene Datei wählen, lokal
/// transkribieren, Ergebnis lesen und teilen.
///
/// Der Unterschied zum Mac liegt nicht in der Technik, sondern im Ablauf: Hier
/// wird **nichts von allein verarbeitet**. Eine Aufnahme landet in der Liste und
/// wartet — ob daraus ein Protokoll wird, ob die Sprecher getrennt werden oder ob
/// die Datei lieber an den Rechner geht, entscheidet sich danach. Auf einem Telefon
/// kostet eine Stunde Meeting sonst ungefragt Akku und eine halbe Ewigkeit.
struct MobileFilesView: View {
    @ObservedObject var engine: MobileEngine
    @ObservedObject var queue: FileTranscriptionQueue

    @State private var picking = false
    @State private var pickerError: String?
    @State private var recording = false
    /// Auftrag, für den gerade die Entscheidung ansteht.
    @State private var choosing: FileTranscriptionJob?
    /// Auftrag, der gerade umbenannt wird, und der neue Name.
    @State private var renaming: FileTranscriptionJob?
    @State private var showRename = false
    @State private var newName = ""

    var body: some View {
        NavigationStack {
            List {
                if engine.transcriberReady {
                    recordSection
                    if !queue.jobs.isEmpty { jobsSection }
                    filesSection
                } else {
                    Section {
                        Text(Loc.t("Zum Transkribieren wird das Sprachmodell gebraucht. Lade es in den Einstellungen — danach geht es hier weiter."))
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }

                Section {
                    Text(Loc.t("Alles läuft auf diesem Gerät — nichts wird hochgeladen. Aufnahmen und fertige Transkripte bleiben liegen, bis du sie hier entfernst."))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle(Loc.t("Meetings"))
            .task {
                // Liegengebliebene Mitschnitte zurückholen. Während einer laufenden
                // Aufnahme nicht: Die Datei wächst gerade noch.
                guard !engine.meetingRecorder.isRecording else { return }
                queue.restore(MeetingRecorder.existingRecordings())
            }
            .fileImporter(isPresented: $picking,
                          allowedContentTypes: [.audio, .movie],
                          allowsMultipleSelection: true) { result in
                switch result {
                case .success(let urls): queue.add(urls, start: false)
                case .failure(let error): pickerError = error.localizedDescription
                }
            }
            .fullScreenCover(isPresented: $recording) {
                MeetingRecordView(recorder: engine.meetingRecorder) { url in
                    queue.add([url], start: false)
                }
            }
            .sheet(item: $choosing) { job in
                ProcessingChoiceView(job: job,
                                     formatterReady: engine.formatterReady,
                                     onStart: { options in queue.start(job, options: options) },
                                     onDelete: { queue.remove(job) })
            }
            // Eigener Schalter statt `renaming != nil`: Sonst räumte der Setter der
            // Bindung den Auftrag womöglich weg, bevor der Knopf ihn liest.
            .alert(Loc.t("Wie soll die Aufnahme heißen?"), isPresented: $showRename) {
                TextField(Loc.t("Name"), text: $newName)
                Button(Loc.t("Sichern")) {
                    if let job = renaming { queue.rename(job, to: newName) }
                    renaming = nil
                }
                Button(Loc.t("Abbrechen"), role: .cancel) { renaming = nil }
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

    /// Der Aufnahme-Knopf ist das, wofür man diese Seite öffnet — also sieht er auch
    /// so aus und nicht wie ein Eintrag unter vielen.
    private var recordSection: some View {
        Section {
            Button {
                recording = true
            } label: {
                HStack(spacing: 16) {
                    ZStack {
                        Circle().fill(Color.shoutLive.opacity(0.15))
                            .frame(width: 52, height: 52)
                        Circle().fill(Color.shoutLive)
                            .frame(width: 22, height: 22)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(Loc.t("Meeting aufnehmen"))
                            .font(.headline).foregroundStyle(.primary)
                        Text(Loc.t("Handy auf den Tisch legen und antippen"))
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } footer: {
            Text(Loc.t("Die Aufnahme läuft weiter, wenn der Bildschirm aus ist. Was danach damit passiert, entscheidest du selbst."))
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

    private var jobsSection: some View {
        Section(Loc.t("Aufträge")) {
            ForEach(queue.jobs) { job in
                MobileJobRow(job: job, queue: queue,
                             formatterReady: engine.formatterReady,
                             onChoose: { choosing = job })
                    // Statt `.onDelete`: Umbenennen gehört an dieselbe Geste, und
                    // beides zusammen geht nur über `swipeActions`.
                    // Kein Voll-Wisch: Ein Meeting ist unwiederbringlich weg, das
                    // darf keine schnelle Handbewegung allein auslösen.
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        if job.isFinished {
                            Button(role: .destructive) {
                                queue.remove(job)
                            } label: {
                                Label(Loc.t("Entfernen"), systemImage: "trash")
                            }
                            if MeetingRecorder.isOwnRecording(job.url) {
                                Button {
                                    newName = job.url.deletingPathExtension().lastPathComponent
                                    renaming = job
                                    showRename = true
                                } label: {
                                    Label(Loc.t("Umbenennen"), systemImage: "pencil")
                                }
                                .tint(.gray)
                            }
                        } else {
                            // Laufendes NICHT über „Entfernen": Das löschte auch die
                            // Aufnahme. Abbrechen lässt die Datei liegen.
                            Button(role: .destructive) {
                                queue.cancel(job)
                            } label: {
                                Label(Loc.t("Abbrechen"), systemImage: "xmark")
                            }
                        }
                    }
            }
        }
    }
}

/// Eine Zeile der Auftragsliste. Wartende führen zur Entscheidung, fertige aufs
/// Ergebnis.
private struct MobileJobRow: View {
    @ObservedObject var job: FileTranscriptionJob
    @ObservedObject var queue: FileTranscriptionQueue
    let formatterReady: Bool
    let onChoose: () -> Void

    private var destination: some View {
        MobileTranscriptView(job: job, queue: queue, formatterReady: formatterReady)
    }

    var body: some View {
        switch job.state {
        case .unprocessed:
            Button(action: onChoose) {
                HStack {
                    label
                    Spacer(minLength: 8)
                    Text(Loc.t("Verarbeiten"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.shoutLive)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        // „Wird aufbereitet" bleibt begehbar: Der Rohtext ist zu diesem Zeitpunkt
        // fertig, und wer das Protokoll gerade angestoßen hat, will nicht aus der
        // Ansicht geworfen werden.
        case .done, .formatting:
            NavigationLink { destination } label: { label }
        default:
            HStack {
                label
                Spacer()
                if !job.isFinished {
                    Button(role: .destructive) { queue.cancel(job) } label: {
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
        case .unprocessed: state = Loc.t("Noch nicht verarbeitet")
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

/// Der Entscheidungspunkt: Was soll mit dieser Aufnahme passieren?
///
/// Die Schalter merken sich ihren Zustand, die Wahl zwischen „nur transkribieren"
/// und „mit Protokoll" bewusst nicht — genau darum geht es hier.
private struct ProcessingChoiceView: View {
    @ObservedObject var job: FileTranscriptionJob
    let formatterReady: Bool
    let onStart: (FileJobOptions) -> Void
    let onDelete: () -> Void

    @Environment(\.dismiss) private var dismiss
    @AppStorage("fileDiarizationEnabled") private var speakers = false
    @AppStorage("fileSpeechCommandsEnabled") private var commands = false
    @State private var confirmDelete = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    choice(title: Loc.t("Nur transkribieren"),
                           detail: Loc.t("Reiner Text mit Zeitmarken. Geht am schnellsten."),
                           icon: "text.alignleft",
                           enabled: true) { start(minutes: false) }

                    choice(title: Loc.t("Transkribieren und Protokoll"),
                           detail: Loc.t("Zusätzlich zum Rohtext ein Protokoll: Zusammenfassung, Kernpunkte und der gegliederte Text. Dauert bei langen Dateien deutlich länger."),
                           icon: "doc.text.magnifyingglass",
                           enabled: formatterReady) { start(minutes: true) }

                    if !formatterReady {
                        Text(Loc.t("Das Modell zum Aufbereiten ist noch nicht geladen. Bis dahin kommt das Rohtranskript."))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                } header: {
                    Text(Loc.t("Auf diesem Gerät"))
                }

                Section {
                    Toggle(Loc.t("Sprecher erkennen"), isOn: $speakers)
                    Toggle(Loc.t("Sprachbefehle anwenden"), isOn: $commands)
                } footer: {
                    Text(Loc.t("Trennt die Stimmen und stellt „Sprecher 1“, „Sprecher 2“ voran. Lädt beim ersten Mal ein zusätzliches Modell und braucht die ganze Datei im Speicher — bei einer Stunde rund 230 MB."))
                }

                Section {
                    ShareLink(item: job.url) {
                        Label(Loc.t("Aufnahme teilen …"), systemImage: "square.and.arrow.up")
                    }
                } footer: {
                    Text(Loc.t("Zum Beispiel per AirDrop an den Rechner — dort geht die Verarbeitung deutlich schneller. Die Aufnahme bleibt hier trotzdem liegen."))
                }

                // „Weg damit" ist eine legitime Antwort auf „was soll damit
                // passieren?" — und der Ort, an dem man sie gibt, ist dieser.
                Section {
                    Button(role: .destructive) { confirmDelete = true } label: {
                        Label(Loc.t("Aufnahme löschen"), systemImage: "trash")
                    }
                }
            }
            .confirmationDialog(Loc.t("Aufnahme löschen?"),
                                isPresented: $confirmDelete, titleVisibility: .visible) {
                Button(Loc.t("Löschen"), role: .destructive) {
                    onDelete()
                    dismiss()
                }
                Button(Loc.t("Abbrechen"), role: .cancel) {}
            } message: {
                Text(Loc.t("Die Audiodatei wird vom Gerät entfernt. Das lässt sich nicht rückgängig machen."))
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(Loc.t("Später entscheiden")) { dismiss() }
                }
            }
        }
    }

    /// Name und Länge — mehr braucht es nicht, um zu wissen, worüber man entscheidet.
    private var title: String {
        job.duration > 0
            ? "\(job.name) · \(TranscriptLayout.timecode(job.duration))"
            : job.name
    }

    private func choice(title: String, detail: String, icon: String,
                        enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(enabled ? Color.shoutLive : Color.secondary)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.headline)
                        .foregroundStyle(enabled ? .primary : .secondary)
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    private func start(minutes: Bool) {
        onStart(FileJobOptions(minutes: minutes, speakers: speakers, commands: commands))
        dismiss()
    }
}

/// Ergebnis eines Auftrags: Umschalter zwischen Protokoll und Rohtext, Teilen.
///
/// Kein zweites Fenster wie am Mac und keine Vergleichsspalte — auf einem Telefon
/// wäre beides unbedienbar. Bearbeiten ebenfalls nicht: Ein Textfeld über ein
/// einstündiges Transkript ist auf dem iPhone eher Falle als Hilfe.
private struct MobileTranscriptView: View {
    @ObservedObject var job: FileTranscriptionJob
    @ObservedObject var queue: FileTranscriptionQueue
    let formatterReady: Bool

    private enum Fassung: Hashable { case protokoll, roh }
    @State private var active: Fassung = .protokoll

    @Environment(\.dismiss) private var dismiss
    @State private var renaming = false
    @State private var newName = ""
    @State private var confirmDelete = false

    /// Umbenennen und Löschen der Datei gibt es nur für eigene Mitschnitte —
    /// ausgewählte Dateien liegen beim Nutzer.
    private var isOwn: Bool { MeetingRecorder.isOwnRecording(job.url) }

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

                minutesInvitation

                if text.isEmpty {
                    Text(Loc.t("Kein gesprochener Inhalt erkannt."))
                        .font(.footnote).foregroundStyle(.secondary)
                } else {
                    Text(text).font(.callout).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                verwaltung
            }
            .padding()
        }
        .navigationTitle(job.name)
        .navigationBarTitleDisplayMode(.inline)
        .alert(Loc.t("Wie soll die Aufnahme heißen?"), isPresented: $renaming) {
            TextField(Loc.t("Name"), text: $newName)
            Button(Loc.t("Sichern")) { queue.rename(job, to: newName) }
            Button(Loc.t("Abbrechen"), role: .cancel) {}
        }
        .confirmationDialog(Loc.t("Aufnahme löschen?"),
                            isPresented: $confirmDelete, titleVisibility: .visible) {
            Button(Loc.t("Löschen"), role: .destructive) {
                // Erst zurück, dann entfernen: Sonst verschwindet die Zeile unter
                // der geöffneten Ansicht und die Navigation räumt selbst auf.
                dismiss()
                queue.remove(job)
            }
            Button(Loc.t("Abbrechen"), role: .cancel) {}
        } message: {
            Text(Loc.t("Die Audiodatei wird vom Gerät entfernt. Das lässt sich nicht rückgängig machen."))
        }
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

    /// Umbenennen und Löschen sichtbar am Ende der Ansicht. Beides geht auch per
    /// Wischen in der Liste — aber eine Geste, die man nicht kennt, ist keine
    /// Funktion, die man hat.
    @ViewBuilder
    private var verwaltung: some View {
        if isOwn, job.isFinished {
            Divider().padding(.vertical, 4)
            HStack(spacing: 12) {
                Button {
                    newName = job.url.deletingPathExtension().lastPathComponent
                    renaming = true
                } label: {
                    Label(Loc.t("Umbenennen"), systemImage: "pencil")
                }
                .buttonStyle(.bordered)

                Button(role: .destructive) { confirmDelete = true } label: {
                    Label(Loc.t("Löschen"), systemImage: "trash")
                }
                .buttonStyle(.bordered)
                .tint(.red)

                Spacer(minLength: 0)
            }
            .font(.subheadline)
        }
    }

    /// Angebot, das Protokoll nachzureichen — der Text ist ja schon gerechnet.
    /// Steht hier und nicht in der Liste, weil hier entsteht, was einem fehlt:
    /// Man liest das Transkript und hätte gern die Kurzfassung.
    @ViewBuilder
    private var minutesInvitation: some View {
        if case .formatting(let fraction) = job.state {
            VStack(alignment: .leading, spacing: 6) {
                Text(Loc.t("Protokoll wird erstellt …")).font(.footnote)
                ProgressView(value: fraction).tint(Color.shoutLive)
            }
        } else if job.canAddMinutes {
            VStack(alignment: .leading, spacing: 6) {
                Button { queue.addMinutes(to: job) } label: {
                    Label(Loc.t("Protokoll erstellen"), systemImage: "doc.text.magnifyingglass")
                        .font(.subheadline.weight(.medium))
                }
                .buttonStyle(.bordered)
                .tint(Color.shoutLive)
                .disabled(!formatterReady)

                Text(formatterReady
                     ? Loc.t("Zusammenfassung und Kernpunkte aus diesem Text — die Datei wird dafür nicht noch einmal transkribiert.")
                     : Loc.t("Das Modell zum Aufbereiten ist noch nicht geladen. Bis dahin kommt das Rohtranskript."))
                    .font(.caption).foregroundStyle(.secondary)
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
