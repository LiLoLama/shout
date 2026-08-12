import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Inhalt des Ergebnisfensters: eine Transkription in voller Fensterbreite,
/// bearbeitbar, mit den Exportwegen darunter.
///
/// Eigenes Fenster statt eines Bereichs auf der Seite „Dateien": Ein Textfeld von
/// 220 Punkt Höhe trägt bei einem einstündigen Transkript nicht — man scrollt
/// darin herum, statt zu lesen.
struct TranscriptWindowView: View {

    /// Welche Fassung gerade die aktive ist.
    private enum Fassung: Hashable { case protokoll, roh }

    @ObservedObject var job: FileTranscriptionJob
    /// Für das nachgereichte Protokoll — es läuft über dieselbe Warteschlange wie
    /// alles andere, damit sich nie zwei Läufe um das Modell streiten.
    @ObservedObject var queue: FileTranscriptionQueue
    /// Zustand beim Öffnen des Fensters. Ein Abbild reicht: Wer hier steht, hat
    /// einen fertigen Auftrag vor sich — bis dahin ist das Modell längst geladen
    /// oder es wurde nie eingeschaltet.
    let formatterReady: Bool
    @ObservedObject private var loc = Loc.shared

    @State private var active: Fassung
    @State private var comparing = false
    @State private var status = ""

    init(job: FileTranscriptionJob, queue: FileTranscriptionQueue, formatterReady: Bool) {
        self.job = job
        self.queue = queue
        self.formatterReady = formatterReady
        // Ohne Aufbereitung gibt es nur den Rohtext — dann ist er auch die aktive Fassung.
        _active = State(initialValue: job.formattedText.isEmpty ? .roh : .protokoll)
    }

    /// Nur wenn beide Fassungen existieren, ergeben Umschalter und Vergleich Sinn.
    private var hasBoth: Bool { !job.formattedText.isEmpty && !job.rawText.isEmpty }

    private var activeText: Binding<String> {
        active == .protokoll ? $job.formattedText : $job.rawText
    }

    private var otherText: String {
        active == .protokoll ? job.rawText : job.formattedText
    }

    private var activeTitle: String {
        active == .protokoll ? Loc.t("Protokoll") : Loc.t("Rohtext")
    }

