using System.Net.Http.Json;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace Shout.Core;

/// <summary>
/// Live-Liste aktueller Formatierungs-Modelle von Hugging Face — das
/// Windows-Pendant zu HuggingFaceModels.swift.
///
/// Zwei Unterschiede zum Mac, beide erzwungen:
/// 1. llama.cpp lädt EINE .gguf-Datei, MLX ein ganzes Repo. Wir brauchen also
///    den Dateinamen im Repo und überspringen aufgeteilte Modelle
///    („…-00001-of-00002.gguf"), die ModelDownloader nicht zusammensetzen kann.
/// 2. Nur Qwen-Modelle (egal von welchem Anbieter). Der LlmFormatter setzt ein
///    Qwen-Chat-Template (im_start/im_end); mit einem Llama- oder Gemma-GGUF käme
///    Unsinn heraus. Lieber eine kurze, verlässliche Liste als eine lange, die
///    still Müll baut.
///
/// Reine Lese-API, kein Token nötig. Nach dem Download läuft alles lokal.
/// </summary>
public static class HuggingFaceModels
{
    private static readonly HttpClient Http = new() { Timeout = TimeSpan.FromSeconds(20) };
    private static readonly JsonSerializerOptions Json = new() { PropertyNameCaseInsensitive = true };

    /// <summary>Quantisierung, die wir suchen: guter Kompromiss und für jede
    /// Qwen-Größe vorhanden.</summary>
    private const string Quant = "q4_k_m";

    private sealed class ApiModel
    {
        public string Id { get; set; } = "";
        public int? Downloads { get; set; }
        public int? Likes { get; set; }
    }

    private sealed class ApiDetail
    {
        public List<ApiSibling>? Siblings { get; set; }
    }

    private sealed class ApiSibling
    {
        [JsonPropertyName("rfilename")] public string Rfilename { get; set; } = "";
    }

    /// <summary>Repos, die zwar Qwen sind, aber nicht zum Aufräumen von Text
    /// taugen (oder ein anderes Template nutzen).</summary>
    private static readonly string[] Excluded =
    {
        "-vl", "vision", "audio", "omni", "embedding", "reranker", "-math", "-coder", "guard",
        "thinking", "-base", "abliterated", "uncensored", "distill",
    };

    /// <summary>Ein entdecktes Modell samt Beliebtheit und geschätztem RAM-Bedarf.</summary>
    public sealed record Discovered(ModelCatalog.Model Model, int Downloads, int Likes, int MinRamGB);

    /// <summary>
    /// Holt beliebte Qwen-Instruct-GGUF-Modelle, nach Downloads sortiert. Wirft
    /// bei Netzfehlern — die Seite zeigt den Fehler dann als Hinweiszeile.
    /// </summary>
    public static async Task<List<Discovered>> FetchLlmAsync(int limit = 6,
                                                            CancellationToken cancel = default)
    {
        // NICHT auf author=Qwen begrenzt: Qwens eigene großen q4_k_m-Dateien sind
        // gesplittet („…-00001-of-00002"), und die kann ModelDownloader nicht
        // zusammensetzen. Community-Repos (bartowski, unsloth …) veröffentlichen
        // dieselben Modelle als Einzeldatei — Qwen bleibt über den Namensfilter
        // unten Pflicht, damit das Chat-Template stimmt.
        const string url = "https://huggingface.co/api/models" +
                           "?search=qwen%20instruct%20gguf&sort=downloads&direction=-1&limit=80";
        var raw = await Http.GetFromJsonAsync<List<ApiModel>>(url, Json, cancel) ?? new();

        var result = new List<Discovered>();
        var seenFiles = new HashSet<string>(StringComparer.OrdinalIgnoreCase);

        foreach (var candidate in raw)
        {
            if (result.Count >= limit) break;

            var lower = candidate.Id.ToLowerInvariant();
            if (!lower.Contains("gguf")) continue;
            // Qwen ist Pflicht: der LlmFormatter setzt dessen Chat-Template.
            if (!lower.Contains("qwen")) continue;
            if (!lower.Contains("instruct")) continue;   // Basismodelle können nicht chatten
            if (Excluded.Any(x => lower.Contains(x))) continue;

            var file = await FindQuantFileAsync(candidate.Id, cancel);
            if (file == null) continue;
            // Der Dateiname ist die Id im Modell-Ordner (Konvention des Katalogs)
            // — zwei Repos mit gleichem Dateinamen wären dieselbe Datei.
            if (!seenFiles.Add(file)) continue;
            if (ModelCatalog.LlmModels.Any(m => m.Id.Equals(file, StringComparison.OrdinalIgnoreCase)))
                continue;   // steht schon fest im Katalog

            var downloadUrl = $"https://huggingface.co/{candidate.Id}/resolve/main/{file}";
            var bytes = await ContentLengthAsync(downloadUrl, cancel);
            var paramsB = ParseParams(lower);
            var gb = bytes > 0 ? bytes / 1024.0 / 1024 / 1024 : EstimateGB(paramsB);

            result.Add(new Discovered(
                new ModelCatalog.Model(
                    Id: file,
                    Name: ShortName(candidate.Id),
                    SizeHint: gb > 0 ? $"{gb:0.#} GB" : "?",
                    // Leer: die Beschreibung baut die Modelle-Seite beim Anzeigen,
                    // sonst würde die Sprache beim Speichern einfrieren.
                    Note: "",
                    DownloadUrl: downloadUrl),
                candidate.Downloads ?? 0,
                candidate.Likes ?? 0,
                // Gewichte plus Kontext und Luft — gleiche Faustregel wie am Mac.
                MinRamGB: gb > 0 ? (int)Math.Round(gb * 1.7) : 0));
        }

        return result;
    }

