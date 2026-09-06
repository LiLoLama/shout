namespace Shout.Core;

/// <summary>Warum ein Anbieter-Aufruf gescheitert ist.</summary>
public enum RemoteFailure
{
    /// <summary>Es ist kein Schlüssel hinterlegt, der Anbieter braucht aber einen.</summary>
    MissingKey,
    /// <summary>Die Basis-Adresse ergibt keine gültige Endpunkt-Adresse.</summary>
    InvalidBaseUrl,
    /// <summary>401/403 — Schlüssel abgelehnt.</summary>
    Unauthorized,
    /// <summary>402 — kein Guthaben.</summary>
    NoCredit,
    /// <summary>404 mit Modellhinweis — die Kennung kennt der Anbieter nicht.</summary>
    UnknownModel,
    /// <summary>429 — zu viele Anfragen.</summary>
    RateLimited,
    /// <summary>Alles andere mit Statuscode.</summary>
    Http,
    /// <summary>Antwort kam an, war aber nicht verwertbar.</summary>
    MalformedResponse,
    /// <summary>Zeitgrenze überschritten.</summary>
    TimedOut,
    /// <summary>Gar keine Verbindung — Netz weg, Host unbekannt, oder der lokale
    /// Server (Ollama, LM Studio) läuft nicht. Eigener Fall, weil die Abhilfe eine
    /// völlig andere ist als bei einem abgelehnten Schlüssel.</summary>
    CannotConnect,
}

/// <summary>
/// Fehler eines Anbieter-Aufrufs (Mac: RemoteProviderError).
///
/// <para>Bewusst OHNE fertige Anzeigetexte: Die Oberfläche ist zweisprachig und
/// übersetzt in <see cref="ProviderText"/>, was hier nur als Struktur ankommt.
/// Und der Schlüssel taucht in keinem Fall auf — auch nicht in
/// <see cref="LogDescription"/>.</para>
/// </summary>
public sealed class RemoteProviderException : Exception
{
    public RemoteFailure Failure { get; }
    /// <summary>HTTP-Status bei <see cref="RemoteFailure.Http"/>, sonst 0.</summary>
    public int Status { get; }
    /// <summary>Modellkennung bei <see cref="RemoteFailure.UnknownModel"/>.</summary>
    public string Model { get; } = "";
    /// <summary>Sekunden bis zum nächsten Versuch bei <see cref="RemoteFailure.RateLimited"/>,
    /// sofern der Anbieter sie nennt.</summary>
    public double? RetryAfter { get; }

    public RemoteProviderException(RemoteFailure failure, int status = 0,
                                   string model = "", double? retryAfter = null)
        : base(Describe(failure, status, model, retryAfter))
    {
        Failure = failure;
        Status = status;
        Model = model;
        RetryAfter = retryAfter;
    }

    /// <summary>
    /// Lohnt ein zweiter Versuch? Nur bei Ursachen, die von selbst weggehen. Ein
    /// abgelehnter Schlüssel oder ein unbekanntes Modell wird beim zweiten Mal
    /// genauso abgelehnt — das wäre nur Wartezeit und, bei Erfolg, Geld.
    /// </summary>
    public bool IsTransient => Failure switch
    {
        RemoteFailure.TimedOut or RemoteFailure.RateLimited or RemoteFailure.CannotConnect => true,
        RemoteFailure.Http => Status >= 500,
        _ => false,
    };

    /// <summary>Kurzform fürs Protokoll. Enthält nie den Schlüssel und nie den
    /// Antwortrumpf — manche Anbieter spiegeln darin die Anfrage samt Kopfzeilen.</summary>
    public string LogDescription => Message;

    private static string Describe(RemoteFailure failure, int status, string model, double? retryAfter)
        => failure switch
        {
            RemoteFailure.MissingKey => "kein Schlüssel hinterlegt",
            RemoteFailure.InvalidBaseUrl => "Basis-Adresse ungültig",
            RemoteFailure.Unauthorized => "Schlüssel abgelehnt (401/403)",
            RemoteFailure.NoCredit => "kein Guthaben (402)",
            RemoteFailure.UnknownModel => $"Modell unbekannt: {model}",
            RemoteFailure.RateLimited => retryAfter is { } after
                ? $"Ratenlimit (429), erneut in {(int)after} s"
                : "Ratenlimit (429)",
            RemoteFailure.Http => $"HTTP {status}",
            RemoteFailure.MalformedResponse => "Antwort nicht verwertbar",
            RemoteFailure.TimedOut => "Zeitgrenze überschritten",
            _ => "keine Verbindung",
        };
}
