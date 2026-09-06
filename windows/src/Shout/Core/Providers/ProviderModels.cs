using System.Diagnostics;
using System.Net.Http.Headers;
using System.Text.Json;

namespace Shout.Core;

/// <summary>
/// Holt die Modell-Liste eines Anbieters — <b>nur auf Knopfdruck</b>, nie von selbst.
/// Die App soll nicht im Hintergrund ins Netz telefonieren; das gilt hier genauso wie
/// bei der Hugging-Face-Liste in der Modell-Ansicht.
/// </summary>
public static class ProviderModels
{
    /// <summary>Ohne eigene Zeitgrenze: Die gilt je Aufruf und wird unten über ein
    /// Abbruch-Token gesetzt, sonst müsste für jede Wartezeit ein eigener Client her.</summary>
    private static readonly HttpClient Shared = new() { Timeout = Timeout.InfiniteTimeSpan };

    /// <summary>
    /// <c>GET /v1/models</c>. Liefert die IDs, alphabetisch.
    ///
    /// <para>Bewusst nur die IDs: Die Antworten der Anbieter unterscheiden sich in allem
    /// außer <c>data[].id</c>, und mehr braucht die Auswahl nicht. Preise stehen dort
    /// ohnehin fast nie.</para>
    /// </summary>
    public static async Task<List<string>> FetchAsync(RemoteConfig config, string? key,
                                                      bool needsKey, HttpClient? http = null,
                                                      double timeoutSeconds = 20,
                                                      CancellationToken cancel = default)
    {
        var url = config.ModelsUrl ?? throw new RemoteProviderException(RemoteFailure.InvalidBaseUrl);
        if (needsKey && string.IsNullOrEmpty(key))
            throw new RemoteProviderException(RemoteFailure.MissingKey);

        using var frist = CancellationTokenSource.CreateLinkedTokenSource(cancel);
        frist.CancelAfter(TimeSpan.FromSeconds(timeoutSeconds));

        string body;
        HttpResponseHeaders headers;
        int status;
        try
        {
            using var request = new HttpRequestMessage(HttpMethod.Get, url);
            if (!string.IsNullOrEmpty(key))
                request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", key);
            using var response = await (http ?? Shared).SendAsync(request, frist.Token);
            status = (int)response.StatusCode;
            headers = response.Headers;
            body = await response.Content.ReadAsStringAsync(frist.Token);
        }
        catch (Exception ex)
        {
            throw RemoteHttp.Translate(ex);
        }

        RemoteHttp.Check(status, body, headers, config.Model);

        var ids = new List<string>();
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
                if (!eintrag.TryGetProperty("id", out var id) ||
                    id.ValueKind != JsonValueKind.String) continue;
                var text = id.GetString();
                if (!string.IsNullOrEmpty(text)) ids.Add(text);
            }
        }
        catch (JsonException)
        {
            throw new RemoteProviderException(RemoteFailure.MalformedResponse);
        }

        if (ids.Count == 0) throw new RemoteProviderException(RemoteFailure.MalformedResponse);
        ids.Sort(StringComparer.Ordinal);
        return ids;
    }
}

/// <summary>Ergebnis von „Verbindung testen".</summary>
public sealed class ProbeResult
{
    public bool Ok { get; private init; }
    public double Seconds { get; private init; }

    /// <summary>null, wenn der Anbieter keine brauchbare Liste liefert — dann ist über
    /// das Modell nichts bekannt, und das darf die Oberfläche nicht als „alles gut"
    /// ausgeben.</summary>
    public bool? ModelListed { get; private init; }

    public RemoteProviderException? Error { get; private init; }

    public static ProbeResult Success(double seconds, bool? modelListed)
        => new() { Ok = true, Seconds = seconds, ModelListed = modelListed };

    public static ProbeResult Failed(RemoteProviderException error)
        => new() { Ok = false, Error = error };
}

/// <summary>
/// „Verbindung testen".
///
/// <para>Prüft über die Modell-Liste, nicht über einen Probe-Aufruf ans Modell: Das
/// kostet nichts, geht schnell, und es prüft genau die drei Dinge, die schiefgehen —
/// Adresse, Schlüssel, und ob das eingetragene Modell dort überhaupt existiert. Ein
/// Chat-Aufruf würde Geld kosten und über die Adresse nicht mehr aussagen.</para>
/// </summary>
public static class ProviderProbe
{
    public static async Task<ProbeResult> RunAsync(RemoteConfig config, string? key,
                                                   bool needsKey, HttpClient? http = null,
                                                   CancellationToken cancel = default)
    {
        // Stoppuhr statt Uhrzeit: Eine Zeitumstellung mitten in der Messung ergäbe sonst
        // eine negative Dauer in der Oberfläche.
        var uhr = Stopwatch.StartNew();
        try
        {
            var ids = await ProviderModels.FetchAsync(config, key, needsKey, http, cancel: cancel);
            return ProbeResult.Success(uhr.Elapsed.TotalSeconds,
                                       ids.Contains(config.Model, StringComparer.Ordinal));
        }
        catch (RemoteProviderException error)
        {
            // Kein `/models`-Endpunkt heißt nicht, dass der Anbieter kaputt ist — manche
            // bieten nur die Chat-Adresse an. Dann ist die Verbindung grundsätzlich in
            // Ordnung, über das Modell wissen wir aber nichts.
            if (error.Failure == RemoteFailure.Http && error.Status == 404)
                return ProbeResult.Success(uhr.Elapsed.TotalSeconds, null);
            if (error.Failure == RemoteFailure.MalformedResponse)
                return ProbeResult.Success(uhr.Elapsed.TotalSeconds, null);
            return ProbeResult.Failed(error);
        }
        catch (Exception ex)
        {
            return ProbeResult.Failed(RemoteHttp.Translate(ex));
        }
    }
}
