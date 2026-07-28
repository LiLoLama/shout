using System.Runtime.InteropServices;
using Shout.Core;

namespace Shout.App;

/// <summary>
/// Globaler Hotkey — das Windows-Pendant zum macOS-Event-Tap, in zwei Bauweisen:
///
///  - <see cref="Mode.Toggle"/>: <c>RegisterHotKey</c>. Günstig und robust, liefert
///    aber nur den Tastendruck. Ist die Kombination schon vergeben, schlägt die
///    Registrierung fehl (das meldet <see cref="Register"/> zurück).
///  - <see cref="Mode.Hold"/>: ein systemweiter Tastatur-Hook (WH_KEYBOARD_LL).
///    Nur so gibt es auch das Loslassen, das der Halten-Modus braucht. Der Hook
///    sieht die Tasten VOR allen Hotkey-Registrierungen anderer Programme und
///    verschluckt die eigene Kombination — im Halten-Modus gibt es deshalb auch
///    keine Kollisionen.
/// </summary>
public sealed class HotkeyManager : NativeWindow, IDisposable
{
    public enum Mode { Toggle, Hold }

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

    /// <summary>Tastendruck im Umschalt-Modus.</summary>
    public event Action? OnHotkey;
    /// <summary>Taste gedrückt (nur im Halten-Modus).</summary>
    public event Action? OnPressed;
    /// <summary>Taste losgelassen (nur im Halten-Modus).</summary>
    public event Action? OnReleased;

    private bool registered;
    private Mode mode = Mode.Toggle;
    private uint activeModifiers, activeKey;

    /// <summary>Der Hook läuft auf dem Faden, der ihn gesetzt hat — dem UI-Faden.
    /// Die Ereignisse werden trotzdem über den Kontext nachgereicht, damit der Hook
    /// sofort zurückkehrt: alles, was er offen hält, verzögert JEDEN Tastendruck im
    /// System.</summary>
    private readonly SynchronizationContext ui;

    public HotkeyManager()
    {
        ui = SynchronizationContext.Current ?? new WindowsFormsSynchronizationContext();
        CreateHandle(new CreateParams());   // unsichtbares Message-Fenster
    }

    /// <summary>
    /// Registriert den Hotkey neu. false heißt: die Kombination ist im Umschalt-Modus
    /// bereits von einem anderen Programm belegt (im Halten-Modus schlägt nur ein
    /// verweigerter Hook fehl).
    /// </summary>
    public bool Register(uint modifiers, uint key, Mode hotkeyMode)
    {
        Unregister();
        mode = hotkeyMode;
        activeModifiers = modifiers;
        activeKey = key;

        registered = hotkeyMode == Mode.Hold
            ? InstallHook()
            : RegisterHotKey(Handle, HotkeyId, modifiers | ModNoRepeat, key);
        return registered;
    }

    public void Unregister()
    {
        if (registered)
        {
            if (mode == Mode.Hold) RemoveHook();
            else UnregisterHotKey(Handle, HotkeyId);
        }
        registered = false;
        held = false;
    }

    protected override void WndProc(ref Message m)
    {
        if (m.Msg == WmHotkey && m.WParam.ToInt32() == HotkeyId)
            OnHotkey?.Invoke();
        base.WndProc(ref m);
    }

    // MARK: Halten-Modus (systemweiter Tastatur-Hook)

    private const int WhKeyboardLl = 13;
    private const int WmKeyDown = 0x0100, WmKeyUp = 0x0101;
    private const int WmSysKeyDown = 0x0104, WmSysKeyUp = 0x0105;

    private const int VkShift = 0x10, VkControl = 0x11, VkMenu = 0x12;
    private const int VkLWin = 0x5B, VkRWin = 0x5C;

    private delegate IntPtr KeyboardProc(int code, IntPtr wParam, IntPtr lParam);

    /// <summary>Muss als Feld leben: der Delegat wird nach Win32 hinüber gegeben,
    /// eine lokale Variable würde eingesammelt und der Hook stürzte ab.</summary>
    private KeyboardProc? hookProc;
    private IntPtr hook;
    private bool held;

    [StructLayout(LayoutKind.Sequential)]
    private struct KeyboardHookStruct
    {
        public uint VkCode;
        public uint ScanCode;
        public uint Flags;
        public uint Time;
        public IntPtr ExtraInfo;
    }

    [DllImport("user32.dll", SetLastError = true)]
    private static extern IntPtr SetWindowsHookEx(int idHook, KeyboardProc proc, IntPtr module, uint threadId);

    [DllImport("user32.dll")]
    private static extern bool UnhookWindowsHookEx(IntPtr hook);

    [DllImport("user32.dll")]
    private static extern IntPtr CallNextHookEx(IntPtr hook, int code, IntPtr wParam, IntPtr lParam);

