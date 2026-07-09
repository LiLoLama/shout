namespace Shout.Core;

/// <summary>
/// Lädt Modelle mit Fortschritts-Callback von Hugging Face. Download in eine
/// .partial-Datei, erst bei Erfolg umbenennen — kein halbes Modell im Ordner.
/// </summary>
public static class ModelDownloader
{
    private static readonly HttpClient Http = new() { Timeout = TimeSpan.FromMinutes(60) };

    /// <summary>Lädt das Modell, falls noch nicht vorhanden. Fortschritt 0…1
    /// (oder -1, wenn der Server keine Größe meldet).</summary>
    public static async Task DownloadAsync(ModelCatalog.Model model,
                                           Action<double>? onProgress = null,
                                           CancellationToken cancel = default)
    {
        var target = ModelCatalog.PathFor(model);
        if (File.Exists(target)) return;

        var partial = target + ".partial";
        using var response = await Http.GetAsync(
            model.DownloadUrl, HttpCompletionOption.ResponseHeadersRead, cancel);
        response.EnsureSuccessStatusCode();

        var total = response.Content.Headers.ContentLength ?? -1;
        await using (var source = await response.Content.ReadAsStreamAsync(cancel))
        await using (var file = File.Create(partial))
        {
            var buffer = new byte[1 << 16];
            long written = 0;
            int read;
            while ((read = await source.ReadAsync(buffer, cancel)) > 0)
            {
                await file.WriteAsync(buffer.AsMemory(0, read), cancel);
                written += read;
                onProgress?.Invoke(total > 0 ? (double)written / total : -1);
            }
        }

        File.Move(partial, target, overwrite: true);
        onProgress?.Invoke(1);
    }
}
