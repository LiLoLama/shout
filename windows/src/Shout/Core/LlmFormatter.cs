namespace Shout.Core;

/// <summary>
/// Die Aufbereitung — Prompts, Abschnitte, Antwort-Schutz, Protokoll und
/// Sprachprofil. Router über einer <see cref="ITextEngine"/>: Ob dahinter
/// llama.cpp auf diesem Gerät steckt oder ein selbst gewählter Anbieter, spielt
/// hier keine Rolle (Mac: Formatter.swift).
///
/// <para>Grundprinzip unverändert: NIEMALS blockieren. Ist keine Engine bereit, das
/// Diktat zu kurz oder tritt ein Fehler auf, kommt der Rohtext zurück.</para>
///
/// <para>Weil die Engine ausgetauscht wird und nicht der Router, greifen
/// <see cref="FormattingGuard"/> und <see cref="TextChunker"/> automatisch auch
/// bei Cloud-Modellen: Ein Anbieter-Modell, das auf das Diktat antwortet statt es
/// zu formatieren, wird genauso verworfen wie ein lokales.</para>
/// </summary>
public sealed class LlmFormatter : IDisposable
{
    /// <summary>Diktate kürzer als das fügen wir roh ein (spart Latenz und, beim
    /// Anbieter, Geld).</summary>
    private const int MinCharsForFormatting = 40;

    private readonly Func<ITextEngine> build;
    private ITextEngine engine;

    /// <param name="build">Woher die Engine kommt. Vorgabe ist die Fabrik, die die
    /// Einstellung „auf diesem Gerät" gegen „Anbieter" liest; für Tests einsetzbar.</param>
    public LlmFormatter(Func<ITextEngine>? build = null)
    {
        this.build = build ?? EngineFactory.Text;
        engine = this.build();
    }

    public bool IsReady => engine.IsReady;

    /// <summary>Was in der Oberfläche steht, z. B. „Qwen 2.5 (3B)" oder
    /// „gpt-5-mini · OpenAI".</summary>
    public string DisplayName => engine.DisplayName;

    /// <summary>Lädt bzw. verbindet. <paramref name="reset"/> baut die Engine neu —
    /// nötig, wenn der Nutzer zwischen Gerät und Anbieter gewechselt hat.</summary>
    public async Task LoadAsync(Action<double>? onProgress = null, bool reset = false,
                                CancellationToken cancel = default)
    {
        if (reset)
        {
            var old = engine;
            engine = build();
            old.Dispose();
        }
        await engine.PrepareAsync(onProgress, cancel);
    }

    public Task WarmUpAsync(CancellationToken cancel = default) => engine.WarmUpAsync(cancel);

    /// <summary>
    /// Liefert bereinigten Text — oder den (getrimmten) Rohtext bei kurzem Diktat,
    /// fehlender Engine oder jedem Fehler.
    ///
    /// <para><paramref name="appHint"/> ist der Name des Programms, in das eingefügt
    /// wird; daraus entsteht der Register-Hinweis (E-Mail formell, Chat knapp,
    /// Terminal wörtlich).</para>
    /// </summary>
    public async Task<string> FormatAsync(string raw, string? termHint,
                                          string? appHint = null,
                                          CancellationToken cancel = default)
    {
        var text = raw.Trim();
        if (!engine.IsReady) return text;
        if (text.Length < MinCharsForFormatting) return text;

        var parts = TextChunker.Chunks(text, engine.ChunkTargetLength, engine.ChunkMinLength);
        if (parts.Count == 0) return text;

        var pieces = new List<string>(parts.Count);
        foreach (var part in parts)
            pieces.Add(await FormatChunkAsync(part, termHint, appHint, cancel));

        var joined = TextChunker.JoinFormatted(pieces);
        return joined.Length == 0 ? text : joined;
    }

    /// <summary>Formatiert EINEN Abschnitt. Bei leerer, fremder oder verschluckter
    /// Ausgabe kommt der Rohtext des Abschnitts zurück — nie stiller Inhaltsverlust.</summary>
    private async Task<string> FormatChunkAsync(string text, string? termHint, string? appHint,
                                                CancellationToken cancel)
    {
        var cleaned = await RespondAsync(FormatterPrompt.System(appHint, termHint),
                                         FormatterPrompt.User(text), 0.2f, 1024, cancel);
        if (cleaned == null) return text;

        cleaned = FormatterPrompt.StripMarkers(cleaned);
        if (cleaned.Length == 0) return text;

        // Netz hinter dem Prompt: Hat das Modell geantwortet statt formatiert, oder
        // den Text verschluckt, ist der Rohtext besser als eine fremde Ausgabe.
        var verdict = FormattingGuard.Check(text, cleaned);
        if (verdict.IsOk) return cleaned;

        StoreIO.Log(verdict.Verdict == FormattingGuard.Verdict.Unrelated
            ? $"Aufbereitung verworfen: nur {verdict.InputSharePercent} % der Ausgabe stammen aus dem Diktat"
            : $"Aufbereitung verworfen: {verdict.InWords} → {verdict.OutWords} Wörter");
        return text;
    }

