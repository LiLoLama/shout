using System.Globalization;
using System.Net.Http.Headers;
using System.Net.Sockets;
using System.Text.Json;

namespace Shout.Core;

/// <summary>
/// Die echten Token-Zahlen einer Antwort. Grundlage der Kostenanzeige — dort wird
/// gezählt, nicht geschätzt.
/// </summary>
public readonly record struct TokenUsage(int Prompt, int Completion)
{
    public int Total => Prompt + Completion;
}

/// <summary>
/// Gemeinsame Auswertung der Antworten — von Text- und Audio-Engine benutzt, damit
/// beide dieselben Fehler auf dieselbe Weise unterscheiden.
/// </summary>
public static class RemoteHttp
{
    /// <summary>
    /// Wirft den passenden Fehler, wenn der Status kein Erfolg ist.
    ///
    /// <para>Die Unterscheidung bei 404 ist wichtig: Mit Modellhinweis im Rumpf ist es
    /// ein veraltetes Modell (der häufigste Fall, wenn eine Vorlage hinterherhängt),
    /// ohne Hinweis eine falsche Adresse. Beides braucht eine andere Abhilfe, und ein
    /// pauschales „404" schickt Leute ans falsche Ende.</para>
    /// </summary>
    public static void Check(int status, string body, HttpResponseHeaders? headers = null,
                             string model = "")
    {
        if (status is >= 200 and < 300) return;

        switch (status)
        {
            case 401:
            case 403:
                throw new RemoteProviderException(RemoteFailure.Unauthorized);
            case 402:
                throw new RemoteProviderException(RemoteFailure.NoCredit);
            case 404:
                if (MessageFrom(body).Contains("model", StringComparison.OrdinalIgnoreCase))
                    throw new RemoteProviderException(RemoteFailure.UnknownModel, model: model);
                throw new RemoteProviderException(RemoteFailure.Http, status: 404);
            case 429:
                throw new RemoteProviderException(RemoteFailure.RateLimited,
                                                  retryAfter: RetryAfter(headers));
            default:
                throw new RemoteProviderException(RemoteFailure.Http, status: status);
        }
    }

    /// <summary>
    /// Sekunden aus „Retry-After". Der Kopf darf laut Norm auch ein Datum enthalten;
    /// gerechnet wird dann die Spanne bis dahin, sonst stünde in der Oberfläche eine
    /// Jahreszahl als Wartezeit.
    /// </summary>
    private static double? RetryAfter(HttpResponseHeaders? headers)
    {
        if (headers == null) return null;
        try
        {
            var value = headers.RetryAfter;
            if (value?.Delta is { } delta) return delta.TotalSeconds;
            if (value?.Date is { } date)
                return Math.Max(0, (date - DateTimeOffset.UtcNow).TotalSeconds);
            if (headers.TryGetValues("Retry-After", out var raw) &&
                double.TryParse(raw.FirstOrDefault(), NumberStyles.Float,
                                CultureInfo.InvariantCulture, out var seconds))
                return seconds;
        }
        catch (FormatException)
        {
            // Ein unlesbarer Kopf ist kein Grund, den eigentlichen Fehler (429) zu
            // verlieren — dann gibt es eben keine Wartezeit zum Anzeigen.
        }
        return null;
    }

    /// <summary>
    /// <c>error.message</c> aus dem Antwortrumpf — nur zur Fallunterscheidung, nie zur
    /// Anzeige und nie ins Protokoll: Manche Anbieter spiegeln darin die Anfrage samt
    /// Kopfzeilen, und dann stünde der Schlüssel in der Datei.
    /// </summary>
    public static string MessageFrom(string body)
    {
        if (string.IsNullOrWhiteSpace(body)) return "";
        try
        {
            using var doc = JsonDocument.Parse(body);
            if (doc.RootElement.ValueKind != JsonValueKind.Object) return "";
            if (doc.RootElement.TryGetProperty("error", out var error) &&
                error.ValueKind == JsonValueKind.Object &&
                error.TryGetProperty("message", out var inner) &&
                inner.ValueKind == JsonValueKind.String)
                return inner.GetString() ?? "";
            if (doc.RootElement.TryGetProperty("message", out var text) &&
                text.ValueKind == JsonValueKind.String)
                return text.GetString() ?? "";
        }
        catch (JsonException)
        {
            // Manche Anbieter antworten im Fehlerfall mit HTML einer Zwischenstelle.
            // Dann gibt es keinen Hinweis, und 404 bleibt „falsche Adresse".
        }
        return "";
    }

    public static TokenUsage? UsageFrom(JsonElement json)
    {
        if (json.ValueKind != JsonValueKind.Object) return null;
        if (!json.TryGetProperty("usage", out var usage) ||
            usage.ValueKind != JsonValueKind.Object) return null;
        if (!usage.TryGetProperty("prompt_tokens", out var prompt) ||
            !usage.TryGetProperty("completion_tokens", out var completion)) return null;
        if (!prompt.TryGetInt32(out var p) || !completion.TryGetInt32(out var c)) return null;
        return new TokenUsage(p, c);
    }

    /// <summary>
    /// Übersetzt Netzfehler. Zeitüberschreitung bekommt einen eigenen Fall, weil der
    /// Router beim Diktat darauf eine harte Grenze setzt.
    ///
    /// <para>Am Mac trug ein einziger <c>URLError</c> beide Fälle; hier sind es zwei
    /// Ausnahmetypen: Läuft die Zeitgrenze eines <c>HttpClient</c> ab, bricht er die
    /// Anfrage über sein eigenes Token ab — das kommt als
    /// <see cref="TaskCanceledException"/> an und ist keine „abgebrochene Anfrage",
    /// sondern genau die Zeitgrenze.</para>
    /// </summary>
    public static RemoteProviderException Translate(Exception error)
    {
        if (error is RemoteProviderException known) return known;
        if (error is TaskCanceledException or OperationCanceledException or TimeoutException)
            return new RemoteProviderException(RemoteFailure.TimedOut);
        if (error is HttpRequestException http)
        {
            // Der Socket-Fehlercode landet als Status im Fehler: Er gehört nicht in die
            // Anzeige, hilft aber im Protokoll bei der Unterscheidung „Host unbekannt"
            // gegen „Verbindung verweigert" (der lokale Ollama läuft nicht).
            var code = (http.InnerException as SocketException)?.ErrorCode ?? 0;
            return new RemoteProviderException(RemoteFailure.CannotConnect, status: code);
        }
        return new RemoteProviderException(RemoteFailure.MalformedResponse);
    }
}
