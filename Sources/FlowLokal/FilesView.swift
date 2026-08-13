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
    /// Öffnet das Ergebnisfenster für einen fertigen Auftrag (AppDelegate verwaltet
    /// die Fenster, weil sie den Auftrag überdauern können).
    let onOpenResult: (FileTranscriptionJob) -> Void
    /// Schließt ein offenes Ergebnisfenster — nötig, bevor der Auftrag aus der
    /// Liste fliegt, sonst bliebe ein Fenster ohne Zeile zurück.
    let onCloseResult: (UUID) -> Void

    @State private var isTargeted = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text(Loc.t("Dateien"))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color(white: 0.92))

                if modelReady {
                    dropZone
                    ProcessingOptionsPanel(formatterReady: formatterReady)
                    if !files.isEmpty { jobsPanel }
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

    // MARK: - Aufträge

    /// Nur eingeworfene Dateien — Mitschnitte stehen unter „Meeting".
    private var files: [FileTranscriptionJob] {
        queue.jobs.filter { !MeetingRecorder.isOwnRecording($0.url) }
    }

    private var jobsPanel: some View {
        ConsolePanel(title: Loc.t("Aufträge")) {
            VStack(spacing: 0) {
                ForEach(Array(files.enumerated()), id: \.element.id) { index, job in
                    JobRow(job: job,
                           selected: job.id == queue.selectedJobID,
                           onSelect: { queue.selectedJobID = job.id },
                           onOpen: { onOpenResult(job) },
                           onCancel: { queue.cancel(job) },
                           onRemove: { onCloseResult(job.id); queue.remove(job) })
                    if index < files.count - 1 { ConsoleDivider() }
                }
                // „Alle abbrechen" erst ab zwei offenen Aufträgen — bei einem einzigen
                // ist das Kreuz in der Zeile der kürzere Weg.
                if files.filter({ !$0.isFinished }).count > 1 {
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

/// Eine Zeile der Auftragsliste. Wird von „Dateien" UND „Meeting" benutzt.
struct JobRow: View {
    @ObservedObject var job: FileTranscriptionJob
    let selected: Bool
    let onSelect: () -> Void
    let onOpen: () -> Void
    let onCancel: () -> Void
    let onRemove: () -> Void
    /// Nur auf der Meeting-Seite gesetzt: Ein zurückgeholter Mitschnitt wartet auf
    /// die Entscheidung, ob er verarbeitet werden soll. Ohne diesen Weg stünde er
    /// für immer auf „Wartet".
    var onStart: (() -> Void)? = nil

    /// Nur fertige Aufträge haben ein Ergebnis zum Anschauen. Abgebrochene und
    /// fehlgeschlagene erklären sich in ihrer Zeile.
    private var hasResult: Bool { job.state == .done }

    private var waiting: Bool {
        if case .unprocessed = job.state { return true }
        return false
    }

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
            if waiting, let onStart {
                Button(Loc.t("Verarbeiten"), action: onStart).buttonStyle(ConsoleButtonStyle())
            }
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
        case .unprocessed: state = Loc.t("Noch nicht verarbeitet")
        case .queued: state = Loc.t("Wartet")
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
