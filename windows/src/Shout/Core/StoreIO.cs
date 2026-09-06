using System.Globalization;
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
        if (!File.Exists(path)) return null;   // Erststart — der Normalfall, kein Fehler
        try
        {
            return JsonSerializer.Deserialize<T>(File.ReadAllText(path), JsonOptions);
        }
        catch (Exception ex)
        {
            // „Fehlt" und „defekt" sind zwei verschiedene Dinge: Eine unlesbare Datei
            // wird zur Beweissicherung umbenannt, statt sie beim nächsten Save()
            // stillschweigend zu überschreiben (wie am Mac, StoreIO.swift).
            Quarantine(path, ex);
            return null;
        }
    }

    /// <summary>Benennt eine unlesbare Datei in „…​.corrupt-&lt;Zeitstempel&gt;" um.</summary>
    private static void Quarantine(string path, Exception ex)
    {
        try
        {
            var stamp = DateTimeOffset.UtcNow.ToUnixTimeSeconds();
            File.Move(path, $"{path}.corrupt-{stamp}", overwrite: true);
            Log($"{Path.GetFileName(path)} ist defekt ({ex.Message}) — gesichert als .corrupt-{stamp}");
        }
        catch (Exception moveFailed)
        {
            Log($"{Path.GetFileName(path)} ist defekt und ließ sich nicht sichern: {moveFailed.Message}");
        }
    }

    public static void Save<T>(T value, string fileName)
    {
        var path = Path.Combine(DataDirectory, fileName);
        var tmp = path + ".tmp";
        try
        {
            // Atomar: erst in Temp-Datei, dann ersetzen (kein halb geschriebenes JSON).
            File.WriteAllText(tmp, JsonSerializer.Serialize(value, JsonOptions));
            File.Move(tmp, path, overwrite: true);
        }
        catch (Exception ex)
        {
            // Speichern darf die App nie zum Absturz bringen — aber still scheitern
            // soll es auch nicht, sonst sucht man den Datenverlust am falschen Ende.
            Log($"{fileName} konnte nicht geschrieben werden: {ex.Message}");
            try { if (File.Exists(tmp)) File.Delete(tmp); } catch { }
        }
    }

    /// <summary>
    /// Schreibt eine Zeile ins Protokoll neben den Daten (%APPDATA%\shout\shout.log).
    /// Darf selbst nie werfen: Sie wird aus Fehlerpfaden gerufen.
    /// </summary>
    public static void Log(string message)
    {
        try
        {
            var stamp = DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss", CultureInfo.InvariantCulture);
            File.AppendAllText(Path.Combine(DataDirectory, "shout.log"), $"{stamp} {message}\n");
        }
        catch { }
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
        => writer.WriteStringValue(value.ToUniversalTime()
            .ToString("yyyy-MM-dd'T'HH:mm:ss'Z'", CultureInfo.InvariantCulture));
}
