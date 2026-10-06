import Foundation
import OSLog

/// Warum ein Transform nichts geliefert hat. Der Text der Notiz bleibt dann, wie er war.
enum TransformError: Error, Equatable {
    case noModel
    case tooLong
    case emptyResult
    case timedOut
    /// Kurzform fürs Log (`RemoteProviderError.logDescription` o. ä.).
    case failed(String)
}

/// Der Formatting-Layer (v3): **Router** über einem austauschbaren Textmodell.
/// Ob das Modell im eigenen Prozess läuft (`LocalTextEngine`, MLX auf Apple
/// Silicon) oder bei einem selbst gewählten Anbieter (`RemoteTextEngine`), weiß
/// diese Klasse nicht — sie kennt nur `TextEngine.respond`.
///
/// Alles Anbieterunabhängige lebt hier: Prompts, Abschnittsbildung, der
/// Kürzungs-Schutz, die Protokoll-Erzeugung, das Sprachprofil. Damit greifen
/// `FormattingGuard` und `TextChunker` automatisch auch bei Cloud-Modellen — ein
/// Cloud-Modell, das auf das Diktat *antwortet* statt es zu formatieren, wird
/// genauso verworfen wie ein lokales.
///
/// Grundprinzip unverändert: **niemals blockieren.** Ist das Modell noch nicht
/// geladen, das Diktat zu kurz oder tritt ein Fehler auf, kommt der Rohtext zurück.
actor Formatter {

    /// Abfragbar per `log show --predicate 'subsystem == "com.inthezone.flowlokal"'`.
    private static let log = Logger(subsystem: "com.inthezone.flowlokal", category: "aufbereitung")

    struct Config {
        /// Diktate kürzer als das fügen wir roh ein (spart LLM-Latenz).
        var minCharsForFormatting = 40
    }

    private let config: Config

    /// Baut das Modell. Als Closure hereingegeben, damit diese Datei die
    /// konkreten Engines nicht kennt und damit keinen MLX-Bezug hat — nur so
    /// liegt der Router im Testziel und ist überhaupt prüfbar. Die Auswahl
    /// (lokal oder Anbieter) trifft `EngineFactory`.
    private let makeEngine: @Sendable () -> any TextEngine
    private var engine: (any TextEngine)?

    /// Verkettung aller Lade-Operationen. Actors sind am `await` reentrant — ein
    /// zweiter load()/reload() würde sonst PARALLEL denselben Multi-GB-Download
    /// starten. Jede Operation wartet daher zuerst auf die vorherige.
    private var loadChain: Task<Void, Never>?

    /// Eigener Ladezustand des Routers: deckt das Fenster ab, in dem die Engine
    /// gerade erst gebaut wird und ihr eigenes `isLoading` noch `false` steht.
    private var routerLoading = false

    init(config: Config = Config(), makeEngine: @escaping @Sendable () -> any TextEngine) {
        self.config = config
        self.makeEngine = makeEngine
    }

    // MARK: - Zustand für die Oberfläche

    var isReady: Bool {
        get async { await engine?.isReady ?? false }
    }

    var isLoading: Bool {
        get async {
            // Kein `||`: dessen rechte Seite ist eine nonisolated Autoclosure und
            // verträgt kein `await`.
            if routerLoading { return true }
            return await engine?.isLoading ?? false
        }
    }

    var activeModelName: String {
        get async {
            guard let engine, await engine.isReady else { return "—" }
            return await engine.displayName
        }
    }

    // MARK: - Modell laden

    /// Lädt das aktuell gewählte Modell. Serialisiert über `loadChain` — kein
    /// paralleler Doppel-Load.
    func load(onProgress: (@Sendable (Double) -> Void)? = nil) async {
        await enqueue(reset: false, onProgress: onProgress)
    }

    /// Wechselt zur Laufzeit auf das aktuell gewählte Modell (erzwingt Neuladen).
    /// Baut die Engine neu, weil sich nicht nur das Modell, sondern die **Art**
    /// geändert haben kann (lokal ↔ Anbieter).
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
        routerLoading = true
        defer { routerLoading = false }
        if reset || engine == nil { engine = makeEngine() }
        await engine?.prepare(reset: reset, onProgress: onProgress)
    }

    func warmUp() async {
        await engine?.warmUp()
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
    ///
    /// Wie groß die Abschnitte sein dürfen, sagt die Engine: ein Modell mit
    /// großem Kontextfenster verträgt mehr, und jeder Aufruf an einen Anbieter
    /// kostet Zeit und Geld.
    func format(_ raw: String, bundleID: String?, termHint: String? = nil) async -> String {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let engine, await engine.isReady else { return text }
        guard text.count >= config.minCharsForFormatting else { return text }

        let parts = TextChunker.chunks(of: text,
                                       targetLength: await engine.chunkTargetLength,
                                       minLength: await engine.chunkMinLength)
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
        guard let engine else { return text }
        do {
            let system = FormatterPrompt.system(for: bundleID, termHint: termHint)
            let user = FormatterPrompt.user(for: text)
            // Beim Diktat KEIN Wiederholungsversuch: Der Mensch steht mit dem
            // Finger auf der Taste, und ein zweiter Anlauf verdoppelt die
            // Wartezeit, statt sie zu retten.
            let out = try await withDeadline(await engine.callTimeout) {
                try await engine.respond(system: system, user: user, temperature: 0.2)
            }
            let cleaned = stripArtifacts(out)
            guard !cleaned.isEmpty else { return text }

            // Netz: Hat das Modell geantwortet statt formatiert, oder den Text
            // verschluckt, ist der Rohtext besser als eine fremde Ausgabe.
            switch FormattingGuard.check(input: text, output: cleaned) {
            case .unrelated(let share):
                Self.log.warning("Aufbereitung verworfen: nur \(share) % der Ausgabe stammen aus dem Diktat")
                return text
            case .truncated(let inWords, let outWords):
                Self.log.warning("Aufbereitung verworfen: \(inWords) → \(outWords) Wörter")
                return text
            case .ok:
                return cleaned
            }
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
        guard let engine, await engine.isReady, !text.isEmpty else { return nil }

        // Größere Abschnitte als beim Diktat: Das Modell soll hier gliedern und
        // verdichten, nicht Wort für Wort putzen — und jeder Aufruf kostet Zeit.
        // Das Doppelte dessen, was die Engine fürs Diktat verträgt.
        let parts = TextChunker.chunks(of: text,
                                       targetLength: await engine.chunkTargetLength * 2,
                                       minLength: await engine.chunkMinLength * 2)
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
    /// Die Zeitgrenze für Hintergrundarbeit — Protokolle und Sprachprofil.
    ///
    /// Achtfach die Diktat-Grenze (bei einem Anbieter: 15 s → 120 s). Das ist
    /// kein runder Daumenwert: Die Abschnitte sind hier doppelt so groß, das
    /// Modell soll gliedern statt putzen, und niemand wartet mit dem Finger auf
    /// der Taste. Lokal bleibt es bei `nil`, also ohne Grenze.
    private func backgroundTimeout(_ engine: any TextEngine) async -> TimeInterval? {
        await engine.callTimeout.map { $0 * 8 }
    }

    private func respond(system: String, user: String, temperature: Float) async -> String? {
        guard let engine else { return nil }
        let deadline = await backgroundTimeout(engine)

        // EIN Wiederholungsversuch, und nur bei Ursachen, die von selbst
        // weggehen. Das läuft im Hintergrund, da ist ein zweiter Anlauf billiger
        // als ein fehlender Protokollabschnitt. Bei einem Ratenlimit wird die
        // vom Anbieter genannte Wartezeit eingehalten, höchstens aber 10 s —
        // länger würde die Warteschlange stehen.
        for versuch in 0...1 {
            do {
                let out = stripArtifacts(try await withDeadline(deadline) {
                    try await engine.respond(system: system, user: user, temperature: temperature)
                })
                return out.isEmpty ? nil : out
            } catch {
                let fehler = error as? RemoteProviderError
                guard versuch == 0, fehler?.isTransient == true else {
                    NSLog("shout: Protokoll-Aufruf fehlgeschlagen: \(fehler?.logDescription ?? "\(error)")")
                    return nil
                }
                if case .rateLimited(let after) = fehler, let after {
                    try? await Task.sleep(nanoseconds: UInt64(min(after, 10) * 1_000_000_000))
                }
            }
        }
        return nil
    }

    @MainActor
    private static func headings() -> TranscriptMinutes.Headings {
        TranscriptMinutes.Headings(summary: Loc.t("Zusammenfassung"),
                                   points: Loc.t("Kernpunkte"),
                                   body: Loc.t("Protokoll"))
    }

    // MARK: - Sprachprofil („Your Voice")

    /// Lässt das Modell den Sprach-/Diktierstil in 2–3 knappen deutschen Sätzen
    /// beschreiben.
    func describeVoice(from sample: String) async -> String? {
        guard let engine, await engine.isReady else { return nil }
        let system = """
        Du analysierst den Sprach- und Diktierstil einer Person anhand ihrer Diktate. \
        Beschreibe den Stil in 2–3 knappen, wohlwollenden deutschen Sätzen und sprich die \
        Person mit „Du" an (z. B. Wortwahl, Tempo, Struktur, typische Muster). \
        Keine Aufzählung, kein Vorwort, keine Anführungszeichen — nur die Beschreibung.
        """
        return await respond(system: system, user: sample, temperature: 0.6)
    }

    /// Arbeitet `text` nach `instruction` um (Zauberstab im Scratchpad). Kein
    /// `FormattingGuard` — eine abweichende Antwort ist hier gewollt. Ein zweiter
    /// Versuch nur bei vorübergehenden Fehlern, Zeitlimit wie bei der Hintergrundarbeit.
    func transform(_ text: String, instruction: String) async throws -> String {
        guard let engine, await engine.isReady else { throw TransformError.noModel }
        guard text.count <= TransformPrompt.maxLength else { throw TransformError.tooLong }
        let system = TransformPrompt.system(instruction: instruction)
        let user = TransformPrompt.user(for: text)
        let deadline = await backgroundTimeout(engine)
        for versuch in 0...1 {
            do {
                let roh = try await withDeadline(deadline) {
                    try await engine.respond(system: system, user: user, temperature: 0.3)
                }
                try Task.checkCancellation()
                let ergebnis = TransformPrompt.clean(roh)
                guard !ergebnis.isEmpty else { throw TransformError.emptyResult }
                return ergebnis
            } catch is CancellationError {
                throw CancellationError()
            } catch let fehler as RemoteProviderError where versuch == 0 && fehler.isTransient {
                try Task.checkCancellation()
                if case .rateLimited(let after) = fehler, let after {
                    try await Task.sleep(nanoseconds: UInt64(min(after, 10) * 1_000_000_000))
                }
            } catch let fehler as RemoteProviderError {
                if Task.isCancelled { throw CancellationError() }
                throw fehler == .timedOut ? TransformError.timedOut : TransformError.failed(fehler.logDescription)
            } catch let fehler as TransformError {
                throw fehler
            } catch {
                if Task.isCancelled { throw CancellationError() }
                throw TransformError.failed(String(describing: error))
            }
        }
        throw TransformError.timedOut
    }

    /// Manche Modelle verpacken die Antwort in ```-Blöcke oder Anführungszeichen.
    private func stripArtifacts(_ s: String) -> String {
        var t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        // Hat das Modell die Markierungen mitgeschrieben, gilt nur, was dazwischen steht.
        if let begin = t.range(of: FormatterPrompt.transcriptBegin) {
            t = String(t[begin.upperBound...])
        }
        if let end = t.range(of: FormatterPrompt.transcriptEnd) {
            t = String(t[..<end.lowerBound])
        }
        t = t.trimmingCharacters(in: .whitespacesAndNewlines)
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
