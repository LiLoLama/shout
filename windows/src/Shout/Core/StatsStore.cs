using System.Globalization;
using System.Text.Json.Serialization;

namespace Shout.Core;

/// <summary>
/// Kumulative Nutzungs-Statistiken (bleiben erhalten, auch wenn der Verlauf
/// gekappt wird) — stats.json, Feldnamen kompatibel zum Mac.
///
/// <para><see cref="Record"/> läuft auf dem Threadpool (Ende eines Diktats), die
/// Statistik-Seite liest auf dem UI-Faden. Alles, was die Listen anfasst oder
/// aufzählt, läuft deshalb unter <c>gate</c> — sonst wirft die Seite gelegentlich
/// „Collection was modified" mitten im Aufbau.</para>
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

    private readonly object gate = new();

    public StatsData Data { get; private set; } = new();

    public StatsStore()
    {
        Data = StoreIO.Load<StatsData>("stats.json") ?? new StatsData();
        Data.ActiveDays ??= new List<string>();
    }

    public void Record(int words, double seconds)
    {
        if (words <= 0) return;
        lock (gate)
        {
            Data.TotalWords += words;
            Data.TotalDictations += 1;
            Data.TotalSeconds += Math.Max(0, seconds);
            var key = DayKey(DateTime.Now);
            if (!Data.ActiveDays.Contains(key)) Data.ActiveDays.Add(key);
            SaveLocked();
        }
    }

    /// <summary>Kopie für den Export — der Serializer darf die Listen nicht
    /// aufzählen, während ein Diktat sie fortschreibt.</summary>
    public StatsData Snapshot()
    {
        lock (gate)
            return new StatsData
            {
                TotalWords = Data.TotalWords,
                TotalDictations = Data.TotalDictations,
                TotalSeconds = Data.TotalSeconds,
                ActiveDays = new List<string>(Data.ActiveDays),
            };
    }

    public int AverageWpm
    {
        get
        {
            lock (gate)
                return Data.TotalSeconds > 1
                    ? (int)Math.Round(Data.TotalWords / (Data.TotalSeconds / 60))
                    : 0;
        }
    }

    /// <summary>Aktueller Streak in Tagen (bis heute oder gestern zurück).</summary>
    public int CurrentStreak
    {
        get
        {
            HashSet<string> days;
            lock (gate) days = new HashSet<string>(Data.ActiveDays);
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
            List<string> active;
            lock (gate) active = new List<string>(Data.ActiveDays);
            var days = active
                .Select(d => DateTime.TryParseExact(d, "yyyy-MM-dd", CultureInfo.InvariantCulture,
                                                    DateTimeStyles.None, out var parsed)
                             ? parsed.Date : (DateTime?)null)
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
    public bool IsActive(DateTime day)
    {
        var key = DayKey(day);
        lock (gate) return Data.ActiveDays.Contains(key);
    }

    /// <summary>Ersetzt die Statistik-Daten (für Import).</summary>
    public void ReplaceData(StatsData newData)
    {
        lock (gate)
        {
            Data = newData;
            Data.ActiveDays ??= new List<string>();
            SaveLocked();
        }
    }

    private void SaveLocked() => StoreIO.Save(Data, "stats.json");

    /// <summary>
    /// Tagesschlüssel. INVARIANT, nicht in der Kultur des Nutzers: Unter einem
    /// nicht-gregorianischen Kalender (Hijri, Buddhist) käme sonst ein anderes Jahr
    /// heraus, und Streak-Berechnung wie Mac-Backup lägen daneben.
    /// </summary>
    public static string DayKey(DateTime date) =>
        date.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture);
}