    /// <summary>
    /// „Dein Sprachprofil": beschreibt den Diktierstil aus einer Textprobe
    /// (Mac: Formatter.describeVoice). Liefert null, wenn keine Engine bereit ist
    /// oder etwas schiefgeht — die Statistik-Seite zeigt dann einen Hinweis.
    /// Anders als <see cref="FormatAsync"/> gilt hier KEINE Mindestlänge; die Probe
    /// kommt aus dem Verlauf und ist ohnehin lang.
    /// </summary>
    public async Task<string?> DescribeVoiceAsync(string sample, CancellationToken cancel = default)
    {
        var text = sample.Trim();
        if (!engine.IsReady || text.Length == 0) return null;
        // Wärmer als die Bereinigung (0,2): hier soll ein lesbarer Absatz
        // entstehen, keine wortgetreue Umschrift.
        return await RespondAsync(VoicePrompt(), text, 0.6f, 260, cancel);
    }

    /// <summary>
    /// Macht aus einem Datei-Transkript ein Protokoll: Zusammenfassung, Kernpunkte,
    /// darunter der gegliederte Volltext (Mac: Formatter.minutes).
    ///
    /// <para>Liefert <c>null</c>, wenn keine Engine bereit ist oder nichts Brauchbares
    /// herauskam. Bewusst null statt des Rohtexts: Wer den Rohtext zurückbekommt,
    /// sieht in der Oberfläche zwei identische Fassungen und hält das für ein
    /// kaputtes Protokoll.</para>
    ///
    /// <para>Zwei Stufen, weil eine Stunde Transkript in kein Kontextfenster passt:
    /// je Abschnitt Überschrift, Kernpunkte und geglätteter Text; danach aus allen
    /// Kernpunkten eine Zusammenfassung.</para>
    /// </summary>
    public async Task<string?> MinutesAsync(string raw, string? termHint,
                                            Action<double>? onProgress = null,
                                            CancellationToken cancel = default)
    {
        var text = raw.Trim();
        if (!engine.IsReady || text.Length == 0) return null;

        // Größere Abschnitte als beim Diktat: Das Modell soll hier gliedern und
        // verdichten, nicht Wort für Wort putzen — und jeder Aufruf kostet Zeit.
        var parts = TextChunker.Chunks(text, engine.ChunkTargetLength * 2, engine.ChunkMinLength * 2);
        if (parts.Count == 0) return null;

        var sections = new List<TranscriptMinutes.Section>();
        for (var i = 0; i < parts.Count; i++)
        {
            cancel.ThrowIfCancellationRequested();
            var answer = await RespondAsync(SectionPrompt(termHint), parts[i], 0.3f, 1536, cancel);
            if (answer == null) continue;
            var section = TranscriptMinutes.ParseSection(answer);
            // Hat das Modell den Text verschluckt, ist der Abschnitt des Transkripts
            // besser als gar nichts.
            if (section.Text.Length == 0) section.Text = parts[i];
            sections.Add(section);
            onProgress?.Invoke((i + 1) / (double)parts.Count * 0.9);
        }
        if (sections.Count == 0) return null;

        var points = TranscriptMinutes.CollectPoints(sections);
        var summary = await SummarizeAsync(sections, points, cancel) ?? "";
        onProgress?.Invoke(1);

        var headings = new TranscriptMinutes.Headings(
            Loc.T("Zusammenfassung"), Loc.T("Kernpunkte"), Loc.T("Protokoll"));
        var document = TranscriptMinutes.Assemble(summary, points, sections, headings);
        return document.Length == 0 ? null : document;
    }

    /// <summary>Stufe 2: aus Überschriften und Kernpunkten eine kurze Zusammenfassung.
    /// Nur die Punkte, nicht der Volltext — sonst platzt das Kontextfenster wieder.</summary>
    private async Task<string?> SummarizeAsync(List<TranscriptMinutes.Section> sections,
                                               List<string> points, CancellationToken cancel)
    {
        var overview = string.Join("\n", sections.Where(s => s.Title != null).Select(s => $"- {s.Title}"))
                     + "\n" + string.Join("\n", points.Select(p => $"- {p}"));
        if (overview.Trim().Length <= 20) return null;

        const string system = """
        Du fasst ein Besprechungs- oder Gesprächsprotokoll zusammen. Du bekommst die Themen und Kernpunkte, nicht den Volltext.
        Regeln:
        - Antworte in derselben Sprache wie die Eingabe.
        - Drei bis fünf Sätze Fließtext, keine Aufzählung, keine Überschrift.
        - Nur zusammenfassen, was dasteht. Nichts hinzuerfinden, nicht bewerten.
        Gib AUSSCHLIESSLICH die Zusammenfassung aus.
        """;
        return await RespondAsync(system, overview, 0.3f, 1536, cancel);
    }

