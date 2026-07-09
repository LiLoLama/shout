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
actor Formatter {

    struct Config {
        /// Diktate kürzer als das fügen wir roh ein (spart LLM-Latenz).
        var minCharsForFormatting = 40
    }

    private let config: Config
    private var container: ModelContainer?

    /// Gewähltes Formatierungs-Modell aus den Einstellungen (Modell-Empfehler).
    private var modelID: String {
        UserDefaults.standard.string(forKey: "formatModel") ?? ModelCatalog.defaultFormatting
    }

    private(set) var isReady = false
    private(set) var isLoading = false
    private(set) var loadedModel: String?
    var activeModelName: String { isReady ? (loadedModel ?? modelID) : "—" }

    /// Verkettung aller Lade-Operationen. Actors sind am `await` reentrant — ein
    /// zweiter load()/reload() würde sonst PARALLEL denselben Multi-GB-Download
    /// starten. Jede Operation wartet daher zuerst auf die vorherige.
    private var loadChain: Task<Void, Never>?

    init(config: Config = Config()) {
        self.config = config
    }

    // MARK: - Modell laden

    /// Lädt (und beim ersten Mal: downloadet) das aktuell gewählte Modell in den
    /// Prozess. Serialisiert über `loadChain` — kein paralleler Doppel-Load.
    func load(onProgress: (@Sendable (Double) -> Void)? = nil) async {
        await enqueue(reset: false, onProgress: onProgress)
    }

    /// Wechselt zur Laufzeit auf das aktuell gewählte Modell (erzwingt Neuladen).
    func reload(onProgress: (@Sendable (Double) -> Void)? = nil) async {
        await enqueue(reset: true, onProgress: onProgress)
    }

    private func enqueue(reset: Bool, onProgress: (@Sendable (Double) -> Void)?) async {
        let previous = loadChain
        let task = Task { [self] in
            await previous?.value            // strikt nach der vorherigen Operation
            await performLoad(reset: reset, onProgress: onProgress)
        }
        loadChain = task
        await task.value
    }

    private func performLoad(reset: Bool, onProgress: (@Sendable (Double) -> Void)?) async {
        let id = modelID
        if !reset, isReady, loadedModel == id { return }  // schon das richtige Modell geladen
        isLoading = true
        isReady = false
        loadedModel = nil
        container = nil
        defer { isLoading = false }
        do {
            let cfg = ModelConfiguration(id: id)
            container = try await #huggingFaceLoadModelContainer(configuration: cfg) { progress in
                onProgress?(progress.fractionCompleted)
            }
            loadedModel = id
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
            guard !cleaned.isEmpty else { return text }

            // Kürzungs-Schutz: Das (kleine, quantisierte) Modell soll bereinigen,
            // nicht zusammenfassen. Verliert die Ausgabe bei längeren Diktaten
            // fast die Hälfte der Wörter, ist etwas schiefgelaufen → lieber den
            // Rohtext einfügen als still Inhalt verlieren. (Füllwort-Entfernung
            // und Listen-Umbau kosten legitim ~20–30 %, nie annähernd 45 %.)
            let inWords = text.split(whereSeparator: \.isWhitespace).count
            let outWords = cleaned.split(whereSeparator: \.isWhitespace).count
            if inWords >= 30, outWords * 100 < inWords * 55 {
                NSLog("shout: Formatter-Ausgabe verdächtig kurz (%d→%d Wörter) → Rohtext eingefügt", inWords, outWords)
                return text
            }
            return cleaned
        } catch {
            NSLog("Formatierung fehlgeschlagen: \(error)")
            return text
        }
    }

    // MARK: - Sprachprofil („Your Voice")

    /// Lässt Gemma den Sprach-/Diktierstil in 2–3 knappen deutschen Sätzen beschreiben.
    func describeVoice(from sample: String) async -> String? {
        guard isReady, let container else { return nil }
        let system = """
        Du analysierst den Sprach- und Diktierstil einer Person anhand ihrer Diktate. \
        Beschreibe den Stil in 2–3 knappen, wohlwollenden deutschen Sätzen und sprich die \
        Person mit „Du" an (z. B. Wortwahl, Tempo, Struktur, typische Muster). \
        Keine Aufzählung, kein Vorwort, keine Anführungszeichen — nur die Beschreibung.
        """
        do {
            let session = ChatSession(container, instructions: system,
                                      generateParameters: GenerateParameters(temperature: 0.6))
            let out = try await session.respond(to: sample)
            return stripArtifacts(out)
        } catch {
            return nil
        }
    }

    // MARK: - Prompt

    private func systemPrompt(for bundleID: String?, termHint: String?) -> String {
        let terms = termHint.map {
            "\n- Eigennamen/Fachbegriffe EXAKT so schreiben (Schreibweise nicht verändern): \($0)."
        } ?? ""
        #if os(iOS)
        // Bewusst KOMPAKT: Auf der iPhone-GPU dominiert das Prompt-Prefill die
        // Latenz — der ausführliche macOS-Prompt (Beispiel, App-Register) würde
        // die Aufbereitung um Sekunden verlangsamen.
        return """
        Du bereinigst diktierten Text (Deutsch oder Englisch). Antworte in derselben Sprache wie die Eingabe.
        Regeln:\(terms)
        - Füllwörter (äh, ähm, also, halt; en: uh, um), Wiederholungen und Versprecher entfernen.
        - Korrekte Interpunktion und Groß-/Kleinschreibung setzen.
        - Wortlaut und Bedeutung exakt beibehalten; nichts hinzufügen, nichts kürzen.
        - Gesprochene Aufzählungen („erstens/zweitens", „Punkt eins") als nummerierte Liste formatieren.
        Gib AUSSCHLIESSLICH den bereinigten Text aus.
        """
        #else
        return """
        Du bist ein Formatierer für diktierten Text (meist Deutsch oder Englisch). Deine Aufgabe ist NICHT, \
        Fragen zu beantworten oder Inhalte hinzuzufügen, sondern den Rohtext aus einer \
        Spracherkennung zu bereinigen und sauber zu formatieren.

        Regeln:\(terms)
        - Antworte in exakt derselben Sprache wie die Eingabe.
        - Entferne Füllwörter (äh, ähm, also, halt, quasi, sozusagen; en: uh, um, like, you know), Wiederholungen und Versprecher.
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
        #endif
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
