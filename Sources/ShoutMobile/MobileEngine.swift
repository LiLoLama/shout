import SwiftUI
import AVFoundation
import UIKit

extension Notification.Name {
    /// Vom App Intent (Action Button / Kurzbefehl) gefeuert: Aufnahme starten.
    static let shoutStartDictation = Notification.Name("shout.startDictation")
}

/// Zustandsmaschine der iOS-App: Aufnahme → WhisperKit → Sprachbefehle →
/// optionales lokales LLM → Korrekturen → Ergebnis in die Zwischenablage.
/// Mobile Besonderheit: Kein Einfügen in fremde Apps (iOS erlaubt das nicht) —
/// das Ergebnis wird automatisch kopiert und in der App angezeigt/geteilt.
@MainActor
final class MobileEngine: ObservableObject {

    enum State: Equatable {
        case loadingModel
        case idle
        case recording
        case working
        case failed(String)
    }

    @Published private(set) var state: State = .loadingModel
    @Published private(set) var level: Float = 0
    @Published private(set) var lastResult: String?
    @Published var asrProgress: Double?
    @Published var formatProgress: Double?
    @Published private(set) var asrLoadingID: String?     // gerade ladendes ASR-Modell
    @Published private(set) var formatLoadingID: String?  // gerade ladendes LLM
    @Published private(set) var transcriberReady = false
    @Published var modelNote: String?

    var activeASR: String { UserDefaults.standard.string(forKey: "asrModel") ?? ModelCatalog.defaultASR }
    var activeFormat: String { UserDefaults.standard.string(forKey: "formatModel") ?? ModelCatalog.defaultFormatting }

    let dictionary = PersonalDictionary()
    let history = DictationHistory()
    let stats = StatsStore()

    private let recorder = AudioRecorder()
    private let transcriber = Transcriber()
    private let formatter = Formatter()
    private let sounds = SoundCues()

