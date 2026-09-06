using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;

namespace Shout.Core;

/// <summary>
/// Spracherkennung <b>bei einem selbst gewählten Anbieter</b> — ein OpenAI-kompatibler
/// <c>/v1/audio/transcriptions</c>-Aufruf (multipart).
///
/// <para>Derselbe Endpunkt bei OpenAI, Groq, Mistral und jedem whisper.cpp-Server; was
/// sich unterscheidet, sind Daten in der Vorlage.</para>
///
/// <para>Lange Aufnahmen werden vorher gefenstert (<see cref="AudioWindows"/>) und der
/// Reihe nach hochgeladen — nicht parallel: Ein Ratenlimit würde sonst den ganzen
/// Auftrag zerreißen, und der Fortschrittsbalken der Warteschlange braucht ohnehin eine
/// Reihenfolge.</para>
/// </summary>
public sealed class RemoteSpeechEngine : ISpeechEngine
{
    private static readonly HttpClient SharedHttp = new() { Timeout = Timeout.InfiniteTimeSpan };

    private readonly RemoteConfig config;
    private readonly string? key;
    private readonly bool needsKey;
    private readonly string providerName;
    private readonly HttpClient http;
    private readonly double timeout;
    private readonly double maxWindowSeconds;
    private readonly int sampleRate;

    /// <summary>Wohin die verschickten Sekunden gemeldet werden.</summary>
    private readonly Action<double>? onSeconds;

    /// <summary>Wie viele Sekunden Audio insgesamt verschickt wurden. Transkription wird
    /// meist pro Minute abgerechnet, nicht pro Token — Grundlage der Kostenanzeige.</summary>
    public double SentSeconds { get; private set; }

    public RemoteSpeechEngine(RemoteConfig config, string? key, bool needsKey,
                              string providerName, HttpClient? http = null,
                              double timeoutSeconds = 120, double maxWindowSeconds = 600,
                              int sampleRate = 16_000, Action<double>? onSeconds = null)
    {
        this.config = config;
        this.key = string.IsNullOrEmpty(key) ? null : key;
        this.needsKey = needsKey;
        this.providerName = providerName;
        this.http = http ?? SharedHttp;
        timeout = timeoutSeconds;
        this.maxWindowSeconds = maxWindowSeconds;
        this.sampleRate = sampleRate;
        this.onSeconds = onSeconds;
    }

    public bool IsReady => config.AudioUrl != null && (!needsKey || key != null);

    public string DisplayName => $"{config.Model} · {providerName}";

    /// <summary>Es gibt nichts zu laden — „geladen" ist genau das eingetragene Modell.</summary>
    public string? LoadedModel => config.Model;

    /// <summary>Nichts zu laden; der Fortschritt ist sofort vollständig.</summary>
    public Task PrepareAsync(Action<double>? onProgress = null, CancellationToken cancel = default)
    {
        onProgress?.Invoke(1);
        return Task.CompletedTask;
    }

    /// <summary>Absichtlich wirkungslos: Stille hochzuladen würde Geld kosten und nichts
    /// beschleunigen.</summary>
    public Task WarmUpAsync(CancellationToken cancel = default) => Task.CompletedTask;

    /// <summary>Nichts zu geben: Der <see cref="HttpClient"/> ist geteilt bzw.
    /// hereingereicht und überlebt die Engine.</summary>
    public void Dispose() { }

    // MARK: Erkennung

    public async Task<SpeechResult> TranscribeAsync(float[] samples, string? language,
                                                    CancellationToken cancel = default)
    {
        if (config.AudioUrl == null) throw new RemoteProviderException(RemoteFailure.InvalidBaseUrl);
        if (needsKey && key == null) throw new RemoteProviderException(RemoteFailure.MissingKey);

        var fenster = AudioWindows.Split(samples, sampleRate, maxWindowSeconds);
        if (fenster.Count == 0) return SpeechResult.Empty;

        var texte = new List<string>();
        var segmente = new List<TranscriptSegment>();

        foreach (var f in fenster)
        {
            // Ein dauerhaft scheiterndes Fenster lässt den GANZEN Aufruf scheitern.
            // Weiterzumachen hieße, eine Lücke ins Transkript zu schreiben, die niemand
            // sieht — der Aufrufer kann dagegen auf das lokale Modell ausweichen oder den
            // Auftrag später wiederholen.
            var teil = await TranscribeWindowAsync(samples[f.Start..f.End], language, cancel);
            if (teil.Text.Length > 0) texte.Add(teil.Text);
            foreach (var s in teil.Segments)
                segmente.Add(new TranscriptSegment(s.Text, s.Start + f.OffsetSeconds,
                                                   s.End + f.OffsetSeconds));

            var sekunden = (double)f.Length / sampleRate;
            SentSeconds += sekunden;
            onSeconds?.Invoke(sekunden);
        }

        return new SpeechResult { Text = string.Join(" ", texte), Segments = segmente };
    }

    /// <summary>
    /// EIN Fenster.
    ///
    /// <para>Zuerst mit <c>verbose_json</c> — nur so kommen Zeitmarken zurück, und ohne
    /// die gibt es keine Untertitel. Lehnt der Anbieter das Format ab (manche neueren
    /// Modelle können nur <c>json</c>), wird EINMAL mit <c>json</c> wiederholt; dann
    /// entsteht ein Ersatzsegment über die ganze Länge.</para>
    /// </summary>
    private async Task<SpeechResult> TranscribeWindowAsync(float[] samples, string? language,
                                                           CancellationToken cancel)
    {
        try
        {
            return await UploadAsync(samples, language, verbose: true, cancel);
        }
        catch (RemoteProviderException error)
            when (error.Failure == RemoteFailure.Http && error.Status == 400)
        {
            return await UploadAsync(samples, language, verbose: false, cancel);
        }
    }

