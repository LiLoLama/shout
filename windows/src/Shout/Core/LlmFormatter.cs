using System.Text;
using LLama;
using LLama.Common;
using LLama.Sampling;

namespace Shout.Core;

/// <summary>
/// Optionale KI-Formatierung über llama.cpp (LLamaSharp) — das Windows-Pendant
/// zum MLX-Formatter. Grundprinzip identisch: NIEMALS blockieren. Ist das
/// Modell nicht geladen, das Diktat zu kurz oder tritt ein Fehler auf, kommt
/// der Rohtext zurück.
///
/// Der Katalog enthält bewusst nur Qwen-2.5-Instruct-Modelle, damit EIN
/// Chat-Template (im_start/im_end) für alle Einträge stimmt.
/// </summary>
public sealed class LlmFormatter : IDisposable
{
    /// <summary>Diktate kürzer als das fügen wir roh ein (spart LLM-Latenz).</summary>
    private const int MinCharsForFormatting = 40;

    private LLamaWeights? weights;
    private LLama.Abstractions.ILLamaParams? modelParams;
    private string? loadedModel;
    private readonly SemaphoreSlim gate = new(1, 1);

    public bool IsReady => weights != null;

    /// <summary>Lädt (und downloadet ggf.) das gewählte Formatierungs-Modell.</summary>
    public async Task LoadAsync(Action<double>? onProgress = null, CancellationToken cancel = default)
    {
        var model = ModelCatalog.LlmById(Settings.Shared.LlmModel) ?? ModelCatalog.RecommendedLlm();
        await gate.WaitAsync(cancel);
        try
        {
            if (loadedModel == model.Id && weights != null) return;
            await ModelDownloader.DownloadAsync(model, onProgress, cancel);

            weights?.Dispose();
            var p = new ModelParams(ModelCatalog.PathFor(model))
            {
                ContextSize = 4096,
                GpuLayerCount = 0,   // CPU-Backend; GPU siehe README (Vulkan/CUDA-Pakete)
            };
            weights = await LLamaWeights.LoadFromFileAsync(p, cancel);
            modelParams = p;
            loadedModel = model.Id;
        }
        catch
        {
            weights = null;   // Formatierung fällt dann still auf Rohtext zurück
        }
        finally
        {
            gate.Release();
        }
    }

    /// <summary>Liefert bereinigten Text — oder den (getrimmten) Rohtext bei
    /// kurzem Diktat, fehlendem Modell oder jedem Fehler.</summary>
    public async Task<string> FormatAsync(string raw, string? termHint, CancellationToken cancel = default)
    {
        var text = raw.Trim();
        if (weights == null || modelParams == null) return text;
        if (text.Length < MinCharsForFormatting) return text;

        await gate.WaitAsync(cancel);
        try
        {
            var executor = new StatelessExecutor(weights, modelParams);
            var prompt =
                "<|im_start|>system\n" + SystemPrompt(termHint) + "<|im_end|>\n" +
                "<|im_start|>user\n" + text + "<|im_end|>\n" +
                "<|im_start|>assistant\n";

            var inference = new InferenceParams
            {
                MaxTokens = 1024,
                AntiPrompts = new[] { "<|im_end|>" },
                SamplingPipeline = new DefaultSamplingPipeline { Temperature = 0.2f },
            };

            var output = new StringBuilder();
            await foreach (var token in executor.InferAsync(prompt, inference, cancel))
                output.Append(token);

            var cleaned = StripArtifacts(output.ToString());
            if (cleaned.Length == 0) return text;

            // Kürzungs-Schutz (wie am Mac): das kleine Modell soll bereinigen,
            // nicht zusammenfassen. Verliert die Ausgabe fast die Hälfte der
            // Wörter, lieber den Rohtext einfügen als still Inhalt verlieren.
            var inWords = text.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries).Length;
            var outWords = cleaned.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries).Length;
            if (inWords >= 30 && outWords * 100 < inWords * 55) return text;

