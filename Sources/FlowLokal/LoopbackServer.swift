import Foundation
import Network

/// Nimmt genau einen Rückruf aus dem Browser entgegen — auf `127.0.0.1`, nie
/// auf einer anderen Schnittstelle, und nur so lange, wie eine Anmeldung läuft.
///
/// Kein HTTP-Server im eigentlichen Sinn: Es wird die erste Zeile der Anfrage
/// gelesen, eine kurze Seite zurückgegeben und die Verbindung geschlossen. Mehr
/// braucht der Rückruf nicht, und weniger Code heißt hier weniger Angriffsfläche.
///
/// Der gesamte Zustand lebt auf `queue`; deshalb `@unchecked Sendable`.
final class LoopbackServer: @unchecked Sendable {

    private(set) var port: UInt16 = 0
    private let path: String
    private let page: String
    private let queue = DispatchQueue(label: "com.inthezone.flowlokal.loopback")
    private var listener: NWListener?
    private var ergebnis: Result<[URLQueryItem], Error>?
    private var wartender: CheckedContinuation<[URLQueryItem], Error>?

    private init(path: String, page: String) {
        self.path = path
        self.page = page
    }

    /// Startet den Listener — zuerst auf `preferredPort`, ist der belegt, auf
    /// einem freien. Kehrt erst zurück, wenn er wirklich lauscht: OpenAI
    /// verlangt, dass der Rückruf bereitsteht, bevor der Browser aufgeht.
    static func start(preferredPort: UInt16, path: String, page: String) async throws -> LoopbackServer {
        let server = LoopbackServer(path: path, page: page)
        for kandidat in [preferredPort, 0] {
            if try await server.listen(on: kandidat) { return server }
        }
        throw ChatGPTAuthError.listenerFailed
    }

    private func listen(on port: UInt16) async throws -> Bool {
        let parameter = NWParameters.tcp
        parameter.requiredLocalEndpoint = .hostPort(host: "127.0.0.1",
                                                    port: NWEndpoint.Port(rawValue: port) ?? .any)
        let listener: NWListener
        do { listener = try NWListener(using: parameter) } catch { return false }

        listener.newConnectionHandler = { [weak self] verbindung in self?.annehmen(verbindung) }

        let bereit: Bool = await withCheckedContinuation { fortsetzung in
            // Der Handler meldet sich danach weiter (etwa beim Beenden); er wird
            // deshalb nach der ersten Antwort abgehängt, sonst liefe die
            // Fortsetzung zweimal.
            listener.stateUpdateHandler = { zustand in
                switch zustand {
                case .ready:
                    listener.stateUpdateHandler = nil
                    fortsetzung.resume(returning: true)
                case .failed, .cancelled:
                    listener.stateUpdateHandler = nil
                    fortsetzung.resume(returning: false)
                default: break
                }
            }
            listener.start(queue: queue)
        }
        guard bereit, let echt = listener.port?.rawValue else {
            listener.cancel()
            return false
        }
        queue.sync {
            self.listener = listener
            self.port = echt
        }
        return true
    }

    /// Wartet auf den Rückruf und liefert dessen Query-Parameter.
    func waitForCallback(timeout: TimeInterval) async throws -> [URLQueryItem] {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { fortsetzung in
                queue.async {
                    if let ergebnis = self.ergebnis {
                        fortsetzung.resume(with: ergebnis)
                    } else {
                        self.wartender = fortsetzung
                    }
                }
                queue.asyncAfter(deadline: .now() + timeout) {
                    self.liefern(.failure(ChatGPTAuthError.timedOut))
                }
            }
        } onCancel: {
            queue.async { self.liefern(.failure(ChatGPTAuthError.cancelled)) }
        }
    }

    func stop() {
        queue.async {
            self.listener?.cancel()
            self.listener = nil
        }
    }

    // MARK: - Auf `queue`

    /// Nur das erste Ergebnis zählt — ein zweiter Rückruf (Neuladen im
    /// Browser) oder die Zeitgrenze danach ändern nichts mehr.
    private func liefern(_ neu: Result<[URLQueryItem], Error>) {
        guard ergebnis == nil else { return }
        ergebnis = neu
        wartender?.resume(with: neu)
        wartender = nil
    }

    private func annehmen(_ verbindung: NWConnection) {
        verbindung.start(queue: queue)
        lesen(verbindung, puffer: Data())
    }

    private func lesen(_ verbindung: NWConnection, puffer: Data) {
        verbindung.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1024) {
            [weak self] daten, _, fertig, fehler in
            guard let self else { verbindung.cancel(); return }
            var gesamt = puffer
            if let daten { gesamt.append(daten) }

            let ende = gesamt.range(of: Data("\r\n\r\n".utf8))
            if ende == nil, !fertig, fehler == nil, gesamt.count < 64 * 1024 {
                self.lesen(verbindung, puffer: gesamt)
                return
            }
            self.beantworten(verbindung, anfrage: gesamt)
        }
    }

    private func beantworten(_ verbindung: NWConnection, anfrage: Data) {
        let zeile = String(decoding: anfrage, as: UTF8.self)
            .split(separator: "\r\n", maxSplits: 1).first.map(String.init) ?? ""
        let teile = zeile.split(separator: " ")
        let ziel = teile.count >= 2 && teile[0] == "GET" ? String(teile[1]) : ""
        let comps = URLComponents(string: "http://127.0.0.1" + ziel)

        let treffer = comps?.path == path
        let status = treffer ? "200 OK" : "404 Not Found"
        let rumpf = treffer ? page : ""
        let antwort = "HTTP/1.1 \(status)\r\n"
            + "Content-Type: text/html; charset=utf-8\r\n"
            + "Content-Length: \(Data(rumpf.utf8).count)\r\n"
            + "Cache-Control: no-store\r\n"
            + "Connection: close\r\n\r\n" + rumpf
        verbindung.send(content: Data(antwort.utf8), completion: .contentProcessed { _ in
            verbindung.cancel()
        })
        if treffer { liefern(.success(comps?.queryItems ?? [])) }
    }
}
