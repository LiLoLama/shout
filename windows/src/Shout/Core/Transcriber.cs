using System.Text;
using Whisper.net;

namespace Shout.Core;

/// <summary>
/// Spracherkennung über whisper.cpp (Whisper.net). Das gewählte ggml-Modell
/// wird beim ersten Mal von Hugging Face geladen und lokal gecached — danach
/// läuft alles offline.
/// </summary>
public sealed class Transcriber : IDisposable
{
    private WhisperFactory? factory;
    private string? loadedModel;
    private readonly SemaphoreSlim gate = new(1, 1);

    public bool IsReady => factory != null;
    public string? LoadedModel => loadedModel;

    /// <summary>Lädt (und downloadet ggf.) das in den Einstellungen gewählte Modell.</summary>
    public async Task LoadAsync(Action<double>? onProgress = null, CancellationToken cancel = default)
    {
        var model = ModelCatalog.AsrById(Settings.Shared.AsrModel) ?? ModelCatalog.RecommendedAsr();
        await gate.WaitAsync(cancel);
        try
        {
            if (loadedModel == model.Id && factory != null) return;
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
    public async Task WarmUpAsync()
    {
        if (factory == null) return;
        try { _ = await TranscribeAsync(new float[16_000]); }
        catch { /* Warm-up darf still scheitern */ }
    }

    /// <summary>
    /// Transkribiert 16-kHz-Mono-Samples.
    ///
    /// BEWUSST OHNE Wörterbuch-Prompt (<c>WithPrompt</c>): Whisper behandelt ihn
    /// als vorangehenden Text und überspringt dann Audio — am Mac am 19./21.08.2026
    /// nachgewiesen, wo dieselbe Stelle denselben Fehler hatte: derselbe
    /// Sample-Puffer ergab mit Prompt &lt; 178 Zeichen, ohne 773; einem
    /// 104-Sekunden-Diktat fehlten ~45 % seines Anfangs. Schon sechs Begriffe
    /// reichten, und der Prompt fährt in JEDEM 30-Sekunden-Fenster erneut mit,
    /// weshalb es lange Aufnahmen häufiger trifft. Der Schaden ist nicht
    /// zuverlässig erkennbar (Whisper stempelt den ersten Abschnitt auch nach dem
    /// Überspringen auf 0,00 s), deshalb ist die Ursache entfernt statt abgefedert.
    ///
    /// Eigennamen richtet weiterhin das Wörterbuch: Korrekturen ersetzen nach der
    /// Erkennung, und die Begriffe gehen als TermHint in die Aufbereitung.
    /// </summary>
    public async Task<string> TranscribeAsync(float[] samples, CancellationToken cancel = default)
    {
        if (factory == null) throw new InvalidOperationException("Modell ist nicht geladen.");
        if (samples.Length == 0) return "";

        await gate.WaitAsync(cancel);
        try
        {
            var builder = factory.CreateBuilder();

            var language = Settings.Shared.Language;
            if (language == "auto") builder = builder.WithLanguageDetection();
            else builder = builder.WithLanguage(language);

            await using var processor = builder.Build();
            var text = new StringBuilder();
            await foreach (var segment in processor.ProcessAsync(samples, cancel))
                text.Append(segment.Text);
            return text.ToString().Trim();
        }
        finally
        {
            gate.Release();
        }
    }

    /// <summary>
    /// Wie <see cref="TranscribeAsync"/>, liefert aber die Abschnitte mit Zeitmarken —
    /// Grundlage für Untertitel und die Gliederung bei der Datei-Transkription.
    /// Ebenfalls ohne Wörterbuch-Prompt, aus demselben Grund.
    /// </summary>
    public async Task<List<TranscriptSegment>> TranscribeSegmentsAsync(
        float[] samples, CancellationToken cancel = default)
    {
        if (factory == null) throw new InvalidOperationException("Modell ist nicht geladen.");
        var result = new List<TranscriptSegment>();
        if (samples.Length == 0) return result;

        await gate.WaitAsync(cancel);
        try
        {
            var builder = factory.CreateBuilder();

            var language = Settings.Shared.Language;
            if (language == "auto") builder = builder.WithLanguageDetection();
            else builder = builder.WithLanguage(language);

            await using var processor = builder.Build();
            await foreach (var segment in processor.ProcessAsync(samples, cancel))
            {
                var text = TranscriptLayout.StripSpecialTokens(segment.Text);
                if (text.Length == 0) continue;
                result.Add(new TranscriptSegment(text,
                                                 segment.Start.TotalSeconds,
                                                 segment.End.TotalSeconds));
            }
            return result;
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
    }
}
