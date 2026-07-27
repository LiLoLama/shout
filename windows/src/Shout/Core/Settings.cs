using System.Text.Json.Serialization;

namespace Shout.Core;

/// <summary>
/// App-Einstellungen — das Windows-Pendant zu UserDefaults, als settings.json.
/// Zugriff über <see cref="Settings.Shared"/>; nach Änderungen Save() rufen.
/// </summary>
public sealed class Settings
{
    // Aufnahme
    public bool AutoStopEnabled { get; set; } = false;
    public double SilenceSeconds { get; set; } = 1.5;

    // Hotkey (Win32-Virtual-Key + Modifier-Bits aus HotkeyManager)
    public uint HotkeyModifiers { get; set; } = 0x0001 | 0x0002;   // MOD_ALT | MOD_CONTROL
    public uint HotkeyKey { get; set; } = 0x20;                    // VK_SPACE

    // Sprache: "de", "en" oder "auto"
    public string Language { get; set; } = "de";

    // Verarbeitung
    public bool SpeechCommandsEnabled { get; set; } = false;
    /// <summary>Wie auf iOS: Formatierung standardmäßig AUS (spart den zweiten
    /// Modell-Download; wer sie will, schaltet sie in den Einstellungen ein).</summary>
    public bool FormattingEnabled { get; set; } = false;

    // Gewählte Modelle (IDs aus ModelCatalog)
    public string AsrModel { get; set; } = "";
    public string LlmModel { get; set; } = "";

    // Einfügen: zusätzlich immer in die Zwischenablage (Standard an)
    public bool KeepInClipboard { get; set; } = true;

    /// <summary>Dezente Töne bei Start der Aufnahme und beim Einfügen.</summary>
    public bool SoundCuesEnabled { get; set; } = true;

    // Pille (wie am Mac): dauerhaft sichtbar, Anker oder frei gezogene Position
    public bool PersistentPill { get; set; } = false;
    /// <summary>"bottomCenter", "bottomLeft", "bottomRight", "topCenter", "topLeft", "topRight".</summary>
    public string PillAnchor { get; set; } = "bottomCenter";
    public bool PillCustom { get; set; } = false;
    public int PillCustomX { get; set; }
    public int PillCustomY { get; set; }

    /// <summary>Aufnahmegerät: -1 = Systemstandard, sonst NAudio-Geräteindex.</summary>
    public int InputDeviceIndex { get; set; } = -1;

    [JsonIgnore]
    public static Settings Shared { get; } = Load();

    private static Settings Load()
    {
        var s = StoreIO.Load<Settings>("settings.json") ?? new Settings();
        // Erststart: für DIESES Gerät empfohlene Modelle als Auswahl setzen.
        if (string.IsNullOrEmpty(s.AsrModel)) s.AsrModel = ModelCatalog.RecommendedAsr().Id;
        if (string.IsNullOrEmpty(s.LlmModel)) s.LlmModel = ModelCatalog.RecommendedLlm().Id;
        return s;
    }

    public void Save() => StoreIO.Save(this, "settings.json");
}
