using System.Runtime.InteropServices;

namespace Shout.App;

/// <summary>
/// Fügt den fertigen Text in die gerade aktive App ein — über die Zwischenablage +
/// simuliertes Strg+V (robusteste Methode unter Windows; zeichenweises SendInput
/// scheitert an vielen Nicht-Unicode-Feldern).
///
/// <para>Der vorherige Inhalt wird danach wiederhergestellt, außer der Nutzer will
/// das Diktat ohnehin in der Zwischenablage behalten. Das Diktat selbst wird als
/// „nicht in den Verlauf" gekennzeichnet, damit es nicht in der Windows-Zwischen­
/// ablage-Historie (Win+V) und in der Cloud-Zwischenablage landet — dasselbe, was
/// am Mac die Marker <c>ConcealedType</c>/<c>TransientType</c> tun.</para>
/// </summary>
public static class TextInjector
{
    [StructLayout(LayoutKind.Sequential)]
    private struct Input
    {
        public uint Type;
        public KeyboardInput Ki;
        // KEYBDINPUT (24 B) auf die größte Union-Variante (MOUSEINPUT, 32 B)
        // auffüllen: Type (4) + Alignment (4) + 32 = exakt 40 B wie Win32-INPUT
        // auf x64/arm64. Stimmt cbSize nicht, sendet SendInput NICHTS (Fehler 87).
        public long Padding;
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
    /// <summary>VK_NONAME — eine reservierte Taste ohne jede Wirkung. Genau dafür
    /// gedacht: Sie unterbricht die Menü-Aktivierung durch ein allein gedrücktes Alt.</summary>
    private const ushort VkNoName = 0xFC;

    /// <summary>
    /// Kennzeichen in <c>dwExtraInfo</c> für alle selbst gesendeten Tastendrücke
    /// („SHOU"). Der Tastatur-Hook überspringt genau diese, damit das Strg+V beim
    /// Einfügen die Aufnahme nicht erneut auslöst. Nur diese Markierung
    /// auszuschließen — und nicht alles Simulierte — hält die App mit
    /// Makro-Tastaturen und AutoHotkey verträglich.
    /// </summary>
    public static readonly IntPtr InputMarker = new(0x53484F55);

    /// <summary>Zwischenablage-Formate, mit denen Windows Inhalte von Verlauf und
    /// Cloud-Abgleich ausnimmt. Der Wert ist gleichgültig, es zählt die Anwesenheit.</summary>
    private const string ExcludeFromHistory = "ExcludeClipboardContentFromMonitorProcessing";
    private const string CanIncludeInHistory = "CanIncludeInClipboardHistory";
    private const string CanUploadToCloud = "CanUploadToCloudClipboard";

    [DllImport("user32.dll", SetLastError = true)]
    private static extern uint SendInput(uint nInputs, Input[] pInputs, int cbSize);

    // Wiederherstellung der Zwischenablage. Wer schnell hintereinander diktiert,
    // startet sonst zwei Wiederherstellungen: Die zweite sichert den Text des ersten
    // Diktats als „Original" und schreibt ihn dem Nutzer in die Ablage.
    private static string? savedClipboard;
    private static bool restorePending;
    private static CancellationTokenSource? restoreCancel;

    /// <summary>Fügt Text ins aktive Fenster ein. Muss vom UI-Thread (STA)
    /// aufgerufen werden — Clipboard-Zugriff verlangt das.</summary>
    public static void Insert(string text, bool keepInClipboard)
    {
        if (!restorePending)
        {
            // Erstes Einfügen einer Serie → den ECHTEN Nutzer-Inhalt sichern.
            savedClipboard = null;
            try { if (Clipboard.ContainsText()) savedClipboard = Clipboard.GetText(); }
            catch { /* Clipboard kann von einem anderen Programm gesperrt sein */ }
        }
        else
        {
            // Serie läuft: die geplante Wiederherstellung abbrechen und den
            // ursprünglichen Schnappschuss behalten.
            restoreCancel?.Cancel();
        }

        if (!SetClipboard(text)) return;   // ohne Zwischenablage kein Einfügen

        SendCtrlV();

        if (keepInClipboard || savedClipboard == null)
        {
            // Eine noch geplante Wiederherstellung aus einem früheren Diktat abbrechen:
            // Sie würde das gerade eingefügte Diktat wieder aus der Zwischenablage
            // werfen — genau das Gegenteil von „behalten".
            restoreCancel?.Cancel();
            restoreCancel = null;
            restorePending = false;
            savedClipboard = null;
            return;
        }

        restorePending = true;
        var cancel = new CancellationTokenSource();
        restoreCancel = cancel;
        var restore = savedClipboard;

        // Erst wiederherstellen, wenn die Ziel-App das Einfügen verarbeitet hat.
        Task.Delay(400, cancel.Token).ContinueWith(_ =>
        {
            if (cancel.IsCancellationRequested) return;
            try { Clipboard.SetText(restore); } catch { }
            restorePending = false;
            savedClipboard = null;
            restoreCancel = null;
        }, CancellationToken.None, TaskContinuationOptions.OnlyOnRanToCompletion,
           TaskScheduler.FromCurrentSynchronizationContext());
    }

    /// <summary>
    /// Schreibt den Text als „nicht in den Verlauf" in die Zwischenablage.
    /// Liefert false, wenn die Ablage gerade gesperrt ist.
    /// </summary>
    private static bool SetClipboard(string text)
    {
        try
        {
            var data = new DataObject();
            data.SetText(text);
            data.SetData(ExcludeFromHistory, new MemoryStream(new byte[] { 0, 0, 0, 0 }));
            data.SetData(CanIncludeInHistory, new MemoryStream(BitConverter.GetBytes(0)));
            data.SetData(CanUploadToCloud, new MemoryStream(BitConverter.GetBytes(0)));
            Clipboard.SetDataObject(data, copy: true);
            return true;
        }
        catch
        {
            // Rückfall auf den einfachen Weg: lieber im Verlauf als gar nicht eingefügt.
            try { Clipboard.SetText(text); return true; }
            catch { return false; }
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
        Send(inputs);
    }

    /// <summary>
    /// Schiebt Windows einen wirkungslosen Tastendruck unter, solange Alt gehalten
    /// wird. Ohne das liest die Shell das spätere Loslassen als „Alt allein" und
    /// aktiviert die Menüleiste des Vordergrundfensters — sichtbar als aufflackerndes
    /// Menü bei jedem Diktat mit einer Alt-Kombination.
    /// </summary>
    public static void SuppressMenuActivation()
        => Send(new[] { Key(VkNoName, down: true), Key(VkNoName, down: false) });

    private static void Send(Input[] inputs)
    {
        var sent = SendInput((uint)inputs.Length, inputs, Marshal.SizeOf<Input>());
        if (sent != inputs.Length)
            Core.StoreIO.Log($"SendInput hat nur {sent} von {inputs.Length} Ereignissen gesendet " +
                             $"(Fehler {Marshal.GetLastWin32Error()}).");
    }

    private static Input Key(ushort vk, bool down) => new()
    {
        Type = InputKeyboard,
        Ki = new KeyboardInput
        {
            Vk = vk,
            Flags = down ? 0 : KeyeventfKeyup,
            ExtraInfo = InputMarker,
        },
    };
}
