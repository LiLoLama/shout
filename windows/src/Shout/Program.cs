using Shout.App;

namespace Shout;

internal static class Program
{
    [STAThread]
    private static void Main()
    {
        // Nur eine Instanz — ein zweiter Start würde Hotkey/Tray doppeln.
        using var mutex = new Mutex(true, "shout-single-instance", out var isFirst);
        if (!isFirst) return;

        ApplicationConfiguration.Initialize();
        Application.Run(new TrayContext());
    }
}
