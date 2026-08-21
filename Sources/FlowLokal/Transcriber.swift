import Foundation
import OSLog
import WhisperKit

enum TranscriberError: Error { case notLoaded }

/// Dünne Hülle um WhisperKit. Lädt beim ersten Start das Modell
/// (wird von WhisperKit automatisch von Hugging Face heruntergeladen und
/// danach lokal gecached) und transkribiert Float-Samples auf Deutsch.
///
/// `actor`, damit Laden (load/reload) und Transkribieren serialisiert werden:
/// Ein Modellwechsel kann so nicht parallel zu einer laufenden Transkription
/// den Zustand zerreißen, und es sind nie zwei WhisperKit-Modelle gleichzeitig
/// in der Initialisierung.
actor Transcriber {

    /// Abfragbar per `log show --predicate 'subsystem == "com.inthezone.flowlokal"'`.
    private static let log = Logger(subsystem: "com.inthezone.flowlokal", category: "diktat")

    /// Gewähltes Modell aus den Einstellungen (Modell-Empfehler). Fällt auf die
    /// macOS-Speed-Variante von large-v3-turbo zurück (Apple Neural Engine).
    private var modelName: String {
        UserDefaults.standard.string(forKey: "asrModel") ?? ModelCatalog.defaultASR
    }

    private var pipe: WhisperKit?

    var isReady: Bool { pipe != nil }
    /// Name des aktuell geladenen Modells (für die UI).
    private(set) var loadedModel: String?

    /// Lädt das gewählte Modell (Cache-first, offline-fähig wie gehabt).
    func load(onProgress: (@Sendable (Double) -> Void)? = nil) async throws {
        let name = modelName
        #if os(iOS)
        // iOS: Zwei-Schritt-Weg (erst Download mit echtem Fortschritt, dann aus dem
        // Ordner laden) — auf dem iPhone (Mobilfunk!) muss der Nutzer den Download
        // sehen. Fallback auf den kombinierten Weg, falls der Download-Pfad hakt.
        do {
            let folder = try await WhisperKit.download(variant: name) { progress in
                onProgress?(progress.fractionCompleted)
            }
            pipe = try await WhisperKit(WhisperKitConfig(modelFolder: folder.path, download: false))
        } catch {
            NSLog("shout: Zwei-Schritt-Load fehlgeschlagen (\(error)) → Fallback")
            pipe = try await WhisperKit(WhisperKitConfig(model: name))
        }
        #else
        pipe = try await WhisperKit(WhisperKitConfig(model: name))
        #endif
        loadedModel = name
    }

    /// Wechselt zur Laufzeit auf das aktuell gewählte Modell. Wirft bei Fehler,
    /// damit der Aufrufer den Status korrekt setzen (und ggf. zurückrollen) kann.
    /// Durch die Actor-Isolation laufen konkurrierende Aufrufe serialisiert.
    func reload(onProgress: (@Sendable (Double) -> Void)? = nil) async throws {
        pipe = nil
        loadedModel = nil
        try await load(onProgress: onProgress)
    }

    /// „Aufwärmen": eine kurze Stumm-Transkription direkt nach dem Laden, damit
    /// die ANE-/GPU-Graphen schon kompiliert sind. Das ERSTE echte Diktat ist
    /// sonst spürbar langsamer (Graph-Kompilierung passiert beim ersten Lauf).
    func warmUp() async {
        guard pipe != nil else { return }
        _ = try? await run(samples: [Float](repeating: 0, count: 16_000))
    }

    func transcribe(_ samples: [Float]) async throws -> String {
        guard pipe != nil else { throw TranscriberError.notLoaded }

        let results = try await runResults(samples: samples)
        let text = Self.joined(results)

        // Wachhund ohne Reparatur: Seit der Wörterbuch-Prompt nicht mehr in den
        // Decoder geht (er ließ Whisper Audio überspringen — bis zu 45 % eines
        // Diktats), gibt es keinen zweiten, anders konfigurierten Durchgang mehr,
        // der etwas retten könnte (Temperatur 0 → identisches Ergebnis). Bleibt
        // ein Transkript trotzdem verdächtig, soll das im Log sichtbar sein:
        // über Logger, nicht NSLog — NSLog dieser App erreicht das System-Log
        // nachweislich nicht (12-h-Abfrage am 21.08.2026: null Zeilen).
        let seconds = Double(samples.count) / 16_000.0
        let firstStart = results.flatMap(\.segments).first.map { Double($0.start) }
        if TranscriptPlausibility.swallowedStart(firstSegmentStart: firstStart, audioSeconds: seconds) {
            Self.log.warning("Transkript verdächtig: erster Abschnitt erst bei \(firstStart ?? 0, format: .fixed(precision: 1)) s von \(seconds, format: .fixed(precision: 0)) s")
        } else if TranscriptPlausibility.tooLittleText(characters: text.count, audioSeconds: seconds) {
            Self.log.warning("Transkript verdächtig: nur \(text.count) Zeichen für \(seconds, format: .fixed(precision: 0)) s Audio")
        }
        return text
    }

    /// Wie `transcribe`, liefert aber die Abschnitte mit Zeitmarken — Grundlage für
    /// Untertitel bei der Datei-Transkription.
    ///
    /// Ohne den Wachhund aus `transcribe`: Eine Datei mit langen Sprechpausen
    /// sähe dort regelmäßig „verdächtig" aus, ohne dass etwas fehlt.
    func transcribeSegments(_ samples: [Float]) async throws -> [TranscriptSegment] {
        guard pipe != nil else { throw TranscriberError.notLoaded }
        let results = try await runResults(samples: samples)
        return results.flatMap(\.segments).map {
            TranscriptSegment(text: TranscriptLayout.stripSpecialTokens($0.text),
                              start: Double($0.start),
                              end: Double($0.end))
        }
    }

    private func run(samples: [Float]) async throws -> String {
        Self.joined(try await runResults(samples: samples))
    }

    /// Fenster-Ergebnisse zu einem Text zusammenziehen.
    private static func joined(_ results: [TranscriptionResult]) -> String {
        results.map(\.text).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func runResults(samples: [Float]) async throws -> [TranscriptionResult] {
        guard let pipe else { throw TranscriberError.notLoaded }

        let lang = UserDefaults.standard.string(forKey: "transcriptionLanguage") ?? "de"
        let auto = (lang == "auto")

        var options = DecodingOptions(language: auto ? nil : lang, detectLanguage: auto)
        // Kein Prefill-Cache: verhindert, dass Decoder-Zustand über Aufnahmen
        // hinweg „hängen bleibt" (Ursache für leere Folge-Transkriptionen).
        options.usePrefillCache = false
        // WhisperKit dekodiert die Steuermarken sonst in den SEGMENT-Text hinein
        // („<|de|>", „<|0.00|>", „<|endoftext|>"). Beim Diktat fiel das nie auf, weil
        // `TranscriptionResult.text` sie ohnehin herausfiltert — die Datei-
        // Transkription arbeitet aber mit den Segmenten und bekam sie voll ab.
        options.skipSpecialTokens = true

        // BEWUSST KEIN Wörterbuch-Prompt (promptTokens/usePrefillPrompt) mehr:
        // Whisper behandelt ihn als vorangehenden Text und überspringt dann
        // gelegentlich Audio — am 19./21.08.2026 nachgewiesen: derselbe
        // Sample-Puffer ergab mit Prompt < 178 Zeichen, ohne 773; ein
        // 104-s-Diktat verlor ~45 % seines Anfangs. Schon 6 Begriffe reichten,
        // und der Prompt fährt in JEDEM 30-s-Fenster erneut mit. Eigennamen
        // korrigiert weiterhin das Wörterbuch (Korrekturen + Formatter-Hinweis)
        // NACH der Erkennung, ohne sie zu gefährden.

        return try await pipe.transcribe(audioArray: samples, decodeOptions: options)
    }
}
