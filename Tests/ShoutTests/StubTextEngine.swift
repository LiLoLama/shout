import Foundation

/// Attrappen-Textmodell für die Router-Tests.
///
/// Damit wird erstmals prüfbar, was bisher nur im Betrieb auffiel: greift der
/// Kürzungs-Schutz, kommt bei einem Fehler wirklich der Rohtext, wird ein kurzes
/// Diktat überhaupt erst ans Modell geschickt. Vor der Engine-Extraktion war
/// `Formatter` dafür nicht erreichbar — die Klasse hing an MLX und lag deshalb
/// nicht im Testziel.
actor StubTextEngine: TextEngine {

    /// Was die Attrappe auf `respond` antwortet. `nil` heißt: den Aufruf werfen.
    private var answers: [String?]
    /// Immer diese Antwort, wenn `answers` leer ist.
    private let fallback: String?
    /// Künstliche Verzögerung je Aufruf — für die Zeitgrenzen-Tests.
    private let delay: Duration?

    private(set) var isReady: Bool
    private(set) var isLoading = false
    let displayName: String
    let chunkTargetLength: Int
    let chunkMinLength: Int

    /// Jede an `respond` übergebene Nutzer-Eingabe, in Aufrufreihenfolge.
    private(set) var recordedPrompts: [String] = []
    /// Jede an `respond` übergebene System-Anweisung, in Aufrufreihenfolge.
    private(set) var recordedSystems: [String] = []
    private(set) var prepareCount = 0
    private(set) var warmUpCount = 0

    init(answers: [String?] = [],
         fallback: String? = nil,
         isReady: Bool = true,
         displayName: String = "Attrappe",
         chunkTargetLength: Int = 1500,
         chunkMinLength: Int = 1000,
         delay: Duration? = nil) {
        self.answers = answers
        self.fallback = fallback
        self.isReady = isReady
        self.displayName = displayName
        self.chunkTargetLength = chunkTargetLength
        self.chunkMinLength = chunkMinLength
        self.delay = delay
    }

    func prepare(reset: Bool, onProgress: (@Sendable (Double) -> Void)?) async {
        prepareCount += 1
        onProgress?(1)
    }

    func warmUp() async { warmUpCount += 1 }

    func respond(system: String, user: String, temperature: Float) async throws -> String {
        recordedSystems.append(system)
        recordedPrompts.append(user)
        if let delay { try await Task.sleep(for: delay) }
        let answer = answers.isEmpty ? fallback : answers.removeFirst()
        guard let answer else { throw StubError.gewollt }
        return answer
    }

    enum StubError: Error { case gewollt }
}
