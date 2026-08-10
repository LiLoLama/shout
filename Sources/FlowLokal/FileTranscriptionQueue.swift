import Foundation
import Combine

/// Ein Transkriptions-Auftrag: eine Datei, ihr Zustand und ihr Ergebnis.
///
/// Ergebnisse leben nur zur Laufzeit. Gesichert wird ausschließlich, was der
/// Nutzer über den Sichern-Dialog selbst ablegt — und weder Verlauf noch
/// Statistiken werden angefasst: Die Statistik misst, wie schnell DU diktierst,
/// eine Stunde fremdes Audio würde diesen Wert bedeutungslos machen.
@MainActor
final class FileTranscriptionJob: ObservableObject, Identifiable {

    enum State: Equatable {
        case queued
        case transcribing(progress: Double)
        case formatting(progress: Double)
        case done
        case failed(String)
        case cancelled
    }

    let id = UUID()
    let url: URL

    @Published var state: State = .queued
    @Published var duration: Double = 0
    /// Rohsegmente mit Zeitmarken — Grundlage der .srt-Datei.
    @Published var segments: [TranscriptSegment] = []
    /// Rohtranskript (Segmente verbunden).
    @Published var rawText = ""
    /// Aufbereiteter Text; leer, wenn nicht aufbereitet wurde.
    @Published var formattedText = ""

    init(url: URL) { self.url = url }

    var name: String { url.lastPathComponent }

    /// Was angezeigt und als .txt gesichert wird.
    var displayText: String { formattedText.isEmpty ? rawText : formattedText }

    var wordCount: Int {
        displayText.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
    }

    var isFinished: Bool {
        switch state {
        case .done, .failed, .cancelled: return true
        case .queued, .transcribing, .formatting: return false
        }
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

    private var runTask: Task<Void, Never>?
    /// Aufträge, die der Nutzer abgebrochen hat. Wird zwischen den Blöcken geprüft.
    private var cancelled: Set<UUID> = []

    init(transcriber: Transcriber, formatter: Formatter, dictionary: PersonalDictionary) {
        self.transcriber = transcriber
        self.formatter = formatter
        self.dictionary = dictionary
    }

    /// Läuft gerade ein Auftrag? Blockiert unter anderem den Modellwechsel.
    var isRunning: Bool { runTask != nil }

    var hasUnfinishedJobs: Bool { jobs.contains { !$0.isFinished } }

    // MARK: - Steuerung

    func add(_ urls: [URL]) {
        for url in urls {
            let job = FileTranscriptionJob(url: url)
            jobs.append(job)
            if selectedJobID == nil { selectedJobID = job.id }
        }
        startIfNeeded()
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
        jobs.first { if case .queued = $0.state { return true } else { return false } }
    }

    private func process(_ job: FileTranscriptionJob) async {
        guard !cancelled.contains(job.id) else { job.markCancelled(); return }

        let useCommands = UserDefaults.standard.bool(forKey: "fileSpeechCommandsEnabled")
        let useFormatting = UserDefaults.standard.object(forKey: "fileFormattingEnabled") as? Bool ?? true
        let bias = dictionary.contents.terms

        job.state = .transcribing(progress: 0)

        let decoder = MediaDecoder(url: job.url)
        var collected: [TranscriptSegment] = []
        do {
            let duration = try await decoder.open()
            job.duration = duration

            while let block = try await decoder.next() {
                if cancelled.contains(job.id) { job.markCancelled(); return }

                let raw = try await transcriber.transcribeSegments(block.samples, biasTerms: bias)
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
                job.rawText = TranscriptLayout.rawText(from: collected)
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

        guard !job.rawText.isEmpty else {
            job.state = .done
            return
        }

        if useFormatting {
            job.state = .formatting(progress: 0)
            let hint = dictionary.termHint
            let jobRef = job
            let cleaned = await formatter.formatLong(job.rawText, termHint: hint) { fraction in
                Task { @MainActor in
                    if case .formatting = jobRef.state { jobRef.state = .formatting(progress: fraction) }
                }
            }
            if cancelled.contains(job.id) { job.markCancelled(); return }
            job.formattedText = cleaned
        }

        job.state = .done
        if selectedJobID == nil { selectedJobID = job.id }
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
