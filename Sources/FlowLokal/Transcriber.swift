import Foundation
import WhisperKit

/// Dünne Hülle um WhisperKit. Lädt beim ersten Start das Modell
/// (wird von WhisperKit automatisch von Hugging Face heruntergeladen und
/// danach lokal gecached) und transkribiert Float-Samples auf Deutsch.
final class Transcriber {

    /// macOS-Speed-Variante von large-v3-turbo (läuft auf der Apple Neural Engine).
    /// Alternativen bei Bedarf: "large-v3-v20240930_626MB" (kompakter) oder
    /// "large-v3" (volle Qualität, langsamer).
    private let modelName = "large-v3-v20240930_turbo"

    private var pipe: WhisperKit?

    var isReady: Bool { pipe != nil }

    func load() async throws {
        pipe = try await WhisperKit(WhisperKitConfig(model: modelName))
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