            return cleaned;
        }
        catch
        {
            return text;
        }
        finally
        {
            gate.Release();
        }
    }

    /// <summary>
    /// „Dein Sprachprofil": beschreibt den Diktierstil aus einer Textprobe
    /// (Mac: Formatter.describeVoice). Liefert null, wenn kein Modell geladen
    /// ist oder etwas schiefgeht — die Statistik-Seite zeigt dann einen Hinweis.
    /// Anders als FormatAsync gilt hier KEINE Mindestlänge; die Probe kommt aus
    /// dem Verlauf und ist ohnehin lang.
    /// </summary>
    public async Task<string?> DescribeVoiceAsync(string sample, CancellationToken cancel = default)
    {
        var text = sample.Trim();
        if (weights == null || modelParams == null) return null;
        if (text.Length == 0) return null;

        await gate.WaitAsync(cancel);
        try
        {
            var executor = new StatelessExecutor(weights, modelParams);
            var prompt =
                "<|im_start|>system\n" + VoicePrompt() + "<|im_end|>\n" +
                "<|im_start|>user\n" + text + "<|im_end|>\n" +
                "<|im_start|>assistant\n";

            // Wärmer als die Bereinigung (0,2): hier soll ein lesbarer Absatz
            // entstehen, keine wortgetreue Umschrift.
            var inference = new InferenceParams
            {
                MaxTokens = 260,
                AntiPrompts = new[] { "<|im_end|>" },
                SamplingPipeline = new DefaultSamplingPipeline { Temperature = 0.6f },
            };

            var output = new StringBuilder();
            await foreach (var token in executor.InferAsync(prompt, inference, cancel))
                output.Append(token);

            var cleaned = StripArtifacts(output.ToString());
            return cleaned.Length == 0 ? null : cleaned;
        }
        catch
        {
            return null;
        }
        finally
        {
            gate.Release();
        }
    }

    /// <summary>
    /// Macht aus einem Datei-Transkript ein Protokoll: Zusammenfassung, Kernpunkte,
    /// darunter der gegliederte Volltext (Mac: Formatter.minutes).
    ///
    /// <para>Liefert <c>null</c>, wenn kein Modell geladen ist oder nichts Brauchbares
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
        if (weights == null || modelParams == null || text.Length == 0) return null;

        // Größere Abschnitte als beim Diktat: Das Modell soll hier gliedern und
        // verdichten, nicht Wort für Wort putzen — und jeder Aufruf kostet Zeit.
        var parts = TextChunker.Chunks(text, 3000, 2000);
        if (parts.Count == 0) return null;

        var sections = new List<TranscriptMinutes.Section>();
        for (var i = 0; i < parts.Count; i++)
        {
            cancel.ThrowIfCancellationRequested();
            var answer = await RespondAsync(SectionPrompt(termHint), parts[i], 0.3f, cancel);
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
        return await RespondAsync(system, overview, 0.3f, cancel);
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
    /// Ein Aufruf ans Modell. Ohne den Kürzungs-Schutz aus <see cref="FormatAsync"/> —
    /// der ist fürs Diktat gedacht und würde hier JEDE Zusammenfassung verwerfen,
    /// weil sie naturgemäß deutlich kürzer ist als die Eingabe.
    /// </summary>
    private async Task<string?> RespondAsync(string system, string user, float temperature,
                                             CancellationToken cancel)
    {
        if (weights == null || modelParams == null) return null;
        await gate.WaitAsync(cancel);
        try
        {
            var executor = new StatelessExecutor(weights, modelParams);
            var prompt =
                "<|im_start|>system\n" + system + "<|im_end|>\n" +
                "<|im_start|>user\n" + user + "<|im_end|>\n" +
                "<|im_start|>assistant\n";
            var inference = new InferenceParams
            {
                MaxTokens = 1536,
                AntiPrompts = new[] { "<|im_end|>" },
                SamplingPipeline = new DefaultSamplingPipeline { Temperature = temperature },
            };
            var output = new StringBuilder();
            await foreach (var token in executor.InferAsync(prompt, inference, cancel))
                output.Append(token);
            var cleaned = StripArtifacts(output.ToString());
            return cleaned.Length == 0 ? null : cleaned;
        }
        catch (OperationCanceledException)
        {
            throw;
        }
        catch
        {
            return null;
        }
        finally
        {
            gate.Release();
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

    private static string SystemPrompt(string? termHint)
    {
        var terms = termHint != null
            ? $"\n- Eigennamen/Fachbegriffe EXAKT so schreiben (Schreibweise nicht verändern): {termHint}."
            : "";
        // Kompakter Prompt (wie auf iOS): auf CPU dominiert das Prompt-Prefill
        // die Latenz — der lange macOS-Prompt würde spürbar bremsen.
        return $"""
        Du bereinigst diktierten Text (Deutsch oder Englisch). Antworte in derselben Sprache wie die Eingabe.
        Regeln:{terms}
        - Füllwörter (äh, ähm, also, halt; en: uh, um), Wiederholungen und Versprecher entfernen.
        - Korrekte Interpunktion und Groß-/Kleinschreibung setzen.
        - Wortlaut und Bedeutung exakt beibehalten; nichts hinzufügen, nichts kürzen.
        - Gesprochene Aufzählungen („erstens/zweitens", „Punkt eins") als nummerierte Liste formatieren.
        Gib AUSSCHLIESSLICH den bereinigten Text aus.
        """;
    }

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

    public void Dispose()
    {
        weights?.Dispose();
        weights = null;
    }
}
