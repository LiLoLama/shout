import Foundation
import WhisperKit

/// Dünne Hülle um WhisperKit. Lädt beim ersten Start das Modell
/// (wird von WhisperKit automatisch von Hugging Face heruntergeladen und
/// danach lokal gecached) und transkribiert Float-Samples auf Deutsch.
final class Transcriber {

    /// Gewähltes Modell aus den Einstellungen (Modell-Empfehler). Fällt auf die
    /// macOS-Speed-Variante von large-v3-turbo zurück (Apple Neural Engine).
    private var modelName: String {
        UserDefaults.standard.string(forKey: "asrModel") ?? ModelCatalog.defaultASR
    }

    private var pipe: WhisperKit?

    var isReady: Bool { pipe != nil }
    /// Name des aktuell geladenen Modells (für die UI).
    private(set) var loadedModel: String?

    func load() async throws {
        let name = modelName
        pipe = try await WhisperKit(WhisperKitConfig(model: name))
        loadedModel = name
    }

    /// Wechselt zur Laufzeit auf das aktuell gewählte Modell. Schluckt Fehler
    /// (die UI zeigt den Ladezustand separat).
    func reload() async {
        pipe = nil
        loadedModel = nil
        do { try await load() }
        catch { NSLog("Transkriptions-Modell konnte nicht geladen werden: \(error)") }
    }

    func transcribe(_ samples: [Float], biasTerms: [String] = []) async throws -> String {
        guard pipe != nil else { return "" }

        let text = try await run(samples: samples, biasTerms: biasTerms)
        // Prompt-Biasing kann bei Folge-Aufnahmen leeren Text verursachen →
        // dann einmal ohne Biasing nachziehen (rettet die Transkription).
        if text.isEmpty, !biasTerms.isEmpty {
            return try await run(samples: samples, biasTerms: [])
        }
        return text
    }

    private func run(samples: [Float], biasTerms: [String]) async throws -> String {
        guard let pipe else { return "" }

        var options = DecodingOptions(language: "de")
        // Kein Prefill-Cache: verhindert, dass Decoder-Zustand über Aufnahmen
        // hinweg „hängen bleibt" (Ursache für leere Folge-Transkriptionen).
        options.usePrefillCache = false

        // Wörterbuch-Begriffe als Konditionierungs-Prompt → Whisper erkennt
        // Eigennamen/Fachbegriffe schon beim Transkribieren besser.
        if !biasTerms.isEmpty, let tokenizer = pipe.tokenizer {
            let promptText = " " + biasTerms.joined(separator: ", ")
            let specialBegin = tokenizer.specialTokens.specialTokenBegin
            let tokens = tokenizer.encode(text: promptText).filter { $0 < specialBegin }
            if !tokens.isEmpty {
                options.promptTokens = Array(tokens.prefix(200))
                options.usePrefillPrompt = true
            }
        }

        let results = try await pipe.transcribe(audioArray: samples, decodeOptions: options)
        return results.map(\.text).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