    /// <summary>Sucht im Repo eine einzelne .gguf-Datei mit der gewünschten
    /// Quantisierung. Aufgeteilte Modelle werden übersprungen.</summary>
    private static async Task<string?> FindQuantFileAsync(string repoId, CancellationToken cancel)
    {
        try
        {
            var detail = await Http.GetFromJsonAsync<ApiDetail>(
                $"https://huggingface.co/api/models/{repoId}", Json, cancel);
            var files = detail?.Siblings?.Select(s => s.Rfilename) ?? Enumerable.Empty<string>();
            return files.FirstOrDefault(f =>
                f.EndsWith(".gguf", StringComparison.OrdinalIgnoreCase) &&
                f.Contains(Quant, StringComparison.OrdinalIgnoreCase) &&
                // Aufgeteilte Modelle kann ModelDownloader nicht zusammensetzen,
                // und ein Unterordner-Pfad würde beim Schreiben ins Leere laufen.
                !f.Contains("-of-", StringComparison.OrdinalIgnoreCase) &&
                !f.Contains('/'));
        }
        catch
        {
            return null;   // einzelnes Repo nicht lesbar → einfach auslassen
        }
    }

    /// <summary>Exakte Dateigröße per HEAD. 0, wenn der Server sie nicht meldet.</summary>
    private static async Task<long> ContentLengthAsync(string url, CancellationToken cancel)
    {
        try
        {
            using var request = new HttpRequestMessage(HttpMethod.Head, url);
            using var response = await Http.SendAsync(request, cancel);
            if (!response.IsSuccessStatusCode) return 0;
            return response.Content.Headers.ContentLength ?? 0;
        }
        catch
        {
            return 0;
        }
    }

    private static string ShortName(string repoId)
    {
        var name = repoId.Split('/').Last();
        // „Qwen2.5-7B-Instruct-GGUF" → „Qwen2.5 7B"
        name = name.Replace("-GGUF", "", StringComparison.OrdinalIgnoreCase)
                   .Replace("-Instruct", "", StringComparison.OrdinalIgnoreCase);
        return name.Replace('-', ' ');
    }

    /// <summary>Grobe Größe der q4-Gewichte: ~0,65 GB je Milliarde Parameter.</summary>
    private static double EstimateGB(double? paramsB) => paramsB is { } p ? p * 0.65 + 0.3 : 0;

    /// <summary>„1234567" → „1,2M". Die Modelle-Seite baut damit die Beschreibung.</summary>
    public static string Compact(int n) => n switch
    {
        >= 1_000_000 => $"{n / 1_000_000.0:0.#}M",
        >= 1_000 => $"{n / 1000}k",
        _ => n.ToString(),
    };

    /// <summary>
    /// Schätzt die Parameterzahl (Mrd.) aus dem Repo-Namen — gleiche Regeln wie
    /// am Mac: „…b"/„…m" gefolgt von einem Buchstaben ist keine Größe, sondern
    /// ein Suffix wie „4bit"/„16mb".
    /// </summary>
    private static double? ParseParams(string lower)
    {
        double? best = null;
        var i = 0;
        while (i < lower.Length)
        {
            if (!char.IsDigit(lower[i])) { i++; continue; }

            var j = i;
            // Auch „1_5b" ist eine Größe (1,5 Mrd.) — Unterstrich als Komma lesen.
            while (j < lower.Length && (char.IsDigit(lower[j]) || lower[j] == '.' || lower[j] == '_')) j++;

            var suffixOk = j < lower.Length && (j + 1 >= lower.Length || !char.IsLetter(lower[j + 1]));
            if (suffixOk &&
                double.TryParse(lower[i..j].Replace('_', '.'), System.Globalization.NumberStyles.Float,
                                System.Globalization.CultureInfo.InvariantCulture, out var value))
            {
                if (lower[j] == 'b' && value is >= 0.5 and <= 500)
                    best = Math.Max(best ?? 0, value);
                else if (lower[j] == 'm' && value is >= 50 and <= 999)
                    best = Math.Max(best ?? 0, value / 1000);
            }
            i = j;
        }
        return best;
    }
}
