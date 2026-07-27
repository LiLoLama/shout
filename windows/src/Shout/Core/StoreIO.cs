using System.Text.Json;
using System.Text.Json.Serialization;

namespace Shout.Core;

/// <summary>
/// Zentrale JSON-Persistenz. Daten liegen unter %APPDATA%\shout\
/// (dictionary.json, history.json, stats.json, settings.json) — Modelle
/// getrennt unter %LOCALAPPDATA%\shout\models\ (groß, nicht roaming-würdig).
/// </summary>
public static class StoreIO
{
    public static string DataDirectory
    {
        get
        {
            var dir = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "shout");
            Directory.CreateDirectory(dir);
            return dir;
        }
    }

    public static string ModelDirectory
    {
        get
        {
            var dir = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                "shout", "models");
            Directory.CreateDirectory(dir);
            return dir;
        }
    }

    /// <summary>
    /// Gemeinsame JSON-Optionen — kompatibel zum Mac-Backup-Format:
    /// camelCase-Namen, ISO-8601-Daten OHNE Sekundenbruchteile (Swifts
    /// .iso8601-Decoder akzeptiert keine Fraktionen), null-Felder weglassen.
    /// </summary>
    public static readonly JsonSerializerOptions JsonOptions = new()
    {
        WriteIndented = true,
        // Ohne Naming-Policy schriebe Settings (einzige Klasse OHNE explizite
        // JsonPropertyName-Attribute) PascalCase — camelCase hier macht alle
        // Dateien einheitlich; case-insensitiv liest ältere Dateien weiter.
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        PropertyNameCaseInsensitive = true,
        DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull,
        Converters = { new IsoSecondsDateConverter() },
    };

    public static T? Load<T>(string fileName) where T : class
    {
        var path = Path.Combine(DataDirectory, fileName);
        try
        {
            if (!File.Exists(path)) return null;
            return JsonSerializer.Deserialize<T>(File.ReadAllText(path), JsonOptions);
        }
        catch
        {
            return null;   // defekte Datei → wie „leer" behandeln, nicht crashen
        }
    }

    public static void Save<T>(T value, string fileName)
    {
        var path = Path.Combine(DataDirectory, fileName);
        try
        {
            // Atomar: erst in Temp-Datei, dann ersetzen (kein halb geschriebenes JSON).
            var tmp = path + ".tmp";
            File.WriteAllText(tmp, JsonSerializer.Serialize(value, JsonOptions));
            File.Move(tmp, path, overwrite: true);
        }
        catch
        {
            // Speichern darf die App nie zum Absturz bringen.
        }
    }
}

/// <summary>
/// ISO 8601 in UTC ohne Sekundenbruchteile ("2026-07-09T17:06:00Z") — exakt das
/// Format von Swifts .iso8601-Strategie, damit Mac ↔ Windows-Backups in BEIDE
/// Richtungen funktionieren. Beim Lesen sind Fraktionen trotzdem erlaubt.
/// </summary>
public sealed class IsoSecondsDateConverter : JsonConverter<DateTime>
{
    public override DateTime Read(ref Utf8JsonReader reader, Type typeToConvert, JsonSerializerOptions options)
        => reader.GetDateTime().ToUniversalTime();

    public override void Write(Utf8JsonWriter writer, DateTime value, JsonSerializerOptions options)
        => writer.WriteStringValue(value.ToUniversalTime().ToString("yyyy-MM-dd'T'HH:mm:ss'Z'"));
}
