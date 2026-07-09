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
    /// `onProgress` bleibt aus API-Gründen erhalten; WhisperKit lädt seinen
    /// festen, kleinen Modellsatz ohne separaten Fortschritt.
    func load(onProgress: (@Sendable (Double) -> Void)? = nil) async throws {
        let name = modelName
        pipe = try await WhisperKit(WhisperKitConfig(model: name))
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

    private func run(samples: [Float], biasTerms: [String]) async throws -> String {
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

        let results = try await pipe.transcribe(audioArray: samples, decodeOptions: options)
        return results.map(\.text).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
