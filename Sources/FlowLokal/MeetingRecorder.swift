import AVFoundation
import Foundation

/// Nimmt ein Meeting auf und schreibt es **direkt in eine Datei**.
///
/// Bewusst getrennt vom `AudioRecorder`: Der ist fürs Diktat gebaut — er sammelt
/// die Samples im Arbeitsspeicher und stoppt bei einer Sprechpause von selbst.
/// Beides ist hier falsch. Eine Stunde Meeting wären als Array rund 230 MB, und
/// eine Denkpause im Gespräch darf die Aufnahme nicht beenden.
///
/// Geschrieben wird AAC in 16 kHz Mono: rund 8 MB pro Stunde und genau das Format,
/// das die Transkription ohnehin braucht. Sobald die Datei liegt, geht sie als ganz
/// normaler Auftrag in die `FileTranscriptionQueue` — es gibt keinen zweiten
/// Verarbeitungsweg.
@MainActor
final class MeetingRecorder: ObservableObject {

    @Published private(set) var isRecording = false
    @Published private(set) var isPaused = false
    /// Aufgenommene Zeit in Sekunden, aus den geschriebenen Frames gerechnet und
    /// nicht aus der Uhr — so zählt eine Pause exakt nicht mit.
    @Published private(set) var duration: TimeInterval = 0
    /// Pegel 0…1 für die Anzeige.
    @Published private(set) var level: Float = 0

    private let engine = AVAudioEngine()
    private var file: AVAudioFile?
    private var url: URL?
    /// Eigene Warteschlange fürs Schreiben: Die Datei-Ausgabe gehört nicht auf den
    /// Audio-Thread, sonst gibt es bei langsamem Speicher Aussetzer in der Aufnahme.
    private let writeQueue = DispatchQueue(label: "shout.meeting.write", qos: .utility)
    private var framesWritten: AVAudioFramePosition = 0
    private var paused = false

    private static let sampleRate = 16_000.0

