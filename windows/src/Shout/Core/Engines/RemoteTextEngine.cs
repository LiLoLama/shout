using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;

namespace Shout.Core;

/// <summary>
/// Das Textmodell <b>bei einem selbst gewählten Anbieter</b> — ein OpenAI-kompatibler
/// <c>/v1/chat/completions</c>-Aufruf.
///
/// <para>Ein einziger Client genügt für OpenAI, OpenRouter, EURouter, Groq, Mistral,
/// DeepSeek, Anthropic, Google, xAI, Ollama, LM Studio und alles andere, was diese
/// Spezifikation erfüllt. Was sich unterscheidet, sind Daten in der Vorlage, nicht
/// Code.</para>
///
/// <para>Der Router darüber (<see cref="LlmFormatter"/>) kennt keinen Unterschied zum
/// lokalen Modell: Prompts, Abschnittsbildung und der Kürzungs-Schutz greifen
/// unverändert. Ein Cloud-Modell, das auf das Diktat antwortet statt es zu formatieren,
/// wird genauso verworfen wie ein lokales.</para>
/// </summary>
public sealed class RemoteTextEngine : ITextEngine
{
    private static readonly HttpClient SharedHttp = new() { Timeout = Timeout.InfiniteTimeSpan };

    private readonly RemoteConfig config;
    private readonly string? key;
    private readonly bool needsKey;
    private readonly string providerName;
    private readonly HttpClient http;
    private readonly double timeout;

    /// <summary>Wohin der gemessene Verbrauch gemeldet wird. Als Rückruf, damit die
    /// Engine nichts über den Verbrauchsspeicher wissen muss und Tests keine echten
    /// Dateien anfassen.</summary>
    private readonly Action<TokenUsage>? onUsage;

    /// <summary>Token-Zahlen der letzten Antwort — echt gemeldet, nicht geschätzt.
    /// Grundlage der Kostenanzeige.</summary>
    public TokenUsage? LastUsage { get; private set; }

    public RemoteTextEngine(RemoteConfig config, string? key, bool needsKey, string providerName,
                            HttpClient? http = null, double timeoutSeconds = 15,
                            Action<TokenUsage>? onUsage = null)
    {
        this.config = config;
        this.key = string.IsNullOrEmpty(key) ? null : key;
        this.needsKey = needsKey;
        this.providerName = providerName;
        this.http = http ?? SharedHttp;
        timeout = timeoutSeconds;
        this.onUsage = onUsage;
    }

    // MARK: Zustand

    /// <summary>
    /// Bereit heißt hier: Die Adresse ist brauchbar und ein Schlüssel liegt vor, falls
    /// der Anbieter einen braucht.
    ///
    /// <para>Das ist mehr als Formsache: Ist die Engine nicht bereit, fügt der Router
    /// den Rohtext ein, ohne zu fragen. Stünde hier immer true, liefe jedes einzelne
    /// Diktat in denselben 401 — statt dass der Fehler einmal in den Einstellungen
    /// sichtbar ist.</para>
    /// </summary>
    public bool IsReady => config.ChatUrl != null && (!needsKey || key != null);

    public string DisplayName => $"{config.Model} · {providerName}";

    /// <summary>Deutlich größer als lokal: Ein Modell mit großem Kontextfenster verträgt
    /// mehr, und jeder Aufruf kostet Zeit und Geld.</summary>
    public int ChunkTargetLength => 6000;

    public int ChunkMinLength => 4000;

    /// <summary>Etwas über der Zeitgrenze der Anfrage selbst: Normalerweise schlägt die
    /// Grenze der Anfrage zuerst zu und liefert einen genauen Fehler; diese hier ist das
    /// Netz darunter, falls der Aufruf wirklich hängt.</summary>
    public double CallTimeoutSeconds => timeout + 2;

    /// <summary>Nichts zu laden — der Fortschritt ist sofort vollständig, damit die
    /// Oberfläche keinen hängenden Balken zeigt.</summary>
    public Task PrepareAsync(Action<double>? onProgress = null, CancellationToken cancel = default)
    {
        onProgress?.Invoke(1);
        return Task.CompletedTask;
    }

    /// <summary>Absichtlich wirkungslos. Aufwärmen wäre hier eine bezahlte Anfrage ohne
    /// jeden Nutzen — es gibt kein Modell in den Speicher zu laden.</summary>
    public Task WarmUpAsync(CancellationToken cancel = default) => Task.CompletedTask;

    /// <summary>Nichts zu geben: Der <see cref="HttpClient"/> ist geteilt bzw.
    /// hereingereicht und überlebt die Engine — ihn hier zu schließen würde die nächste
    /// Engine mit abwürgen.</summary>
    public void Dispose() { }

    // MARK: Aufruf

    public async Task<string> RespondAsync(string system, string user, float temperature,
                                           int maxTokens, CancellationToken cancel = default)
    {
        var url = config.ChatUrl ?? throw new RemoteProviderException(RemoteFailure.InvalidBaseUrl);
        if (needsKey && key == null) throw new RemoteProviderException(RemoteFailure.MissingKey);

        var payload = new
        {
            model = config.Model,
            messages = new[]
            {
                new { role = "system", content = system },
                new { role = "user", content = user },
            },
            // Gerundet: (double)0.2f ist 0.20000000298023224, und das stünde dann so im
            // Rumpf. Anbieter nehmen es hin, aber es ist Rauschen in jeder Anfrage und in
            // jedem Fehlerbericht.
            temperature = Math.Round(temperature * 100.0) / 100,
            // Kein Streaming: Der Router braucht die ganze Antwort, bevor der
            // Kürzungs-Schutz urteilen kann.
            stream = false,
            // maxTokens wird bewusst NICHT mitgeschickt: Die Zahl ist auf die kleinen
            // Abschnitte des lokalen Modells zugeschnitten, hier sind die Abschnitte
            // 6000 Zeichen lang. Als harte Obergrenze bräche sie die Antwort mitten im
            // Satz ab — und der Kürzungs-Schutz verwürfe daraufhin den ganzen Abschnitt.
        };

        using var frist = CancellationTokenSource.CreateLinkedTokenSource(cancel);
        frist.CancelAfter(TimeSpan.FromSeconds(timeout));

        string body;
        HttpResponseHeaders headers;
        int status;
        try
        {
            using var request = new HttpRequestMessage(HttpMethod.Post, url)
            {
                Content = new StringContent(JsonSerializer.Serialize(payload),
                                            Encoding.UTF8, "application/json"),
            };
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
                !root.TryGetProperty("choices", out var choices) ||
                choices.ValueKind != JsonValueKind.Array || choices.GetArrayLength() == 0)
                throw new RemoteProviderException(RemoteFailure.MalformedResponse);

            var content = choices[0].TryGetProperty("message", out var message) &&
                          message.ValueKind == JsonValueKind.Object &&
                          message.TryGetProperty("content", out var feld) &&
                          feld.ValueKind == JsonValueKind.String
                ? feld.GetString() ?? ""
                : "";
            if (content.Trim().Length == 0)
                throw new RemoteProviderException(RemoteFailure.MalformedResponse);

            var usage = RemoteHttp.UsageFrom(root);
            LastUsage = usage;
            if (usage is { } gemessen) onUsage?.Invoke(gemessen);
            return content;
        }
        catch (JsonException)
        {
            throw new RemoteProviderException(RemoteFailure.MalformedResponse);
        }
    }
}
