import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// „Dateien" — fertige Audio- und Videodateien lokal transkribieren.
struct FilesView: View {
    @ObservedObject var queue: FileTranscriptionQueue
    /// Mitschnitt einer Besprechung. Gehört dem AppDelegate, nicht dieser Ansicht —
    /// eine laufende Aufnahme muss das Schließen des Fensters überstehen.
    @ObservedObject var recorder: MeetingRecorder
    /// Ist das Transkriptions-Modell geladen? Ohne Modell wäre jeder Knopf hier
    /// eine Lüge, deshalb steht dann nur ein Hinweis da.
    let modelReady: Bool
    /// Ist das Formatierungs-Modell geladen? Ohne das gibt `Formatter.format` still
    /// den Rohtext zurück — der Schalter würde also nichts tun und wird ausgegraut.
    let formatterReady: Bool
    /// Öffnet das Ergebnisfenster für einen fertigen Auftrag (AppDelegate verwaltet
    /// die Fenster, weil sie den Auftrag überdauern können).
    let onOpenResult: (FileTranscriptionJob) -> Void
    /// Schließt ein offenes Ergebnisfenster — nötig, bevor der Auftrag aus der
    /// Liste fliegt, sonst bliebe ein Fenster ohne Zeile zurück.
    let onCloseResult: (UUID) -> Void

