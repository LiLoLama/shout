import Foundation

/// Fängt HTTP-Aufrufe im Test ab, damit die Anbieter-Engines ohne Netz und ohne
/// Schlüssel prüfbar sind.
///
/// Bewusst über `URLProtocol` statt über eine eigene Netz-Abstraktion: So läuft
/// im Test genau der Code, der später auch echte Anfragen stellt — inklusive
/// Kopfzeilen, Rumpf und Statusauswertung. Eine selbstgebaute Abstraktion würde
/// gerade den Teil überspringen, in dem die Fehler stecken.
final class StubURLProtocol: URLProtocol {

    struct Antwort {
        var status: Int = 200
        var body: Data = Data()
        var headers: [String: String] = ["Content-Type": "application/json"]
        /// Statt einer Antwort ein Fehler (z. B. Zeitüberschreitung).
        var error: Error?
    }

    /// Was auf die nächste Anfrage geantwortet wird. Mehrere Einträge werden der
    /// Reihe nach abgearbeitet — für die Fensterung langer Aufnahmen.
    nonisolated(unsafe) static var antworten: [Antwort] = []
    /// Alle gestellten Anfragen, in Reihenfolge. Der Rumpf wird mitgeschnitten,
    /// weil `URLProtocol` ihn sonst verwirft.
    nonisolated(unsafe) static var anfragen: [(request: URLRequest, body: Data)] = []

    static func reset() {
        antworten = []
        anfragen = []
    }

    /// Die Sitzung, die durch diese Attrappe läuft.
    static func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: config)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        // `httpBody` ist bei URLSession-Aufrufen leer, der Rumpf kommt als Strom.
        var body = request.httpBody ?? Data()
        if body.isEmpty, let stream = request.httpBodyStream {
            stream.open()
            let size = 64 * 1024
            var buffer = [UInt8](repeating: 0, count: size)
            while stream.hasBytesAvailable {
                let read = stream.read(&buffer, maxLength: size)
                if read <= 0 { break }
                body.append(contentsOf: buffer[0..<read])
            }
            stream.close()
        }
        Self.anfragen.append((request, body))

        let antwort = Self.antworten.isEmpty ? Antwort() : Self.antworten.removeFirst()

        if let error = antwort.error {
            client?.urlProtocol(self, didFailWithError: error)
            return
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: antwort.status,
                                       httpVersion: "HTTP/1.1", headerFields: antwort.headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: antwort.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

// MARK: - Hilfsmittel für die Tests

extension StubURLProtocol.Antwort {

    /// Eine gültige Chat-Antwort mit Token-Zahlen.
    static func chatAntwort(_ inhalt: String, promptTokens: Int = 120,
                            completionTokens: Int = 40) -> Self {
        let json = """
        {"id":"x","object":"chat.completion",
         "choices":[{"index":0,"message":{"role":"assistant","content":\(quote(inhalt))},
                     "finish_reason":"stop"}],
         "usage":{"prompt_tokens":\(promptTokens),"completion_tokens":\(completionTokens),
                  "total_tokens":\(promptTokens + completionTokens)}}
        """
        return Self(body: Data(json.utf8))
    }

    static func fehlerAntwort(status: Int, message: String = "",
                              headers: [String: String] = [:]) -> Self {
        let json = """
        {"error":{"message":\(quote(message)),"type":"invalid_request_error"}}
        """
        var alle = ["Content-Type": "application/json"]
        alle.merge(headers) { _, neu in neu }
        return Self(status: status, body: Data(json.utf8), headers: alle)
    }

    private static func quote(_ s: String) -> String {
        let data = try? JSONSerialization.data(withJSONObject: [s], options: [])
        guard let data, let text = String(data: data, encoding: .utf8) else { return "\"\"" }
        return String(text.dropFirst().dropLast())   // ["…"] → "…"
    }
}
