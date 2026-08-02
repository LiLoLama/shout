import Foundation
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
        _ = try? await run(samples: [Float](repeating: 0, count: 16_000), biasTerms: [])
    }

    func transcribe(_ samples: [Float], biasTerms: [String] = []) async throws -> String {
        guard pipe != nil else { throw TranscriberError.notLoaded }

        let text = try await run(samples: samples, biasTerms: biasTerms)

        // Der Bias-Prompt kann Whisper Inhalte verschlucken lassen — nicht nur
        // komplett leere Ergebnisse, sondern auch teilweise (Anfang fehlt, nur
        // letzter Satz …). Deshalb zusätzlich zur Leer-Prüfung eine Plausibilitäts-
        // Prüfung: deutlich zu wenig Text für die Audiolänge (< 3 Zeichen/s bei
        // > 5 s; normales Diktat liegt bei 10–15) → ohne Bias nachziehen, das
        // längere Ergebnis gewinnt. Nur sinnvoll, wenn Bias angewandt wurde
        // (im Auto-Sprachmodus ist er in run() deaktiviert).
        let auto = (UserDefaults.standard.string(forKey: "transcriptionLanguage") ?? "de") == "auto"
        let seconds = Double(samples.count) / 16_000.0
        let suspicious = seconds > 5 && Double(text.count) < seconds * 3
        if !auto, !biasTerms.isEmpty, text.isEmpty || suspicious {
            let unbiased = try await run(samples: samples, biasTerms: [])
            if unbiased.count > text.count {
                NSLog("shout: Bias-Transkript verdächtig kurz (%d Zeichen für %.0f s) → ohne Bias: %d Zeichen",
                      text.count, seconds, unbiased.count)
                return unbiased
            }
        }
        return text
    }

    /// Wie `transcribe`, liefert aber die Abschnitte mit Zeitmarken — Grundlage für
    /// Untertitel bei der Datei-Transkription.
    ///
    /// Ohne die Plausibilitätsprüfung aus `transcribe`: Die vergleicht Textlänge mit
    /// Audiolänge und zieht im Verdachtsfall einen zweiten Durchgang nach. Bei einem
    /// Diktat ist das billig, bei einer Datei würde es die Laufzeit verdoppeln — und
    /// eine Aufnahme mit langen Sprechpausen sieht dort regelmäßig „verdächtig" aus.
    func transcribeSegments(_ samples: [Float], biasTerms: [String] = []) async throws -> [TranscriptSegment] {
        guard pipe != nil else { throw TranscriberError.notLoaded }
        let results = try await runResults(samples: samples, biasTerms: biasTerms)
        return results.flatMap(\.segments).map {
            TranscriptSegment(text: $0.text.trimmingCharacters(in: .whitespacesAndNewlines),
                              start: Double($0.start),
                              end: Double($0.end))
        }
    }

    private func run(samples: [Float], biasTerms: [String]) async throws -> String {
        let results = try await runResults(samples: samples, biasTerms: biasTerms)
        return results.map(\.text).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func runResults(samples: [Float], biasTerms: [String]) async throws -> [TranscriptionResult] {
        guard let pipe else { throw TranscriberError.notLoaded }

        let lang = UserDefaults.standard.string(forKey: "transcriptionLanguage") ?? "de"
        let auto = (lang == "auto")

        var options = DecodingOptions(language: auto ? nil : lang, detectLanguage: auto)
        // Kein Prefill-Cache: verhindert, dass Decoder-Zustand über Aufnahmen
        // hinweg „hängen bleibt" (Ursache für leere Folge-Transkriptionen).
        options.usePrefillCache = false

        // Wörterbuch-Begriffe als Konditionierungs-Prompt → Whisper erkennt
        // Eigennamen/Fachbegriffe schon beim Transkribieren besser.
        // Im Auto-Modus deaktiviert (Prompt-Prefill kollidiert mit der Spracherkennung).
        if !auto, !biasTerms.isEmpty, let tokenizer = pipe.tokenizer {
            let promptText = " " + biasTerms.joined(separator: ", ")
            let specialBegin = tokenizer.specialTokens.specialTokenBegin
            let tokens = tokenizer.encode(text: promptText).filter { $0 < specialBegin }
            if !tokens.isEmpty {
                // Bewusst knapp (64 statt 200): Je größer der Prompt, desto eher
                // „verschluckt" Whisper Audio-Anfänge oder lässt Inhalte aus.
                // Das Wörterbuch wächst durch Auto-Lernen — ohne Deckel wird das
                // Problem mit der Zeit schleichend schlimmer.
                options.promptTokens = Array(tokens.prefix(64))
                options.usePrefillPrompt = true
            }
        }

        return try await pipe.transcribe(audioArray: samples, decodeOptions: options)
    }
}