    // iOS-Default: Formatierung AUS — spart den zweiten Modell-Download und
    // Speicher; wer sie will, schaltet sie in den Einstellungen ein.
    var formattingEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "formattingEnabled") as? Bool ?? false }
        set {
            UserDefaults.standard.set(newValue, forKey: "formattingEnabled")
            if newValue { loadFormatterIfNeeded() }
        }
    }

    init() {
        // Erststart: die für DIESES Gerät empfohlenen Modelle als Auswahl setzen
        // (statt des kleinsten Fallbacks) — geladen wird die Empfehlung.
        let d = UserDefaults.standard
        if d.string(forKey: "asrModel") == nil {
            d.set(ModelCatalog.recommendedASR(ramGB: Hardware.physicalMemoryGB).id, forKey: "asrModel")
        }
        if d.string(forKey: "formatModel") == nil {
            d.set(ModelCatalog.recommendedFormatting(ramGB: Hardware.physicalMemoryGB).id, forKey: "formatModel")
        }

        recorder.onLevel = { [weak self] level in
            Task { @MainActor in
                guard let self else { return }
                self.level = self.level * 0.5 + level * 0.5
            }
        }
        recorder.onSilence = { [weak self] in
            guard let self, self.state == .recording else { return }
            self.stopAndProcess()
        }
        NotificationCenter.default.addObserver(forName: .shoutStartDictation, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.state == .idle else { return }
                self.startRecording()
            }
        }
        loadModels()
    }

    // MARK: - Modelle

    func loadModels() {
        state = .loadingModel
        asrProgress = 0
        asrLoadingID = activeASR
        Task {
            do {
                try await transcriber.load { [weak self] frac in
                    Task { @MainActor in self?.asrProgress = frac }
                }
                transcriberReady = true
                state = .idle
            } catch {
                NSLog("shout: Modell-Ladefehler: \(error)")
                state = .failed("Sprachmodell konnte nicht geladen werden. Internet prüfen und erneut versuchen.")
            }
            asrProgress = nil
            asrLoadingID = nil
            if formattingEnabled { loadFormatterIfNeeded() }
        }
    }

    private func loadFormatterIfNeeded() {
        Task {
            formatProgress = 0
            formatLoadingID = activeFormat
            await formatter.load { [weak self] frac in
                Task { @MainActor in self?.formatProgress = frac }
            }
            formatProgress = nil
            formatLoadingID = nil
        }
    }

    /// Modellwechsel (aus den Einstellungen) — nur im Ruhezustand.
    func switchASRModel(to id: String) async {
        guard state == .idle || isFailed else {
            modelNote = "Modellwechsel ist nur möglich, wenn gerade nicht aufgenommen wird."
            return
        }
        modelNote = nil
        let previous = UserDefaults.standard.string(forKey: "asrModel") ?? ModelCatalog.defaultASR
        UserDefaults.standard.set(id, forKey: "asrModel")
        state = .loadingModel
        asrProgress = 0
        asrLoadingID = id
        do {
            try await transcriber.reload { [weak self] frac in
                Task { @MainActor in self?.asrProgress = frac }
            }
            state = .idle
        } catch {
            UserDefaults.standard.set(previous, forKey: "asrModel")
            try? await transcriber.reload()
            state = .idle
            modelNote = "Modell konnte nicht geladen werden (offline?). Vorheriges bleibt aktiv."
        }
        asrProgress = nil
        asrLoadingID = nil
    }

    func switchFormatModel(to id: String) async {
        guard state == .idle || isFailed else {
            modelNote = "Modellwechsel ist nur möglich, wenn gerade nicht aufgenommen wird."
            return
        }
        modelNote = nil
        UserDefaults.standard.set(id, forKey: "formatModel")
        formatProgress = 0
        formatLoadingID = id
        await formatter.reload { [weak self] frac in
            Task { @MainActor in self?.formatProgress = frac }
        }
        formatProgress = nil
        formatLoadingID = nil
    }

    private var isFailed: Bool { if case .failed = state { return true }; return false }

    // MARK: - Aufnahme

    func toggleRecording() {
        switch state {
        case .idle: startRecording()
        case .recording: stopAndProcess()
        default: break
        }
    }

    func startRecording() {
        guard state == .idle else { return }
        AVAudioApplication.requestRecordPermission { [weak self] granted in
            Task { @MainActor in
                guard let self else { return }
                guard granted else {
                    self.state = .failed("Kein Mikrofon-Zugriff. Bitte in den Einstellungen erlauben.")
                    return
                }
                self.beginRecording()
            }
        }
    }

    private func beginRecording() {
        recorder.autoStopEnabled = UserDefaults.standard.bool(forKey: "autoStopEnabled")
        recorder.silenceSeconds = UserDefaults.standard.object(forKey: "silenceSeconds") as? Double ?? 1.5
        do {
            try recorder.start()
            state = .recording
            sounds.play(.start)
        } catch {
            sounds.play(.error)
            state = .failed("Aufnahme konnte nicht gestartet werden: \(error.localizedDescription)")
        }
    }

    func cancelRecording() {
        guard state == .recording else { return }
        _ = recorder.stop()
        state = .idle
        level = 0
        sounds.play(.error)
    }

    func stopAndProcess() {
        guard state == .recording else { return }
        let samples = recorder.stop()
        level = 0
        sounds.play(.stop)
        state = .working
        let useFormatting = formattingEnabled
        let useCommands = UserDefaults.standard.bool(forKey: "speechCommandsEnabled")

        Task {
            defer { if state == .working { state = .idle } }
            guard !samples.isEmpty else { return }
            do {
                let raw = try await transcriber.transcribe(samples, biasTerms: dictionary.contents.terms)
                var output = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !output.isEmpty else { return }

                if useCommands { output = SpeechCommands.apply(to: output) }
                if useFormatting {
                    output = await formatter.format(output, bundleID: nil, termHint: dictionary.termHint)
                }
                output = dictionary.applyCorrections(to: output)

                let final = output.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !final.isEmpty else { return }

                // iOS-Weg: automatisch in die Zwischenablage (systemweites Einfügen
                // in fremde Apps gibt es auf iOS nicht).
                UIPasteboard.general.string = final
                lastResult = final
                sounds.play(.done)
                history.add(final)
                let words = final.split(whereSeparator: { $0.isWhitespace }).count
                stats.record(words: words, seconds: Double(samples.count) / 16_000.0)
            } catch {
                NSLog("shout: Verarbeitung fehlgeschlagen: \(error)")
                sounds.play(.error)
            }
        }
    }

    /// Aus dem Fehlerzustand zurück (nach Berechtigungs-/Netzproblem).
    func recover() {
        if transcriberReady { state = .idle } else { loadModels() }
    }
}
