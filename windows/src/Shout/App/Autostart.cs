using Microsoft.Win32;

namespace Shout.App;

/// <summary>
/// „Mit Windows starten" — das Pendant zu <c>SMAppService</c> in der Mac-App.
/// Eingetragen wird unter <c>HKEY_CURRENT_USER</c>, also ohne Administratorrechte
/// und nur für den angemeldeten Nutzer.
/// </summary>
public static class Autostart
{
    private const string RunKey = @"Software\Microsoft\Windows\CurrentVersion\Run";
    private const string ValueName = "shout.";

    /// <summary>
    /// Der Pfad, der eingetragen wird. Bei einer per Setup installierten Kopie ist das
    /// der <b>Stub</b> im Installationsordner, nicht die Exe im Versionsordner: Velopack
    /// legt jede Version in einen eigenen Ordner („current", „app-1.2.0"), und ein
    /// Eintrag darauf zeigte nach der nächsten Aktualisierung ins Leere.
    /// </summary>
    private static string? LaunchPath()
    {
        var exe = Environment.ProcessPath;
        if (string.IsNullOrEmpty(exe)) return null;

        var directory = Path.GetDirectoryName(exe);
        var name = Path.GetFileName(exe);
        while (!string.IsNullOrEmpty(directory))
        {
            var folder = Path.GetFileName(directory);
            if (folder.Equals("current", StringComparison.OrdinalIgnoreCase)
                || folder.StartsWith("app-", StringComparison.OrdinalIgnoreCase))
            {
                var parent = Path.GetDirectoryName(directory);
                var stub = parent == null ? null : Path.Combine(parent, name);
                if (stub != null && File.Exists(stub)) return stub;
            }
            directory = Path.GetDirectoryName(directory);
        }
        return exe;
    }

    /// <summary>Steht der Eintrag? (Die Wahrheit steht in der Registry, nicht in den
    /// Einstellungen — ein Nutzer kann ihn über den Task-Manager abschalten.)</summary>
    public static bool IsEnabled
    {
        get
        {
            try
            {
                using var key = Registry.CurrentUser.OpenSubKey(RunKey);
                return key?.GetValue(ValueName) is string value && value.Length > 0;
            }
            catch
            {
                return false;
            }
        }
    }

    /// <summary>Setzt oder entfernt den Eintrag. Liefert false, wenn die Registry
    /// nicht schreibbar ist (verwaltete Rechner) — die Oberfläche sagt es dann.</summary>
    public static bool Apply(bool enabled)
    {
        try
        {
            using var key = Registry.CurrentUser.CreateSubKey(RunKey);
            if (key == null) return false;
            if (enabled)
            {
                var path = LaunchPath();
                if (path == null) return false;
                key.SetValue(ValueName, $"\"{path}\"");
            }
            else if (key.GetValue(ValueName) != null)
            {
                key.DeleteValue(ValueName, throwOnMissingValue: false);
            }
            return true;
        }
        catch (Exception ex)
        {
            Core.StoreIO.Log($"Autostart konnte nicht gesetzt werden: {ex.Message}");
            return false;
        }
    }
}