    @AppStorage("fileFormattingEnabled") private var formattingEnabled = true
    @AppStorage("fileSpeechCommandsEnabled") private var speechCommands = false
    /// Standard AUS: Sie kostet einen Modell-Download, Speicher und Zeit — das soll
    /// niemand ungefragt bezahlen, der nur ein Transkript will.
    @AppStorage("fileDiarizationEnabled") private var diarization = false
    @State private var isTargeted = false
    /// Einmaliger Hinweis auf die Rechtslage vor dem ersten Mitschnitt.
    @AppStorage("meetingLegalHintShown") private var legalHintShown = false
    @State private var showLegalHint = false
    @State private var recorderError: String?
    /// Fertige Aufnahme, die noch auf ihren Namen wartet.
    @State private var finished: URL?
    @State private var naming = false
    @State private var name = ""
    /// Zuletzt gewählte Tonquelle. Als roher Wert, damit @AppStorage sie sichern kann.
    @AppStorage("meetingSource") private var source = MeetingSource.microphone.rawValue

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text(Loc.t("Dateien"))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color(white: 0.92))

                if modelReady {
                    meetingPanel
                    dropZone
                    optionsPanel
                    if !queue.jobs.isEmpty { jobsPanel }
                } else {
                    ConsolePanel {
                        Text(Loc.t("Zum Transkribieren wird das Sprachmodell gebraucht. Lade es unter „Modelle“ herunter — danach geht es hier weiter."))
                            .font(.system(size: 13))
                            .foregroundStyle(Color(white: 0.62))
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(16)
                    }
                }

                Text(Loc.t("Die Datei wird auf diesem Gerät gelesen — nichts wird hochgeladen. Ergebnisse werden nicht automatisch gespeichert und tauchen weder im Verlauf noch in den Statistiken auf."))
                    .font(.system(size: 11)).foregroundStyle(Color(white: 0.5))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: 640).frame(maxWidth: .infinity)
            .padding(.horizontal, 28).padding(.top, 42).padding(.bottom, 28)
        }
        .background(Color.shoutWindow)
        .scrollContentBackground(.hidden)
        // Liegengebliebene Mitschnitte zurück in die Liste — sonst wäre eine
        // Aufnahme nach einem Neustart der App unauffindbar.
        .task {
            guard !recorder.isRecording else { return }
            queue.restore(MeetingRecorder.existingRecordings())
        }
        .alert(Loc.t("Kurz vorweg"), isPresented: $showLegalHint) {
            Button(Loc.t("Verstanden")) { legalHintShown = true; beginRecording() }
            Button(Loc.t("Abbrechen"), role: .cancel) {}
        } message: {
            Text(Loc.t("Ein Gespräch mitzuschneiden ist ohne Einverständnis der anderen Beteiligten in Deutschland und Österreich strafbar. Frag kurz, bevor du aufnimmst."))
        }
        // Der Name fällt direkt nach dem Stoppen — da weiß man noch, worum es ging.
        .alert(Loc.t("Wie soll die Aufnahme heißen?"), isPresented: $naming) {
            TextField(Loc.t("Name"), text: $name)
            Button(Loc.t("Sichern")) { hand(over: true) }
            Button(Loc.t("Später"), role: .cancel) { hand(over: false) }
        } message: {
            Text(Loc.t("Du kannst sie auch später in der Liste umbenennen."))
        }
    }

    // MARK: - Mitschnitt

    /// Läuft nichts, steht hier der Aufnahme-Knopf; läuft etwas, dieselbe Fläche mit
    /// Zeit, Pegel und den Knöpfen. Bewusst kein eigenes Fenster: Eine laufende
    /// Aufnahme soll man sehen, wo man sie gestartet hat.
    @ViewBuilder
    private var meetingPanel: some View {
        ConsolePanel {
            if recorder.isRecording {
                HStack(spacing: 14) {
                    Text(Self.clock(recorder.duration))
                        .font(.system(size: 26, weight: .light, design: .rounded)).monospacedDigit()
                        .foregroundStyle(Color(white: recorder.isPaused ? 0.55 : 0.92))
                    VStack(alignment: .leading, spacing: 6) {
                        Text(recorder.isPaused ? Loc.t("Pausiert") : Loc.t("Nimmt auf …"))
                            .font(.system(size: 11)).foregroundStyle(Color(white: 0.55))
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.white.opacity(0.12))
                                Capsule().fill(Color.shoutLive)
                                    .frame(width: geo.size.width * CGFloat(recorder.isPaused ? 0 : recorder.level))
                                    .animation(.linear(duration: 0.1), value: recorder.level)
                            }
                        }
                        .frame(height: 4)
                    }
                    Button(recorder.isPaused ? Loc.t("Fortsetzen") : Loc.t("Pause")) {
                        recorder.isPaused ? recorder.resume() : recorder.pause()
                    }
                    .buttonStyle(ConsoleButtonStyle())
                    Button(Loc.t("Stoppen")) { stopRecording() }
                        .buttonStyle(ConsoleButtonStyle())
                }
                .padding(15)
                if recorder.noSignal {
                    Text(Loc.t("Es kommt kein Ton an. Beim Systemton fehlt dann meist die Erlaubnis: Systemeinstellungen → Datenschutz & Sicherheit → Tonaufnahme."))
                        .font(.system(size: 11))
                        .foregroundStyle(Color(red: 0.95, green: 0.7, blue: 0.2))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 15).padding(.bottom, 12)
                }
            } else {
                HStack(spacing: 14) {
                    Image(systemName: "record.circle")
                        .font(.system(size: 22)).foregroundStyle(Color.shoutLive)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(Loc.t("Meeting aufnehmen"))
                            .font(.system(size: 13, weight: .semibold)).foregroundStyle(Color(white: 0.9))
                        Text(recorderError ?? sourceHelp)
                            .font(.system(size: 11))
                            .foregroundStyle(recorderError == nil ? Color(white: 0.5) : Color(red: 0.95, green: 0.7, blue: 0.2))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                    Picker("", selection: $source) {
                        Text(Loc.t("Mikrofon")).tag(MeetingSource.microphone.rawValue)
                        Text(Loc.t("Systemton")).tag(MeetingSource.systemAudio.rawValue)
                        Text(Loc.t("Beides")).tag(MeetingSource.both.rawValue)
                    }
                    .labelsHidden().pickerStyle(.menu).frame(width: 130)
                    Button(Loc.t("Aufnehmen")) {
                        recorderError = nil
                        legalHintShown ? beginRecording() : (showLegalHint = true)
                    }
                    .buttonStyle(ConsoleButtonStyle())
                }
                .padding(15)
            }
        }
    }

    /// Was die gewählte Quelle bedeutet — direkt unter dem Knopf, wo die
    /// Entscheidung fällt.
    private var sourceHelp: String {
        switch MeetingSource(rawValue: source) ?? .microphone {
        case .microphone:
            return Loc.t("Nimmt über das Mikrofon auf — für Besprechungen im Raum.")
        case .systemAudio:
            return Loc.t("Nimmt den Ton anderer Programme auf — für Online-Meetings. Deine eigene Stimme ist dann NICHT dabei.")
        case .both:
            return Loc.t("Mikrofon und Ton anderer Programme zusammen — für Online-Meetings, bei denen du mitsprichst.")
        }
    }

    private func beginRecording() {
        do {
            try recorder.start(source: MeetingSource(rawValue: source) ?? .microphone)
        } catch {
            recorderError = error.localizedDescription
        }
    }

    private func stopRecording() {
        guard let url = recorder.stop() else { return }
        name = url.deletingPathExtension().lastPathComponent
        finished = url
        naming = true
    }

    /// Übergibt die fertige Aufnahme an die Warteschlange — mit oder ohne neuen
    /// Namen. Dieser Weg wird IMMER durchlaufen: Eine Aufnahme, die niemand
    /// übernimmt, wäre verloren.
    private func hand(over rename: Bool) {
        guard let url = finished else { return }
        finished = nil
        // Am Mac startet die Verarbeitung sofort — anders als am iPhone. Dort fällt
        // die Entscheidung nachträglich, weil eine Stunde Rechnen auf dem Telefon
        // teuer ist; hier stehen die Schalter sichtbar über dem Knopf, die Frage ist
        // also schon beantwortet, bevor die Aufnahme beginnt.
        queue.add([rename ? MeetingRecorder.rename(url, to: name) : url])
    }

    /// „1:02:44" bzw. „7:31" — ohne führende Stunde, solange keine gebraucht wird.
    private static func clock(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        return total >= 3600
            ? String(format: "%d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
            : String(format: "%d:%02d", total / 60, total % 60)
    }

    // MARK: - Ablagefläche

    private var dropZone: some View {
        VStack(spacing: 10) {
            Image(systemName: "waveform.badge.plus")
                .font(.system(size: 26)).foregroundStyle(Color.shoutLive)
            Text(Loc.t("Audio- oder Videodateien hierher ziehen"))
                .font(.system(size: 13)).foregroundStyle(Color(white: 0.75))
            Text(Loc.t("MP3, M4A, WAV, MP4, MOV und alles, was macOS abspielen kann"))
                .font(.system(size: 11)).foregroundStyle(Color(white: 0.5))
            Button(Loc.t("Auswählen …"), action: chooseFiles).buttonStyle(ConsoleButtonStyle())
        }
        .frame(maxWidth: .infinity).padding(.vertical, 30)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(white: 0.13)))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(isTargeted ? Color.shoutLive : Color.white.opacity(0.12),
                              style: StrokeStyle(lineWidth: isTargeted ? 2 : 1, dash: [6, 4]))
        )
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            load(providers)
            return true
        }
    }

    private var optionsPanel: some View {
        ConsolePanel(title: Loc.t("Verarbeitung")) {
            FieldRow(title: Loc.t("Protokoll erstellen"),
                     help: formatterReady
                        ? Loc.t("Zusätzlich zum Rohtext ein Protokoll: Zusammenfassung, Kernpunkte und der gegliederte Text. Dauert bei langen Dateien deutlich länger.")
                        : Loc.t("Das Modell zum Aufbereiten ist noch nicht geladen. Sobald es bereit ist, lässt sich der Schalter umlegen — bis dahin kommt das Rohtranskript.")) {
                Toggle("", isOn: $formattingEnabled).labelsHidden().toggleStyle(.switch)
                    .tint(Color.shoutLive).disabled(!formatterReady)
            }
            ConsoleDivider()
            FieldRow(title: Loc.t("Sprecher erkennen"),
                     help: Loc.t("Trennt die Stimmen und stellt „Sprecher 1“, „Sprecher 2“ voran. Lädt beim ersten Mal ein zusätzliches Modell und braucht die ganze Datei im Speicher — bei einer Stunde rund 230 MB.")) {
                Toggle("", isOn: $diarization).labelsHidden().toggleStyle(.switch).tint(Color.shoutLive)
            }
            ConsoleDivider()
            FieldRow(title: Loc.t("Sprachbefehle anwenden"),
                     help: Loc.t("Standardmäßig aus: In einer Aufzeichnung ist „Punkt“ meist ein normales Wort und kein Satzzeichen.")) {
                Toggle("", isOn: $speechCommands).labelsHidden().toggleStyle(.switch).tint(Color.shoutLive)
            }
        }
    }

    // MARK: - Aufträge

    private var jobsPanel: some View {
        ConsolePanel(title: Loc.t("Aufträge")) {
            VStack(spacing: 0) {
                ForEach(Array(queue.jobs.enumerated()), id: \.element.id) { index, job in
                    JobRow(job: job,
                           selected: job.id == queue.selectedJobID,
                           onSelect: { queue.selectedJobID = job.id },
                           onOpen: { onOpenResult(job) },
                           onCancel: { queue.cancel(job) },
                           onRemove: { onCloseResult(job.id); queue.remove(job) })
                    if index < queue.jobs.count - 1 { ConsoleDivider() }
                }
                // „Alle abbrechen" erst ab zwei offenen Aufträgen — bei einem einzigen
                // ist das Kreuz in der Zeile der kürzere Weg.
                if queue.jobs.filter({ !$0.isFinished }).count > 1 {
                    ConsoleDivider()
                    HStack {
                        Spacer()
                        Button(Loc.t("Alle abbrechen")) { queue.cancelAll() }
                            .buttonStyle(ConsoleButtonStyle())
                    }
                    .padding(.horizontal, 15).padding(.vertical, 10)
                }
            }
        }
    }

    // MARK: - Dateien annehmen

    private func chooseFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        // .audio und .movie decken MP3, M4A, WAV, AIFF, MP4, MOV und alles Weitere ab,
        // was AVFoundation lesen kann — eine längere Liste wäre nur redundant.
        panel.allowedContentTypes = [.audio, .movie]
        guard panel.runModal() == .OK else { return }
        queue.add(panel.urls)
    }

    private func load(_ providers: [NSItemProvider]) {
        for provider in providers {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                Task { @MainActor in queue.add([url]) }
            }
        }
    }
}

