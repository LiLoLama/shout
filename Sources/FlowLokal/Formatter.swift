import AppKit
import Foundation

/// Der Formatting-Layer (v1): schickt das Roh-Transkript an einen lokalen,
/// OpenAI-kompatiblen LLM-Server (LM Studio auf :1234 oder Ollama auf :11434)
/// und bekommt bereinigten Text zurück — Füllwörter raus, Interpunktion,
/// Absätze, app-abhängiges Register.
///
/// Grundprinzip: **niemals blockieren.** Ist kein Server da, das Diktat zu
/// kurz, oder tritt ein Fehler auf, geben wir einfach den Rohtext zurück.
final class Formatter {

    struct Config {
        var baseURL = URL(string: "http://localhost:1234/v1")!
        /// Diktate kürzer als das fügen wir roh ein (spart LLM-Latenz).
        var minCharsForFormatting = 40
        var requestTimeout: TimeInterval = 20
    }

    private let config: Config
    private let session: URLSession
    private var modelID: String?

    var isReady: Bool { modelID != nil }
    var activeModelName: String { modelID ?? "—" }

    init(config: Config = Config()) {
        self.config = config
        let sc = URLSessionConfiguration.default
        sc.timeoutIntervalForRequest = config.requestTimeout
        self.session = URLSession(configuration: sc)
    }

    // MARK: - Modell-Discovery

    /// Fragt den Server nach verfügbaren Modellen und wählt bevorzugt Gemma.
    /// Setzt `modelID` (oder nil, wenn kein Server erreichbar ist).
    @discardableResult
    func discoverModel() async -> Bool {
        struct ModelsResponse: Decodable {
            struct M: Decodable { let id: String }
            let data: [M]
        }
        var req = URLRequest(url: config.baseURL.appendingPathComponent("models"))
        req.httpMethod = "GET"

        guard let (data, resp) = try? await session.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let parsed = try? JSONDecoder().decode(ModelsResponse.self, from: data),
              !parsed.data.isEmpty else {
            modelID = nil
            return false
        }
        let ids = parsed.data.map(\.id)
        // Bevorzuge Gemma (stark im Deutschen), sonst das erste verfügbare Modell.
        modelID = ids.first(where: { $0.lowercased().contains("gemma") }) ?? ids.first
        return modelID != nil
    }

    // MARK: - Formatierung

    /// Liefert bereinigten Text — oder den (getrimmten) Rohtext bei kurzem
    /// Diktat, fehlendem Server oder jedem Fehler.
    func format(_ raw: String, bundleID: String?) async -> String {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let modelID else { return text }
        guard text.count >= config.minCharsForFormatting else { return text }

        let body: [String: Any] = [
            "model": modelID,
            "temperature": 0.2,
            "stream": false,
            "messages": [
                ["role": "system", "content": systemPrompt(for: bundleID)],
                ["role": "user", "content": text]
            ]
        ]
        guard let payload = try? JSONSerialization.data(withJSONObject: body) else { return text }

        var req = URLRequest(url: config.baseURL.appendingPathComponent("chat/completions"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = payload

        guard let (data, resp) = try? await session.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200 else { return text }

        struct ChatResponse: Decodable {
            struct Choice: Decodable {
                struct Msg: Decodable { let content: String }
                let message: Msg
            }
            let choices: [Choice]
        }
        guard let parsed = try? JSONDecoder().decode(ChatResponse.self, from: data),
              let out = parsed.choices.first?.message.content else { return text }

        let cleaned = stripArtifacts(out)
        return cleaned.isEmpty ? text : cleaned
    }

    // MARK: - Prompt

    private func systemPrompt(for bundleID: String?) -> String {
        """
        Du bist ein Formatierer für diktierten deutschen Text. Deine Aufgabe ist NICHT, \
        Fragen zu beantworten oder Inhalte hinzuzufügen, sondern den Rohtext aus einer \
        Spracherkennung zu bereinigen:
        - Entferne Füllwörter (äh, ähm, also, halt, quasi, sozusagen), Wiederholungen und Versprecher.
        - Setze korrekte Interpunktion und Groß-/Kleinschreibung.
        - Gliedere in Sätze und Absätze; erkenne Aufzählungen und formatiere sie als Liste.
        - Behalte Wortwahl, Bedeutung und Sprache exakt bei. Erfinde nichts dazu und kürze inhaltlich nicht.
        \(registerHint(for: bundleID))
        Gib AUSSCHLIESSLICH den bereinigten Text aus — keine Erklärung, keine Anführungszeichen, kein Codeblock.
        """
    }

    /// App-abhängiges Register (Wisprs „App-Awareness", lokal über die Bundle-ID).
    private func registerHint(for bundleID: String?) -> String {
        guard let id = bundleID?.lowercased() else { return "" }
        if id.contains("mail") || id.contains("outlook") || id.contains("pages")
            || id.contains("word") || id.contains("docs") || id.contains("notion") {
            return "- Register: formell, vollständige höfliche Sätze (Kontext: E-Mail/Dokument)."
        }
        if id.contains("slack") || id.contains("messages") || id.contains("whatsapp")
            || id.contains("telegram") || id.contains("discord") {
            return "- Register: locker und knapp, wie eine Chat-Nachricht."
        }
        if id.contains("terminal") || id.contains("iterm") || id.contains("xcode")
            || id.contains("code") || id.contains("vscode") {
            return "- Register: technisch; erzwinge keine Interpunktion; lasse Fachbegriffe/Variablennamen wörtlich (Kontext: Terminal/IDE)."
        }
        return ""
    }

    /// Manche Modelle verpacken die Antwort in ```-Blöcke oder Anführungszeichen.
    private func stripArtifacts(_ s: String) -> String {
        var t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.hasPrefix("```") {
            if let firstNewline = t.firstIndex(of: "\n") {
                t = String(t[t.index(after: firstNewline)...])
            }
            if let range = t.range(of: "```", options: .backwards) {
                t = String(t[..<range.lowerBound])
            }
            t = t.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return t
    }
}
