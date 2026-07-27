using Shout.Core;

namespace Shout.UI;

/// <summary>
/// „Statistiken" — Kennzahlen-Kacheln, Streak mit Aktivitäts-Kalender und
/// abgeleitete Werte aus dem Verlauf (Mac: StatisticsView.swift). Das
/// KI-Sprachprofil der Mac-App fehlt hier noch.
/// </summary>
internal sealed class StatisticsPage : PageBase, IRefreshablePage
{
    protected override int MaxContentWidth => 680;

    private readonly StatsStore stats;
    private readonly DictationHistory history;
    private readonly PersonalDictionary dictionary;

    public StatisticsPage(StatsStore stats, DictationHistory history, PersonalDictionary dictionary)
    {
        this.stats = stats;
        this.history = history;
        this.dictionary = dictionary;
        Push(new SectionHeader(Loc.T("Statistiken")), 0);
        Rebuild();
    }

    public void Refresh2() => Rebuild();

    private void Rebuild()
    {
        TrimStack(1);

        Push(new GridRow(new Control[]
        {
            new StatCard(stats.Data.TotalWords.ToString("N0"), Loc.T("Wörter gesamt")),
            new StatCard(stats.AverageWpm.ToString(), Loc.T("Ø Wörter/Minute")),
            new StatCard(stats.Data.TotalDictations.ToString(), Loc.T("Diktate")),
            new StatCard(dictionary.Data.Corrections.Count.ToString(), Loc.T("Korrekturen gelernt")),
        }, 150));

        var streak = new ConsoleBox { Title = Loc.T("Streak") };
        streak.Add(new MetricRow(new[]
        {
            (stats.CurrentStreak.ToString(), Loc.T("Tage aktuell")),
            (stats.LongestStreak.ToString(), Loc.T("längster")),
        }), 0);
        streak.Add(new HeatmapView(stats), 14);
        Push(streak);

        Push(new GridRow(new Control[]
        {
            new InfoCard(Loc.T("Meistgenutztes Wort"), MostUsedWord() ?? "—"),
            new InfoCard(Loc.T("Aktivste Zeit"), PeakTime() ?? "—"),
        }, 220));

        NotifyHeightChanged();
    }

    // MARK: Ableitungen aus dem Verlauf (gleiche Regeln wie am Mac)

    /// <summary>Füllwörter, die als „meistgenutztes Wort" nichts aussagen — deutsch
    /// und englisch, weil diktiert werden kann, was der Nutzer will.</summary>
    private static readonly HashSet<string> Stopwords = new(StringComparer.OrdinalIgnoreCase)
    {
        "that", "this", "these", "those", "with", "from", "have", "been", "were", "they",
        "them", "their", "there", "then", "than", "what", "when", "which", "would", "could",
        "should", "will", "just", "like", "about", "your", "yours", "mine", "into", "some",
        "also", "because", "here", "very", "much", "more", "most", "only", "even", "does",

        "und", "oder", "aber", "dass", "eine", "einen", "einem", "einer", "nicht", "auch",
        "dann", "wenn", "also", "dieser", "diese", "dieses", "noch", "schon", "sein", "sind",
        "haben", "hier", "dort", "mein", "dein", "kann", "können", "wird", "werden", "mich",
        "dich", "sich", "wir", "ihr", "ihre", "über", "unter", "beim", "vom", "zum", "zur",
    };

    private string? MostUsedWord()
    {
        var counts = new Dictionary<string, int>(StringComparer.OrdinalIgnoreCase);
        foreach (var entry in history.Entries)
        {
            foreach (var raw in entry.Text.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries))
            {
                var word = new string(raw.Where(char.IsLetter).ToArray()).ToLowerInvariant();
                if (word.Length < 4 || Stopwords.Contains(word)) continue;
                counts[word] = counts.GetValueOrDefault(word) + 1;
            }
        }
        return counts.Count == 0 ? null : counts.MaxBy(kv => kv.Value).Key;
    }

    private string? PeakTime()
    {
        if (history.Entries.Count == 0) return null;
        var buckets = new Dictionary<int, int>();
        foreach (var entry in history.Entries)
        {
            var hour = entry.Date.ToLocalTime().Hour;
            buckets[hour] = buckets.GetValueOrDefault(hour) + 1;
        }
        var peak = buckets.MaxBy(kv => kv.Value).Key;
        return peak switch
        {
            >= 5 and < 11 => Loc.T("Vormittags"),
            >= 11 and < 14 => Loc.T("Mittags"),
            >= 14 and < 18 => Loc.T("Nachmittags"),
            >= 18 and < 23 => Loc.T("Abends"),
            _ => Loc.T("Nachts"),
        };
    }
}
