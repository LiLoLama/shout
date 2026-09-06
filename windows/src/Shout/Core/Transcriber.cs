namespace Shout.Core;

/// <summary>
/// Die Spracherkennung — Router über einer <see cref="ISpeechEngine"/>. Ob
/// dahinter whisper.cpp auf diesem Gerät steckt oder ein selbst gewählter
/// Anbieter, entscheidet die Einstellung (Mac: Transcriber.swift).
///
/// <para>Alles, was nicht die Erkennung selbst ist, liegt hier: die Sprachwahl aus
/// den Einstellungen und der Rückfall auf ein vorhandenes lokales Modell, wenn der
/// Anbieter scheitert. Damit gilt beides für jeden Erkenner.</para>
/// </summary>
public sealed class Transcriber : IDisposable
{
    private readonly Func<ISpeechEngine> build;
    private readonly Func<ISpeechEngine?> buildFallback;
    private ISpeechEngine engine;
    private ISpeechEngine? fallback;

    /// <param name="build">Woher die Engine kommt — Vorgabe ist die Fabrik, die die
    /// Einstellung „auf diesem Gerät" gegen „Anbieter" liest.</param>
    /// <param name="buildFallback">Ersatz-Erkenner für den Fall, dass der Anbieter
    /// scheitert. Liefert null, wenn ohnehin lokal gearbeitet wird.</param>
    public Transcriber(Func<ISpeechEngine>? build = null, Func<ISpeechEngine?>? buildFallback = null)
    {
        this.build = build ?? EngineFactory.Speech;
        this.buildFallback = buildFallback ?? EngineFactory.SpeechFallback;
        engine = this.build();
    }

    public bool IsReady => engine.IsReady;
    public string? LoadedModel => engine.LoadedModel;

    /// <summary>Was in der Oberfläche steht, z. B. „Whisper Small" oder
    /// „whisper-large-v3 · Groq".</summary>
    public string DisplayName => engine.DisplayName;

    /// <summary>Diktier-Sprache aus den Einstellungen; null heißt „selbst erkennen".</summary>
    private static string? Language
    {
        get
        {
            var language = Settings.Shared.Language;
            return string.IsNullOrEmpty(language) || language == "auto" ? null : language;
        }
    }

    /// <summary>Lädt bzw. verbindet. <paramref name="reset"/> baut die Engine neu —
    /// nötig, wenn zwischen Gerät und Anbieter gewechselt wurde.</summary>
    public async Task LoadAsync(Action<double>? onProgress = null, bool reset = false,
                                CancellationToken cancel = default)
    {
        if (reset)
        {
            var old = engine;
            engine = build();
            fallback = null;
            old.Dispose();
        }
        await engine.PrepareAsync(onProgress, cancel);
    }

    public Task WarmUpAsync(CancellationToken cancel = default) => engine.WarmUpAsync(cancel);

    /// <summary>Fertiger Text fürs Diktat.</summary>
    public async Task<string> TranscribeAsync(float[] samples, CancellationToken cancel = default)
        => (await RecognizeAsync(samples, cancel)).Text;

    /// <summary>Wie <see cref="TranscribeAsync"/>, liefert aber die Abschnitte mit
    /// Zeitmarken — Grundlage für Untertitel und die Gliederung bei der
    /// Datei-Transkription.</summary>
    public async Task<List<TranscriptSegment>> TranscribeSegmentsAsync(
        float[] samples, CancellationToken cancel = default)
        => (await RecognizeAsync(samples, cancel)).Segments;

    /// <summary>
    /// Erkennt — und weicht bei einem Fehler des Anbieters auf ein vorhandenes
    /// lokales Modell aus.
    ///
    /// <para>Scheitert auch der Rückfall, wird der URSPRÜNGLICHE Fehler geworfen:
    /// „Schlüssel abgelehnt" hilft weiter, „lokales Modell nicht im Cache" führt in
    /// die Irre — das lokale Modell war ja nie die Absicht des Nutzers.</para>
    /// </summary>
    private async Task<SpeechResult> RecognizeAsync(float[] samples, CancellationToken cancel)
    {
        if (samples.Length == 0) return SpeechResult.Empty;
        try
        {
            return await engine.TranscribeAsync(samples, Language, cancel);
        }
        catch (Exception original)
        {
            if (cancel.IsCancellationRequested) throw;

            var spare = Fallback();
            if (spare == null) throw;

            StoreIO.Log($"Erkennung beim Anbieter fehlgeschlagen ({Describe(original)}), " +
                        "lokales Modell übernimmt");
            try
            {
                if (!spare.IsReady) await spare.PrepareAsync(cancel: cancel);
                return await spare.TranscribeAsync(samples, Language, cancel);
            }
            catch
            {
                // Bewusst der ursprüngliche Fehler: Sonst stünde in der Oberfläche
                // „lokales Modell nicht im Cache" statt „Schlüssel abgelehnt".
                throw original;
            }
        }
    }

    /// <summary>Ersatz-Erkenner, einmal gebaut und behalten — ihn bei jedem
    /// Fehlschlag neu aufzubauen hieße, das Modell jedes Mal neu einzulesen.</summary>
    private ISpeechEngine? Fallback() => fallback ??= buildFallback();

    private static string Describe(Exception ex)
        => ex is RemoteProviderException remote ? remote.LogDescription : ex.Message;

    public void Dispose()
    {
        engine.Dispose();
        fallback?.Dispose();
        fallback = null;
    }
}