    private async Task<SpeechResult> UploadAsync(float[] samples, string? language,
                                                 bool verbose, CancellationToken cancel)
    {
        var url = config.AudioUrl ?? throw new RemoteProviderException(RemoteFailure.InvalidBaseUrl);
        var dauer = (double)samples.Length / sampleRate;

        var felder = new List<(string Name, string Value)>
        {
            ("model", config.Model),
            ("response_format", verbose ? "verbose_json" : "json"),
        };
        // Ohne Sprache erkennt der Anbieter selbst — genau wie lokal bei „auto".
        if (!string.IsNullOrEmpty(language)) felder.Add(("language", language));

        var grenze = "shout-" + Guid.NewGuid().ToString("N");

        using var frist = CancellationTokenSource.CreateLinkedTokenSource(cancel);
        frist.CancelAfter(TimeSpan.FromSeconds(timeout));

        string body;
        HttpResponseHeaders headers;
        int status;
        try
        {
            var content = new ByteArrayContent(
                MultipartBody(grenze, felder, WavEncoder.Data(samples, sampleRate)));
            // Von Hand gesetzt statt über MultipartFormDataContent: Das .NET-Gegenstück
            // schreibt die Grenze in Anführungszeichen, und daran verschlucken sich
            // einzelne whisper.cpp-Server.
            content.Headers.TryAddWithoutValidation(
                "Content-Type", $"multipart/form-data; boundary={grenze}");

            using var request = new HttpRequestMessage(HttpMethod.Post, url) { Content = content };
            if (key != null)
                request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", key);

            using var response = await http.SendAsync(request, frist.Token);
            status = (int)response.StatusCode;
            headers = response.Headers;
            body = await response.Content.ReadAsStringAsync(frist.Token);
        }
        catch (Exception ex)
        {
            throw RemoteHttp.Translate(ex);
        }

        RemoteHttp.Check(status, body, headers, config.Model);

        try
        {
            using var doc = JsonDocument.Parse(body);
            var root = doc.RootElement;
            if (root.ValueKind != JsonValueKind.Object ||
                !root.TryGetProperty("text", out var feld) ||
                feld.ValueKind != JsonValueKind.String)
                throw new RemoteProviderException(RemoteFailure.MalformedResponse);

            var sauber = (feld.GetString() ?? "").Trim();
            return new SpeechResult
            {
                Text = sauber,
                Segments = Segments(root, sauber, dauer),
            };
        }
        catch (JsonException)
        {
            throw new RemoteProviderException(RemoteFailure.MalformedResponse);
        }
    }

    /// <summary>
    /// Segmente aus der Antwort — oder ein Ersatzsegment über die ganze Länge.
    ///
    /// <para>Das Ersatzsegment ist eine bewusste Notlösung: Diktat und <c>.txt</c>
    /// funktionieren damit weiter, <c>.srt</c>-Untertitel und die Sprechertrennung werden
    /// unbrauchbar. Die Oberfläche sagt das an der Vorlage; still eine falsche Zeitmarke
    /// zu liefern wäre schlimmer.</para>
    /// </summary>
    public static List<TranscriptSegment> Segments(JsonElement json, string fallbackText,
                                                   double duration)
    {
        var segmente = new List<TranscriptSegment>();
        if (json.ValueKind == JsonValueKind.Object &&
            json.TryGetProperty("segments", out var rohe) &&
            rohe.ValueKind == JsonValueKind.Array)
        {
            foreach (var eintrag in rohe.EnumerateArray())
            {
                if (eintrag.ValueKind != JsonValueKind.Object) continue;
                if (!eintrag.TryGetProperty("text", out var text) ||
                    text.ValueKind != JsonValueKind.String) continue;
                if (!eintrag.TryGetProperty("start", out var start) ||
                    start.ValueKind != JsonValueKind.Number) continue;
                if (!eintrag.TryGetProperty("end", out var end) ||
                    end.ValueKind != JsonValueKind.Number) continue;

                var sauber = (text.GetString() ?? "").Trim();
                if (sauber.Length == 0) continue;
                segmente.Add(new TranscriptSegment(sauber, start.GetDouble(), end.GetDouble()));
            }
        }
        if (segmente.Count > 0) return segmente;

        if (fallbackText.Length == 0) return segmente;
        segmente.Add(new TranscriptSegment(fallbackText, 0, duration));
        return segmente;
    }

    /// <summary>Baut den Multipart-Rumpf. Die Datei kommt zuletzt, damit ein Anbieter, der
    /// den Strom mitlesend auswertet, das Modell schon kennt, wenn die Bytes
    /// eintreffen.</summary>
    public static byte[] MultipartBody(string boundary,
                                       IEnumerable<(string Name, string Value)> fields,
                                       byte[] wav, string filename = "audio.wav")
    {
        using var stream = new MemoryStream(wav.Length + 512);

        void Append(string text)
        {
            var bytes = Encoding.UTF8.GetBytes(text);
            stream.Write(bytes, 0, bytes.Length);
        }

        foreach (var (name, value) in fields)
        {
            Append($"--{boundary}\r\n");
            Append($"Content-Disposition: form-data; name=\"{name}\"\r\n\r\n");
            Append($"{value}\r\n");
        }
        Append($"--{boundary}\r\n");
        Append($"Content-Disposition: form-data; name=\"file\"; filename=\"{filename}\"\r\n");
        Append("Content-Type: audio/wav\r\n\r\n");
        stream.Write(wav, 0, wav.Length);
        Append($"\r\n--{boundary}--\r\n");

        return stream.ToArray();
    }
}