    private var otherTitle: String {
        active == .protokoll ? Loc.t("Rohtext") : Loc.t("Protokoll")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Rectangle().fill(Color.white.opacity(0.07)).frame(height: 1)
            if job.rawText.isEmpty && job.formattedText.isEmpty {
                empty
            } else {
                editors
                Rectangle().fill(Color.white.opacity(0.07)).frame(height: 1)
                footer
            }
        }
        .id(loc.language)
        // Kommt das Protokoll nachträglich, ist es auch das, was man sehen will —
        // sonst bliebe das Fenster auf dem Rohtext stehen und der Knopf wirkte
        // folgenlos.
        .onChange(of: job.formattedText) { _, neu in
            if !neu.isEmpty, active == .roh, !comparing { active = .protokoll }
        }
        .background(Color.shoutWindow)
        .preferredColorScheme(.dark)
        .frame(minWidth: 620, minHeight: 420)
    }

    // MARK: - Kopf

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(job.name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color(white: 0.92))
                    .lineLimit(1).truncationMode(.middle)
                Text(meta).font(.system(size: 11)).foregroundStyle(Color(white: 0.55))
            }
            Spacer(minLength: 12)
            if hasBoth {
                ConsoleSegmented(selection: $active,
                                 options: [(.protokoll, Loc.t("Protokoll")),
                                           (.roh, Loc.t("Rohtext"))])
                Button(comparing ? Loc.t("Vergleich ausblenden") : Loc.t("Vergleichen")) {
                    comparing.toggle()
                }
                .buttonStyle(ConsoleButtonStyle())
            } else {
                Text(Loc.t("Rohtext"))
                    .font(.system(size: 11, weight: .semibold)).tracking(0.8)
                    .foregroundStyle(Color(white: 0.45))
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 16)
    }

    /// Länge der Datei und Wortzahl der aktiven Fassung.
    private var meta: String {
        let words = activeText.wrappedValue
            .split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
        guard job.duration > 0 else { return Loc.f("%d Wörter", words) }
        return Loc.f("%@ · %d Wörter", Self.length(job.duration), words)
    }

    private static func length(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        return total >= 3600
            ? String(format: "%d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
            : String(format: "%d:%02d", total / 60, total % 60)
    }

    // MARK: - Textfelder

    private var empty: some View {
        VStack {
            Spacer()
            Text(Loc.t("Kein gesprochener Inhalt erkannt."))
                .font(.system(size: 13)).foregroundStyle(Color(white: 0.62))
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var editors: some View {
        HStack(spacing: 0) {
            editor
            if comparing, hasBoth {
                Rectangle().fill(Color.white.opacity(0.07)).frame(width: 1)
                comparison
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Die aktive Fassung — bearbeitbar. Was hier geändert wird, gilt für Kopieren,
    /// Sichern und die Wortzahl in der Auftragsliste.
    private var editor: some View {
        VStack(alignment: .leading, spacing: 0) {
            if comparing, hasBoth { columnTitle(activeTitle, editable: true) }
            TextEditor(text: activeText)
                .font(.system(size: 13))
                .foregroundStyle(Color(white: 0.9))
                .scrollContentBackground(.hidden)
                .background(Color.shoutWindow)
                .padding(.horizontal, 14).padding(.vertical, 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Die andere Fassung — bewusst NUR LESBAR. Wären beide Spalten bearbeitbar,
    /// wäre bei jedem Klick auf „Sichern" unklar, welcher Text gemeint ist.
    private var comparison: some View {
        VStack(alignment: .leading, spacing: 0) {
            columnTitle(otherTitle, editable: false)
            ScrollView {
                Text(otherText)
                    .font(.system(size: 13))
                    .foregroundStyle(Color(white: 0.62))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14).padding(.vertical, 10)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(white: 0.09))
    }

    private func columnTitle(_ title: String, editable: Bool) -> some View {
        HStack(spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold)).tracking(0.8)
                .foregroundStyle(Color(white: 0.45))
            if !editable {
                Text(Loc.t("nur lesen"))
                    .font(.system(size: 10)).foregroundStyle(Color(white: 0.35))
            }
            Spacer()
        }
        .padding(.horizontal, 15).padding(.top, 12).padding(.bottom, 4)
    }

    // MARK: - Fuß

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            minutesRow
            HStack(spacing: 10) {
                Button(Loc.t("Kopieren")) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(activeText.wrappedValue, forType: .string)
                    status = Loc.f("%@ in die Zwischenablage kopiert.", activeTitle)
                }.buttonStyle(ConsoleButtonStyle())
                Button(Loc.t("Als Text sichern …")) { saveText() }
                    .buttonStyle(ConsoleButtonStyle())
                Button(Loc.t("Untertitel sichern …")) { saveSubtitles() }
                    .buttonStyle(ConsoleButtonStyle())
                    .disabled(job.segments.isEmpty)
                Spacer()
                if !status.isEmpty {
                    Text(status).font(.system(size: 11)).foregroundStyle(Color.shoutLive)
                        .lineLimit(1).truncationMode(.middle)
                }
            }
            Text(Loc.t("Untertitel folgen immer dem ursprünglichen Transkript — Änderungen in diesem Fenster wirken sich nicht auf die Zeitmarken aus."))
                .font(.system(size: 11)).foregroundStyle(Color(white: 0.45))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 20).padding(.vertical, 14)
    }

    /// Nachgereichtes Protokoll. Steht über den Exportknöpfen, weil es den Inhalt
    /// des Fensters ändert und nicht nur, wohin er geht.
    @ViewBuilder
    private var minutesRow: some View {
        if case .formatting(let fraction) = job.state {
            HStack(spacing: 10) {
                ProgressView(value: fraction)
                    .progressViewStyle(.linear).tint(Color.shoutLive).frame(width: 160)
                Text(Loc.t("Protokoll wird erstellt …"))
                    .font(.system(size: 11)).foregroundStyle(Color(white: 0.62))
                Spacer()
            }
        } else if job.canAddMinutes {
            HStack(spacing: 10) {
                Button(Loc.t("Protokoll erstellen")) { queue.addMinutes(to: job) }
                    .buttonStyle(ConsoleButtonStyle())
                    .disabled(!formatterReady)
                Text(formatterReady
                     ? Loc.t("Zusammenfassung und Kernpunkte aus diesem Text — die Datei wird dafür nicht noch einmal transkribiert.")
                     : Loc.t("Dafür wird das Modell zum Aufbereiten gebraucht. Lade es unter „Modelle“ herunter."))
                    .font(.system(size: 11)).foregroundStyle(Color(white: 0.45))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: - Sichern

    private func saveText() {
        // Zusatz nur, wenn es zwei Fassungen gibt — sonst braucht der Name ihn nicht.
        let suffix = (hasBoth && active == .roh) ? (Loc.isGerman ? "-roh" : "-raw") : ""
        let name = TranscriptExport.fileName(for: job.url, suffix: suffix, extension: "txt")
        write(activeText.wrappedValue, suggesting: name, types: [.plainText])
    }

    private func saveSubtitles() {
        let name = TranscriptExport.fileName(for: job.url, suffix: "", extension: "srt")
        // Sprecher stehen im Untertitel vor dem Text — nur wenn die Trennung
        // tatsächlich etwas gefunden hat.
        let hasSpeakers = job.segments.contains { $0.speaker != nil }
        let label: ((Int) -> String)? = hasSpeakers
            ? { number in FileTranscriptionJob.speakerLabel(number) }
            : nil
        write(SubtitleWriter.srt(from: job.segments, speakerLabel: label),
              suggesting: name, types: [])
    }

    private func write(_ content: String, suggesting name: String, types: [UTType]) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = name
        panel.allowedContentTypes = types
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
            status = Loc.f("Gesichert: %@", url.lastPathComponent)
        } catch {
            status = Loc.f("Sichern fehlgeschlagen: %@", error.localizedDescription)
        }
    }
}
