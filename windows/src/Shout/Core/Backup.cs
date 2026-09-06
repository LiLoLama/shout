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

    /// <summary>Höchste Fassung, die diese App versteht. Eine neuere Datei wird
    /// abgewiesen statt halb eingelesen — sonst gingen die Felder verloren, die sie
    /// zusätzlich enthält, und der nächste Export schriebe sie endgültig weg.</summary>
    public const int CurrentVersion = 1;

    /// <summary>Geteilte Einstellungen (Teilmenge; plattformspezifische Felder wie
    /// der Mac-Tastencode werden beim Import schlicht ignoriert).</summary>
    public sealed class SettingsSnapshot
    {
        /// <summary>Aufnahme-Art — auf beiden Plattformen dieselben drei Werte
        /// ("hold", "toggle", "doubleTap").</summary>
        [JsonPropertyName("mode")] public string? Mode { get; set; }
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
            Dictionary = dictionary.Snapshot(),
            History = history.Entries,
            Stats = stats.Snapshot(),
            Settings = new SettingsSnapshot
            {
                Mode = s.HotkeyMode,
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
        if (bundle.Version > CurrentVersion)
            return Loc.F("Dieses Backup stammt aus einer neueren Version von shout. (Fassung {0}). Bitte zuerst shout. aktualisieren.",
                         bundle.Version);

        dictionary.ReplaceContents(bundle.Dictionary);
        history.ReplaceEntries(bundle.History);
        stats.ReplaceData(bundle.Stats);

        var s = Core.Settings.Shared;
        // Die Aufnahme-Art wandert mit, die Tastenbelegung NICHT: Tastencodes und
        // Modifier-Bits sind auf beiden Systemen verschieden, und eine übernommene
        // Mac-Kombination wäre unter Windows im besten Fall unbelegt.
        if (bundle.Settings.Mode is "hold" or "toggle" or "doubleTap") s.HotkeyMode = bundle.Settings.Mode;
        if (bundle.Settings.AutoStop is { } auto) s.AutoStopEnabled = auto;
        if (bundle.Settings.SilenceSeconds is { } sil) s.SilenceSeconds = sil;
        if (bundle.Settings.FormattingEnabled is { } fmt) s.FormattingEnabled = fmt;
        if (bundle.Settings.VoiceProfile is { } profile) s.VoiceProfile = profile;
        s.Save();

        return Loc.F("Importiert: {0} Begriffe, {1} Diktate.",
                     bundle.Dictionary.Terms.Count, bundle.History.Count);
    }
}
