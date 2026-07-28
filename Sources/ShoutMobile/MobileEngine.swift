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

    /// Wurde diese Aufnahme von der shout-Tastatur (via shout://dictate) angestoßen?
    /// Dann zeigt der Home-Screen den Hinweis, zurück in die App zu wischen und
    /// „Einfügen" zu tippen.
    @Published var cameFromKeyboard = false
    /// URL-Aufruf kam, bevor die Modelle bereit waren → Aufnahme nachholen.
    private var pendingAutoStart = false

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
        // Erststart: auch diktiert wird in der Systemsprache (wie Mac und Windows).
        if d.string(forKey: "transcriptionLanguage") == nil {
            let system = Locale.preferredLanguages.first ?? Locale.current.identifier
            d.set(system.hasPrefix("de") ? "de" : "en", forKey: "transcriptionLanguage")
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
            Task { @MainActor in self?.requestDictation() }
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
                await transcriber.warmUp()   // erstes Diktat schon schnell
                transcriberReady = true
                state = .idle
                if pendingAutoStart { pendingAutoStart = false; startRecording() }
            } catch {
                NSLog("shout: Modell-Ladefehler: \(error)")
                state = .failed(Loc.t("Sprachmodell konnte nicht geladen werden. Internet prüfen und erneut versuchen."))
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
            await formatter.warmUp()
            formatProgress = nil
            formatLoadingID = nil
        }
    }

    /// Modellwechsel (aus den Einstellungen) — nur im Ruhezustand.
    func switchASRModel(to id: String) async {
        guard state == .idle || isFailed else {
            modelNote = Loc.t("Modellwechsel ist nur möglich, wenn gerade nicht aufgenommen wird.")
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
            await transcriber.warmUp()
            state = .idle
        } catch {
            UserDefaults.standard.set(previous, forKey: "asrModel")
            try? await transcriber.reload()
            state = .idle
            modelNote = Loc.t("Modell konnte nicht geladen werden (offline?). Vorheriges bleibt aktiv.")
        }
        asrProgress = nil
        asrLoadingID = nil
    }

    func switchFormatModel(to id: String) async {
        guard state == .idle || isFailed else {
            modelNote = Loc.t("Modellwechsel ist nur möglich, wenn gerade nicht aufgenommen wird.")
            return
        }
        modelNote = nil
        UserDefaults.standard.set(id, forKey: "formatModel")
        formatProgress = 0
        formatLoadingID = id
        await formatter.reload { [weak self] frac in
            Task { @MainActor in self?.formatProgress = frac }
        }
        await formatter.warmUp()
        formatProgress = nil
        formatLoadingID = nil
    }

    private var isFailed: Bool { if case .failed = state { return true }; return false }

    // MARK: - Aufnahme

    func toggleRecording() {
        cameFromKeyboard = false   // manueller Start → kein Tastatur-Rückkehr-Hinweis
        switch state {
        case .idle: startRecording()
        case .recording: stopAndProcess()
        default: break
        }
    }

    /// Von der Tastatur (shout://dictate) oder vom App Intent angestoßen.
    /// Startet sofort, wenn bereit — sonst nach dem Modell-Laden.
    func requestDictation(fromKeyboard: Bool = false) {
        cameFromKeyboard = fromKeyboard
        switch state {
        case .idle: startRecording()
        case .loadingModel: pendingAutoStart = true
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
                // in fremde Apps gibt es auf iOS nicht) UND in die App Group, damit
                // die shout-Tastatur den Text nach dem Zurückwischen einfügen kann.
                UIPasteboard.general.string = final
                AppGroup.setPendingDictation(final)
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

    // MARK: - Daten-Übertragung (Mac ↔ iPhone)

    /// Schreibt ein Backup (Wörterbuch, Verlauf, Statistiken, Einstellungen) in
    /// eine temporäre Datei und gibt deren URL zum Teilen zurück.
    func exportBundleURL() -> URL? {
        let snapshot = SettingsSnapshot(
            autoStop: UserDefaults.standard.bool(forKey: "autoStopEnabled"),
            silenceSeconds: UserDefaults.standard.object(forKey: "silenceSeconds") as? Double,
            formattingEnabled: UserDefaults.standard.object(forKey: "formattingEnabled") as? Bool,
            voiceProfile: UserDefaults.standard.string(forKey: "voiceProfile")
        )
        let bundle = BackupBundle(dictionary: dictionary.contents, history: history.entries,
                                  stats: stats.data, settings: snapshot)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(bundle) else { return nil }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("shout-backup.json")
        do { try data.write(to: url, options: .atomic); return url } catch { return nil }
    }

    /// Übernimmt ein am Mac (oder iPhone) exportiertes Backup. Ersetzt Wörterbuch,
    /// Verlauf und Statistiken; überträgt die geteilten Einstellungen.
    @discardableResult
    func importBundle(from url: URL) -> String {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { return Loc.t("Datei nicht lesbar.") }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let bundle = try? decoder.decode(BackupBundle.self, from: data) else {
            return Loc.t("Ungültige Backup-Datei.")
        }
        dictionary.replaceContents(bundle.dictionary)
        history.replaceEntries(bundle.history)
        stats.replaceData(bundle.stats)
        if let f = bundle.settings.formattingEnabled { UserDefaults.standard.set(f, forKey: "formattingEnabled") }
        if let vp = bundle.settings.voiceProfile { UserDefaults.standard.set(vp, forKey: "voiceProfile") }
        return Loc.f("Importiert: %d Begriffe, %d Diktate.",
                     bundle.dictionary.terms.count, bundle.history.count)
    }
}
