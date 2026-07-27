using System.Text.Json.Serialization;

namespace Shout.Core;

/// <summary>
/// Kumulative Nutzungs-Statistiken (bleiben erhalten, auch wenn der Verlauf
/// gekappt wird) — stats.json, Feldnamen kompatibel zum Mac.
/// </summary>
public sealed class StatsStore
{
    public sealed class StatsData
    {
        [JsonPropertyName("totalWords")] public int TotalWords { get; set; }
        [JsonPropertyName("totalDictations")] public int TotalDictations { get; set; }
        [JsonPropertyName("totalSeconds")] public double TotalSeconds { get; set; }
        [JsonPropertyName("activeDays")] public List<string> ActiveDays { get; set; } = new();   // "yyyy-MM-dd"
    }

    public StatsData Data { get; private set; } = new();

    public StatsStore()
    {
        Data = StoreIO.Load<StatsData>("stats.json") ?? new StatsData();
    }

    public void Record(int words, double seconds)
    {
        if (words <= 0) return;
        Data.TotalWords += words;
        Data.TotalDictations += 1;
        Data.TotalSeconds += Math.Max(0, seconds);
        var key = DayKey(DateTime.Now);
        if (!Data.ActiveDays.Contains(key)) Data.ActiveDays.Add(key);
        Save();
    }

    public int AverageWpm =>
        Data.TotalSeconds > 1
            ? (int)Math.Round(Data.TotalWords / (Data.TotalSeconds / 60))
            : 0;

    /// <summary>Aktueller Streak in Tagen (bis heute oder gestern zurück).</summary>
    public int CurrentStreak
    {
        get
        {
            var days = new HashSet<string>(Data.ActiveDays);
            var day = DateTime.Today;
            if (!days.Contains(DayKey(day))) day = day.AddDays(-1);
            var streak = 0;
            while (days.Contains(DayKey(day)))
            {
                streak++;
                day = day.AddDays(-1);
            }
            return streak;
        }
    }

    /// <summary>Längster jemals erreichter Streak (für die Statistik-Seite).</summary>
    public int LongestStreak
    {
        get
        {
            var days = Data.ActiveDays
                .Select(d => DateTime.TryParse(d, out var parsed) ? parsed.Date : (DateTime?)null)
                .Where(d => d.HasValue)
                .Select(d => d!.Value)
                .Distinct()
                .OrderBy(d => d)
                .ToList();

            var best = 0;
            var run = 0;
            DateTime? previous = null;
            foreach (var day in days)
            {
                run = previous.HasValue && (day - previous.Value).Days == 1 ? run + 1 : 1;
                best = Math.Max(best, run);
                previous = day;
            }
            return best;
        }
    }

    /// <summary>War an diesem Tag mindestens ein Diktat? (Aktivitäts-Kalender)</summary>
    public bool IsActive(DateTime day) => Data.ActiveDays.Contains(DayKey(day));

    /// <summary>Ersetzt die Statistik-Daten (für Import).</summary>
    public void ReplaceData(StatsData newData)
    {
        Data = newData;
        Save();
    }

    private void Save() => StoreIO.Save(Data, "stats.json");

    public static string DayKey(DateTime date) => date.ToString("yyyy-MM-dd");
}
