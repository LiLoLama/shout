using System.Text;
using LLama;
using LLama.Common;
using LLama.Sampling;

namespace Shout.Core;

/// <summary>
/// Das Textmodell auf diesem Gerät — llama.cpp über LLamaSharp. Das ist der Teil,
/// der vorher direkt in <see cref="LlmFormatter"/> stand; herausgelöst, damit
/// derselbe Router auch einen Anbieter bedienen kann (Mac: LocalTextEngine.swift).
///
/// <para>Der Katalog enthält bewusst nur Qwen-2.5-Instruct-Modelle, damit EIN
/// Chat-Template (im_start/im_end) für alle Einträge stimmt.</para>
/// </summary>
public sealed class LocalTextEngine : ITextEngine
{
    private LLamaWeights? weights;
    private LLama.Abstractions.ILLamaParams? modelParams;
    private string? loadedModel;
    private readonly SemaphoreSlim gate = new(1, 1);

    public bool IsReady => weights != null;

    public string DisplayName =>
        (loadedModel is { } id ? ModelCatalog.LlmById(id)?.Name : null)
        ?? ModelCatalog.RecommendedLlm().Name;

    /// <summary>Klein geschnitten: Das kleine quantisierte Modell lässt bei langen
    /// Eingaben still Inhalt weg.</summary>
    public int ChunkTargetLength => 1500;
    public int ChunkMinLength => 1000;

    /// <summary>Keine Grenze. Ein großes Modell auf einem langsamen Rechner hängt
    /// nicht, es rechnet — und abgeschnitten wurde hier noch nie etwas.</summary>
    public double CallTimeoutSeconds => 0;

    public async Task PrepareAsync(Action<double>? onProgress = null, CancellationToken cancel = default)
    {
        var model = ModelCatalog.LlmById(Settings.Shared.LlmModel) ?? ModelCatalog.RecommendedLlm();
        await gate.WaitAsync(cancel);
        try
        {
            if (loadedModel == model.Id && weights != null) return;
            await ModelDownloader.DownloadAsync(model, onProgress, cancel);

            var p = new ModelParams(ModelCatalog.PathFor(model))
            {
                ContextSize = 4096,
                GpuLayerCount = 0,   // CPU-Backend; GPU siehe README (Vulkan/CUDA-Pakete)
            };
            // Erst laden, dann das alte Modell freigeben: Scheitert der Wechsel,
            // bleibt die Aufbereitung mit dem bisherigen Modell einsatzbereit,
            // statt bis zum nächsten Neustart auszufallen.
            var next = await LLamaWeights.LoadFromFileAsync(p, cancel);
            weights?.Dispose();
            weights = next;
            modelParams = p;
            loadedModel = model.Id;
        }
        catch (Exception ex)
        {
            // Ohne geladenes Modell fällt die Formatierung still auf den Rohtext
            // zurück; ein bereits geladenes bleibt bestehen.
            StoreIO.Log($"Textmodell nicht geladen: {ex.Message}");
        }
        finally
        {
            gate.Release();
        }
    }

    /// <summary>Ein winziger Durchlauf, damit das erste echte Diktat nicht die
    /// einmalige Einrichtung des Ausführers mitbezahlt.</summary>
    public async Task WarmUpAsync(CancellationToken cancel = default)
    {
        if (weights == null || modelParams == null) return;
        try { _ = await RespondAsync("Antworte mit OK.", "OK", 0.1f, 4, cancel); }
        catch { /* Aufwärmen darf still scheitern */ }
    }

    public async Task<string> RespondAsync(string system, string user, float temperature,
                                           int maxTokens, CancellationToken cancel = default)
    {
        if (weights == null || modelParams == null)
            throw new InvalidOperationException("Textmodell ist nicht geladen.");

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
                MaxTokens = maxTokens,
                AntiPrompts = new[] { "<|im_end|>" },
                SamplingPipeline = new DefaultSamplingPipeline { Temperature = temperature },
            };
            var output = new StringBuilder();
            await foreach (var token in executor.InferAsync(prompt, inference, cancel))
                output.Append(token);
            return output.ToString();
        }
        finally
        {
            gate.Release();
        }
    }

    public void Dispose()
    {
        weights?.Dispose();
        weights = null;
        gate.Dispose();
    }
}
