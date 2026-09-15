import Foundation
import MLXLLM
import MLXLMCommon
import MLXHuggingFace
import HuggingFace
import Tokenizers

/// Das Textmodell **im eigenen Prozess** (MLX, Apple Silicon) — kein LM Studio,
/// kein Ollama, kein Server. Das Modell wird beim ersten Start einmalig von
/// Hugging Face geholt und danach lokal gecached; es lebt anschließend komplett
/// in der App.
///
/// Dieser Code stand bis zur Engine-Extraktion in `Formatter`. Er ist unverändert
/// hierher gewandert; `Formatter` ist jetzt der Router darüber und weiß nicht
/// mehr, ob ein Modell im Prozess läuft oder bei einem Anbieter.
actor LocalTextEngine: TextEngine {

    /// Gewähltes Formatierungs-Modell aus den Einstellungen (Modell-Empfehler).
    private var modelID: String {
        UserDefaults.standard.string(forKey: "formatModel") ?? ModelCatalog.defaultFormatting
    }

    private var container: ModelContainer?

    private(set) var isReady = false
    private(set) var isLoading = false
    private(set) var loadedModel: String?

    var displayName: String { loadedModel ?? modelID }

    /// Klein geschnitten, weil das kleine quantisierte Modell bei langen
    /// Eingaben still Inhalt weglässt — die Werte entsprechen den bisherigen
    /// Standardwerten von `TextChunker.chunks`.
    let chunkTargetLength = 1500
    let chunkMinLength = 1000

    /// Keine Grenze — ein lokales Modell hängt nicht, es rechnet. Auf einem
    /// langsamen Rechner mit einem großen Modell dauert ein Abschnitt eben, und
    /// abgeschnitten wurde das noch nie.
    let callTimeout: TimeInterval? = nil

    // MARK: - Modell laden

    /// Lädt (und beim ersten Mal: downloadet) das aktuell gewählte Modell in den
    /// Prozess. Die Serialisierung mehrerer Ladevorgänge macht der Router — sonst
    /// würden zwei parallele Aufrufe denselben Multi-GB-Download zweimal starten.
    func prepare(reset: Bool, onProgress: (@Sendable (Double) -> Void)?) async {
        let id = modelID
        if !reset, isReady, loadedModel == id { return }  // schon das richtige Modell geladen
        isLoading = true
        isReady = false
        loadedModel = nil
        container = nil
        defer { isLoading = false }
        do {
            let cfg = ModelConfiguration(id: id)
            // Der eigene Basisordner ist bewusst nur eine macOS-Erweiterung:
            // am iPhone gibt es kein geteiltes Dateisystem, in dem ein Nutzer
            // einen Ordner wählen könnte, und das iOS-Ziel (ShoutMobile) kennt
            // `ModelPaths`/`ShoutDownloader` nicht — project.yml listet für iOS
            // nur eine Teilmenge der Dateien. Deshalb dort weiterhin der alte
            // Weg über das Makro mit dem Standard-Hub.
            #if os(macOS)
            // Ausgeschrieben statt über das Makro: Nur so lässt sich der
            // Downloader austauschen — das Makro nimmt fest den Standard-Hub.
            let pfade = ModelPaths.laden(aus: .standard,
                                         vorgabe: { HubCache.default.cacheDirectory })
            container = try await loadModelContainer(
                from: ShoutDownloader(store: pfade.store,
                                      gewaehlterBasisordner: pfade.gewaehlterBasisordner),
                using: #huggingFaceTokenizerLoader(),
                configuration: cfg) { progress in
                onProgress?(progress.fractionCompleted)
            }
            #else
            container = try await #huggingFaceLoadModelContainer(configuration: cfg) { progress in
                onProgress?(progress.fractionCompleted)
            }
            #endif
            loadedModel = id
            isReady = true
            #if os(macOS)
            Abkuerzungsgedaechtnis.geteilt.ladenGelungen(id)
            #endif
        } catch {
            NSLog("Formatter-Modell konnte nicht geladen werden: \(error)")
            isReady = false
            #if os(macOS)
            // Kam der Pfad aus der Abkürzung in einen fremden Ordner, darf der
            // nächste Versuch sie nicht erneut nehmen: Ein Ordner kann die
            // Prüfung des Stores bestehen (config.json plus irgendeine
            // *.safetensors) und trotzdem nicht ladbar sein — fehlende
            // tokenizer.json, halber Shard-Satz, andere Architektur. Sonst
            // nähme jeder weitere Versuch denselben Weg, und die Aufbereitung
            // bliebe dauerhaft und unbemerkt tot. Der nächste Versuch geht an
            // den Hub.
            Abkuerzungsgedaechtnis.geteilt.ladenGescheitert(id)
            #endif
        }
    }

    /// „Aufwärmen": ein Ein-Token-Durchlauf, damit die Metal-Pipeline kompiliert
    /// ist und die erste echte Aufbereitung nicht spürbar länger dauert.
    func warmUp() async {
        guard isReady, let container else { return }
        let session = ChatSession(container, instructions: "Antworte knapp.",
                                  generateParameters: GenerateParameters(maxTokens: 1))
        _ = try? await session.respond(to: "Hallo")
    }

    // MARK: - Aufruf

    func respond(system: String, user: String, temperature: Float) async throws -> String {
        guard let container else { throw LocalTextEngineError.notLoaded }
        let session = ChatSession(
            container,
            instructions: system,
            generateParameters: GenerateParameters(temperature: temperature)
        )
        return try await session.respond(to: user)
    }
}

enum LocalTextEngineError: Error { case notLoaded }
