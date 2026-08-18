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

    /// „Aufwärmen": ein Ein-Token-Durchlauf, damit die Metal-Pipeline kompiliert
    /// ist und die erste echte Aufbereitung nicht spürbar länger dauert.
    func warmUp() async {
        guard isReady, let container else { return }
        let session = ChatSession(container, instructions: "Antworte knapp.",
                                  generateParameters: GenerateParameters(maxTokens: 1))
        _ = try? await session.respond(to: "Hallo")
    }

    // MARK: - Formatierung

    /// Liefert bereinigten Text — oder den (getrimmten) Rohtext bei kurzem
    /// Diktat, noch nicht geladenem Modell oder jedem Fehler.
    ///
    /// Lange Diktate laufen abschnittsweise durchs Modell (Schnitt an
    /// Satzgrenzen via `TextChunker`): Das kleine quantisierte Modell lässt bei
    /// langen Eingaben sonst still Inhalt weg — typisch fehlt hinten ein ganzes
    /// Stück. Nebeneffekt: Der Kürzungs-Schutz prüft jeden Abschnitt einzeln.
    /// Vorher fiel erst ein Gesamtverlust von ~45 % auf; ein verschlucktes
    /// letztes Drittel rutschte durch. Jetzt fällt ein leerer oder stark
    /// gekürzter Abschnitt immer auf und wird durch seinen Rohtext ersetzt.
    func format(_ raw: String, bundleID: String?, termHint: String? = nil) async -> String {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isReady, container != nil else { return text }
        guard text.count >= config.minCharsForFormatting else { return text }

        let parts = TextChunker.chunks(of: text)
        var pieces: [String] = []
        for part in parts {
            pieces.append(await formatChunk(part, bundleID: bundleID, termHint: termHint))
        }
        let joined = TextChunker.joinFormatted(pieces)
        return joined.isEmpty ? text : joined
    }

    /// Formatiert EINEN Abschnitt. Bei leerer/verdächtiger Ausgabe oder Fehler
    /// kommt der Rohtext des Abschnitts zurück — nie stiller Inhaltsverlust.
    private func formatChunk(_ text: String, bundleID: String?, termHint: String?) async -> String {
        guard let container else { return text }
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
            // nicht zusammenfassen. Verliert die Ausgabe fast die Hälfte der
            // Wörter, ist etwas schiefgelaufen → lieber den Rohtext einfügen als
            // still Inhalt verlieren. (Füllwort-Entfernung und Listen-Umbau
            // kosten legitim ~20–30 %, nie annähernd 45 %.)
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

    // MARK: - Protokoll aus einem Transkript

    /// Macht aus einem Datei-Transkript ein Protokoll: Zusammenfassung, Kernpunkte,
    /// darunter der gegliederte Volltext. Gibt `nil` zurück, wenn kein Modell geladen
    /// ist oder nichts Brauchbares herauskam.
    ///
    /// `nil` statt des Rohtexts ist Absicht: Wer den Rohtext zurückbekommt, sieht in
    /// der Oberfläche zwei identische Fassungen und hält das für ein kaputtes
    /// Protokoll. Ohne Modell gibt es eben nur den Rohtext, und die Oberfläche sagt das.
    ///
    /// Zwei Stufen, weil eine Stunde Transkript in kein Kontextfenster passt:
    /// 1. Je Abschnitt: Überschrift, ein paar Kernpunkte, geglätteter Text.
    /// 2. Aus allen Kernpunkten und Überschriften eine Zusammenfassung.
    func minutes(from raw: String, termHint: String? = nil,
                 onProgress: (@Sendable (Double) -> Void)? = nil) async -> String? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isReady, container != nil, !text.isEmpty else { return nil }

        // Größere Abschnitte als beim Diktat: Das Modell soll hier gliedern und
        // verdichten, nicht Wort für Wort putzen — und jeder Aufruf kostet Zeit.
        let parts = TextChunker.chunks(of: text, targetLength: 3000, minLength: 2000)
        guard !parts.isEmpty else { return nil }

        // Stufe 1 macht den Löwenanteil der Arbeit — 90 % des Fortschritts.
        var sections: [TranscriptMinutes.Section] = []
        for (i, part) in parts.enumerated() {
            guard let answer = await respond(system: sectionPrompt(termHint: termHint),
                                             user: part, temperature: 0.3) else { continue }
            var section = TranscriptMinutes.parseSection(answer)
            // Hat das Modell den Text verschluckt, ist der Abschnitt des Transkripts
            // besser als gar nichts.
            if section.text.isEmpty { section.text = part }
            sections.append(section)
            onProgress?(Double(i + 1) / Double(parts.count) * 0.9)
        }
        guard !sections.isEmpty else { return nil }

        let points = TranscriptMinutes.collectPoints(from: sections)
        let summary = await summarize(sections: sections, points: points) ?? ""
        onProgress?(1)

        let document = TranscriptMinutes.assemble(
            summary: summary, points: points, sections: sections,
            headings: await Self.headings())
        return document.isEmpty ? nil : document
    }

    /// Stufe 2: aus Überschriften und Kernpunkten eine kurze Zusammenfassung.
    /// Nur die Punkte, nicht der Volltext — sonst platzt das Kontextfenster wieder.
    private func summarize(sections: [TranscriptMinutes.Section], points: [String]) async -> String? {
        let overview = sections.compactMap(\.title).map { "- \($0)" }.joined(separator: "\n")
            + "\n" + points.map { "- \($0)" }.joined(separator: "\n")
        guard overview.count > 20 else { return nil }
        let system = """
        Du fasst ein Besprechungs- oder Gesprächsprotokoll zusammen. Du bekommst die \
        Themen und Kernpunkte, nicht den Volltext.
        Regeln:
        - Antworte in derselben Sprache wie die Eingabe.
        - Drei bis fünf Sätze Fließtext, keine Aufzählung, keine Überschrift.
        - Nur zusammenfassen, was dasteht. Nichts hinzuerfinden, nicht bewerten.
        Gib AUSSCHLIESSLICH die Zusammenfassung aus.
        """
        return await respond(system: system, user: overview, temperature: 0.3)
    }

    private func sectionPrompt(termHint: String?) -> String {
        let terms = termHint.map {
            "\n- Eigennamen/Fachbegriffe EXAKT so schreiben: \($0)."
        } ?? ""
        return """
        Du machst aus einem automatisch erstellten Transkript ein lesbares Protokoll. \
        Du bekommst einen Abschnitt des Transkripts.

        Regeln:\(terms)
        - Antworte in exakt derselben Sprache wie die Eingabe.
        - Erfinde nichts dazu. Was nicht im Abschnitt steht, kommt nicht ins Protokoll.
        - Entferne Füllwörter, Wiederholungen, Versprecher und Erkennungsfehler-Reste.
        - Fasse zusammengehörende Sätze zu Absätzen zusammen und formuliere sie flüssig.
        - Kürze Geplauder ohne Inhalt weg.

        Antworte GENAU in diesem Format:
        TITEL: <kurze Überschrift für diesen Abschnitt, höchstens sieben Wörter>
        PUNKTE:
        - <die wichtigsten Aussagen, Entscheidungen oder Aufgaben, ein bis vier Stichpunkte>
        TEXT:
        <der aufbereitete Abschnitt in Absätzen>
        """
    }

    /// Ein Aufruf ans Modell. Ohne den Kürzungs-Schutz aus `format` — der ist fürs
    /// Diktat gedacht und würde hier JEDE Zusammenfassung verwerfen, weil sie
    /// naturgemäß deutlich kürzer ist als die Eingabe.
    private func respond(system: String, user: String, temperature: Float) async -> String? {
        guard let container else { return nil }
        do {
            let session = ChatSession(container, instructions: system,
                                      generateParameters: GenerateParameters(temperature: temperature))
            let out = stripArtifacts(try await session.respond(to: user))
            return out.isEmpty ? nil : out
        } catch {
            NSLog("shout: Protokoll-Aufruf fehlgeschlagen: \(error)")
            return nil
        }
    }

    @MainActor
    private static func headings() -> TranscriptMinutes.Headings {
        TranscriptMinutes.Headings(summary: Loc.t("Zusammenfassung"),
                                   points: Loc.t("Kernpunkte"),
                                   body: Loc.t("Protokoll"))
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
