import Foundation
import OSLog

enum TranscriberError: Error { case notLoaded }

/// **Router** über einem austauschbaren Spracherkenner. Ob WhisperKit im
/// eigenen Prozess läuft (`LocalSpeechEngine`) oder ein selbst gewählter
/// Anbieter erkennt (`RemoteSpeechEngine`), weiß diese Klasse nicht.
///
/// Was hier bleibt, gilt damit für jeden Erkenner: die Sprachwahl aus den
/// Einstellungen und der Plausibilitäts-Wachhund.
///
/// `actor`, damit Laden und Transkribieren serialisiert werden: Ein Modellwechsel
/// kann so nicht parallel zu einer laufenden Transkription den Zustand
/// zerreißen.
actor Transcriber {

    /// Abfragbar per `log show --predicate 'subsystem == "com.inthezone.flowlokal"'`.
    private static let log = Logger(subsystem: "com.inthezone.flowlokal", category: "diktat")

    /// Baut den Erkenner. Als Closure hereingegeben, damit diese Datei WhisperKit
    /// nicht kennt und im Testziel liegen kann — vorher war der Wachhund nicht
    /// prüfbar. Die Auswahl trifft `EngineFactory`.
    private let makeEngine: @Sendable () -> any SpeechEngine
    private var engine: (any SpeechEngine)?

    init(makeEngine: @escaping @Sendable () -> any SpeechEngine) {
        self.makeEngine = makeEngine
    }

    /// Diktier-Sprache aus den Einstellungen. `nil` heißt: automatisch erkennen.
    private var language: String? {
        let lang = UserDefaults.standard.string(forKey: "transcriptionLanguage") ?? "de"
        return lang == "auto" ? nil : lang
    }

    var isReady: Bool {
        get async { await engine?.isReady ?? false }
    }

    var activeModelName: String {
        get async {
            guard let engine, await engine.isReady else { return "—" }
            return await engine.displayName
        }
    }

    // MARK: - Laden

    /// Lädt das gewählte Modell (Cache-first, offline-fähig wie gehabt).
    func load(onProgress: (@Sendable (Double) -> Void)? = nil) async throws {
        if engine == nil { engine = makeEngine() }
        try await engine?.prepare(reset: false, onProgress: onProgress)
    }

    /// Wechselt zur Laufzeit auf das aktuell gewählte Modell. Wirft bei Fehler,
    /// damit der Aufrufer den Status korrekt setzen (und ggf. zurückrollen) kann.
    /// Baut den Erkenner neu, weil sich nicht nur das Modell, sondern die **Art**
    /// geändert haben kann (auf diesem Gerät ↔ Anbieter).
    func reload(onProgress: (@Sendable (Double) -> Void)? = nil) async throws {
        engine = makeEngine()
        try await engine?.prepare(reset: true, onProgress: onProgress)
    }

    func warmUp() async {
        await engine?.warmUp(language: language)
    }

    // MARK: - Diktat

    func transcribe(_ samples: [Float]) async throws -> String {
        guard let engine else { throw TranscriberError.notLoaded }

        let result = try await engine.transcribe(samples: samples, language: language)

        // Wachhund ohne Reparatur: Seit der Wörterbuch-Prompt nicht mehr in den
        // Decoder geht (er ließ Whisper Audio überspringen — bis zu 45 % eines
        // Diktats), gibt es keinen zweiten, anders konfigurierten Durchgang mehr,
        // der etwas retten könnte (Temperatur 0 → identisches Ergebnis). Bleibt
        // ein Transkript trotzdem verdächtig, soll das im Log sichtbar sein:
        // über Logger, nicht NSLog — NSLog dieser App erreicht das System-Log
        // nachweislich nicht (12-h-Abfrage am 21.08.2026: null Zeilen).
        let seconds = Double(samples.count) / 16_000.0
        let firstStart = result.segments.first.map(\.start)
        if TranscriptPlausibility.swallowedStart(firstSegmentStart: firstStart, audioSeconds: seconds) {
            Self.log.warning("Transkript verdächtig: erster Abschnitt erst bei \(firstStart ?? 0, format: .fixed(precision: 1)) s von \(seconds, format: .fixed(precision: 0)) s")
        } else if TranscriptPlausibility.tooLittleText(characters: result.text.count, audioSeconds: seconds) {
            Self.log.warning("Transkript verdächtig: nur \(result.text.count) Zeichen für \(seconds, format: .fixed(precision: 0)) s Audio")
        }
        return result.text
    }

    /// Wie `transcribe`, liefert aber die Abschnitte mit Zeitmarken — Grundlage für
    /// Untertitel bei der Datei-Transkription.
    ///
    /// Ohne den Wachhund aus `transcribe`: Eine Datei mit langen Sprechpausen
    /// sähe dort regelmäßig „verdächtig" aus, ohne dass etwas fehlt.
    func transcribeSegments(_ samples: [Float]) async throws -> [TranscriptSegment] {
        guard let engine else { throw TranscriberError.notLoaded }
        return try await engine.transcribe(samples: samples, language: language).segments
    }
}
