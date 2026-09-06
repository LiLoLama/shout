using System.Globalization;
using System.Text.Json.Serialization;

namespace Shout.Core;

/// <summary>Gemessene Token einer Anfrage bzw. eines Monats.</summary>
public sealed class TokenCount
{
    public int Prompt { get; set; }
    public int Completion { get; set; }
}

/// <summary>Verbrauch eines Monats, aufgeschlüsselt nach „anbieter · modell".</summary>
public sealed class ProviderMonth
{
    public Dictionary<string, TokenCount> Tokens { get; set; } = new();
    public Dictionary<string, double> Seconds { get; set; } = new();

    // Berechnet und deshalb nicht mitgeschrieben: Sonst stünden die Summen doppelt in
    // der Datei und wären beim nächsten Lesen womöglich älter als die Einzelwerte.
    [JsonIgnore]
    public int TotalTokens => Tokens.Values.Sum(t => t.Prompt + t.Completion);
    [JsonIgnore]
    public double TotalSeconds => Seconds.Values.Sum();
    [JsonIgnore]
    public bool IsEmpty => Tokens.Count == 0 && Seconds.Count == 0;
}

/// <summary>
/// Zählt, was bei Anbietern verbraucht wurde — <b>gemessen, nicht geschätzt</b>: Jede
/// Antwort liefert die echten Token-Zahlen mit, und für Transkription zählen wir die
/// verschickten Sekunden. Dafür braucht es kein Netz.
///
/// <para>Eigene Datei und <b>nicht</b> Teil von <see cref="StatsStore"/>, mit Absicht:</para>
/// <list type="number">
/// <item>Ausgaben sind gerätebezogen. Sie über die Sicherungsdatei auf ein zweites Gerät
/// zu tragen und dort zu addieren würde eine Zahl ergeben, die nichts beschreibt.</item>
/// <item>Das Backup-Format bleibt damit unverändert — kein neues Feld, kein
/// Migrationspfad, ältere Sicherungen lesen sich wie bisher.</item>
/// <item>Die Engines können hier ohne Umweg melden, statt an <see cref="StatsStore"/>
/// gekoppelt zu werden.</item>
/// </list>
///
/// <para>Monate werden nebeneinander behalten, nicht überschrieben: Ein Monatswechsel
/// setzt die Anzeige zurück, ohne die Vorgeschichte zu verlieren.</para>
///
/// <para>Geschrieben wird vom Threadpool (Ende eines Diktats), gelesen vom UI-Faden
/// (Anbieter-Seite). Alles, was die Wörterbücher anfasst, läuft deshalb unter
/// <c>gate</c> — sonst wirft die Seite gelegentlich „Collection was modified" mitten im
/// Aufbau.</para>
/// </summary>
public sealed class ProviderUsageStore
{
    public static ProviderUsageStore Shared { get; } = new();

    private const string UsageFile = "anbieter-verbrauch.json";
    private const string PriceFile = "anbieter-preise.json";

    private readonly object gate = new();
    private Dictionary<string, ProviderMonth> months = new();
    private PriceTable prices = PriceTable.Bundled;

    public ProviderUsageStore()
    {
        months = StoreIO.Load<Dictionary<string, ProviderMonth>>(UsageFile) ?? new();
        // Eine gespeicherte Tabelle gewinnt nur, wenn sie NEUER ist als die
        // mitgelieferte. Sonst würde ein Programm-Update mit frischen Preisen von einem
        // alten Abruf überstimmt.
        var geladen = StoreIO.Load<PriceTable>(PriceFile);
        if (geladen != null && geladen.Updated > PriceTable.BundledUpdated) prices = geladen;
    }

    /// <summary>Kopie für die Anzeige — der Aufbau der Seite darf nicht aufzählen,
    /// während ein Diktat fortschreibt.</summary>
    public Dictionary<string, ProviderMonth> Months
    {
        get { lock (gate) return new Dictionary<string, ProviderMonth>(months); }
    }

    public PriceTable Prices
    {
        get { lock (gate) return prices; }
    }

    // MARK: Aufzeichnen