    [DllImport("user32.dll")]
    private static extern short GetAsyncKeyState(int key);

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)]
    private static extern IntPtr GetModuleHandle(string? name);

    private bool InstallHook()
    {
        if (hook != IntPtr.Zero) return true;
        hookProc = HookCallback;
        // threadId 0 = systemweit; das Modul-Handle wertet Windows bei einem
        // Low-Level-Hook nicht aus, der eigene Prozess ist der übliche Wert.
        hook = SetWindowsHookEx(WhKeyboardLl, hookProc, GetModuleHandle(null), 0);
        return hook != IntPtr.Zero;
    }

    private void RemoveHook()
    {
        if (hook == IntPtr.Zero) return;
        UnhookWindowsHookEx(hook);
        hook = IntPtr.Zero;
        hookProc = null;
    }

    private IntPtr HookCallback(int code, IntPtr wParam, IntPtr lParam)
    {
        if (code < 0) return CallNextHookEx(hook, code, wParam, lParam);

        var data = Marshal.PtrToStructure<KeyboardHookStruct>(lParam);
        // Nur die EIGENEN simulierten Tastendrücke überspringen (das Strg+V beim
        // Einfügen, erkennbar an der Markierung) — fremdes simuliertes Tippen von
        // Makro-Tastaturen oder AutoHotkey soll die App weiterhin auslösen können.
        if (data.VkCode != activeKey || data.ExtraInfo == TextInjector.InputMarker)
            return CallNextHookEx(hook, code, wParam, lParam);

        var message = (int)wParam;
        var down = message is WmKeyDown or WmSysKeyDown;
        var up = message is WmKeyUp or WmSysKeyUp;

        if (down && !held && ModifiersMatch())
        {
            held = true;
            ui.Post(_ => OnPressed?.Invoke(), null);
            return 1;   // Taste verschlucken: die Zielanwendung soll sie nicht sehen
        }
        if (down && held) return 1;   // Tastenwiederholung beim Halten
        if (up && held)
        {
            held = false;
            ui.Post(_ => OnReleased?.Invoke(), null);
            return 1;
        }
        return CallNextHookEx(hook, code, wParam, lParam);
    }

    /// <summary>Genau die eingestellten Modifier — nicht mehr und nicht weniger,
    /// wie es RegisterHotKey im Umschalt-Modus auch handhabt.</summary>
    private bool ModifiersMatch()
    {
        static bool Down(int key) => (GetAsyncKeyState(key) & 0x8000) != 0;
        var control = Down(VkControl);
        var alt = Down(VkMenu);
        var shift = Down(VkShift);
        var win = Down(VkLWin) || Down(VkRWin);
        return control == ((activeModifiers & ModControl) != 0)
            && alt == ((activeModifiers & ModAlt) != 0)
            && shift == ((activeModifiers & ModShift) != 0)
            && win == ((activeModifiers & ModWin) != 0);
    }

    public void Dispose()
    {
        Unregister();
        DestroyHandle();
    }

    // MARK: Ausweich-Kombinationen

    /// <summary>
    /// Reihenfolge, in der eine Ersatz-Kombination probiert wird, wenn die
    /// eingestellte belegt ist (Strg+Alt+Leertaste gehört z. B. der Claude-App).
    /// Bewusst ohne Win-Taste: die ist voller Systemkürzel.
    /// </summary>
    public static readonly (uint Modifiers, uint Key)[] Fallbacks =
    {
        (ModControl | ModShift, 0x20),            // Strg + Umschalt + Leertaste
        (ModControl | ModAlt | ModShift, 0x20),   // Strg + Alt + Umschalt + Leertaste
        (ModControl | ModShift, 0x44),            // Strg + Umschalt + D
        (ModControl | ModAlt, 0x78),              // Strg + Alt + F9
        (ModControl | ModShift, 0x78),            // Strg + Umschalt + F9
    };

    /// <summary>Lesbare Beschreibung („Strg + Alt + Leertaste") für die UI.</summary>
    public static string Describe(uint modifiers, uint key)
    {
        var parts = new List<string>();
        if ((modifiers & ModControl) != 0) parts.Add(Loc.T("Strg"));
        if ((modifiers & ModAlt) != 0) parts.Add("Alt");
        if ((modifiers & ModShift) != 0) parts.Add(Loc.T("Umschalt"));
        if ((modifiers & ModWin) != 0) parts.Add("Win");
        parts.Add(KeyName(key));
        return string.Join(" + ", parts);
    }

    private static string KeyName(uint vk) => vk switch
    {
        0x20 => Loc.T("Leertaste"),
        0x0D => Loc.T("Eingabe"),
        >= 0x70 and <= 0x87 => "F" + (vk - 0x6F),
        _ => ((Keys)vk).ToString(),
    };
}
