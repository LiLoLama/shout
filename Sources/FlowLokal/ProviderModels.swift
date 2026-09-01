import Foundation

/// Holt die Modell-Liste eines Anbieters — **nur auf Knopfdruck**, nie von
/// selbst. Die App soll nicht im Hintergrund ins Netz telefonieren; das gilt
/// hier genauso wie bei der Hugging-Face-Liste in der Modell-Ansicht.
enum ProviderModels {

    /// `GET /v1/models`. Liefert die IDs, alphabetisch.
    ///
    /// Bewusst nur die IDs: Die Antworten der Anbieter unterscheiden sich in
    /// allem außer `data[].id`, und mehr braucht die Auswahl nicht. Preise stehen
    /// dort ohnehin fast nie.
    static func fetch(config: RemoteConfig,
                      key: String?,
                      needsKey: Bool,
                      session: URLSession = .shared,
                      timeout: TimeInterval = 20) async throws -> [String] {
        guard let url = config.modelsURL else { throw RemoteProviderError.invalidBaseURL }
        if needsKey, key == nil { throw RemoteProviderError.missingKey }

        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        if let key { request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization") }

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
              let entries = json["data"] as? [[String: Any]]
        else { throw RemoteProviderError.malformedResponse }

        let ids = entries.compactMap { $0["id"] as? String }.filter { !$0.isEmpty }
        guard !ids.isEmpty else { throw RemoteProviderError.malformedResponse }
        return ids.sorted()
    }
}

/// „Verbindung testen".
///
/// Prüft über die Modell-Liste, nicht über einen Probe-Aufruf ans Modell: Das
/// kostet nichts, geht schnell, und es prüft genau die drei Dinge, die
/// schiefgehen — Adresse, Schlüssel, und ob das eingetragene Modell dort
/// überhaupt existiert. Ein Chat-Aufruf würde Geld kosten und über die Adresse
/// nicht mehr aussagen.
enum ProviderProbe {

    enum Result: Equatable {
        /// Verbindung steht. `modelListed` ist `nil`, wenn der Anbieter keine
        /// brauchbare Liste liefert — dann ist über das Modell nichts bekannt,
        /// und das darf die Oberfläche nicht als „alles gut" ausgeben.
        case ok(seconds: Double, modelListed: Bool?)
        case failed(RemoteProviderError)
    }

    static func run(config: RemoteConfig,
                    key: String?,
                    needsKey: Bool,
                    session: URLSession = .shared,
                    now: () -> Date = Date.init) async -> Result {
        let start = now()
        do {
            let ids = try await ProviderModels.fetch(config: config, key: key,
                                                     needsKey: needsKey, session: session)
            let dauer = now().timeIntervalSince(start)
            return .ok(seconds: dauer, modelListed: ids.contains(config.model))
        } catch let error as RemoteProviderError {
            // Kein `/models`-Endpunkt heißt nicht, dass der Anbieter kaputt ist —
            // manche bieten nur die Chat-Adresse an. Dann ist die Verbindung
            // grundsätzlich in Ordnung, über das Modell wissen wir aber nichts.
            if case .http(let status) = error, status == 404 {
                return .ok(seconds: now().timeIntervalSince(start), modelListed: nil)
            }
            if case .malformedResponse = error {
                return .ok(seconds: now().timeIntervalSince(start), modelListed: nil)
            }
            return .failed(error)
        } catch {
            return .failed(.malformedResponse)
        }
    }
}