    public static string Key(string provider, string model) => $"{provider} · {model}";

    /// <summary>Monatsschlüssel. INVARIANT, nicht in der Kultur des Nutzers: Unter einem
    /// nicht-gregorianischen Kalender käme sonst ein anderes Jahr heraus, und die
    /// Monatsanzeige zeigte auf einen Eintrag, den niemand wiederfindet.</summary>
    public static string MonthKey(DateTime date) => date.ToString("yyyy-MM", CultureInfo.InvariantCulture);

    public void Record(TokenUsage tokens, string provider, string model, DateTime? date = null)
    {
        if (tokens.Total <= 0) return;
        lock (gate)
        {
            var eintrag = Key(provider, model);
            var monat = Monat(date);
            if (!monat.Tokens.TryGetValue(eintrag, out var zaehler))
                monat.Tokens[eintrag] = zaehler = new TokenCount();
            zaehler.Prompt += tokens.Prompt;
            zaehler.Completion += tokens.Completion;
            SaveLocked();
        }
    }

    public void Record(double seconds, string provider, string model, DateTime? date = null)
    {
        if (seconds <= 0) return;
        lock (gate)
        {
            var eintrag = Key(provider, model);
            var monat = Monat(date);
            monat.Seconds[eintrag] = monat.Seconds.GetValueOrDefault(eintrag) + seconds;
            SaveLocked();
        }
    }

    // MARK: Abfragen

    public ProviderMonth? Month(DateTime? date = null)
    {
        lock (gate) return months.GetValueOrDefault(MonthKey(date ?? DateTime.Now));
    }

    /// <summary>
    /// Kosten eines Monats. Für Anteile, deren Preis unbekannt ist, gibt es keine Zahl —
    /// deshalb kommt zusätzlich zurück, ob etwas ungerechnet blieb. Die Oberfläche muss
    /// das sagen können, sonst liest sich eine Teilsumme wie die Gesamtsumme.
    /// </summary>
    public (double Usd, bool Unknown) Cost(DateTime? date = null)
    {
        ProviderMonth? monat;
        PriceTable tabelle;
        lock (gate)
        {
            monat = months.GetValueOrDefault(MonthKey(date ?? DateTime.Now));
            tabelle = prices;
            if (monat == null) return (0, false);
            // Unter dem Schloss kopieren, danach rechnen: Die Rechnung selbst braucht
            // es nicht, und ein Diktat soll währenddessen weiterschreiben können.
            monat = new ProviderMonth
            {
                Tokens = new Dictionary<string, TokenCount>(monat.Tokens),
                Seconds = new Dictionary<string, double>(monat.Seconds),
            };
        }

        var summe = 0.0;
        var unbekannt = false;

        foreach (var (eintrag, tokens) in monat.Tokens)
        {
            var teil = ProviderCosts.Cost(tokens, tabelle.PriceForText(ModelFrom(eintrag)));
            if (teil is { } wert) summe += wert; else unbekannt = true;
        }
        foreach (var (eintrag, sekunden) in monat.Seconds)
        {
            var teil = ProviderCosts.Cost(sekunden, tabelle.PriceForAudio(ModelFrom(eintrag)));
            if (teil is { } wert) summe += wert; else unbekannt = true;
        }
        return (summe, unbekannt);
    }

    /// <summary>Modell-ID aus einem Eintragsschlüssel „Anbieter · Modell".</summary>
    public static string ModelFrom(string key)
    {
        var index = key.IndexOf(" · ", StringComparison.Ordinal);
        return index < 0 ? key : key[(index + 3)..];
    }

    // MARK: Preise

    public void ReplacePrices(PriceTable neu)
    {
        lock (gate)
        {
            prices = neu;
            StoreIO.Save(neu, PriceFile);
        }
    }

    // MARK: Persistenz

    private ProviderMonth Monat(DateTime? date)
    {
        var schluessel = MonthKey(date ?? DateTime.Now);
        if (!months.TryGetValue(schluessel, out var monat))
            months[schluessel] = monat = new ProviderMonth();
        return monat;
    }

    private void SaveLocked() => StoreIO.Save(months, UsageFile);
}
