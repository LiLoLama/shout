using System.Globalization;
using System.Net.Http.Headers;
using System.Text.Json;

namespace Shout.Core;

/// <summary>
/// Holt aktuelle Preise — <b>nur auf Knopfdruck</b>, wie die Modell-Listen.
///
/// <para>Quelle ist die freie Modell-API von OpenRouter. Das ist die einzige
/// maschinenlesbare Preisliste, die hunderte Modelle mehrerer Anbieter abdeckt und ohne
/// Schlüssel abrufbar ist; die Endpunkte der Anbieter selbst liefern Modell-IDs, aber
/// praktisch nie Preise.</para>
///
/// <para>Damit sind die Zahlen eine <b>Näherung</b> für Anbieter, bei denen man direkt
/// kauft: OpenRouter gibt weiter, was es selbst zahlt, und das liegt nah an den
/// Listenpreisen, ist aber nicht dieselbe Rechnung. Die Oberfläche sagt das.</para>
///
/// <para>Transkriptions-Preise stehen dort nicht — die bleiben aus der mitgelieferten
/// Tabelle. Deshalb wird zusammengeführt und nicht ersetzt.</para>
/// </summary>
public static class PriceFetch
{
    public const string OpenRouterModelsUrl = "https://openrouter.ai/api/v1/models";

    private static readonly HttpClient Shared = new() { Timeout = Timeout.InfiniteTimeSpan };

    public static async Task<PriceTable> FetchAsync(HttpClient? http = null,
                                                    double timeoutSeconds = 30,
                                                    DateTime? now = null,
                                                    CancellationToken cancel = default)
    {
        using var frist = CancellationTokenSource.CreateLinkedTokenSource(cancel);
        frist.CancelAfter(TimeSpan.FromSeconds(timeoutSeconds));

        string body;
        HttpResponseHeaders headers;
        int status;
        try
        {
            using var response = await (http ?? Shared).GetAsync(OpenRouterModelsUrl, frist.Token);
            status = (int)response.StatusCode;
            headers = response.Headers;
            body = await response.Content.ReadAsStringAsync(frist.Token);
        }
        catch (Exception ex)
        {
            throw RemoteHttp.Translate(ex);
        }

        RemoteHttp.Check(status, body, headers);
        return Parse(body, now ?? DateTime.UtcNow);
    }

    /// <summary>
    /// Wandelt die Antwort um. Die Preise stehen dort als Zeichenketten und <b>je
    /// einzelnem Token</b> — unsere Tabelle rechnet je Million, wie die Anbieter es auf
    /// ihren Seiten ausweisen.
    /// </summary>
    public static PriceTable Parse(string body, DateTime now)
    {
        var text = new Dictionary<string, ModelPrice>();
        try
        {
            using var doc = JsonDocument.Parse(body);
            if (doc.RootElement.ValueKind != JsonValueKind.Object ||
                !doc.RootElement.TryGetProperty("data", out var data) ||
                data.ValueKind != JsonValueKind.Array)
                throw new RemoteProviderException(RemoteFailure.MalformedResponse);

            foreach (var eintrag in data.EnumerateArray())
            {
                if (eintrag.ValueKind != JsonValueKind.Object) continue;
                if (!eintrag.TryGetProperty("id", out var idFeld) ||
                    idFeld.ValueKind != JsonValueKind.String) continue;
                var id = idFeld.GetString();
                if (string.IsNullOrEmpty(id)) continue;
                if (!eintrag.TryGetProperty("pricing", out var pricing) ||
                    pricing.ValueKind != JsonValueKind.Object) continue;

                // Kostenlose Modelle mit 0 sind gültig und sollen als 0 erscheinen —
                // aber nur, wenn beide Werte wirklich da waren.
                var prompt = Zahl(pricing, "prompt");
                var completion = Zahl(pricing, "completion");
                if (prompt is not { } p || completion is not { } c) continue;

                text[id] = new ModelPrice(p * 1_000_000, c * 1_000_000);
            }
        }
        catch (JsonException)
        {
            throw new RemoteProviderException(RemoteFailure.MalformedResponse);
        }

        if (text.Count == 0) throw new RemoteProviderException(RemoteFailure.MalformedResponse);

        // Die mitgelieferten Werte bleiben als Rückfall stehen, wo der Abruf nichts
        // hergibt: Audio überhaupt, und Modelle, die OpenRouter nicht führt (etwa die
        // Transkriptions-Modelle von Groq).
        var mitgeliefert = PriceTable.Bundled;
        var zusammen = new Dictionary<string, ModelPrice>(mitgeliefert.Text);
        foreach (var (id, preis) in text) zusammen[id] = preis;

        return new PriceTable { Updated = now, Text = zusammen, Audio = mitgeliefert.Audio };
    }

    /// <summary>OpenRouter liefert Zahlen als Zeichenkette („0.00000025"). Manche
    /// Spiegelungen liefern echte Zahlen — beides wird genommen.</summary>
    private static double? Zahl(JsonElement objekt, string name)
    {
        if (!objekt.TryGetProperty(name, out var wert)) return null;
        return wert.ValueKind switch
        {
            JsonValueKind.Number => wert.GetDouble(),
            JsonValueKind.String => double.TryParse(wert.GetString(), NumberStyles.Float,
                                                    CultureInfo.InvariantCulture, out var d)
                ? d : null,
            _ => null,
        };
    }
}
