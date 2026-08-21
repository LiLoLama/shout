import Foundation
import AVFoundation
import Combine
#if os(iOS)
import UIKit
#endif

/// Was mit einer Datei geschehen soll.
///
/// Hängt am einzelnen Auftrag statt an den Einstellungen, weil die Entscheidung
/// nicht immer vorher fällt: Am iPhone steht nach einem Meeting erst einmal nur
/// die Aufnahme da, und ob daraus ein Protokoll wird — oder ob die Datei lieber
/// an den Rechner geht — entscheidet sich danach.
struct FileJobOptions: Equatable {
    var minutes: Bool
    var speakers: Bool
    var commands: Bool

    /// Am Mac stehen die Schalter direkt über der Dateiauswahl; dort gilt weiter,
    /// was dort eingestellt ist.
    static func fromSettings() -> FileJobOptions {
        let d = UserDefaults.standard
        return FileJobOptions(
            minutes: d.object(forKey: "fileFormattingEnabled") as? Bool ?? true,
            speakers: d.bool(forKey: "fileDiarizationEnabled"),
            commands: d.bool(forKey: "fileSpeechCommandsEnabled"))
    }
}

/// Ein Transkriptions-Auftrag: eine Datei, ihr Zustand und ihr Ergebnis.
///
/// Ergebnisse leben nur zur Laufzeit. Gesichert wird ausschließlich, was der
/// Nutzer über den Sichern-Dialog selbst ablegt — und weder Verlauf noch
/// Statistiken werden angefasst: Die Statistik misst, wie schnell DU diktierst,
/// eine Stunde fremdes Audio würde diesen Wert bedeutungslos machen.
@MainActor
final class FileTranscriptionJob: ObservableObject, Identifiable {

    enum State: Equatable {
        /// Liegt bereit, aber niemand hat gesagt, was damit passieren soll. Nur der
        /// Mitschnitt am iPhone landet hier: Nach einer Stunde Meeting ist das
        /// Telefon der schlechteste Ort, um ungefragt loszurechnen.
        case unprocessed
        case queued
        case transcribing(progress: Double)
        /// Sprechertrennung. Ohne Fortschritt, weil SpeakerKit die ganze Datei in
        /// einem Rutsch verarbeitet und dabei nichts Zwischendrin meldet.
        case separatingSpeakers
        case formatting(progress: Double)
        case done
        case failed(String)
        case cancelled
    }

    let id = UUID()
    /// Änderbar, weil ein Mitschnitt umbenannt werden kann; die Identität des
    /// Auftrags hängt an der `id`, nicht am Dateinamen.
    @Published fileprivate(set) var url: URL

    /// Wird beim Anlegen aus den Einstellungen gefüllt und vor dem Start noch
    /// einmal überschrieben, wenn der Nutzer selbst entscheidet.
    var options = FileJobOptions.fromSettings()

    /// Nachgereichtes Protokoll: Der Text steht schon, es fehlt nur die Aufbereitung.
    /// Die Datei wird dafür NICHT noch einmal transkribiert.
    fileprivate(set) var minutesOnly = false

    @Published var state: State = .queued
    @Published var duration: Double = 0
    /// Rohsegmente mit Zeitmarken — Grundlage der .srt-Datei.
    @Published var segments: [TranscriptSegment] = []
    /// Rohtranskript (Segmente verbunden).
    @Published var rawText = ""
    /// Aufbereiteter Text; leer, wenn nicht aufbereitet wurde.
    @Published var formattedText = ""
    /// Hinweis, wenn die Sprechertrennung nicht geklappt hat — der Text ist dann
    /// trotzdem vollständig, nur ohne Namen davor.
    @Published var speakerNote: String?

    init(url: URL) { self.url = url }

    var name: String { url.lastPathComponent }

    /// Was angezeigt und als .txt gesichert wird.
    var displayText: String { formattedText.isEmpty ? rawText : formattedText }

    var wordCount: Int {
        displayText.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
    }

