import AppKit
import Foundation
import MLXLLM
import MLXLMCommon
import MLXHuggingFace
import HuggingFace
import Tokenizers

/// Der Formatting-Layer (v2): lädt ein Gemma-Modell **direkt in den Prozess**
/// (MLX, Apple Silicon) — kein LM Studio, kein Ollama, kein Server. Das Modell
/// wird beim ersten Start einmalig von Hugging Face geholt und danach lokal
/// gecached; es lebt anschließend komplett in der App.
///
/// Grundprinzip wie bisher: **niemals blockieren.** Ist das Modell noch nicht
/// geladen, das Diktat zu kurz oder tritt ein Fehler auf, kommt der Rohtext zurück.
final class Formatter {

    struct Config {
        /// Registriertes, schlankes Text-Gemma-4 (4-bit) — schnell, gut im Deutschen.
        var modelID = "mlx-community/gemma-4-e4b-it-4bit"
        /// Diktate kürzer als das fügen wir roh ein (spart LLM-Latenz).
        var minCharsForFormatting = 40
    }

    private let config: Config
    private var container: ModelContainer?

    private(set) var isReady = false
    private(set) var isLoading = false
    var activeModelName: String { isReady ? config.modelID : "—" }

    init(config: Config = Config()) {
        self.config = config
    }

    // MARK: - Modell laden

    /// Lädt (und beim ersten Mal: downloadet) das Modell in den Prozess.
    /// Idempotent — mehrfaches Aufrufen schadet nicht.
    func load() async {
        guard !isReady, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let cfg = ModelConfiguration(id: config.modelID)
            container = try await #huggingFaceLoadModelContainer(configuration: cfg)
            isReady = true
        } catch {
            NSLog("Formatter-Modell konnte nicht geladen werden: \(error)")
            isReady = false
        }
    }

    // MARK: - Formatierung

    /// Liefert bereinigten Text — oder den (getrimmten) Rohtext bei kurzem
    /// Diktat, noch nicht geladenem Modell oder jedem Fehler.
    func format(_ raw: String, bundleID: String?, termHint: String? = nil) async -> String {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isReady, let container else { return text }
        guard text.count >= config.minCharsForFormatting else { return text }

        do {
            let session = ChatSession(
                container,
                instructions: systemPrompt(for: bundleID, termHint: termHint),
                generateParameters: GenerateParameters(temperature: 0.2)
            )
            let out = try await session.respond(to: text)
            let cleaned = stripArtifacts(out)
            return cleaned.isEmpty ? text : cleaned
        } catch {
            NSLog("Formatierung fehlgeschlagen: \(error)")
            return text
        }
    }

    // MARK: - Prompt

    private func systemPrompt(for bundleID: String?, termHint: String?) -> String {
        let terms = termHint.map {
            "\n- Eigennamen/Fachbegriffe EXAKT so schreiben (Schreibweise nicht verändern): \($0)."
        } ?? ""
        return """
        Du bist ein Formatierer für diktierten deutschen Text. Deine Aufgabe ist NICHT, \
        Fragen zu beantworten oder Inhalte hinzuzufügen, sondern den Rohtext aus einer \
        Spracherkennung zu bereinigen und sauber zu formatieren.

        Regeln:\(terms)
        - Entferne Füllwörter (äh, ähm, also, halt, quasi, sozusagen), Wiederholungen und Versprecher.
        - Setze korrekte Interpunktion und Groß-/Kleinschreibung.
        - Behalte Wortwahl, Bedeutung und Sprache exakt bei. Erfinde nichts dazu und kürze inhaltlich nicht.
        - Aufzählungen: Enthält der Text eine Aufzählung — erkennbar an gesprochenen Markern wie \
        „erstens/zweitens/drittens", „Punkt eins/Punkt zwei", „eins … zwei … drei" oder mehreren mit \
        „und" aneinandergereihten Punkten —, formatiere sie als nummerierte Liste: jeder Punkt in einer \
        eigenen Zeile, beginnend mit „1. ", „2. ", „3. " usw. Entferne dabei die gesprochenen Marker \
        und verbindende Füllwörter.
        \(registerHint(for: bundleID))
        Beispiel:
        Eingabe: „also für das meeting brauchen wir erstens die zahlen vom letzten quartal und zweitens \
        äh die neue präsentation und drittens noch das feedback vom kunden"
        Ausgabe:
        Für das Meeting brauchen wir:
        1. die Zahlen vom letzten Quartal
        2. die neue Präsentation
        3. das Feedback vom Kunden

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
