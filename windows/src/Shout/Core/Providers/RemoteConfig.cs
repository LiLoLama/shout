namespace Shout.Core;

/// <summary>
/// Die Einstellung eines Anbieters für einen Schritt. <b>Ohne Schlüssel</b> — der
/// liegt DPAPI-verschlüsselt in <see cref="ProviderKeyStore"/> und darf nie in
/// settings.json oder ins Backup.
///
/// <para>Klasse mit setzbaren Eigenschaften und parameterlosem Konstruktor, weil
/// System.Text.Json sie als Teil von <see cref="Settings"/> in beide Richtungen
/// verarbeiten muss.</para>
/// </summary>
public sealed class RemoteConfig
{
    public string TemplateId { get; set; } = "";
    public string BaseUrl { get; set; } = "";
    public string Model { get; set; } = "";

    public RemoteConfig() { }

    public RemoteConfig(string templateId, string baseUrl, string model)
    {
        TemplateId = templateId;
        BaseUrl = baseUrl;
        Model = model;
    }

    /// <summary>Startwerte aus einer Vorlage.</summary>
    public RemoteConfig(ProviderTemplate template, EnginePurpose purpose)
    {
        TemplateId = template.Id;
        BaseUrl = template.BaseUrl;
        Model = (purpose == EnginePurpose.Text ? template.ChatModels : template.AudioModels)
            .FirstOrDefault() ?? "";
    }

    // MARK: Adressen

    public string? ChatUrl => Url("chat/completions");
    public string? AudioUrl => Url("audio/transcriptions");
    public string? ModelsUrl => Url("models");

    /// <summary>Endpunkt-Pfade, die am Ende einer eingetragenen Basis abgeschnitten werden.</summary>
    private static readonly string[] Endpoints =
        { "/chat/completions", "/audio/transcriptions", "/models" };

    /// <summary>
    /// Baut die Endpunkt-Adresse aus der Basis.
    ///
    /// <para>Die Regeln sind an den Fehlern orientiert, die Leute wirklich machen:</para>
    /// <list type="bullet">
    /// <item>Leerzeichen aus der Zwischenablage fliegen raus.</item>
    /// <item>Schrägstriche am Ende werden entfernt, auch mehrere.</item>
    /// <item>Wer den <b>ganzen</b> Endpunkt kopiert hat, landet trotzdem richtig: die
    /// bekannten Endpunkt-Pfade werden abgeschnitten. Das erlaubt auch den
    /// Quereinstieg — aus einer kopierten Chat-Adresse entsteht die Audio-Adresse,
    /// sonst funktionierte nur der Schritt, den man zuerst eingerichtet hat.</item>
    /// <item>Steht <b>gar kein</b> Pfad da (nur Host, evtl. mit Port), ergänzen wir
    /// <c>/v1</c>. Praktisch alle OpenAI-kompatiblen Endpunkte liegen dort, und „nur
    /// den Host eintragen" ist der häufigste Fall.</item>
    /// </list>
    ///
    /// <para>Was NICHT passiert: ein vorhandener, abweichender Pfad wird nie
    /// „korrigiert". Google liegt unter <c>/v1beta/openai</c>, und daran darf keine
    /// Klugheit der App etwas ändern.</para>
    /// </summary>
    private string? Url(string path)
    {
        var text = (BaseUrl ?? "").Trim();
        if (text.Length == 0) return null;

        text = text.TrimEnd('/');
        foreach (var endpoint in Endpoints)
        {
            if (!text.EndsWith(endpoint, StringComparison.Ordinal)) continue;
            text = text[..^endpoint.Length];
            break;
        }
        text = text.TrimEnd('/');

        // Ohne Schema ist „api.example.com" für Uri keine absolute Adresse; mit einem
        // fremden („localhost:1234" wird als Schema „localhost" gelesen) fällt es
        // unten durch die Schema-Prüfung. Beides muss scheitern, sonst ginge die
        // Anfrage später ins Leere statt beim Eintragen aufzufallen.
        if (!Uri.TryCreate(text, UriKind.Absolute, out var uri)) return null;
        if (uri.Scheme != Uri.UriSchemeHttp && uri.Scheme != Uri.UriSchemeHttps) return null;
        if (string.IsNullOrEmpty(uri.Host)) return null;

        var basePath = uri.AbsolutePath.TrimEnd('/');
        if (basePath.Length == 0) basePath = "/v1";
        return $"{uri.Scheme}://{uri.Authority}{basePath}/{path}";
    }

    // MARK: Speichern

    /// <summary>
    /// Die Konfiguration liegt in settings.json, nicht in einer eigenen Datei: Sie ist
    /// harmlos (kein Schlüssel), und so bleibt sie mit den beiden Schaltern
    /// „lokal/Anbieter" an einer Stelle.
    /// </summary>
    public static RemoteConfig? Load(EnginePurpose purpose)
        => purpose == EnginePurpose.Text ? Settings.Shared.RemoteText : Settings.Shared.RemoteAudio;

    public void Save(EnginePurpose purpose)
    {
        if (purpose == EnginePurpose.Text) Settings.Shared.RemoteText = this;
        else Settings.Shared.RemoteAudio = this;
        Settings.Shared.Save();
    }
}
