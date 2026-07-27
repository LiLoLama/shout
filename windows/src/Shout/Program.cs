using System.Runtime.InteropServices;
using Shout.App;

namespace Shout;

internal static class Program
{
    /// <summary>Systemweit registrierte Nachricht: „Einstellungen öffnen".</summary>
    internal static readonly uint OpenSettingsMessage = RegisterWindowMessage("ShoutOpenSettings");

    private const int HwndBroadcast = 0xFFFF;

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern uint RegisterWindowMessage(string name);

    [DllImport("user32.dll")]
    private static extern bool PostMessage(IntPtr hWnd, uint msg, IntPtr wParam, IntPtr lParam);

    [STAThread]
    private static void Main(string[] args)
    {
        // Nur eine Instanz — ein zweiter Start würde Hotkey/Tray doppeln.
        using var mutex = new Mutex(true, "shout-single-instance", out var isFirst);
        if (!isFirst)
        {
            // Zweiter Start (z. B. „shout.exe --settings" aus einer Verknüpfung):
            // die laufende Instanz holt ihr Fenster nach vorn, dieser Prozess endet.
            if (args.Contains("--settings", StringComparer.OrdinalIgnoreCase))
                PostMessage(HwndBroadcast, OpenSettingsMessage, IntPtr.Zero, IntPtr.Zero);
            return;
        }

        ApplicationConfiguration.Initialize();
        Application.Run(new TrayContext(openSettings: args.Contains("--settings", StringComparer.OrdinalIgnoreCase)));
    }
}
