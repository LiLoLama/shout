using System.Runtime.InteropServices;

namespace Shout.App;

/// <summary>
/// Globaler System-Hotkey über RegisterHotKey — das Windows-Pendant zum
/// macOS-Event-Tap. Ein unsichtbares NativeWindow empfängt WM_HOTKEY.
/// </summary>
public sealed class HotkeyManager : NativeWindow, IDisposable
{
    // Modifier-Bits für RegisterHotKey
    public const uint ModAlt = 0x0001;
    public const uint ModControl = 0x0002;
    public const uint ModShift = 0x0004;
    public const uint ModWin = 0x0008;
    private const uint ModNoRepeat = 0x4000;   // kein Dauerfeuer beim Halten

    private const int WmHotkey = 0x0312;
    private const int HotkeyId = 0xB00F;

    [DllImport("user32.dll")]
    private static extern bool RegisterHotKey(IntPtr hWnd, int id, uint fsModifiers, uint vk);

    [DllImport("user32.dll")]
    private static extern bool UnregisterHotKey(IntPtr hWnd, int id);

    public event Action? OnHotkey;
    private bool registered;

    public HotkeyManager()
    {
        CreateHandle(new CreateParams());   // unsichtbares Message-Fenster
    }

    /// <summary>Registriert den Hotkey neu. false, wenn die Kombination belegt ist.</summary>
    public bool Register(uint modifiers, uint key)
    {
        Unregister();
        registered = RegisterHotKey(Handle, HotkeyId, modifiers | ModNoRepeat, key);
        return registered;
    }

    public void Unregister()
    {
        if (registered) UnregisterHotKey(Handle, HotkeyId);
        registered = false;
    }

    protected override void WndProc(ref Message m)
    {
        if (m.Msg == WmHotkey && m.WParam.ToInt32() == HotkeyId)
            OnHotkey?.Invoke();
        base.WndProc(ref m);
    }

    public void Dispose()
    {
        Unregister();
        DestroyHandle();
    }

    /// <summary>Lesbare Beschreibung („Strg + Alt + Leertaste") für die UI.</summary>
    public static string Describe(uint modifiers, uint key)
    {
        var parts = new List<string>();
        if ((modifiers & ModControl) != 0) parts.Add("Strg");
        if ((modifiers & ModAlt) != 0) parts.Add("Alt");
        if ((modifiers & ModShift) != 0) parts.Add("Umschalt");
        if ((modifiers & ModWin) != 0) parts.Add("Win");
        parts.Add(KeyName(key));
        return string.Join(" + ", parts);
    }

    private static string KeyName(uint vk) => vk switch
    {
        0x20 => "Leertaste",
        0x0D => "Eingabe",
        >= 0x70 and <= 0x87 => "F" + (vk - 0x6F),
        _ => ((Keys)vk).ToString(),
    };
}
