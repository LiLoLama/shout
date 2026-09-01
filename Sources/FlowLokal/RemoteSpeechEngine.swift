import Foundation

/// Spracherkennung **bei einem selbst gewählten Anbieter** — ein
/// OpenAI-kompatibler `/v1/audio/transcriptions`-Aufruf (multipart).
///
/// Derselbe Endpunkt bei OpenAI, Groq, Mistral und jedem whisper.cpp-Server;
/// was sich unterscheidet, sind Daten in der Vorlage.
///
/// Lange Aufnahmen werden vorher gefenstert (`AudioWindows`) und der Reihe nach
/// hochgeladen — nicht parallel: Ein Ratenlimit würde sonst den ganzen Auftrag
/// zerreißen, und der Fortschrittsbalken der Warteschlange braucht ohnehin eine
/// Reihenfolge.
actor RemoteSpeechEngine: SpeechEngine {

    private let config: RemoteConfig
    private let key: String?
    private let needsKey: Bool
    private let providerName: String
    private let session: URLSession
    private let timeout: TimeInterval
    private let maxWindowSeconds: Double
    private let sampleRate: Int

    /// Wie viele Sekunden Audio insgesamt verschickt wurden. Transkription wird
    /// meist pro Minute abgerechnet, nicht pro Token — Grundlage der
    /// Kostenanzeige.
    private(set) var sentSeconds: Double = 0

    /// Wohin die verschickten Sekunden gemeldet werden.
    private let onSeconds: (@Sendable (Double) -> Void)?

    init(config: RemoteConfig,
         key: String?,
         needsKey: Bool,
         providerName: String,
         session: URLSession = .shared,
         timeout: TimeInterval = 120,
         maxWindowSeconds: Double = 600,
         sampleRate: Int = 16_000,
         onSeconds: (@Sendable (Double) -> Void)? = nil) {
        self.onSeconds = onSeconds
        self.config = config
        self.key = key?.isEmpty == true ? nil : key
        self.needsKey = needsKey
        self.providerName = providerName
        self.session = session
        self.timeout = timeout
        self.maxWindowSeconds = maxWindowSeconds
        self.sampleRate = sampleRate
    }

    var isReady: Bool {
        guard config.audioURL != nil else { return false }
        return !needsKey || key != nil
    }

    var displayName: String { "\(config.model) · \(providerName)" }

    /// Nichts zu laden.
    func prepare(reset: Bool, onProgress: (@Sendable (Double) -> Void)?) async throws {
        onProgress?(1)
    }

    /// Absichtlich leer: Stille hochzuladen würde Geld kosten und nichts
    /// beschleunigen. Es gibt hier keine ANE-Graphen zu kompilieren.
    func warmUp(language: String?) async {}

    // MARK: - Erkennung

    func transcribe(samples: [Float], language: String?) async throws -> SpeechResult {
        guard config.audioURL != nil else { throw RemoteProviderError.invalidBaseURL }
        if needsKey, key == nil { throw RemoteProviderError.missingKey }

        let fenster = AudioWindows.split(samples, sampleRate: sampleRate,
                                         maxSeconds: maxWindowSeconds)
        guard !fenster.isEmpty else { return SpeechResult(text: "", segments: []) }

        var texte: [String] = []
        var segmente: [TranscriptSegment] = []

        for f in fenster {
            // Ein dauerhaft scheiterndes Fenster lässt den GANZEN Aufruf
            // scheitern. Weitermachen hieße, eine Lücke ins Transkript zu
            // schreiben, die niemand sieht — der Aufrufer kann dagegen auf das
            // lokale Modell ausweichen oder den Auftrag später wiederholen.
            let teil = try await transcribeWindow(Array(samples[f.range]), language: language)
            if !teil.text.isEmpty { texte.append(teil.text) }
            segmente += teil.segments.map {
                TranscriptSegment(text: $0.text,
                                  start: $0.start + f.offsetSeconds,
                                  end: $0.end + f.offsetSeconds)
            }
            let sekunden = Double(f.range.count) / Double(sampleRate)
            sentSeconds += sekunden
            onSeconds?(sekunden)
        }

        return SpeechResult(text: texte.joined(separator: " "), segments: segmente)
    }

    /// EIN Fenster.
    ///
    /// Zuerst mit `verbose_json` — nur so kommen Zeitmarken zurück, und ohne die
    /// gibt es keine Untertitel. Lehnt der Anbieter das Format ab (manche
    /// neueren Modelle können nur `json`), wird EINMAL mit `json` wiederholt;
    /// dann entsteht ein Ersatzsegment über die ganze Länge.
    private func transcribeWindow(_ samples: [Float],
                                  language: String?) async throws -> SpeechResult {
        do {
            return try await upload(samples, language: language, verbose: true)
        } catch let error as RemoteProviderError {
            guard case .http(let status) = error, status == 400 else { throw error }
            return try await upload(samples, language: language, verbose: false)
        }
    }

    private func upload(_ samples: [Float], language: String?,
                        verbose: Bool) async throws -> SpeechResult {
        guard let url = config.audioURL else { throw RemoteProviderError.invalidBaseURL }
        let dauer = Double(samples.count) / Double(sampleRate)

        var felder: [(String, String)] = [
            ("model", config.model),
            ("response_format", verbose ? "verbose_json" : "json"),
        ]
        // Ohne Sprache erkennt der Anbieter selbst — genau wie lokal bei „auto".
        if let language { felder.append(("language", language)) }

        let grenze = "shout-\(UUID().uuidString)"
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("multipart/form-data; boundary=\(grenze)",
                         forHTTPHeaderField: "Content-Type")
        if let key { request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization") }
        request.httpBody = Self.multipartBody(boundary: grenze, fields: felder,
                                              wav: WAVEncoder.data(from: samples,
                                                                   sampleRate: sampleRate))

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw RemoteHTTP.translate(error)
        }

        let http = response as? HTTPURLResponse
        try RemoteHTTP.check(status: http?.statusCode ?? 0, body: data,
                             headers: http?.allHeaderFields ?? [:], model: config.model)

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let text = json["text"] as? String
        else { throw RemoteProviderError.malformedResponse }

        let sauber = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let segmente = Self.segments(from: json, fallbackText: sauber, duration: dauer)
        return SpeechResult(text: sauber, segments: segmente)
    }

    /// Segmente aus der Antwort — oder ein Ersatzsegment über die ganze Länge.
    ///
    /// Das Ersatzsegment ist eine bewusste Notlösung: Diktat und `.txt`
    /// funktionieren damit weiter, `.srt`-Untertitel und die Sprechertrennung
    /// werden unbrauchbar. Die Oberfläche sagt das an der Vorlage; still eine
    /// falsche Zeitmarke zu liefern wäre schlimmer.
    static func segments(from json: [String: Any], fallbackText: String,
                         duration: Double) -> [TranscriptSegment] {
        if let rohe = json["segments"] as? [[String: Any]], !rohe.isEmpty {
            let segmente = rohe.compactMap { eintrag -> TranscriptSegment? in
                guard let text = (eintrag["text"] as? String)?
                        .trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty,
                      let start = eintrag["start"] as? Double,
                      let end = eintrag["end"] as? Double
                else { return nil }
                return TranscriptSegment(text: text, start: start, end: end)
            }
            if !segmente.isEmpty { return segmente }
        }
        guard !fallbackText.isEmpty else { return [] }
        return [TranscriptSegment(text: fallbackText, start: 0, end: duration)]
    }

    /// Baut den Multipart-Rumpf. Die Datei kommt zuletzt, damit ein Anbieter, der
    /// den Strom mitlesend auswertet, das Modell schon kennt, wenn die Bytes
    /// eintreffen.
    static func multipartBody(boundary: String, fields: [(String, String)],
                              wav: Data, filename: String = "audio.wav") -> Data {
        var body = Data()
        func append(_ text: String) { body.append(contentsOf: Array(text.utf8)) }

        for (name, value) in fields {
            append("--\(boundary)\r\n")
            append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
            append("\(value)\r\n")
        }
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n")
        append("Content-Type: audio/wav\r\n\r\n")
        body.append(wav)
        append("\r\n--\(boundary)--\r\n")
        return body
    }
}
