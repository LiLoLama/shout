import Foundation
import WhisperKit
import HuggingFace

/// Dünne Hülle um WhisperKit. Lädt beim ersten Start das Modell (wird von
/// WhisperKit automatisch von Hugging Face heruntergeladen und danach lokal
/// gecached) und transkribiert Float-Samples.
///
/// Dieser Code stand bis zur Engine-Extraktion in `Transcriber`. Er ist
/// unverändert hierher gewandert; `Transcriber` ist jetzt der Router darüber.
///
/// `actor`, damit Laden und Transkribieren serialisiert werden: Ein Modellwechsel
/// kann so nicht parallel zu einer laufenden Transkription den Zustand
/// zerreißen, und es sind nie zwei WhisperKit-Modelle gleichzeitig in der
/// Initialisierung.
actor LocalSpeechEngine: SpeechEngine {

    /// Gewähltes Modell aus den Einstellungen (Modell-Empfehler). Fällt auf die
    /// macOS-Speed-Variante von large-v3-turbo zurück (Apple Neural Engine).
    private var modelName: String {
        UserDefaults.standard.string(forKey: "asrModel") ?? ModelCatalog.defaultASR
    }

    private var pipe: WhisperKit?
    private(set) var loadedModel: String?

    /// Darf beim Laden heruntergeladen werden?
    ///
    /// `false` ist der Rückfall-Modus: Scheitert die Erkennung bei einem
    /// Anbieter, soll ein bereits vorhandenes lokales Modell einspringen — aber
    /// **niemals** mitten im Diktat einen Multi-GB-Download anstoßen. Ohne
    /// Download schlägt das Laden dann einfach fehl, und der Aufrufer nimmt den
    /// anderen Weg.
    private let allowDownload: Bool

    init(allowDownload: Bool = true) {
        self.allowDownload = allowDownload
    }

    var isReady: Bool { pipe != nil }
    var displayName: String { loadedModel ?? modelName }

    // MARK: - Laden

    func prepare(reset: Bool, onProgress: (@Sendable (Double) -> Void)?) async throws {
        if reset {
            pipe = nil
            loadedModel = nil
        }
        let name = modelName
        guard allowDownload else {
            // Nur aus dem Cache — aber im selben Ordner, aus dem auch der normale
            // Ladeweg lädt: Sonst findet dieser Rückfall (Anbieter ausgefallen,
            // ein vorhandenes lokales Modell soll einspringen) Modelle nicht, die
            // auf einem gewählten Basisordner (z. B. externe Platte) liegen.
            //
            // Nur die Ermittlung ist auf macOS beschränkt: `ModelPaths` steht
            // nicht in der Quellenliste des iOS-Ziels `ShoutMobile` (project.yml)
            // — ein ungeschützter Aufruf würde dessen Build brechen.
            #if os(macOS)
            let basisordner = ModelPaths.laden(aus: .standard,
                                               vorgabe: { HubCache.default.cacheDirectory }).basisordner
            #else
            let basisordner: URL? = nil
            #endif
            // Fehlt das Modell, wirft WhisperKit — genau so ist es gemeint.
            pipe = try await WhisperKit(WhisperKitConfig(model: name, downloadBase: basisordner, download: false))
            loadedModel = name
            return
        }
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
        // Ablageort wie beim Textmodell: derselbe Basisordner (`ModelPaths`),
        // dieselbe Vorgabe (`HubCache.default.cacheDirectory`, beachtet
        // HF_HUB_CACHE/HF_HOME) — nur der Ort ist wählbar, kein Mitbenutzen
        // fremder Ordner (das bleibt dem Textmodell vorbehalten).
        let pfade = ModelPaths.laden(aus: .standard,
                                     vorgabe: { HubCache.default.cacheDirectory })
        pipe = try await WhisperKit(WhisperKitConfig(model: name, downloadBase: pfade.basisordner))
        #endif
        loadedModel = name
    }

    /// „Aufwärmen": eine kurze Stumm-Transkription direkt nach dem Laden, damit
    /// die ANE-/GPU-Graphen schon kompiliert sind. Das ERSTE echte Diktat ist
    /// sonst spürbar langsamer (Graph-Kompilierung passiert beim ersten Lauf).
    func warmUp(language: String?) async {
        guard pipe != nil else { return }
        _ = try? await transcribe(samples: [Float](repeating: 0, count: 16_000),
                                  language: language)
    }

    // MARK: - Erkennung

    func transcribe(samples: [Float], language: String?) async throws -> SpeechResult {
        guard let pipe else { throw TranscriberError.notLoaded }

        let auto = (language == nil)
        var options = DecodingOptions(language: language, detectLanguage: auto)
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

        let results = try await pipe.transcribe(audioArray: samples, decodeOptions: options)

        // `text` aus den Fenster-Ergebnissen, NICHT aus den Segmenten
        // zusammengesetzt: WhisperKit filtert die Steuermarken in beiden
        // unterschiedlich, und das Diktat hat immer diesen Weg genommen.
        let text = results.map(\.text).joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let segments = results.flatMap(\.segments).map {
            TranscriptSegment(text: TranscriptLayout.stripSpecialTokens($0.text),
                              start: Double($0.start),
                              end: Double($0.end))
        }
        return SpeechResult(text: text, segments: segments)
    }
}
