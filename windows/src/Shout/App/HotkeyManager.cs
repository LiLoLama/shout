using System.Runtime.InteropServices;
using Shout.Core;

namespace Shout.App;

/// <summary>
/// Globaler Hotkey — das Windows-Pendant zum macOS-Event-Tap, in zwei Bauweisen:
///
///  - <c>RegisterHotKey</c>: günstig und robust, liefert aber nur den Tastendruck
///    und verlangt zwingend einen Modifier. Reicht genau für den Umschalt-Modus
///    mit einer normalen Kombination.
///  - Ein systemweiter Tastatur-Hook (WH_KEYBOARD_LL) für alles andere: Halten
///    (braucht das Loslassen), Doppeltipp (braucht die Zeit zwischen zwei
///    Anschlägen) und Tastenwahlen, die <c>RegisterHotKey</c> nicht kennt — eine
///    reine Modifier-Taste oder eine Taste ganz ohne Modifier. Der Hook sieht die
///    Tasten VOR allen Hotkey-Registrierungen anderer Programme; dort gibt es
///    deshalb auch keine Kollisionen.
/// </summary>
public sealed class HotkeyManager : NativeWindow, IDisposable
{
    public enum Mode { Toggle, Hold, DoubleTap }

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

    /// <summary>Tastendruck im Umschalt-Modus (und Start/Stopp beim Doppeltipp).</summary>
    public event Action? OnHotkey;
    /// <summary>Taste gedrückt (nur im Halten-Modus).</summary>
    public event Action? OnPressed;
    /// <summary>Taste losgelassen (nur im Halten-Modus).</summary>
    public event Action? OnReleased;
    /// <summary>Erster Tipp erkannt, der zweite wird erwartet (nur Doppeltipp).</summary>
    public event Action? OnArmed;

    /// <summary>Läuft gerade eine Aufnahme? Der Doppeltipp braucht die Antwort, um
    /// zwischen „starten" (zwei Anschläge) und „stoppen" (einer) zu unterscheiden.</summary>
    public Func<bool>? IsRecording { get; set; }

    private bool registered;
    private Mode mode = Mode.Toggle;
    private uint activeModifiers, activeKey;
    private bool modifierOnly;
    private readonly DoubleTapDetector doubleTap = new();

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
    /// Braucht diese Kombination den Hook? Alles außer „Umschalten mit einer
    /// gewöhnlichen Kombination" tut das.
    /// </summary>
    private static bool NeedsHook(uint modifiers, Mode mode, bool modifierOnly)
        => mode != Mode.Toggle || modifierOnly || modifiers == 0;

    /// <summary>
    /// Registriert den Hotkey neu. false heißt: die Kombination ist im Umschalt-Modus
    /// bereits von einem anderen Programm belegt (mit Hook schlägt nur ein
    /// verweigerter Hook fehl).
    /// </summary>
    public bool Register(uint modifiers, uint key, Mode hotkeyMode, bool isModifierOnly = false)
    {
        Unregister();
        mode = hotkeyMode;
        activeModifiers = modifiers;
        activeKey = key;
        modifierOnly = isModifierOnly || IsModifierKey(key);
        doubleTap.Reset();

        registered = NeedsHook(modifiers, mode, modifierOnly)
            ? InstallHook()
            : RegisterHotKey(Handle, HotkeyId, modifiers | ModNoRepeat, key);
        return registered;
    }

    public void Unregister()
    {
        if (registered)
        {
            if (hook != IntPtr.Zero) RemoveHook();
            else UnregisterHotKey(Handle, HotkeyId);
        }
        registered = false;
        held = false;
        doubleTap.Reset();
    }

    protected override void WndProc(ref Message m)
    {
        if (m.Msg == WmHotkey && (long)m.WParam == HotkeyId)
            OnHotkey?.Invoke();
        base.WndProc(ref m);
    }

    // MARK: Hook (Halten, Doppeltipp, Sonder-Tastenwahlen)

    private const int WhKeyboardLl = 13;
    private const int WmKeyDown = 0x0100, WmKeyUp = 0x0101;
    private const int WmSysKeyDown = 0x0104, WmSysKeyUp = 0x0105;

    private const int VkShift = 0x10, VkControl = 0x11, VkMenu = 0x12;
    private const int VkLWin = 0x5B, VkRWin = 0x5C;
    private const int VkLShift = 0xA0, VkRShift = 0xA1;
    private const int VkLControl = 0xA2, VkRControl = 0xA3;
    private const int VkLMenu = 0xA4, VkRMenu = 0xA5;

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
        if (!MatchesKey(data.VkCode) || data.ExtraInfo == TextInjector.InputMarker)
            return CallNextHookEx(hook, code, wParam, lParam);

        var message = (int)wParam;
        var down = message is WmKeyDown or WmSysKeyDown;
        var up = message is WmKeyUp or WmSysKeyUp;

        // Eine reine Modifier-Taste wird NICHT verschluckt: Auf deutschen Tastaturen
        // ist die rechte Alt-Taste AltGr, und ohne sie gäbe es kein @, kein € und
        // keine eckigen Klammern mehr. Sie behält also ihre normale Wirkung und löst
        // zusätzlich aus.
        var swallow = !modifierOnly;

        if (mode == Mode.Hold)
        {
            if (down && !held && ModifiersMatch())
            {
                held = true;
                SuppressMenuIfAlt();
                ui.Post(_ => OnPressed?.Invoke(), null);
                return swallow ? 1 : CallNextHookEx(hook, code, wParam, lParam);
            }
            if (down && held) return swallow ? 1 : CallNextHookEx(hook, code, wParam, lParam);
            if (up && held)
            {
                held = false;
                ui.Post(_ => OnReleased?.Invoke(), null);
                return swallow ? 1 : CallNextHookEx(hook, code, wParam, lParam);
            }
            return CallNextHookEx(hook, code, wParam, lParam);
        }

