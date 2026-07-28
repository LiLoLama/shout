using System.Text.Json;
using System.Text.Json.Serialization;

namespace Shout.Core;

/// <summary>
/// Backup-Bundle — dasselbe JSON-Format wie die Mac-/iOS-App (shout-backup.json),
/// damit Wörterbuch, Verlauf und Statistiken zwischen ALLEN Plattformen
/// übertragbar sind. Unbekannte Felder werden beim Import ignoriert.
/// </summary>
public sealed class BackupBundle
{
    [JsonPropertyName("version")] public int Version { get; set; } = 1;
    [JsonPropertyName("exportedAt")] public DateTime ExportedAt { get; set; } = DateTime.UtcNow;
    [JsonPropertyName("dictionary")] public PersonalDictionary.Contents Dictionary { get; set; } = new();
    [JsonPropertyName("history")] public List<DictationHistory.Entry> History { get; set; } = new();
    [JsonPropertyName("stats")] public StatsStore.StatsData Stats { get; set; } = new();
    [JsonPropertyName("settings")] public SettingsSnapshot Settings { get; set; } = new();

    /// <summary>Geteilte Einstellungen (Teilmenge; plattformspezifische Felder wie
    /// der Mac-Hotkey werden beim Import schlicht ignoriert).</summary>
    public sealed class SettingsSnapshot
    {
        [JsonPropertyName("autoStop")] public bool? AutoStop { get; set; }
        [JsonPropertyName("silenceSeconds")] public double? SilenceSeconds { get; set; }
        [JsonPropertyName("formattingEnabled")] public bool? FormattingEnabled { get; set; }
        [JsonPropertyName("voiceProfile")] public string? VoiceProfile { get; set; }
    }

    // MARK: Export / Import

    public static string ExportToFile(string path, PersonalDictionary dictionary,
                                      DictationHistory history, StatsStore stats)
    {
        var s = Core.Settings.Shared;
        var bundle = new BackupBundle
        {
            Dictionary = dictionary.Data,
            History = history.Entries,
            Stats = stats.Data,
            Settings = new SettingsSnapshot
            {
                AutoStop = s.AutoStopEnabled,
                SilenceSeconds = s.SilenceSeconds,
                FormattingEnabled = s.FormattingEnabled,
                VoiceProfile = s.VoiceProfile.Length > 0 ? s.VoiceProfile : null,
            },
        };
        File.WriteAllText(path, JsonSerializer.Serialize(bundle, StoreIO.JsonOptions));
        return path;
    }

    /// <summary>Übernimmt ein Backup (von Mac, iPhone oder Windows). Ersetzt
    /// Wörterbuch, Verlauf, Statistiken; überträgt geteilte Einstellungen.
    /// Liefert eine Ergebnis-Meldung für die UI.</summary>
    public static string ImportFromFile(string path, PersonalDictionary dictionary,
                                        DictationHistory history, StatsStore stats)
    {
        BackupBundle? bundle;
        try
        {
            bundle = JsonSerializer.Deserialize<BackupBundle>(File.ReadAllText(path), StoreIO.JsonOptions);
        }
        catch
        {
            return Loc.T("Ungültige Backup-Datei.");
        }
        if (bundle == null) return Loc.T("Ungültige Backup-Datei.");

        dictionary.ReplaceContents(bundle.Dictionary);
        history.ReplaceEntries(bundle.History);
        stats.ReplaceData(bundle.Stats);

        var s = Core.Settings.Shared;
        if (bundle.Settings.AutoStop is { } auto) s.AutoStopEnabled = auto;
        if (bundle.Settings.SilenceSeconds is { } sil) s.SilenceSeconds = sil;
        if (bundle.Settings.FormattingEnabled is { } fmt) s.FormattingEnabled = fmt;
        if (bundle.Settings.VoiceProfile is { } profile) s.VoiceProfile = profile;
        s.Save();

        return Loc.F("Importiert: {0} Begriffe, {1} Diktate.",
                     bundle.Dictionary.Terms.Count, bundle.History.Count);
    }
}
