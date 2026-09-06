namespace Shout.Core;

/// <summary>
/// Klartext für die Anbieter-Oberfläche (Mac: ProviderText.swift).
///
/// <para><see cref="RemoteProviderException"/> trägt absichtlich keine
/// Anzeigetexte: Die Oberfläche ist zweisprachig und übersetzt über
/// <see cref="Loc"/>, und ein Fehlerwert soll außerdem nichts enthalten, was im
/// Protokoll landen könnte. Übersetzt wird deshalb hier, an genau einer Stelle.</para>
/// </summary>
public static class ProviderText
{
    public static string Describe(Exception error)
    {
        if (error is not RemoteProviderException fehler) return Loc.T("Unbekannter Fehler.");

        return fehler.Failure switch
        {
            RemoteFailure.MissingKey => Loc.T("Es ist kein Schlüssel hinterlegt."),
            RemoteFailure.InvalidBaseUrl =>
                Loc.T("Die Adresse ist unbrauchbar. Sie muss mit http:// oder https:// beginnen."),
            RemoteFailure.Unauthorized => Loc.T("Der Schlüssel wurde abgelehnt."),
            RemoteFailure.NoCredit => Loc.T("Beim Anbieter ist kein Guthaben vorhanden."),
            RemoteFailure.UnknownModel => Loc.F("Das Modell „{0}“ kennt der Anbieter nicht.", fehler.Model),
            RemoteFailure.RateLimited => fehler.RetryAfter is { } after
                ? Loc.F("Zu viele Anfragen. Erneut möglich in etwa {0} Sekunden.", (int)after)
                : Loc.T("Zu viele Anfragen. Später erneut versuchen."),
            RemoteFailure.Http => Loc.F("Der Anbieter antwortete mit Fehler {0}.", fehler.Status),
            RemoteFailure.MalformedResponse => Loc.T("Die Antwort des Anbieters war nicht verwertbar."),
            RemoteFailure.TimedOut => Loc.T("Der Anbieter hat nicht rechtzeitig geantwortet."),
            _ => Loc.T("Keine Verbindung. Stimmt die Adresse — und läuft der Server?"),
        };
    }
}
