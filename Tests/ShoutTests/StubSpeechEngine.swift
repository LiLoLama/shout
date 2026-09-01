import Foundation

/// Attrappen-Spracherkenner für die Router-Tests.
actor StubSpeechEngine: SpeechEngine {

    /// Was die Attrappe liefert. `nil` heißt: den Aufruf werfen.
    private let result: SpeechResult?

    private(set) var isReady: Bool
    let displayName: String

    /// Die Sprache, mit der der Router zuletzt gerufen hat — `nil` ist ein
    /// gültiger Wert („automatisch"), deshalb doppelt verpackt.
    private(set) var lastLanguage: String??
    private(set) var lastWarmUpLanguage: String??
    private(set) var transcribeCount = 0
    private(set) var prepareCount = 0
    private(set) var lastPrepareWasReset: Bool?

    init(result: SpeechResult? = SpeechResult(text: "", segments: []),
         isReady: Bool = true,
         displayName: String = "Attrappe") {
        self.result = result
        self.isReady = isReady
        self.displayName = displayName
    }

    func prepare(reset: Bool, onProgress: (@Sendable (Double) -> Void)?) async throws {
        prepareCount += 1
        lastPrepareWasReset = reset
        onProgress?(1)
    }

    func warmUp(language: String?) async {
        lastWarmUpLanguage = .some(language)
    }

    func transcribe(samples: [Float], language: String?) async throws -> SpeechResult {
        transcribeCount += 1
        lastLanguage = .some(language)
        guard let result else { throw StubError.gewollt }
        return result
    }

    enum StubError: Error { case gewollt }
}
