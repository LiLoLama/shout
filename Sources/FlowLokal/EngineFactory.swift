import Foundation

/// Baut die Engines für `Formatter` und `Transcriber`.
///
/// Diese Datei ist der **einzige** Ort, der die konkreten Engines kennt, und sie
/// liegt bewusst NICHT im Testziel. Nur deshalb sind `Formatter` und
/// `Transcriber` frei von MLX- und WhisperKit-Bezügen und damit überhaupt in
/// Unit-Tests hängbar — vorher waren beide ungetestet.
///
/// Hier entscheidet sich später auch „auf diesem Gerät" gegen „Anbieter": Die
/// Fabrik liest die Einstellung und gibt die passende Engine zurück. `reload()`
/// am Router ruft sie erneut auf, damit ein Wechsel zur Laufzeit greift.
enum EngineFactory {

    /// `@Sendable`, weil die Router die Fabrik als Closure halten und sie aus
    /// ihrem eigenen Actor-Kontext aufrufen. Sie liest nur Einstellungen und
    /// baut einen neuen Actor — kein geteilter Zustand.
    @Sendable static func text() -> any TextEngine {
        switch EngineSelection.decide(for: .text) {
        case .local:
            return LocalTextEngine()
        case .remote(let config, let template):
            return RemoteTextEngine(config: config,
                                    key: ProviderKeychain.read(for: template.id),
                                    needsKey: template.needsKey,
                                    providerName: template.name)
        }
    }

    @Sendable static func speech() -> any SpeechEngine {
        LocalSpeechEngine()
    }
}
