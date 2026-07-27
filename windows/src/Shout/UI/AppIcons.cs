using System.Reflection;

namespace Shout.UI;

/// <summary>
/// Das App-Logo (dieselbe Grafik wie Mac und iOS) für Fenster, Taskleiste und
/// Infobereich. Die .ico liegt als eingebettete Ressource bei, damit sich zu
/// jeder Stelle die passgenaue Größe holen lässt — ein hochskaliertes 32er-Icon
/// sieht in der 16-px-Taskleiste unscharf aus.
/// </summary>
internal static class AppIcons
{
    private const string ResourceName = "shout.ico";

    private static Icon? window;
    private static Icon? trayIdle;
    private static Icon? trayRecording;

    /// <summary>
    /// Fenster- und Taskleisten-Symbol. Immer mit ausdrücklicher Größe geladen:
    /// ohne Größenangabe scheitert System.Drawing.Icon an den PNG-komprimierten
    /// Ebenen der .ico und WinForms fällt auf sein Standardsymbol zurück.
    /// </summary>
    public static Icon? Window => window ??= Load(SystemInformation.IconSize);

    /// <summary>
    /// Symbol im Infobereich. Wie am Mac (dort wechselt die Menüleiste zwischen
    /// 🎙️ und 🔴) zeigt der Ruhezustand das Logo und die laufende Aufnahme einen
    /// gefüllten Signalpunkt — bei 16 px ist das der einzige Unterschied, den man
    /// zuverlässig erkennt.
    /// </summary>
    public static Icon Tray(bool recording)
    {
        if (recording) return trayRecording ??= RecordingDot();
        // Genau die kleine Ebene entnehmen — sonst skaliert Windows eine große
        // herunter und das Symbol wird unscharf.
        return trayIdle ??= Load(SystemInformation.SmallIconSize) ?? RecordingDot();
    }

    private static Icon? Load(Size? size)
    {
        try
        {
            using var stream = Assembly.GetExecutingAssembly()
                .GetManifestResourceStream(ResourceName);
            if (stream == null) return null;
            return size is { } s ? new Icon(stream, s) : new Icon(stream);
        }
        catch
        {
            return null;   // ohne Logo lieber der gezeichnete Punkt als ein Absturz
        }
    }

    /// <summary>Gefüllter Signalpunkt für die laufende Aufnahme.</summary>
    private static Icon RecordingDot()
    {
        using var bmp = new Bitmap(32, 32);
        using var g = Graphics.FromImage(bmp);
        g.SmoothingMode = System.Drawing.Drawing2D.SmoothingMode.AntiAlias;
        using var brush = new SolidBrush(Theme.Live);
        g.FillEllipse(brush, 3, 3, 26, 26);
        var handle = bmp.GetHicon();
        return Icon.FromHandle(handle);
    }
}