    /// Ist gerade nichts zu tun? „Noch nicht verarbeitet" gehört dazu — der Auftrag
    /// wartet auf eine Entscheidung, nicht auf Rechenzeit, und darf das Beenden der
    /// App nicht blockieren.
    var isFinished: Bool {
        switch state {
        case .unprocessed, .done, .failed, .cancelled: return true
        case .queued, .transcribing, .separatingSpeakers, .formatting: return false
        }
    }

    /// Anrede für eine Sprechernummer — an einer Stelle, damit Text, Untertitel und
    /// der Eingang fürs Sprachmodell dieselbe verwenden.
    static func speakerLabel(_ number: Int) -> String {
        Loc.f("Sprecher %d", number)
    }

    /// Kann noch ein Protokoll nachgereicht werden? Nur wenn der Text fertig ist
    /// und keins existiert.
    var canAddMinutes: Bool {
        if case .done = state { return formattedText.isEmpty && !rawText.isEmpty }
        return false
    }

    /// Eingang fürs Sprachmodell: **ohne** Zeitmarken — die kosten dort nur Kontext
    /// und tauchten sonst mitten im Protokoll wieder auf — und **mit** Sprechern,
    /// sofern welche erkannt wurden. Das entscheiden die Segmente selbst und nicht
    /// die Einstellungen: Bei einem später nachgereichten Protokoll sagen die
    /// Einstellungen nichts mehr darüber aus, was damals tatsächlich lief.
    var minutesInput: String {
        guard !segments.isEmpty else { return rawText }
        let label: ((Int) -> String)? = segments.contains { $0.speaker != nil }
            ? { number in FileTranscriptionJob.speakerLabel(number) }
            : nil
        return TranscriptLayout.rawText(from: segments, timestamps: false, speakerLabel: label)
    }

    /// Zustand zum Sichern.
    var snapshot: StoredTranscript {
        StoredTranscript(rawText: rawText, formattedText: formattedText,
                         segments: segments, duration: duration, speakerNote: speakerNote)
    }

    /// Übernimmt ein gesichertes Ergebnis. Der Auftrag ist damit fertig — er wurde
    /// ja schon einmal gerechnet.
    func apply(_ stored: StoredTranscript) {
        rawText = stored.rawText
        formattedText = stored.formattedText
        segments = stored.segments
        duration = stored.duration
        speakerNote = stored.speakerNote
        state = .done
    }

    /// Bricht den Auftrag ab und verwirft das Teilergebnis. Ein halbes Transkript
    /// anzuzeigen wäre eine Falle: Es sieht aus wie ein fertiges und ließe sich
    /// genauso sichern.
    func markCancelled() {
        segments = []
        rawText = ""
        formattedText = ""
        state = .cancelled
    }
}

/// Arbeitet Datei-Aufträge nacheinander ab.
///
/// Seriell und nicht parallel, weil ohnehin nur ein Whisper-Modell im Speicher
/// liegt: Zwei Aufträge gleichzeitig würden sich am `Transcriber`-actor
/// gegenseitig blockieren und nur die Fortschrittsanzeige unehrlich machen.
@MainActor
final class FileTranscriptionQueue: ObservableObject {

    @Published private(set) var jobs: [FileTranscriptionJob] = []
    @Published var selectedJobID: UUID?

    private let transcriber: Transcriber
    private let formatter: Formatter
    private let dictionary: PersonalDictionary
    private let separator = SpeakerSeparator()

    private var runTask: Task<Void, Never>?
    /// Hat iOS zwischenzeitlich Speicherdruck gemeldet? Dann wird die Sprechertrennung
    /// übersprungen — sie ist der mit Abstand speicherhungrigste Schritt, und ein
    /// fertiges Transkript ohne Namen ist unendlich viel besser als eine App, die das
    /// System nach einer Stunde Meeting abschießt.
    private var memoryPressure = false
    /// Aufträge, die der Nutzer abgebrochen hat. Wird zwischen den Blöcken geprüft.
    private var cancelled: Set<UUID> = []

