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
            factory?.Dispose();
            factory = WhisperFactory.FromPath(ModelCatalog.PathFor(model));
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
        try { _ = await TranscribeAsync(new float[16_000], null); }
        catch { /* Warm-up darf still scheitern */ }
    }

    /// <summary>
    /// Transkribiert 16-kHz-Mono-Samples. <paramref name="biasTerms"/> (das
    /// persönliche Wörterbuch) geht als Initial-Prompt an Whisper — bekannte
    /// Eigennamen werden dadurch deutlich öfter richtig geschrieben.
    /// </summary>
    public async Task<string> TranscribeAsync(float[] samples, IReadOnlyList<string>? biasTerms,
                                              CancellationToken cancel = default)
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

            if (biasTerms is { Count: > 0 })
                builder = builder.WithPrompt(string.Join(", ", biasTerms));

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

    public void Dispose()
    {
        factory?.Dispose();
        factory = null;
    }
}
