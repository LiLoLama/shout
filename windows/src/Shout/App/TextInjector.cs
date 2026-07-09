using System.Runtime.InteropServices;

namespace Shout.App;

/// <summary>
/// Fügt den fertigen Text in die gerade aktive App ein — über die
/// Zwischenablage + simuliertes Strg+V (robusteste Methode unter Windows;
/// zeichenweises SendInput scheitert an vielen Nicht-Unicode-Feldern).
/// Der vorherige Text-Inhalt der Zwischenablage wird danach wiederhergestellt,
/// außer der Nutzer will das Diktat ohnehin in der Zwischenablage behalten.
/// </summary>
public static class TextInjector
{
    [StructLayout(LayoutKind.Sequential)]
    private struct Input
    {
        public uint Type;
        public KeyboardInput Ki;
        // Padding auf die Größe der größten Union-Variante (MOUSEINPUT).
        public long Padding1;
        public int Padding2;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct KeyboardInput
    {
        public ushort Vk;
        public ushort Scan;
        public uint Flags;
        public uint Time;
        public IntPtr ExtraInfo;
    }

    private const uint InputKeyboard = 1;
    private const uint KeyeventfKeyup = 0x0002;
    private const ushort VkControl = 0x11;
    private const ushort VkV = 0x56;

    [DllImport("user32.dll", SetLastError = true)]
    private static extern uint SendInput(uint nInputs, Input[] pInputs, int cbSize);

    /// <summary>Fügt Text ins aktive Fenster ein. Muss vom UI-Thread (STA)
    /// aufgerufen werden — Clipboard-Zugriff verlangt das.</summary>
    public static void Insert(string text, bool keepInClipboard)
    {
        // Bisherigen Text-Inhalt sichern (nur Text — reicht für den Alltag;
        // exotische Formate wiederherzustellen ist das Risiko nicht wert).
        string? previous = null;
        try { if (Clipboard.ContainsText()) previous = Clipboard.GetText(); }
        catch { /* Clipboard kann gesperrt sein */ }

        try { Clipboard.SetText(text); }
        catch { return; }   // ohne Clipboard kein Einfügen

        SendCtrlV();

        if (!keepInClipboard && previous != null)
        {
            // Erst wiederherstellen, wenn die Ziel-App das Paste verarbeitet hat.
            var restore = previous;
            Task.Delay(300).ContinueWith(_ =>
            {
                try { Clipboard.SetText(restore); } catch { }
            }, TaskScheduler.FromCurrentSynchronizationContext());
        }
    }

    private static void SendCtrlV()
    {
        var inputs = new[]
        {
            Key(VkControl, down: true),
            Key(VkV, down: true),
            Key(VkV, down: false),
            Key(VkControl, down: false),
        };
        SendInput((uint)inputs.Length, inputs, Marshal.SizeOf<Input>());
    }

    private static Input Key(ushort vk, bool down) => new()
    {
        Type = InputKeyboard,
        Ki = new KeyboardInput { Vk = vk, Flags = down ? 0 : KeyeventfKeyup },
    };
}
