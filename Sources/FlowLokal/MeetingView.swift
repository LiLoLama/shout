import AppKit
import SwiftUI

/// „Meeting" — Besprechungen mitschneiden und daraus ein Transkript machen.
///
/// Eigene Seite statt eines Kastens auf „Dateien": Aufnehmen ist ein anderer
/// Vorgang als eine vorhandene Datei einzuwerfen. Hier entsteht das Material erst,
/// und während der Aufnahme will man eine ruhige Fläche sehen und keine
/// Ablagezone daneben.
///
/// Die Warteschlange ist dieselbe wie auf „Dateien" — es gibt nur einen
/// Verarbeitungsweg. Angezeigt werden hier ausschließlich die eigenen Mitschnitte,
/// drüben ausschließlich die eingeworfenen Dateien.
struct MeetingView: View {
    @ObservedObject var queue: FileTranscriptionQueue
    @ObservedObject var recorder: MeetingRecorder
    let modelReady: Bool
    let formatterReady: Bool
    let onOpenResult: (FileTranscriptionJob) -> Void
    let onCloseResult: (UUID) -> Void

    @AppStorage("meetingSource") private var source = MeetingSource.microphone.rawValue
    @AppStorage("meetingLegalHintShown") private var legalHintShown = false
    @State private var showLegalHint = false
    @State private var recorderError: String?
    @State private var finished: URL?
    @State private var naming = false
    @State private var name = ""
    @AppStorage("meetingDetect") private var detect = "ask"
    /// Programme, bei denen nie gefragt wird. Steht als Liste in den
    /// Voreinstellungen; „Nie bei Zoom" auf der Karte schreibt hierhin.
    @State private var muted: [String] = MeetingDetector.mutedPrefixes

    /// Nur eigene Mitschnitte — eingeworfene Dateien stehen auf „Dateien".
    private var recordings: [FileTranscriptionJob] {
        queue.jobs.filter { MeetingRecorder.isOwnRecording($0.url) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text(Loc.t("Meeting"))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color(white: 0.92))

                if modelReady {
                    stage
                    if !recorder.isRecording {
                        ProcessingOptionsPanel(formatterReady: formatterReady)
                        detectionPanel
                    }
                    if !recordings.isEmpty { recordingsPanel }
                } else {
                    ConsolePanel {
                        Text(Loc.t("Zum Transkribieren wird das Sprachmodell gebraucht. Lade es unter „Modelle“ herunter — danach geht es hier weiter."))
                            .font(.system(size: 13)).foregroundStyle(Color(white: 0.62))
                            .fixedSize(horizontal: false, vertical: true).padding(16)
                    }
                }

                Text(Loc.t("Der Mitschnitt bleibt auf diesem Rechner und wird hier transkribiert. Ein Gespräch ohne Einverständnis der anderen mitzuschneiden ist in Deutschland und Österreich strafbar."))
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
        .alert(Loc.t("Wie soll die Aufnahme heißen?"), isPresented: $naming) {
            TextField(Loc.t("Name"), text: $name)
            Button(Loc.t("Sichern")) { hand(over: true) }
            Button(Loc.t("Später"), role: .cancel) { hand(over: false) }
        } message: {
            Text(Loc.t("Du kannst sie auch später in der Liste umbenennen."))
        }
    }

    // MARK: - Bühne

    /// Die große Fläche oben: im Ruhezustand die Quellenwahl, während der Aufnahme
    /// Zeit und Pegel. Bewusst dieselbe Fläche, damit der Blick nicht springt.
    @ViewBuilder
    private var stage: some View {
        ConsolePanel {
            VStack(spacing: 0) {
                if recorder.isRecording { running } else { idle }
            }
        }
    }