    private static string SectionPrompt(string? termHint)
    {
        var terms = termHint != null
            ? $"\n- Eigennamen/Fachbegriffe EXAKT so schreiben: {termHint}."
            : "";
        return $"""
        Du machst aus einem automatisch erstellten Transkript ein lesbares Protokoll. Du bekommst einen Abschnitt des Transkripts.

        Regeln:{terms}
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
        """;
    }

    /// <summary>
    /// Ein Aufruf an die Engine, mit Zeitgrenze und ohne den Kürzungs-Schutz aus
    /// <see cref="FormatChunkAsync"/> — der ist fürs Diktat gedacht und würde hier
    /// JEDE Zusammenfassung verwerfen, weil sie naturgemäß kürzer ist als die Eingabe.
    /// Liefert null bei jedem Fehler; der Aufrufer entscheidet, was das bedeutet.
    /// </summary>
    private async Task<string?> RespondAsync(string system, string user, float temperature,
                                             int maxTokens, CancellationToken cancel)
    {
        try
        {
            // Beim Diktat KEIN Wiederholungsversuch: Der Mensch steht mit dem Finger
            // auf der Taste, und ein zweiter Anlauf verdoppelt die Wartezeit, statt
            // sie zu retten.
            var raw = await WithDeadline(engine.CallTimeoutSeconds, cancel,
                token => engine.RespondAsync(system, user, temperature, maxTokens, token));
            var cleaned = StripArtifacts(raw);
            return cleaned.Length == 0 ? null : cleaned;
        }
        catch (OperationCanceledException) when (cancel.IsCancellationRequested)
        {
            throw;
        }
        catch (Exception ex)
        {
            StoreIO.Log($"Aufbereitung fehlgeschlagen: {Describe(ex)}");
            return null;
        }
    }

    /// <summary>Fehlertext fürs Protokoll — bei einem Anbieter die knappe Form ohne
    /// Schlüssel und ohne Antwortrumpf.</summary>
    private static string Describe(Exception ex)
        => ex is RemoteProviderException remote ? remote.LogDescription : ex.Message;

    /// <summary>
    /// Führt den Aufruf aus und bricht nach <paramref name="seconds"/> ab. Bei 0
    /// läuft er ohne Grenze — so verhält sich das lokale Modell weiter wie bisher.
    /// </summary>
    private static async Task<string> WithDeadline(double seconds, CancellationToken cancel,
                                                   Func<CancellationToken, Task<string>> operation)
    {
        if (seconds <= 0) return await operation(cancel);

        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(cancel);
        timeout.CancelAfter(TimeSpan.FromSeconds(seconds));
        try
        {
            return await operation(timeout.Token);
        }
        catch (OperationCanceledException) when (!cancel.IsCancellationRequested)
        {
            throw new RemoteProviderException(RemoteFailure.TimedOut);
        }
    }

    /// <summary>Der Profiltext steht in der Oberfläche, folgt also der
    /// Oberflächensprache — nicht der Diktier-Sprache.</summary>
    private static string VoicePrompt() => Loc.IsGerman
        ? """
        Du analysierst den Sprach- und Diktierstil einer Person anhand ihrer Diktate. Beschreibe den Stil in 2–3 knappen, wohlwollenden deutschen Sätzen und sprich die Person mit „Du" an (z. B. Wortwahl, Tempo, Struktur, typische Muster). Keine Aufzählung, kein Vorwort, keine Anführungszeichen — nur die Beschreibung.
        """
        : """
        You analyse how a person speaks and dictates, based on their dictations. Describe the style in 2 to 3 short, kind English sentences and address the person as "you" (for example word choice, pace, structure, recurring patterns). No list, no preamble, no quotation marks, just the description.
        """;

    /// <summary>Manche Modelle verpacken die Antwort in ```-Blöcke — auspacken.
    /// Außerdem das Anti-Prompt-Token abschneiden, falls es mitkommt.</summary>
    private static string StripArtifacts(string s)
    {
        var t = s.Replace("<|im_end|>", "").Trim();
        if (t.StartsWith("```"))
        {
            var firstNewline = t.IndexOf('\n');
            if (firstNewline >= 0) t = t[(firstNewline + 1)..];
            var lastFence = t.LastIndexOf("```", StringComparison.Ordinal);
            if (lastFence >= 0) t = t[..lastFence];
            t = t.Trim();
        }
        return t;
    }

    public void Dispose() => engine.Dispose();
}
