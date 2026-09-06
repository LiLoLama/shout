using System.Text;
using Whisper.net;

namespace Shout.Core;

/// <summary>
/// Spracherkennung auf diesem Gerät — whisper.cpp über Whisper.net. Das ist der
/// Teil, der vorher direkt in <see cref="Transcriber"/> stand; herausgelöst,
/// damit derselbe Router auch einen Anbieter bedienen kann (Mac:
/// LocalSpeechEngine.swift).
/// </summary>
public sealed class LocalSpeechEngine : ISpeechEngine
{
    private WhisperFactory? factory;
    private string? loadedModel;
    private readonly SemaphoreSlim gate = new(1, 1);
    private readonly bool allowDownload;

    /// <param name="allowDownload">
    /// false für den Ersatz-Erkenner, der einspringt, wenn der Anbieter scheitert:
    /// Ein 1,6-GB-Download mitten im Diktat wäre keine Rettung, sondern eine
    /// zweite Panne.
    /// </param>
    public LocalSpeechEngine(bool allowDownload = true) => this.allowDownload = allowDownload;

    public bool IsReady => factory != null;
    public string? LoadedModel => loadedModel;

    public string DisplayName =>
        (loadedModel is { } id ? ModelCatalog.AsrById(id)?.Name : null)
        ?? ModelCatalog.RecommendedAsr().Name;

    public async Task PrepareAsync(Action<double>? onProgress = null, CancellationToken cancel = default)
    {
        var model = ModelCatalog.AsrById(Settings.Shared.AsrModel) ?? ModelCatalog.RecommendedAsr();
        await gate.WaitAsync(cancel);
        try
        {
            if (loadedModel == model.Id && factory != null) return;
            if (!allowDownload && !ModelCatalog.IsDownloaded(model))
                throw new InvalidOperationException(
                    $"Ersatz-Erkenner: {model.Id} liegt nicht im Cache.");

            await ModelDownloader.DownloadAsync(model, onProgress, cancel);

            // Das neue Modell ZUERST öffnen, das alte erst danach wegwerfen.
            // Andersherum stünde die App nach einem gescheiterten Wechsel ganz ohne
            // Spracherkennung da, obwohl das vorherige Modell noch auf der Platte
            // liegt — die Oberfläche kann so auf den alten Stand zurückfallen.
            var next = WhisperFactory.FromPath(ModelCatalog.PathFor(model));
            factory?.Dispose();
            factory = next;
            loadedModel = model.Id;
        }
        finally
        {
            gate.Release();
        }
    }

    /// <summary>„Aufwärmen": ein kurzer Durchlauf mit Stille, damit das erste
    /// echte Diktat nicht spürbar länger dauert.</summary>
    public async Task WarmUpAsync(CancellationToken cancel = default)
    {
        if (factory == null) return;
        try { _ = await TranscribeAsync(new float[16_000], Settings.Shared.Language, cancel); }
        catch { /* Warm-up darf still scheitern */ }
    }

    /// <summary>
    /// Transkribiert 16-kHz-Mono-Samples und liefert beide Formen in EINEM Durchlauf.
    ///
    /// <para>Fertiger Text und Segmente sind nicht dasselbe: Der Text hängt die
    /// Segmente roh aneinander, die Segmente sind von Steuermarken befreit und
    /// tragen ihre Zeitmarken. Zweimal zu erkennen, nur um beides zu haben, wäre
    /// bei einer Stunde Audio die doppelte Rechenzeit.</para>
    ///
    /// <para>BEWUSST OHNE Wörterbuch-Prompt (<c>WithPrompt</c>): Whisper behandelt ihn
    /// als vorangehenden Text und überspringt dann Audio — am Mac am 19./21.08.2026
    /// nachgewiesen, wo dieselbe Stelle denselben Fehler hatte: derselbe
    /// Sample-Puffer ergab mit Prompt &lt; 178 Zeichen, ohne 773; einem
    /// 104-Sekunden-Diktat fehlten ~45 % seines Anfangs. Schon sechs Begriffe
    /// reichten, und der Prompt fährt in JEDEM 30-Sekunden-Fenster erneut mit.
    /// Eigennamen richtet stattdessen das Wörterbuch nach der Erkennung.</para>
    /// </summary>
    public async Task<SpeechResult> TranscribeAsync(float[] samples, string? language,
                                                    CancellationToken cancel = default)
    {
        if (factory == null) throw new InvalidOperationException("Modell ist nicht geladen.");
        if (samples.Length == 0) return SpeechResult.Empty;

        await gate.WaitAsync(cancel);
        try
        {
            var builder = factory.CreateBuilder();
            builder = language is null or "auto"
                ? builder.WithLanguageDetection()
                : builder.WithLanguage(language);

            await using var processor = builder.Build();
            var text = new StringBuilder();
            var segments = new List<TranscriptSegment>();

            await foreach (var segment in processor.ProcessAsync(samples, cancel))
            {
                text.Append(segment.Text);
                var clean = TranscriptLayout.StripSpecialTokens(segment.Text);
                if (clean.Length == 0) continue;
                segments.Add(new TranscriptSegment(clean,
                                                   segment.Start.TotalSeconds,
                                                   segment.End.TotalSeconds));
            }

            return new SpeechResult { Text = text.ToString().Trim(), Segments = segments };
        }
        finally
        {
            gate.Release();
        }
    }

    public void Dispose()
    {
        factory?.Dispose();
        factory = null;
        gate.Dispose();
    }
}
