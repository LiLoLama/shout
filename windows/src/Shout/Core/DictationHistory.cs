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
    }

    private const int MaxEntries = 300;

    public List<Entry> Entries { get; private set; } = new();

    public DictationHistory()
    {
        var loaded = StoreIO.Load<List<Entry>>("history.json");
        if (loaded != null) Entries = loaded.Take(MaxEntries).ToList();
    }

    public void Add(string text)
    {
        var trimmed = text.Trim();
        if (trimmed.Length == 0) return;
        Entries.Insert(0, new Entry { Text = trimmed, Date = DateTime.UtcNow });
        if (Entries.Count > MaxEntries) Entries.RemoveRange(MaxEntries, Entries.Count - MaxEntries);
        Save();
    }

    public void Delete(Entry entry)
    {
        Entries.RemoveAll(e => e.Id == entry.Id);
        Save();
    }

    public void Clear()
    {
        Entries.Clear();
        Save();
    }

    /// <summary>Ersetzt alle Einträge (für Import) — ebenfalls gekappt.</summary>
    public void ReplaceEntries(List<Entry> newEntries)
    {
        Entries = newEntries.Take(MaxEntries).ToList();
        Save();
    }

    private void Save() => StoreIO.Save(Entries, "history.json");
}