    init(transcriber: Transcriber, formatter: Formatter, dictionary: PersonalDictionary) {
        self.transcriber = transcriber
        self.formatter = formatter
        self.dictionary = dictionary

        #if os(iOS)
        NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.memoryPressure = true }
        }
        #endif
    }

    /// Läuft gerade ein Auftrag? Blockiert unter anderem den Modellwechsel.
    var isRunning: Bool { runTask != nil }

    var hasUnfinishedJobs: Bool { jobs.contains { !$0.isFinished } }

    // MARK: - Steuerung

    /// Nimmt Dateien auf. `start: false` legt sie nur ab — dann entscheidet der
    /// Nutzer später, was damit geschehen soll (iPhone).
    func add(_ urls: [URL], start: Bool = true) {
        for url in urls {
            let job = FileTranscriptionJob(url: url)
            if !start {
                // Schon einmal verarbeitet? Dann steht das Ergebnis daneben.
                if let stored = TranscriptStore.load(for: url) {
                    job.apply(stored)
                } else {
                    job.state = .unprocessed
                    probeDuration(job)
                }
            }
            jobs.append(job)
            if start, selectedJobID == nil { selectedJobID = job.id }
        }
        if start { startIfNeeded() }
    }

    /// Holt liegengebliebene Mitschnitte zurück in die Liste. Ergebnisse leben nur
    /// zur Laufzeit, die Aufnahmen selbst aber nicht: Wer ein Meeting aufnimmt und
    /// die App schließt, muss die Datei danach wiederfinden.
    func restore(_ urls: [URL]) {
        let known = Set(jobs.map(\.url))
        let fresh = urls.filter { !known.contains($0) }
        guard !fresh.isEmpty else { return }
        add(fresh, start: false)
    }

    /// Benennt einen Mitschnitt um. Nur solange nichts läuft: Der Decoder liest die
    /// Datei gerade, und ein wandernder Name wäre unnötiges Risiko für nichts.
    func rename(_ job: FileTranscriptionJob, to name: String) {
        guard job.isFinished else { return }
        job.url = MeetingRecorder.rename(job.url, to: name)
    }

    /// Reicht das Protokoll nach — aus dem vorhandenen Text, ohne die Datei noch
    /// einmal zu transkribieren. Wer sich für „nur transkribieren" entschieden hat,
    /// müsste sonst eine Stunde neu rechnen lassen, obwohl der Text längst dasteht.
    func addMinutes(to job: FileTranscriptionJob) {
        guard job.canAddMinutes else { return }
        job.options.minutes = true
        job.minutesOnly = true
        // Direkt auf „wird erstellt" statt über „wartet": Die Zeile bleibt so
        // durchgehend navigierbar und die geöffnete Ansicht klappt nicht zu.
        job.state = .formatting(progress: 0)
        startIfNeeded()
    }

    /// Startet einen wartenden Auftrag mit den gewählten Einstellungen.
    func start(_ job: FileTranscriptionJob, options: FileJobOptions) {
        guard case .unprocessed = job.state else { return }
        job.options = options
        job.state = .queued
        startIfNeeded()
    }

    /// Länge einer noch nicht verarbeiteten Datei. Sie ist die entscheidende Angabe,
    /// wenn jemand abwägt, ob er das auf dem Telefon rechnen lässt — der Decoder
    /// liefert sie sonst erst, wenn die Verarbeitung längst läuft.
    private func probeDuration(_ job: FileTranscriptionJob) {
        let url = job.url
        Task { [weak job] in
            let seconds = try? await AVURLAsset(url: url).load(.duration).seconds
            guard let seconds, seconds.isFinite, seconds > 0 else { return }
            job?.duration = seconds
        }
    }

    func cancel(_ job: FileTranscriptionJob) {
        cancelled.insert(job.id)
        // Wartende Aufträge sofort abräumen; der laufende merkt es beim nächsten Block.
        if case .queued = job.state { job.markCancelled() }
    }

    func cancelAll() {
        for job in jobs where !job.isFinished { cancel(job) }
    }

    func remove(_ job: FileTranscriptionJob) {
        cancel(job)
        jobs.removeAll { $0.id == job.id }
        // Nachrücken auf einen Auftrag MIT Ergebnis — sonst zeigt die Seite nach dem
        // Entfernen auf einen abgebrochenen und der Ergebnisbereich verschwindet.
        if selectedJobID == job.id { selectedJobID = jobs.first { $0.state == .done }?.id }
        // Eigene Mitschnitte mitlöschen: Sie liegen in unserem Ordner, tauchen nach
        // einem Neustart wieder in der Liste auf und sammelten sich sonst
        // unsichtbar an. Ausgewählte Dateien gehören dem Nutzer — Finger weg.
        if MeetingRecorder.isOwnRecording(job.url) {
            TranscriptStore.remove(for: job.url)
            try? FileManager.default.removeItem(at: job.url)
        }
    }

    // MARK: - Abarbeitung

    private func startIfNeeded() {
        guard runTask == nil else { return }
        runTask = Task { [weak self] in
            while let job = self?.nextJob() {
                await self?.process(job)
            }
            self?.runTask = nil
        }
    }

    private func nextJob() -> FileTranscriptionJob? {
        jobs.first { job in
            if case .queued = job.state { return true }
            // Nachgereichtes Protokoll steht schon auf „wird erstellt"; die Marke
            // fällt beim Abarbeiten, deshalb wird derselbe Auftrag nicht zweimal
            // gezogen.
            return job.minutesOnly
        }
    }

    private func process(_ job: FileTranscriptionJob) async {
        if job.minutesOnly { await addMinutesOnly(to: job); return }
        guard !cancelled.contains(job.id) else { job.markCancelled(); return }

        let useCommands = job.options.commands
        let useMinutes = job.options.minutes
        let useSpeakers = job.options.speakers

        job.state = .transcribing(progress: 0)

        // Dateien aus der Dateien-App kommen als „security-scoped" URL: ohne diesen
        // Zugriff schlägt das Öffnen auf dem iPhone fehl. Am Mac ist der Aufruf
        // folgenlos (liefert false, und dann wird auch nichts freigegeben).
        let scoped = job.url.startAccessingSecurityScopedResource()
        defer { if scoped { job.url.stopAccessingSecurityScopedResource() } }

        let decoder = MediaDecoder(url: job.url)
        var collected: [TranscriptSegment] = []
        // Nur wenn die Sprechertrennung an ist: Die braucht die GANZE Datei am Stück
        // (siehe SpeakerSeparator) — eine Stunde sind rund 230 MB. Ist sie aus,
        // bleibt der Speicherbedarf bei einem Block.
        var allSamples: [Float] = []
        do {
            let duration = try await decoder.open()
            job.duration = duration

            while let block = try await decoder.next() {
                if cancelled.contains(job.id) { job.markCancelled(); return }
                if useSpeakers { allSamples.append(contentsOf: block.samples) }

                let raw = try await transcriber.transcribeSegments(block.samples)
                for segment in raw {
                    var text = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !text.isEmpty else { continue }
                    // Sprachbefehle und Korrekturen PRO SEGMENT — sonst passt der Text
                    // der .srt nicht mehr zu dem, was im Fenster steht.
                    if useCommands { text = SpeechCommands.apply(to: text) }
                    text = dictionary.applyCorrections(to: text)
                    guard !text.isEmpty else { continue }
                    collected.append(TranscriptSegment(text: text,
                                                       start: segment.start + block.startTime,
                                                       end: segment.end + block.startTime))
                }

                job.segments = collected
                job.rawText = TranscriptLayout.rawText(from: collected, timestamps: true)
                let processed = block.startTime + Double(block.samples.count) / MediaDecoder.sampleRate
                job.state = .transcribing(progress: duration > 0 ? min(1, processed / duration) : 0)
            }
        } catch let error as MediaDecoderError {
            job.state = .failed(Self.message(for: error))
            return
        } catch {
            job.state = .failed(error.localizedDescription)
            return
        }

        if cancelled.contains(job.id) { job.markCancelled(); return }

        guard !collected.isEmpty else {
            finish(job)
            return
        }

        // Sprechertrennung, bevor die Texte endgültig gebaut werden — sie ändert die
        // Segmente, und daraus entstehen Rohtext, Untertitel und der Eingang fürs
        // Sprachmodell.
        if useSpeakers, !allSamples.isEmpty, !memoryPressure {
            job.state = .separatingSpeakers
            do {
                let ranges = try await separator.ranges(for: allSamples)
                collected = SpeakerAssignment.assign(ranges, to: collected)
                job.segments = collected
                job.rawText = TranscriptLayout.rawText(
                    from: collected, timestamps: true,
                    speakerLabel: FileTranscriptionJob.speakerLabel)
            } catch {
                // Ohne Sprecher weiterzumachen ist besser, als den fertigen Text
                // wegen der Kür zu verwerfen.
                NSLog("shout: Sprechertrennung fehlgeschlagen: \(error)")
                job.speakerNote = Loc.t("Die Sprecher konnten nicht getrennt werden — der Text ist trotzdem vollständig.")
            }
            allSamples = []   // Speicher sofort freigeben, nicht erst am Ende
            await separator.unload()
        } else if useSpeakers, memoryPressure {
            job.speakerNote = Loc.t("Zu wenig Speicher für die Sprechertrennung — der Text ist trotzdem vollständig.")
        }

        if cancelled.contains(job.id) { job.markCancelled(); return }

        guard !job.rawText.isEmpty else {
            finish(job)
            return
        }

        if useMinutes {
            await writeMinutes(for: job)
            if cancelled.contains(job.id) { job.markCancelled(); return }
        }

        finish(job)
        if selectedJobID == nil { selectedJobID = job.id }
    }

    /// Der nachgereichte Weg: nur die Aufbereitung, der Text steht ja schon.
    private func addMinutesOnly(to job: FileTranscriptionJob) async {
        job.minutesOnly = false
        await writeMinutes(for: job)
        // Ein Abbruch verwirft hier NICHTS: Anders als beim ersten Durchlauf ist
        // das Transkript fertig und bleibt es auch — es fehlt dann nur das
        // Protokoll. Die Marke muss trotzdem weg, sonst liefe ein zweiter Anlauf
        // sofort ins Leere.
        cancelled.remove(job.id)
        finish(job)
    }

    /// Erstellt das Protokoll aus dem vorhandenen Text und trägt es ein.
    private func writeMinutes(for job: FileTranscriptionJob) async {
        job.state = .formatting(progress: 0)
        let hint = dictionary.termHint
        let jobRef = job
        let document = await formatter.minutes(from: job.minutesInput, termHint: hint) { fraction in
            Task { @MainActor in
                if case .formatting = jobRef.state { jobRef.state = .formatting(progress: fraction) }
            }
        }
        guard !cancelled.contains(job.id) else { return }
        // Nur setzen, wenn wirklich ein Protokoll herauskam. Sonst stünden im
        // Fenster zwei identische Fassungen — genau der Eindruck, der beim
        // ersten Anlauf entstanden ist.
        if let document { job.formattedText = document }
    }

    /// Auftrag fertig — und bei einem eigenen Mitschnitt das Ergebnis daneben legen.
    /// Ohne das wäre nach einem Neustart der App die Aufnahme zwar noch da, die
    /// gerechnete Stunde aber weg.
    private func finish(_ job: FileTranscriptionJob) {
        job.state = .done
        guard MeetingRecorder.isOwnRecording(job.url) else { return }
        TranscriptStore.save(job.snapshot, for: job.url)
    }

    /// Übersetzt die Decoder-Fehler. Hier statt im `MediaDecoder`, weil `Loc` an den
    /// Main-Actor gebunden ist und der Decoder auf seinem eigenen läuft.
    private static func message(for error: MediaDecoderError) -> String {
        switch error {
        case .noAudioTrack:
            return Loc.t("Diese Datei enthält keine Tonspur.")
        case .unreadable(let detail):
            return Loc.f("Diese Datei kann nicht gelesen werden (%@).", detail)
        }
    }
}