/// Eine Zeile der Auftragsliste.
private struct JobRow: View {
    @ObservedObject var job: FileTranscriptionJob
    let selected: Bool
    let onSelect: () -> Void
    let onOpen: () -> Void
    let onCancel: () -> Void
    let onRemove: () -> Void

    /// Nur fertige Aufträge haben ein Ergebnis zum Anschauen. Abgebrochene und
    /// fehlgeschlagene erklären sich in ihrer Zeile.
    private var hasResult: Bool { job.state == .done }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 14))
                .foregroundStyle(color).frame(width: 20)
            VStack(alignment: .leading, spacing: 3) {
                Text(job.name).font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color(white: 0.9)).lineLimit(1).truncationMode(.middle)
                Text(subtitle).font(.system(size: 11)).foregroundStyle(Color(white: 0.55))
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                if let fraction = progress {
                    ProgressView(value: fraction).progressViewStyle(.linear)
                        .tint(Color.shoutLive).frame(maxWidth: 220)
                }
            }
            Spacer(minLength: 8)
            if hasResult {
                Button(Loc.t("Öffnen"), action: onOpen).buttonStyle(ConsoleButtonStyle())
            }
            Button(action: job.isFinished ? onRemove : onCancel) {
                Image(systemName: "xmark").font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color(white: 0.6))
            }
            .buttonStyle(.plain)
            .help(job.isFinished ? Loc.t("Aus der Liste entfernen") : Loc.t("Abbrechen"))
        }
        .padding(.horizontal, 15).padding(.vertical, 12)
        .background(selected ? Color.shoutLive.opacity(0.10) : Color.clear)
        .contentShape(Rectangle())
        // Doppelklick zuerst — sonst schluckt der einfache Klick das Ereignis.
        .onTapGesture(count: 2) { if hasResult { onOpen() } else { onSelect() } }
        .onTapGesture(perform: onSelect)
    }

    private var progress: Double? {
        switch job.state {
        case .transcribing(let p), .formatting(let p): return p
        default: return nil
        }
    }

    private var icon: String {
        switch job.state {
        // „Noch nicht verarbeitet" entsteht nur am iPhone; am Mac starten Dateien
        // sofort, weil die Schalter direkt über der Auswahl stehen.
        case .unprocessed, .queued: return "clock"
        case .separatingSpeakers: return "person.2.wave.2"
        case .transcribing, .formatting: return "waveform"
        case .done: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.triangle.fill"
        case .cancelled: return "slash.circle"
        }
    }

    private var color: Color {
        switch job.state {
        case .done: return Color.shoutLive
        case .failed: return Color(red: 0.95, green: 0.7, blue: 0.2)
        default: return Color(white: 0.6)
        }
    }

    /// Zustand, davor die Länge der Datei, sobald sie bekannt ist (sie steht erst
    /// nach dem Öffnen fest, deshalb nicht schon im Zustand „Wartet").
    private var subtitle: String {
        let state: String
        switch job.state {
        case .unprocessed, .queued: state = Loc.t("Wartet")
        case .transcribing: state = Loc.t("Wird transkribiert …")
        case .separatingSpeakers: state = Loc.t("Sprecher werden getrennt …")
        case .formatting: state = Loc.t("Protokoll wird erstellt …")
        case .done:
            let fertig = Loc.f("Fertig · %d Wörter", job.wordCount)
            // Scheiterte die Sprechertrennung, steht der Grund gleich in der Zeile —
            // sonst rätselt man, warum keine Namen im Text stehen.
            state = job.speakerNote.map { "\(fertig) · \($0)" } ?? fertig
        case .failed(let reason): return reason
        case .cancelled: state = Loc.t("Abgebrochen")
        }
        guard job.duration > 0 else { return state }
        return "\(Self.length(job.duration)) · \(state)"
    }

    /// Länge als „3:07" bzw. „1:02:44" — kurz genug für die Zeile.
    private static func length(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        return total >= 3600
            ? String(format: "%d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
            : String(format: "%d:%02d", total / 60, total % 60)
    }
}