        // Umschalten und Doppeltipp reagieren nur auf das Drücken; das Loslassen
        // wird durchgereicht (bzw. verschluckt, damit die Taste nicht doch noch im
        // Zielfenster landet). Zurückgesetzt wird IMMER — sonst bliebe die Marke bei
        // einer durchgereichten Taste (reiner Modifier) für immer stehen, und jeder
        // weitere Anschlag gälte als Tastenwiederholung.
        if (up)
        {
            var wasHeld = held;
            held = false;
            return swallow && wasHeld ? 1 : CallNextHookEx(hook, code, wParam, lParam);
        }
        if (!down || !ModifiersMatch()) return CallNextHookEx(hook, code, wParam, lParam);
        if (held) return swallow ? 1 : CallNextHookEx(hook, code, wParam, lParam);   // Tastenwiederholung

        held = true;
        SuppressMenuIfAlt();

        if (mode == Mode.DoubleTap)
        {
            var recording = IsRecording?.Invoke() ?? false;
            switch (doubleTap.HandleDown(Environment.TickCount64 / 1000.0, recording))
            {
                case DoubleTapDetector.Action.Armed:
                    ui.Post(_ => OnArmed?.Invoke(), null);
                    break;
                case DoubleTapDetector.Action.Start:
                case DoubleTapDetector.Action.Stop:
                    ui.Post(_ => OnHotkey?.Invoke(), null);
                    break;
                case DoubleTapDetector.Action.Ignored:
                    break;
            }
        }
        else
        {
            ui.Post(_ => OnHotkey?.Invoke(), null);
        }

        return swallow ? 1 : CallNextHookEx(hook, code, wParam, lParam);
    }

    /// <summary>
    /// Passt der Tastencode? Bei den Modifiern akzeptiert Windows im Hook die
    /// seitenrichtigen Codes (0xA0–0xA5); wer „Strg" allgemein gewählt hat, meint
    /// beide Seiten.
    /// </summary>
    private bool MatchesKey(uint vk)
    {
        if (vk == activeKey) return true;
        return activeKey switch
        {
            VkShift => vk is VkLShift or VkRShift,
            VkControl => vk is VkLControl or VkRControl,
            VkMenu => vk is VkLMenu or VkRMenu,
            _ => false,
        };
    }

    /// <summary>
    /// Welche SEITE einer Modifier-Taste ist gerade unten? Für die Aufnahme einer
    /// reinen Modifier-Kombination: WinForms meldet nur „Alt", der Hook sieht aber
    /// „Alt rechts" — ohne die Auflösung könnte man die rechte Alt-Taste nicht
    /// getrennt von der linken belegen.
    /// </summary>
    public static uint SidedKey(uint vk) => vk switch
    {
        VkShift => (uint)(Down(VkRShift) ? VkRShift : VkLShift),
        VkControl => (uint)(Down(VkRControl) ? VkRControl : VkLControl),
        VkMenu => (uint)(Down(VkRMenu) ? VkRMenu : VkLMenu),
        _ => vk,
    };

    private static bool Down(int key) => (GetAsyncKeyState(key) & 0x8000) != 0;

    public static bool IsModifier(uint vk) => IsModifierKey(vk);

    private static bool IsModifierKey(uint vk) =>
        vk is VkShift or VkControl or VkMenu or VkLShift or VkRShift
           or VkLControl or VkRControl or VkLMenu or VkRMenu or VkLWin or VkRWin;

    /// <summary>
    /// Ist Alt im Spiel, bekommt Windows einen harmlosen Tastendruck untergeschoben.
    /// Sonst wertet die Shell das Loslassen von Alt als „Alt allein" und springt in
    /// die Menüleiste des Vordergrundfensters — bei Strg+Alt+Leertaste als
    /// Halten-Kombination flackerte so bei jedem Diktat das Menü auf, weil unsere
    /// eigentliche Taste ja verschluckt wird und Windows sie nie sieht.
    /// </summary>
    private void SuppressMenuIfAlt()
    {
        var altInCombo = (activeModifiers & ModAlt) != 0
                         || activeKey is VkMenu or VkLMenu or VkRMenu;
        if (altInCombo) TextInjector.SuppressMenuActivation();
    }

    /// <summary>Genau die eingestellten Modifier — nicht mehr und nicht weniger,
    /// wie es RegisterHotKey im Umschalt-Modus auch handhabt. Bei einer reinen
    /// Modifier-Taste gibt es nichts zu vergleichen.</summary>
    private bool ModifiersMatch()
    {
        if (modifierOnly) return true;
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
        VkLMenu => Loc.T("Alt links"),
        VkRMenu => Loc.T("Alt rechts"),
        VkLControl => Loc.F("{0} links", Loc.T("Strg")),
        VkRControl => Loc.F("{0} rechts", Loc.T("Strg")),
        VkLShift => Loc.F("{0} links", Loc.T("Umschalt")),
        VkRShift => Loc.F("{0} rechts", Loc.T("Umschalt")),
        VkMenu => "Alt",
        VkControl => Loc.T("Strg"),
        VkShift => Loc.T("Umschalt"),
        >= 0x70 and <= 0x87 => "F" + (vk - 0x6F),
        _ => ((Keys)vk).ToString(),
    };
}
