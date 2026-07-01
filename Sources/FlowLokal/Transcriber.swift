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

    func transcribe(_ samples: [Float]) async throws -> String {
        guard let pipe else { return "" }
        let results = try await pipe.transcribe(
            audioArray: samples,
            decodeOptions: DecodingOptions(language: "de")
        )
        return results.map(\.text).joined(separator: " ")
    }
}
