import AVFoundation
import Foundation

/// Woher der Ton kommt. Am iPhone gibt es nur das Mikrofon — iOS lässt Apps nicht
/// an den Ton anderer Apps.
enum MeetingSource: String, CaseIterable, Sendable {
    case microphone
    case systemAudio
    case both
}

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
    /// Läuft der Mitschnitt, ohne dass je ein Ton ankam? Bei Systemton heißt das
    /// fast immer: Die Erlaubnis zur Tonaufnahme fehlt. macOS meldet das nicht —
    /// der Tap liefert einfach Nullen, und ohne diesen Hinweis stünde man nach
    /// einer Stunde vor einer stummen Datei.
    @Published private(set) var noSignal = false
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
    /// Wurde seit dem Start überhaupt ein Ausschlag gemessen?
    private var sawSignal = false

    #if os(macOS)
    private var tap: Any?
    /// Wandelt die Mono-Samples des Taps ins Dateiformat.
    private var tapConverter: AVAudioConverter?
    private var tapFormat: AVAudioFormat?
    #endif

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

    // MARK: - Umbenennen

    /// Benennt einen Mitschnitt um und nimmt das gesicherte Transkript mit.
    /// Gibt die neue Adresse zurück — oder die alte, wenn nichts zu tun war oder
    /// das Umbenennen scheiterte. Der Aufrufer arbeitet also immer mit einer
    /// gültigen Datei weiter.
    @discardableResult
    static func rename(_ url: URL, to raw: String) -> URL {
        guard isOwnRecording(url), let name = safeName(raw) else { return url }
        let directory = url.deletingLastPathComponent()
        let ext = url.pathExtension
        // Unveränderter Name ZUERST, vor der Suche nach einem freien Platz: Sonst
        // schöbe die Suche an der Datei selbst vorbei und machte aus „Kickoff"
        // beim zweiten Bestätigen „Kickoff 2".
        guard directory.appendingPathComponent(name).appendingPathExtension(ext) != url else {
            return url
        }
        let target = freeTarget(in: directory, name: name, extension: ext)

        do {
            try FileManager.default.moveItem(at: url, to: target)
        } catch {
            NSLog("shout: Mitschnitt konnte nicht umbenannt werden: \(error)")
            return url
        }
        // Erst nach der Audiodatei: Bleibt die Ablage liegen, wäre das Transkript
        // verwaist — andersherum stünde es neben einer Datei, die es nicht gibt.
        try? FileManager.default.moveItem(at: TranscriptStore.sidecar(for: url),
                                          to: TranscriptStore.sidecar(for: target))
        return target
    }

    /// Freier Platz für den Namen: „Kickoff", sonst „Kickoff 2", „Kickoff 3" …
    /// Zwei Meetings am selben Tag dürfen sich nicht gegenseitig überschreiben.
    static func freeTarget(in directory: URL, name: String, extension ext: String) -> URL {
        let candidate = { (base: String) in
            directory.appendingPathComponent(base).appendingPathExtension(ext)
        }
        var target = candidate(name)
        var suffix = 2
        while FileManager.default.fileExists(atPath: target.path) {
            target = candidate("\(name) \(suffix)")
            suffix += 1
        }
        return target
    }

    /// Macht aus einer Eingabe einen brauchbaren Dateinamen: keine Schrägstriche
    /// und Doppelpunkte (die zerlegen Pfade), kein führender Punkt (das wäre eine
    /// versteckte Datei) und nicht endlos lang.
    static func safeName(_ raw: String) -> String? {
        var name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        for zeichen in ["/", ":", "\\"] {
            name = name.replacingOccurrences(of: zeichen, with: "-")
        }
        while name.hasPrefix(".") { name.removeFirst() }
        name = String(name.prefix(80)).trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? nil : name
    }

    // MARK: - Steuerung

    @discardableResult
    func start(source: MeetingSource = .microphone) throws -> URL {
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
        // Das Zielformat kommt von der Datei selbst — so passt die Umrechnung
        // garantiert zu dem, was write(from:) erwartet.
        let writeFormat = audioFile.processingFormat

        file = audioFile
        url = target
        framesWritten = 0
        paused = false
        duration = 0
        level = 0
        sawSignal = false
        noSignal = false

        do {
            switch source {
            case .microphone:
                try startMicrophone(writeFormat: writeFormat)
            case .systemAudio, .both:
                try startSystemAudio(includeMicrophone: source == .both, writeFormat: writeFormat)
            }
        } catch {
            // Angefangene Datei nicht liegen lassen, sonst taucht ein leerer
            // Mitschnitt in der Liste auf.
            file = nil
            url = nil
            try? FileManager.default.removeItem(at: target)
            throw error
        }

        isRecording = true
        isPaused = false
        observeInterruptions()
        watchForSilence()
        return target
    }

    private func startMicrophone(writeFormat: AVAudioFormat) throws {
        let input = engine.inputNode
        let inputFormat = input.inputFormat(forBus: 0)
        guard let converter = AVAudioConverter(from: inputFormat, to: writeFormat) else {
            throw MeetingRecorderError.converterFailed
        }
        input.installTap(onBus: 0, bufferSize: 4_096, format: inputFormat) { [weak self] buffer, _ in
            self?.handle(buffer, converter: converter, format: writeFormat)
        }
        engine.prepare()
        try engine.start()
    }

    #if os(macOS)
    private func startSystemAudio(includeMicrophone: Bool, writeFormat: AVAudioFormat) throws {
        guard #available(macOS 14.2, *) else { throw MeetingRecorderError.systemAudioUnsupported }
        let capture = SystemAudioTap()
        try capture.start(includeMicrophone: includeMicrophone) { [weak self] samples in
            self?.handleTap(samples)
        }
        // Format erst NACH dem Start: Die Rate richtet sich nach dem Ausgabegerät.
        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                         sampleRate: capture.sampleRate,
                                         channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: format, to: writeFormat) else {
            capture.stop()
            throw MeetingRecorderError.converterFailed
        }
        tapFormat = format
        tapConverter = converter
        tap = capture
    }
    #else
    private func startSystemAudio(includeMicrophone: Bool, writeFormat: AVAudioFormat) throws {
        // iOS lässt Apps nicht an den Ton anderer Apps — es gibt keine API dafür.
        throw MeetingRecorderError.systemAudioUnsupported
    }
    #endif

    /// Meldet nach ein paar Sekunden, wenn nie ein Ausschlag kam. Bei Systemton
    /// fehlt dann fast immer die Erlaubnis zur Tonaufnahme — macOS sagt das nicht,
    /// der Tap liefert einfach Nullen.
    private func watchForSilence() {
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            guard let self, self.isRecording, !self.sawSignal else { return }
            self.noSignal = true
        }
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
        #if os(macOS)
        if #available(macOS 14.2, *) { (tap as? SystemAudioTap)?.stop() }
        tap = nil
        tapConverter = nil
        tapFormat = nil
        #endif
        noSignal = false
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
            if peak > 0.0001 { self.sawSignal = true; self.noSignal = false }
            guard !self.paused else { return }
            self.write(converted)
        }
    }

    #if os(macOS)
    /// Mono-Samples aus dem Systemton-Tap: in einen Puffer packen, umrechnen,
    /// schreiben. Läuft auf dem Audio-Thread des Aggregats.
    private nonisolated func handleTap(_ samples: [Float]) {
        Task { @MainActor [weak self] in
            guard let self, self.isRecording,
                  let format = self.tapFormat, let converter = self.tapConverter,
                  let source = AVAudioPCMBuffer(pcmFormat: format,
                                                frameCapacity: AVAudioFrameCount(samples.count)),
                  let channel = source.floatChannelData?[0] else { return }
            samples.withUnsafeBufferPointer { channel.update(from: $0.baseAddress!, count: samples.count) }
            source.frameLength = AVAudioFrameCount(samples.count)

            let peak = Self.peak(of: source)
            self.level = self.isPaused ? 0 : peak
            if peak > 0.0001 { self.sawSignal = true; self.noSignal = false }
            guard !self.paused else { return }

            let ratio = converter.outputFormat.sampleRate / format.sampleRate
            let capacity = AVAudioFrameCount(Double(samples.count) * ratio) + 1_024
            guard let converted = AVAudioPCMBuffer(pcmFormat: converter.outputFormat,
                                                   frameCapacity: capacity) else { return }
            var delivered = false
            var error: NSError?
            converter.convert(to: converted, error: &error) { _, status in
                if delivered { status.pointee = .noDataNow; return nil }
                delivered = true
                status.pointee = .haveData
                return source
            }
            guard error == nil, converted.frameLength > 0 else { return }
            self.write(converted)
        }
    }
    #endif

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
    case systemAudioUnsupported
    case systemAudioFailed(String)

    var errorDescription: String? {
        switch self {
        case .alreadyRunning: return "Es läuft bereits eine Aufnahme."
        case .converterFailed: return "Die Audio-Umrechnung konnte nicht aufgesetzt werden."
        case .systemAudioUnsupported:
            return "Den Systemton mitzuschneiden braucht macOS 14.2 oder neuer."
        case .systemAudioFailed(let detail):
            return "Der Systemton konnte nicht abgegriffen werden: \(detail)"
        }
    }
}
