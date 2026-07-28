using Shout.App;
using Shout.Core;

namespace Shout.UI;

/// <summary>
/// „Statistiken" — Kennzahlen-Kacheln, Streak mit Aktivitäts-Kalender,
/// abgeleitete Werte aus dem Verlauf und „Dein Sprachprofil" vom lokalen
/// KI-Textmodell (Mac: StatisticsView.swift).
/// </summary>
internal sealed class StatisticsPage : PageBase, IRefreshablePage
{
    protected override int MaxContentWidth => 680;

    /// <summary>Diktate, bis „Dein Sprachprofil" freigeschaltet ist (wie am Mac).</summary>
    private const int UnlockAt = 5;

    private readonly TrayContext app;
    private readonly StatsStore stats;
    private readonly DictationHistory history;
    private readonly PersonalDictionary dictionary;

    /// <summary>Läuft gerade eine Profil-Erzeugung? Steuert Knopftext und Sperre.</summary>
    private bool generating;
    /// <summary>Letzter Fehlschlag, wird bis zum nächsten Versuch angezeigt.</summary>
    private bool lastAttemptFailed;

    public StatisticsPage(TrayContext app, StatsStore stats, DictationHistory history,
                          PersonalDictionary dictionary)
    {
        this.app = app;
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

        PushVoiceProfile();

        NotifyHeightChanged();
    }

    // MARK: „Dein Sprachprofil"

    /// <summary>
    /// Freigeschaltet ab <see cref="UnlockAt"/> Diktaten. Ohne geladenes
    /// KI-Textmodell gibt es nichts zu erzeugen — das ist unter Windows der
    /// Normalfall, weil die Aufbereitung standardmäßig AUS ist. Darum in diesem
    /// Fall ein klarer Hinweis statt eines Knopfs, der nichts tut.
    /// </summary>
    private void PushVoiceProfile()
    {
        var box = new ConsoleBox { Title = Loc.T("Dein Sprachprofil") };
        var done = stats.Data.TotalDictations;

        if (done < UnlockAt)
        {
            box.Add(TextBlock.Body(Loc.F("Wird nach {0} weiteren Diktaten freigeschaltet.", UnlockAt - done)), 0);
            Push(box);
            return;
        }

        var profile = Settings.Shared.VoiceProfile;
        box.Add(profile.Length > 0
            ? new TextBlock(profile, Theme.Body, Theme.Gray(0.9))
            : TextBlock.Body(Loc.T("shout. kann aus deinen Diktaten ein kurzes Profil deines Sprachstils erstellen — vollständig lokal.")), 0);

        if (!app.FormatterReady && !generating)
        {
            box.Add(TextBlock.Footnote(
                Loc.T("Dafür muss „Text automatisch aufräumen“ eingeschaltet sein — das lädt das KI-Textmodell.")), 10);
            Push(box);
            return;
        }

        if (lastAttemptFailed)
            box.Add(TextBlock.Footnote(Loc.T("Profil konnte nicht erstellt werden.")), 10);

        var button = new ConsoleButton(generating
            ? Loc.T("Erstelle …")
            : profile.Length > 0 ? Loc.T("Aktualisieren") : Loc.T("Profil erstellen"));
        button.SetEnabled(!generating);
        button.Click2 += GenerateVoiceProfile;
        box.Add(new Cluster(new Control[] { button }), 14);

        Push(box);
    }

    /// <summary>Textprobe aus dem Verlauf ans Modell geben (wie am Mac: die
    /// letzten 25 Diktate, auf 2000 Zeichen begrenzt).</summary>
    private void GenerateVoiceProfile()
    {
        if (generating) return;

        var sample = string.Join("\n", history.Entries.Take(25).Select(e => e.Text));
        if (sample.Length > 2000) sample = sample[..2000];
        if (sample.Trim().Length == 0) return;

        generating = true;
        lastAttemptFailed = false;
        // NICHT synchron neu aufbauen: wir stecken noch im Click-Handler des
        // Knopfs, den TrimStack gerade disposen würde. Erst nach der
        // Maus-Verarbeitung umbauen.
        BeginInvoke(new Action(Rebuild));

        _ = Task.Run(async () =>
        {
            var profile = await app.DescribeVoiceAsync(sample);
            // Das Fenster wird beim Sprachwechsel neu gebaut — nach dem Warten
            // kann diese Seite also schon weg sein.
            if (IsDisposed || !IsHandleCreated) return;
            BeginInvoke(() =>
            {
                generating = false;
                if (string.IsNullOrWhiteSpace(profile))
                {
                    lastAttemptFailed = true;
                }
                else
                {
                    Settings.Shared.VoiceProfile = profile.Trim();
                    Settings.Shared.Save();
                }
                Rebuild();
            });
        });
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
