import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// „Dateien" — fertige Audio- und Videodateien lokal transkribieren.
struct FilesView: View {
    @ObservedObject var queue: FileTranscriptionQueue
    /// Ist das Transkriptions-Modell geladen? Ohne Modell wäre jeder Knopf hier
    /// eine Lüge, deshalb steht dann nur ein Hinweis da.
    let modelReady: Bool
    /// Ist das Formatierungs-Modell geladen? Ohne das gibt `Formatter.format` still
    /// den Rohtext zurück — der Schalter würde also nichts tun und wird ausgegraut.
    let formatterReady: Bool

    @AppStorage("fileFormattingEnabled") private var formattingEnabled = true
    @AppStorage("fileSpeechCommandsEnabled") private var speechCommands = false
    @State private var isTargeted = false
    @State private var status = ""

    /// Nur ein wirklich fertiger Auftrag zeigt ein Ergebnis. Abgebrochene und
    /// fehlgeschlagene erklären sich in ihrer Zeile — ein Ergebnisfeld dazu wäre
    /// bestenfalls leer und schlimmstenfalls irreführend.
    private var selectedJob: FileTranscriptionJob? {
        queue.jobs.first { $0.id == queue.selectedJobID && $0.state == .done }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text(Loc.t("Dateien"))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color(white: 0.92))

                if modelReady {
                    dropZone
                    optionsPanel
                    if !queue.jobs.isEmpty { jobsPanel }
                    if let job = selectedJob { resultPanel(job) }
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
            FieldRow(title: Loc.t("Text aufbereiten"),
                     help: formatterReady
                        ? Loc.t("Füllwörter entfernen, Satzzeichen setzen — abschnittsweise durch das lokale Sprachmodell.")
                        : Loc.t("Das Modell zum Aufbereiten ist noch nicht geladen. Sobald es bereit ist, lässt sich der Schalter umlegen — bis dahin kommt das Rohtranskript.")) {
                Toggle("", isOn: $formattingEnabled).labelsHidden().toggleStyle(.switch)
                    .tint(Color.shoutLive).disabled(!formatterReady)
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
                           onCancel: { queue.cancel(job) },
                           onRemove: { queue.remove(job) })
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

    // MARK: - Ergebnis

    private func resultPanel(_ job: FileTranscriptionJob) -> some View {
        ConsolePanel(title: Loc.t("Ergebnis")) {
            VStack(alignment: .leading, spacing: 12) {
                if job.displayText.isEmpty {
                    Text(Loc.t("Kein gesprochener Inhalt erkannt."))
                        .font(.system(size: 13)).foregroundStyle(Color(white: 0.62))
                } else {
                    ScrollView {
                        Text(job.displayText)
                            .font(.system(size: 12.5))
                            .foregroundStyle(Color(white: 0.88))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                    }
                    .frame(height: 220)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color(white: 0.11)))

                    HStack(spacing: 10) {
                        Button(Loc.t("Kopieren")) {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(job.displayText, forType: .string)
                            status = Loc.t("In die Zwischenablage kopiert.")
                        }.buttonStyle(ConsoleButtonStyle())
                        Button(Loc.t("Als Text sichern …")) { save(job, asSubtitles: false) }
                            .buttonStyle(ConsoleButtonStyle())
                        Button(Loc.t("Untertitel sichern …")) { save(job, asSubtitles: true) }
                            .buttonStyle(ConsoleButtonStyle())
                            .disabled(job.segments.isEmpty)
                    }
                    Text(Loc.t("Untertitel enthalten immer das Rohtranskript — nur so passen die Zeitmarken zum Wortlaut."))
                        .font(.system(size: 11)).foregroundStyle(Color(white: 0.5))
                        .fixedSize(horizontal: false, vertical: true)
                    if !status.isEmpty {
                        Text(status).font(.system(size: 12)).foregroundStyle(Color.shoutLive)
                    }
                }
            }
            .padding(16)
        }
    }

    // MARK: - Dateien annehmen und sichern

    private func chooseFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        // .audio und .movie decken MP3, M4A, WAV, AIFF, MP4, MOV und alles Weitere ab,
        // was AVFoundation lesen kann — eine längere Liste wäre nur redundant.
        panel.allowedContentTypes = [.audio, .movie]
        guard panel.runModal() == .OK else { return }
        status = ""
        queue.add(panel.urls)
    }

    private func load(_ providers: [NSItemProvider]) {
        for provider in providers {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                Task { @MainActor in
                    status = ""
                    queue.add([url])
                }
            }
        }
    }

    private func save(_ job: FileTranscriptionJob, asSubtitles: Bool) {
        let panel = NSSavePanel()
        let base = job.url.deletingPathExtension().lastPathComponent
        panel.nameFieldStringValue = base + (asSubtitles ? ".srt" : ".txt")
        panel.allowedContentTypes = asSubtitles ? [] : [.plainText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let content = asSubtitles ? SubtitleWriter.srt(from: job.segments) : job.displayText
        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
            status = Loc.f("Gesichert: %@", url.lastPathComponent)
        } catch {
            status = Loc.f("Sichern fehlgeschlagen: %@", error.localizedDescription)
        }
    }
}

/// Eine Zeile der Auftragsliste.
private struct JobRow: View {
    @ObservedObject var job: FileTranscriptionJob
    let selected: Bool
    let onSelect: () -> Void
    let onCancel: () -> Void
    let onRemove: () -> Void

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
        case .queued: return "clock"
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
        case .queued: state = Loc.t("Wartet")
        case .transcribing: state = Loc.t("Wird transkribiert …")
        case .formatting: state = Loc.t("Text wird aufbereitet …")
        case .done: state = Loc.f("Fertig · %d Wörter", job.wordCount)
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
