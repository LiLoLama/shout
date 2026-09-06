namespace Shout.Core;

/// <summary>Preis eines Textmodells, in <b>USD je Million Token</b>.</summary>
public sealed record ModelPrice(double Input, double Output);

/// <summary>Preis einer Transkription, in <b>USD je Minute</b> — so rechnen die
/// Anbieter dort ab, nicht nach Token.</summary>
public sealed record AudioPrice(double PerMinute);

/// <summary>
/// Preistabelle. Mitgeliefert im Programm, auf Knopfdruck aktualisierbar.
///
/// <para><b>Näherung, und die Oberfläche sagt das auch.</b> Abgerechnet wird beim
/// Anbieter; hier steht, was zum Zeitpunkt des Releases (bzw. des letzten Abrufs)
/// veröffentlicht war. Die Endpunkte der Anbieter liefern Modell-IDs, aber praktisch
/// nie Preise — deshalb ist die einzige maschinenlesbare Quelle die freie Modell-API
/// von OpenRouter.</para>
/// </summary>
public sealed class PriceTable
{
    /// <summary>Wann diese Tabelle entstanden ist — steht in der Oberfläche als „Stand".</summary>
    public DateTime Updated { get; set; }

    /// <summary>Textmodelle, Schlüssel ist die Modell-ID.</summary>
    public Dictionary<string, ModelPrice> Text { get; set; } = new();

    /// <summary>Transkriptions-Modelle.</summary>
    public Dictionary<string, AudioPrice> Audio { get; set; } = new();

    /// <summary>
    /// Preis eines Textmodells.
    ///
    /// <para>Erst genau, dann ohne Organisationsvorsilbe: OpenRouter nennt dasselbe
    /// Modell „openai/gpt-5-mini", OpenAI selbst nur „gpt-5-mini". Ohne diesen zweiten
    /// Versuch wäre die halbe Tabelle nutzlos.</para>
    ///
    /// <para>Ist nichts zu finden, kommt null — <b>es wird keine Zahl erfunden.</b> Eine
    /// erfundene Kostenanzeige ist schlimmer als keine.</para>
    /// </summary>
    public ModelPrice? PriceForText(string model) => Lookup(model, Text);

    public AudioPrice? PriceForAudio(string model) => Lookup(model, Audio);

    private static TValue? Lookup<TValue>(string model, Dictionary<string, TValue> table)
        where TValue : class
    {
        var key = (model ?? "").ToLowerInvariant();
        if (key.Length == 0) return null;

        foreach (var eintrag in table)
            if (eintrag.Key.ToLowerInvariant() == key) return eintrag.Value;

        var ohneVorsilbe = key.Split('/').Last();
        foreach (var eintrag in table)
        {
            var kandidat = eintrag.Key.ToLowerInvariant();
            if (kandidat.Split('/').Last() == ohneVorsilbe) return eintrag.Value;
        }
        return null;
    }

    /// <summary>Stand der mitgelieferten Tabelle: 01.09.2026.</summary>
    public static readonly DateTime BundledUpdated = new(2026, 9, 1, 0, 0, 0, DateTimeKind.Utc);

    /// <summary>
    /// Die mitgelieferte Tabelle. Stand: 01.09.2026, Angaben in USD.
    ///
    /// <para>Bewusst kurz und auf die Modelle beschränkt, die der Katalog vorschlägt:
    /// Eine lange handgepflegte Liste veraltet nur an mehr Stellen gleichzeitig. Alles
    /// Übrige holt der „Preise aktualisieren"-Knopf.</para>
    ///
    /// <para>Jeder Zugriff baut eine frische Tabelle: Sie ist veränderbar (weil sie aus
    /// JSON gelesen wird), und eine geteilte Instanz ließe sich von einer Aufrufstelle
    /// aus für alle anderen verbiegen.</para>
    /// </summary>
    public static PriceTable Bundled => new()
    {
        Updated = BundledUpdated,
        Text = new Dictionary<string, ModelPrice>
        {
            ["gpt-5-mini"] = new(0.25, 2.00),
            ["gpt-5"] = new(1.25, 10.00),
            ["claude-haiku-4.5"] = new(1.00, 5.00),
            ["claude-sonnet-4.5"] = new(3.00, 15.00),
            ["gemini-2.5-flash"] = new(0.30, 2.50),
            ["gemini-2.5-pro"] = new(1.25, 10.00),
            ["mistral-small-latest"] = new(0.20, 0.60),
            ["mistral-large-latest"] = new(2.00, 6.00),
            ["deepseek-chat"] = new(0.27, 1.10),
            ["llama-3.3-70b-versatile"] = new(0.59, 0.79),
            ["grok-4-fast"] = new(0.20, 0.50),
            ["grok-4"] = new(3.00, 15.00),
        },
        Audio = new Dictionary<string, AudioPrice>
        {
            ["whisper-1"] = new(0.006),
            ["gpt-4o-mini-transcribe"] = new(0.003),
            ["whisper-large-v3"] = new(0.00185),
            ["whisper-large-v3-turbo"] = new(0.00067),
            ["voxtral-mini-latest"] = new(0.001),
        },
    };
}