    /// Ordner für Mitschnitte. Sie bleiben liegen, auch nach der Verarbeitung:
    /// Eine Stunde Meeting kann man nicht noch einmal aufnehmen, wenn beim
    /// Transkribieren etwas schiefgeht.
    static func recordingsDirectory() -> URL {
        let dir = recordingsPath
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Nur der Pfad, ohne ihn anzulegen — fürs Nachschauen und Vergleichen. Sonst
    /// entstünde der Ordner auch am Mac, wo es gar keine Mitschnitte gibt.
    private static var recordingsPath: URL {
        StoreIO.directory().appendingPathComponent("Recordings", isDirectory: true)
    }

    /// Alle liegengebliebenen Mitschnitte, neueste zuerst. Grundlage dafür, dass ein
    /// Meeting nach dem Neustart der App noch da ist.
    static func existingRecordings() -> [URL] {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: recordingsPath,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles])) ?? []
        return files
            .filter { $0.pathExtension.lowercased() == "m4a" }
            .sorted { modified($0) > modified($1) }
    }

    private static func modified(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
            ?? .distantPast
    }

    /// Stammt die Datei aus unserem Mitschnitt-Ordner? Nur solche darf die App von
    /// sich aus löschen.
    static func isOwnRecording(_ url: URL) -> Bool {
        url.deletingLastPathComponent().standardizedFileURL
            == recordingsDirectory().standardizedFileURL
    }

    /// „Meeting 2026-08-11 17-42.m4a" — lesbar und ohne Zeichen, die Dateisysteme
    /// oder Freigabe-Dialoge stören (kein Doppelpunkt, kein Schrägstrich).
    static func fileName(for date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH-mm"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return "Meeting \(formatter.string(from: date)).m4a"
    }

    // MARK: - Steuerung

    @discardableResult
    func start() throws -> URL {
        guard !isRecording else { throw MeetingRecorderError.alreadyRunning }

        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        // Bewusst ohne .duckOthers: Bei einem Mitschnitt soll nichts anderes leiser
        // werden. .playAndRecord statt .record, damit die Klang-Signale hörbar bleiben.
        try session.setCategory(.playAndRecord, mode: .default,
                                options: [.defaultToSpeaker, .allowBluetooth])
        try session.setActive(true)
        #endif

        let target = Self.recordingsDirectory().appendingPathComponent(Self.fileName())
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: Self.sampleRate,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 32_000,
        ]
        let audioFile = try AVAudioFile(forWriting: target, settings: settings)

        let input = engine.inputNode
        let inputFormat = input.inputFormat(forBus: 0)
        // Das Zielformat kommt von der Datei selbst — so passt die Umrechnung
        // garantiert zu dem, was write(from:) erwartet.
        let writeFormat = audioFile.processingFormat
        guard let converter = AVAudioConverter(from: inputFormat, to: writeFormat) else {
            throw MeetingRecorderError.converterFailed
        }

        file = audioFile
        url = target
        framesWritten = 0
        paused = false
        duration = 0
        level = 0

        input.installTap(onBus: 0, bufferSize: 4_096, format: inputFormat) { [weak self] buffer, _ in
            self?.handle(buffer, converter: converter, format: writeFormat)
        }

        engine.prepare()
        try engine.start()

        isRecording = true
        isPaused = false
        observeInterruptions()
        return target
    }

    func pause() {
        guard isRecording, !isPaused else { return }
        paused = true
        isPaused = true
    }

    func resume() {
        guard isRecording, isPaused else { return }
        // Nach einer Unterbrechung kann die Session inaktiv sein.
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif
        if !engine.isRunning { try? engine.start() }
        paused = false
        isPaused = false
    }

    /// Beendet die Aufnahme und gibt die fertige Datei zurück.
    @discardableResult
    func stop() -> URL? {
        guard isRecording else { return nil }
        teardown()
        let finished = url
        // Erst hier freigeben: write(from:) läuft asynchron, die Datei muss bis zum
        // Ende der Warteschlange am Leben bleiben.
        writeQueue.sync { file = nil }
        url = nil
        return finished
    }

    /// Bricht ab und löscht die angefangene Datei.
    func cancel() {
        guard isRecording else { return }
        teardown()
        let started = url
        writeQueue.sync { file = nil }
        url = nil
        if let started { try? FileManager.default.removeItem(at: started) }
    }

    private func teardown() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRecording = false
        isPaused = false
        paused = false
        level = 0
        NotificationCenter.default.removeObserver(self)
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
    }

    // MARK: - Aufnahme

    /// Läuft auf dem Audio-Thread. Umgerechnet wird hier (der Puffer des Taps gilt
    /// nur für die Dauer des Aufrufs), geschrieben wird auf der eigenen Warteschlange.
    private nonisolated func handle(_ buffer: AVAudioPCMBuffer,
                                    converter: AVAudioConverter,
                                    format: AVAudioFormat) {
        let ratio = format.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1_024
        guard let converted = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return }

        var delivered = false
        var error: NSError?
        converter.convert(to: converted, error: &error) { _, status in
            if delivered {
                status.pointee = .noDataNow
                return nil
            }
            delivered = true
            status.pointee = .haveData
            return buffer
        }
        guard error == nil, converted.frameLength > 0 else { return }

        let peak = Self.peak(of: converted)

        Task { @MainActor [weak self] in
            guard let self, self.isRecording else { return }
            self.level = self.isPaused ? 0 : peak
            guard !self.paused else { return }
            self.write(converted)
        }
    }

    private func write(_ buffer: AVAudioPCMBuffer) {
        // Die Datei-Referenz HIER greifen, solange wir auf dem Main-Actor sind, und
        // in die Warteschlange mitgeben. Sie von dort aus zu lesen wäre ein Zugriff
        // über Actor-Grenzen hinweg.
        guard let audioFile = file else { return }
        let frames = buffer.frameLength
        writeQueue.async {
            do {
                try audioFile.write(from: buffer)
            } catch {
                NSLog("shout: Mitschnitt konnte nicht geschrieben werden: \(error)")
            }
        }
        framesWritten += AVAudioFramePosition(frames)
        duration = Double(framesWritten) / Self.sampleRate
    }

    /// `nonisolated`, weil der Aufruf vom Audio-Thread kommt — die Klasse selbst ist
    /// an den Main-Actor gebunden, diese reine Rechnung braucht ihn aber nicht.
    private nonisolated static func peak(of buffer: AVAudioPCMBuffer) -> Float {
        guard let channel = buffer.floatChannelData?[0] else { return 0 }
        var maximum: Float = 0
        for i in 0..<Int(buffer.frameLength) { maximum = max(maximum, abs(channel[i])) }
        // Leicht angehoben, damit normale Sprache die Anzeige gut ausfüllt.
        return min(1, maximum * 2.2)
    }

    // MARK: - Unterbrechungen

    /// Ein eingehender Anruf beendet die Aufnahme sonst still. Stattdessen pausieren
    /// und danach weitermachen — eine Stunde Meeting wegen eines Anrufs zu verlieren
    /// wäre das schlechteste denkbare Verhalten.
    private func observeInterruptions() {
        #if os(iOS)
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(), queue: .main
        ) { [weak self] note in
            guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
            Task { @MainActor in
                guard let self, self.isRecording else { return }
                switch type {
                case .began:
                    self.pause()
                case .ended:
                    let options = (note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt)
                        .map(AVAudioSession.InterruptionOptions.init(rawValue:)) ?? []
                    if options.contains(.shouldResume) { self.resume() }
                @unknown default:
                    break
                }
            }
        }
        #endif
    }
}

enum MeetingRecorderError: LocalizedError {
    case alreadyRunning
    case converterFailed

    var errorDescription: String? {
        switch self {
        case .alreadyRunning: return "Es läuft bereits eine Aufnahme."
        case .converterFailed: return "Die Audio-Umrechnung konnte nicht aufgesetzt werden."
        }
    }
}