    private var idle: some View {
        VStack(spacing: 18) {
            Image(systemName: "record.circle")
                .font(.system(size: 34)).foregroundStyle(Color.shoutLive)
            VStack(spacing: 6) {
                Text(Loc.t("Meeting aufnehmen"))
                    .font(.system(size: 15, weight: .semibold)).foregroundStyle(Color(white: 0.92))
                Text(recorderError ?? sourceHelp)
                    .font(.system(size: 12))
                    .foregroundStyle(recorderError == nil ? Color(white: 0.55)
                                                          : Color(red: 0.95, green: 0.7, blue: 0.2))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 420)
            }
            HStack(spacing: 10) {
                Picker("", selection: $source) {
                    Text(Loc.t("Mikrofon")).tag(MeetingSource.microphone.rawValue)
                    Text(Loc.t("Systemton")).tag(MeetingSource.systemAudio.rawValue)
                    Text(Loc.t("Beides")).tag(MeetingSource.both.rawValue)
                }
                .labelsHidden().pickerStyle(.menu).frame(width: 150)
                Button(Loc.t("Aufnehmen")) {
                    recorderError = nil
                    legalHintShown ? beginRecording() : (showLegalHint = true)
                }
                .buttonStyle(ConsoleButtonStyle())
            }
        }
        .frame(maxWidth: .infinity).padding(.vertical, 34).padding(.horizontal, 20)
    }

    private var running: some View {
        VStack(spacing: 16) {
            Text(Self.clock(recorder.duration))
                .font(.system(size: 46, weight: .light, design: .rounded)).monospacedDigit()
                .foregroundStyle(Color(white: recorder.isPaused ? 0.5 : 0.94))
                .contentTransition(.numericText())
            Text(recorder.isPaused ? Loc.t("Pausiert") : "\(Loc.t("Nimmt auf …"))  ·  \(sourceLabel)")
                .font(.system(size: 11)).foregroundStyle(Color(white: 0.55))

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.12))
                    Capsule().fill(Color.shoutLive)
                        .frame(width: geo.size.width * CGFloat(recorder.isPaused ? 0 : recorder.level))
                        .animation(.linear(duration: 0.1), value: recorder.level)
                }
            }
            .frame(height: 5).frame(maxWidth: 380)

            if recorder.noSignal {
                Text(Loc.t("Es kommt kein Ton an. Beim Systemton fehlt dann meist die Erlaubnis: Systemeinstellungen → Datenschutz & Sicherheit → Tonaufnahme."))
                    .font(.system(size: 11)).foregroundStyle(Color(red: 0.95, green: 0.7, blue: 0.2))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true).frame(maxWidth: 420)
            }

            HStack(spacing: 10) {
                Button(recorder.isPaused ? Loc.t("Fortsetzen") : Loc.t("Pause")) {
                    recorder.isPaused ? recorder.resume() : recorder.pause()
                }
                .buttonStyle(ConsoleButtonStyle())
                Button(Loc.t("Stoppen")) { stopRecording() }
                    .buttonStyle(ConsoleButtonStyle())
            }
            Text(Loc.t("Diktieren geht weiter — Mitschnitt und Diktat stören sich nicht."))
                .font(.system(size: 11)).foregroundStyle(Color(white: 0.4))
        }
        .frame(maxWidth: .infinity).padding(.vertical, 30).padding(.horizontal, 20)
    }

    /// „Meeting erkennen" — ob und wie von selbst gefragt wird.
    ///
    /// Voreinstellung ist „fragen": Eine Frage ist keine Aufnahme. „Von selbst
    /// aufnehmen" gibt es nur auf ausdrücklichen Wunsch, weil ein Mitschnitt ohne
    /// Einverständnis der anderen strafbar ist — das darf eine App nicht von sich
    /// aus tun.
    private var detectionPanel: some View {
        ConsolePanel(title: Loc.t("Meeting erkennen")) {
            VStack(spacing: 0) {
                FieldRow(title: Loc.t("Wenn ein Meeting läuft"),
                         help: Loc.t("Erkannt werden Zoom, Teams, Webex, Skype, FaceTime, Discord, Slack und Jitsi — daran, dass ihr Ton läuft. Dein Mikrofon spielt dabei keine Rolle, du kannst also stumm dabeisitzen.")) {
                    ConsoleSegmented(selection: $detect, options: [
                        ("off", Loc.t("Nichts tun")),
                        ("ask", Loc.t("Fragen")),
                        ("auto", Loc.t("Aufnehmen")),
                    ])
                }
                if !muted.isEmpty {
                    ConsoleDivider()
                    FieldRow(title: Loc.t("Nie fragen bei"), help: mutedNames) {
                        Button(Loc.t("Wieder fragen")) {
                            MeetingDetector.mutedPrefixes = []
                            muted = []
                            NotificationCenter.default.post(name: .shoutMeetingDetectChanged, object: nil)
                        }
                        .buttonStyle(ConsoleButtonStyle())
                    }
                }
            }
        }
        .onChange(of: detect) { _, _ in
            NotificationCenter.default.post(name: .shoutMeetingDetectChanged, object: nil)
        }
        .onAppear { muted = MeetingDetector.mutedPrefixes }
    }

    /// Aus den gemerkten Präfixen wieder lesbare Namen machen.
    private var mutedNames: String {
        let names = muted.compactMap { prefix in
            MeetingDetector.known.first { $0.prefix == prefix }?.name
        }
        return names.isEmpty ? muted.joined(separator: ", ") : names.joined(separator: ", ")
    }

    private var recordingsPanel: some View {
        ConsolePanel(title: Loc.t("Mitschnitte")) {
            VStack(spacing: 0) {
                ForEach(Array(recordings.enumerated()), id: \.element.id) { index, job in
                    JobRow(job: job,
                           selected: job.id == queue.selectedJobID,
                           onSelect: { queue.selectedJobID = job.id },
                           onOpen: { onOpenResult(job) },
                           onCancel: { queue.cancel(job) },
                           onRemove: { onCloseResult(job.id); queue.remove(job) },
                           onStart: { queue.start(job, options: .fromSettings()) })
                    if index < recordings.count - 1 { ConsoleDivider() }
                }
            }
        }
    }

    // MARK: - Texte und Steuerung

    private var sourceLabel: String {
        switch MeetingSource(rawValue: source) ?? .microphone {
        case .microphone: return Loc.t("Mikrofon")
        case .systemAudio: return Loc.t("Systemton")
        case .both: return Loc.t("Beides")
        }
    }

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
        queue.add([rename ? MeetingRecorder.rename(url, to: name) : url])
    }

    /// „1:02:44" bzw. „7:31" — ohne führende Stunde, solange keine gebraucht wird.
    private static func clock(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        return total >= 3600
            ? String(format: "%d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
            : String(format: "%d:%02d", total / 60, total % 60)
    }
}

/// Die Verarbeitungs-Schalter. Gelten für beide Wege — was hier steht, wird beim
/// **Hinzufügen** eines Auftrags gelesen, also gleich beim Stoppen der Aufnahme.
struct ProcessingOptionsPanel: View {
    let formatterReady: Bool

    @AppStorage("fileFormattingEnabled") private var formattingEnabled = true
    @AppStorage("fileSpeechCommandsEnabled") private var speechCommands = false
    /// Standard AUS: Sie kostet einen Modell-Download, Speicher und Zeit — das soll
    /// niemand ungefragt bezahlen, der nur ein Transkript will.
    @AppStorage("fileDiarizationEnabled") private var diarization = false

    var body: some View {
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
}
