using System.Text.Json.Serialization;

namespace Shout.Core;

/// <summary>
/// Verlauf der Diktate — lokal als history.json, Feldnamen kompatibel zum Mac.
/// </summary>
public sealed class DictationHistory
{
    public sealed class Entry
    {
        [JsonPropertyName("id")] public Guid Id { get; set; } = Guid.NewGuid();
        [JsonPropertyName("text")] public string Text { get; set; } = "";
        [JsonPropertyName("date")] public DateTime Date { get; set; } = DateTime.UtcNow;

        /// <summary>
        /// Das, was die Spracherkennung WIRKLICH geliefert hat, vor Sprachbefehlen,
        /// Aufbereitung und Wörterbuch (Mac: Entry.raw). Nur gesetzt, wenn sich der
        /// fertige Text davon unterscheidet — sonst stünde alles doppelt in der Datei.
        /// Ohne ihn lässt sich fehlender Inhalt nicht der richtigen Stufe zuordnen.
        /// </summary>
        [JsonPropertyName("raw")] public string? Raw { get; set; }
    }

    private const int MaxEntries = 300;

    private readonly object gate = new();
    private List<Entry> entries = new();

    /// <summary>Kopie der Einträge. Der Verlauf wächst auf dem Threadpool, gelesen
    /// wird auf dem UI-Faden — eine geteilte Liste würde beim Aufzählen werfen.</summary>
    public List<Entry> Entries
    {
        get { lock (gate) return new List<Entry>(entries); }
    }

    public DictationHistory()
    {
        var loaded = StoreIO.Load<List<Entry>>("history.json");
        if (loaded != null) entries = loaded.Take(MaxEntries).ToList();
    }

    /// <summary>Nimmt ein Diktat auf. <paramref name="raw"/> ist das Rohtranskript;
    /// es wird nur gesichert, wenn es vom eingefügten Text abweicht.</summary>
    public void Add(string text, string? raw = null)
    {
        var trimmed = text.Trim();
        if (trimmed.Length == 0) return;
        var rawTrimmed = raw?.Trim();
        lock (gate)
        {
            entries.Insert(0, new Entry
            {
                Text = trimmed,
                Date = DateTime.UtcNow,
                Raw = string.IsNullOrEmpty(rawTrimmed) || rawTrimmed == trimmed ? null : rawTrimmed,
            });
            if (entries.Count > MaxEntries) entries.RemoveRange(MaxEntries, entries.Count - MaxEntries);
            SaveLocked();
        }
    }

    public void Delete(Entry entry)
    {
        lock (gate)
        {
            entries.RemoveAll(e => e.Id == entry.Id);
            SaveLocked();
        }
    }

    public void Clear()
    {
        lock (gate)
        {
            entries.Clear();
            SaveLocked();
        }
    }

    /// <summary>Ersetzt alle Einträge (für Import) — ebenfalls gekappt.</summary>
    public void ReplaceEntries(List<Entry> newEntries)
    {
        lock (gate)
        {
            entries = newEntries.Take(MaxEntries).ToList();
            SaveLocked();
        }
    }

    private void SaveLocked() => StoreIO.Save(entries, "history.json");
}
