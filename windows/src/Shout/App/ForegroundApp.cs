using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;

namespace Shout.App;

/// <summary>
/// Welches Programm ist gerade im Vordergrund? Daraus entsteht der Register-Hinweis
/// für die Aufbereitung (Mac: die Bundle-ID des zuletzt aktiven Programms) — in eine
/// E-Mail gehört ein anderer Ton als in ein Terminal.
///
/// <para>Der Name wird beim START der Aufnahme genommen, nicht am Ende: Bis der Text
/// fertig ist, kann längst ein anderes Fenster vorne sein.</para>
/// </summary>
public static class ForegroundApp
{
    [DllImport("user32.dll")]
    private static extern IntPtr GetForegroundWindow();

    [DllImport("user32.dll")]
    private static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern int GetClassName(IntPtr hWnd, StringBuilder text, int count);

    /// <summary>
    /// Name der Programmdatei des Vordergrundfensters, klein geschrieben und ohne
    /// Endung („outlook", „code"). <c>null</c>, wenn es sich nicht ermitteln lässt
    /// oder shout. selbst vorne ist.
    /// </summary>
    public static string? Current()
    {
        try
        {
            var window = GetForegroundWindow();
            if (window == IntPtr.Zero) return null;
            _ = GetWindowThreadProcessId(window, out var processId);
            if (processId == 0) return null;

            using var process = Process.GetProcessById((int)processId);
            var name = process.ProcessName.ToLowerInvariant();
            // Das eigene Fenster sagt nichts über das Ziel aus.
            return name == Process.GetCurrentProcess().ProcessName.ToLowerInvariant() ? null : name;
        }
        catch
        {
            // Zugriff verweigert (erhöhte Rechte), Prozess schon beendet — der
            // Register-Hinweis ist eine Zugabe, kein Grund für einen Fehler.
            return null;
        }
    }
}
