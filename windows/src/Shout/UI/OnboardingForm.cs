using System.Diagnostics;
using Shout.App;
using Shout.Core;

namespace Shout.UI;

/// <summary>
/// Erststart-Assistent — die Windows-Fassung von OnboardingView.swift: Willkommen,
/// Mikrofon, Tastenkombination, Sprachmodell, Probediktat.
///
/// Zwei Schritte weichen bewusst vom Mac ab: „Bedienungshilfen" gibt es unter
/// Windows nicht (SendInput braucht keine Freigabe), dafür ist die Tastenkombination
/// hier der wacklige Punkt — sie kann belegt sein. Und weil Windows Desktop-Apps
/// keinen Mikrofon-Dialog zeigt, wird das Mikrofon zur Probe wirklich geöffnet:
/// ein Pegelbalken sagt mehr als jede Freigabe-Abfrage.
/// </summary>
internal sealed class OnboardingForm : Form
{
    /// <summary>„Los geht's" — der Assistent ist durch.</summary>
    public event Action? Finished;

    private const int StepCount = 5;
    private const int PadH = 34;
    private const int HeaderHeight = 58;
    private const int FooterHeight = 62;

    private readonly TrayContext app;
    private readonly ConsoleButton back, next;
    /// <summary>Bedienelemente des aktuellen Schritts (bei jedem Wechsel neu gebaut).</summary>
    private readonly Panel extras = new() { BackColor = Theme.Window };
    /// <summary>Hält Mikrofon-Pegel und Modell-Fortschritt in Bewegung.</summary>
    private readonly System.Windows.Forms.Timer poll = new() { Interval = 300 };

    private int step;
    /// <summary>Erst wenn die Bedienelemente stehen, darf gelayoutet werden — schon
    /// das Setzen von <c>Font</c> im Konstruktor löst ein Layout aus.</summary>
    private bool ready;

    public OnboardingForm(TrayContext app)
    {
        this.app = app;

        Text = "shout.";
        Icon = AppIcons.Window;
        BackColor = Theme.Window;
        ForeColor = Theme.Ink;
        Font = Theme.Body;
        ClientSize = new Size(600, 540);
        // Feste Größe: das Layout des Assistenten ist auf diese Maße gerechnet.
        FormBorderStyle = FormBorderStyle.FixedSingle;
        MaximizeBox = false;
        MinimizeBox = false;
        StartPosition = FormStartPosition.CenterScreen;
        KeyPreview = true;   // für die Hotkey-Aufnahme

        back = new ConsoleButton(Loc.T("Zurück"));
        back.Click2 += () => GoTo(step - 1);
        next = new ConsoleButton(Loc.T("Weiter"), primary: true, width: 116);
        next.Click2 += () =>
        {
            if (step < StepCount - 1) GoTo(step + 1);
            else Finished?.Invoke();
        };

        Controls.Add(extras);
        Controls.Add(back);
        Controls.Add(next);

        poll.Tick += (_, _) => RefreshLiveState();
        poll.Start();

        ready = true;
        GoTo(0);
    }

    protected override void OnHandleCreated(EventArgs e)
    {
        base.OnHandleCreated(e);
        DarkTitleBar.Apply(Handle);
    }

    protected override void OnFormClosed(FormClosedEventArgs e)
    {
        poll.Stop();
        poll.Dispose();
        StopMicTest();
        // Bricht der Nutzer während der Tastenaufnahme ab, muss der Hotkey zurück.
        if (capturingHotkey) app.RegisterHotkeyFromSettings();
        base.OnFormClosed(e);
    }

    // MARK: Schritte

    private void GoTo(int target)
    {
        step = Math.Clamp(target, 0, StepCount - 1);
        StopMicTest();
        if (capturingHotkey) EndHotkeyCapture();

        back.Visible = step > 0;
        next.Text = step < StepCount - 1 ? Loc.T("Weiter") : Loc.T("Los geht’s");
        next.Invalidate();   // eigengezeichnet: neuer Text will neu gemalt werden

        RebuildExtras();
        PerformLayout();
        Invalidate();
        // Im Probediktat soll der Cursor gleich im Textfeld stehen.
        testField?.Inner.Focus();
    }

    /// <summary>Symbol, Titel und Erklärung des aktuellen Schritts.</summary>
    private (Icons.Kind Icon, Color Color, string Title, string Text) Content() => step switch
    {
        0 => (Icons.Kind.Mic, Theme.Live, Loc.T("Willkommen bei shout."),
              Loc.T("Diktieren in jede App — komplett lokal auf deinem PC. Keine Cloud, keine Konten. In vier kurzen Schritten ist alles startklar.")),

        1 => micState switch
        {
            MicState.Ok => (Icons.Kind.Check, Color.FromArgb(76, 175, 80), Loc.T("Mikrofon"),
                            Loc.T("Perfekt — shout. hört dein Mikrofon.")),
            MicState.Testing => (Icons.Kind.Mic, Theme.Live, Loc.T("Mikrofon"),
                            Loc.T("Sprich einfach los — der Balken zeigt, was ankommt.")),
            MicState.NoSignal => (Icons.Kind.Warning, Theme.Live, Loc.T("Mikrofon"),
                            Loc.T("Es kam kein Ton an. Prüf, ob oben das richtige Mikrofon steht — und ob Windows Desktop-Apps den Zugriff erlaubt.")),
            MicState.NoDevice => (Icons.Kind.Warning, Theme.Live, Loc.T("Mikrofon"),
                            Loc.T("Windows meldet kein Aufnahmegerät. Schließ ein Mikrofon oder Headset an und probier es erneut.")),
            _ => (Icons.Kind.Mic, Theme.Live, Loc.T("Mikrofon"),
                  Loc.T("shout. braucht dein Mikrofon, um Sprache lokal in Text zu verwandeln. Mach kurz die Probe — sprich, und der Balken schlägt aus.")),
        },

        2 => (Icons.Kind.Keyboard, Theme.Live, Loc.T("Tastenkombination"),
              Loc.F("Mit {0} startest du das Diktat — in jeder App. Ist die Kombination von einem anderen Programm belegt, sucht shout. sich selbst eine freie und sagt es dir.",
                    HotkeyManager.Describe(Settings.Shared.HotkeyModifiers, Settings.Shared.HotkeyKey))),

        3 => app.TranscriberReady
            ? (Icons.Kind.Check, Color.FromArgb(76, 175, 80), Loc.T("Sprachmodell"),
               Loc.T("Das Sprachmodell ist geladen und liegt lokal auf deinem PC."))
            : app.ModelFailed
                ? (Icons.Kind.Warning, Theme.Live, Loc.T("Sprachmodell"),
                   Loc.T("Das Sprachmodell konnte nicht geladen werden — meist fehlt beim ersten Start die Internet-Verbindung. Prüfe die Verbindung und versuch es erneut."))
                : (Icons.Kind.Chip, Theme.Live, Loc.T("Sprachmodell"),
                   app.AsrProgress is { } p
                       ? Loc.F("Das Sprachmodell wird geladen … {0} %. Das passiert nur dieses eine Mal, danach läuft alles offline.", (int)(p * 100))
                       : Loc.T("Beim ersten Start lädt shout. das Sprachmodell einmalig herunter (danach läuft alles offline). Das kann je nach Verbindung ein paar Minuten dauern.")),

        _ => (Icons.Kind.Keyboard, Theme.Live, Loc.T("Probier es aus"),
              Loc.F("Klick ins Feld, {0} und sprich einen Satz. Dein Text erscheint direkt hier.",
                    TrayContext.HotkeyTrigger)),
    };

    // MARK: Bedienelemente je Schritt

    private ConsoleButton? micTest, micPrivacy, modelRetry;
    private ConsoleDropdown? micDevice;
    private LevelMeter? meter;
    private Keycap? hotkeyCap;
    private ConsoleButton? changeHotkey;
    private ConsoleSegmented? hotkeyMode;
    private ConsoleTextArea? testField;

    private void RebuildExtras()
    {
        foreach (Control child in extras.Controls.Cast<Control>().ToArray()) child.Dispose();
        extras.Controls.Clear();
        micTest = micPrivacy = modelRetry = null;
        micDevice = null;
        meter = null;
        hotkeyCap = null;
        changeHotkey = null;
        hotkeyMode = null;
        testField = null;

        switch (step)
        {
            case 1: BuildMicStep(); break;
            case 2: BuildHotkeyStep(); break;
            case 3: BuildModelStep(); break;
            case 4: BuildTestStep(); break;
        }
    }

    private void BuildMicStep()
    {
        var s = Settings.Shared;
        micDevice = new ConsoleDropdown(300);
        var devices = new List<(string, string)> { ("-1", Loc.T("Systemstandard")) };
        devices.AddRange(AudioRecorder.InputDevices().Select(d => (d.Index.ToString(), d.Name)));
        micDevice.SetItems(devices, s.InputDeviceIndex.ToString());
        micDevice.Changed += key =>
        {
            s.InputDeviceIndex = int.TryParse(key, out var index) ? index : -1;
            s.Save();
            StopMicTest();
            micState = MicState.Unknown;
            RebuildExtras();
            PerformLayout();
            Invalidate();
        };

        meter = new LevelMeter { Width = 300 };
        micTest = new ConsoleButton(micState == MicState.Testing
            ? Loc.T("Läuft …") : Loc.T("Mikrofon prüfen"), primary: true);
        micTest.Click2 += StartMicTest;
        micTest.SetEnabled(micState != MicState.Testing);

        extras.Controls.Add(micDevice);
        extras.Controls.Add(meter);
        extras.Controls.Add(micTest);

        if (micState is MicState.NoSignal or MicState.NoDevice)
        {
            micPrivacy = new ConsoleButton(Loc.T("Mikrofon-Einstellungen öffnen"));
            micPrivacy.Click2 += () => OpenUrl("ms-settings:privacy-microphone");
            extras.Controls.Add(micPrivacy);
        }
    }

    private void BuildHotkeyStep()
    {
        var s = Settings.Shared;
        hotkeyCap = new Keycap(HotkeyManager.Describe(s.HotkeyModifiers, s.HotkeyKey));
        changeHotkey = new ConsoleButton(Loc.T("Ändern"));
        changeHotkey.Click2 += BeginHotkeyCapture;

        hotkeyMode = new ConsoleSegmented(new[]
        {
            ("hold", Loc.T("Halten")),
            ("toggle", Loc.T("Umschalten")),
        }, s.HotkeyMode == "hold" ? "hold" : "toggle");
        hotkeyMode.Changed += key =>
        {
            s.HotkeyMode = key;
            s.Save();
            app.RegisterHotkeyFromSettings();
            Invalidate();
        };

        extras.Controls.Add(hotkeyCap);
        extras.Controls.Add(changeHotkey);
        extras.Controls.Add(hotkeyMode);
    }

    private void BuildModelStep()
    {
        if (!app.ModelFailed) return;
        modelRetry = new ConsoleButton(Loc.T("Erneut versuchen"), primary: true);
        modelRetry.Click2 += () =>
        {
            app.ReloadModels();
            Invalidate();
        };
        extras.Controls.Add(modelRetry);
    }

    private void BuildTestStep()
    {
        testField = new ConsoleTextArea(90);
        extras.Controls.Add(testField);
    }

    // MARK: Mikrofon-Probe

    private enum MicState { Unknown, Testing, Ok, NoSignal, NoDevice }

    private MicState micState = MicState.Unknown;
    private AudioRecorder? micRecorder;
    private System.Windows.Forms.Timer? micTimer;
    private float micLevel;
    private bool micHeard;

    private void StartMicTest()
    {
        if (micState == MicState.Testing) return;
        if (AudioRecorder.InputDevices().Count == 0 && Settings.Shared.InputDeviceIndex < 0)
        {
            micState = MicState.NoDevice;
            RebuildExtras();
            PerformLayout();
            Invalidate();
            return;
        }

        micHeard = false;
        micLevel = 0;
        micRecorder = new AudioRecorder();
        // Der Pegel kommt vom Audio-Faden — nur merken, gezeichnet wird im Takt
        // des Poll-Timers.
        micRecorder.OnLevel += level =>
        {
            micLevel = level;
            if (level > 0.06f) micHeard = true;
        };
        try
        {
            micRecorder.Start();
        }
        catch (Exception)
        {
            micRecorder.Dispose();
            micRecorder = null;
            micState = MicState.NoSignal;
            RebuildExtras();
            PerformLayout();
            Invalidate();
            return;
        }

        micState = MicState.Testing;
        // Nach sechs Sekunden ist die Probe entschieden — länger will niemand
        // ins Leere sprechen.
        micTimer = new System.Windows.Forms.Timer { Interval = 6000 };
        micTimer.Tick += (_, _) => FinishMicTest();
        micTimer.Start();
        RebuildExtras();
        PerformLayout();
        Invalidate();
    }

    private void FinishMicTest()
    {
        var heard = micHeard;
        StopMicTest();
        micState = heard ? MicState.Ok : MicState.NoSignal;
        RebuildExtras();
        PerformLayout();
        Invalidate();
    }

    private void StopMicTest()
    {
        micTimer?.Stop();
        micTimer?.Dispose();
        micTimer = null;
        if (micRecorder != null)
        {
            try { _ = micRecorder.Stop(); } catch { /* Probe darf still enden */ }
            micRecorder.Dispose();
            micRecorder = null;
        }
        micLevel = 0;
        if (micState == MicState.Testing) micState = MicState.Unknown;
    }

    /// <summary>Pegelbalken und Modell-Fortschritt nachziehen (Poll-Timer).</summary>
    private void RefreshLiveState()
    {
        if (step == 1 && micState == MicState.Testing)
        {
            meter?.SetLevel(micLevel);
            // Sobald Ton ankommt, ist die Sache klar — nicht die volle Zeit abwarten.
            if (micHeard) FinishMicTest();
            return;
        }
        // Der Modell-Schritt lebt von Fortschritt und Zustand: neu zeichnen, und
        // den „Erneut versuchen"-Knopf ein-/ausblenden, wenn er sich ändert.
        if (step != 3) return;
        var wantsRetry = app.ModelFailed;
        if (wantsRetry != (modelRetry != null))
        {
            RebuildExtras();
            PerformLayout();
        }
        Invalidate();
    }

    // MARK: Hotkey-Aufnahme

    private bool capturingHotkey;

    private void BeginHotkeyCapture()
    {
        if (capturingHotkey) return;
        capturingHotkey = true;
        hotkeyCap?.SetText(Loc.T("Taste drücken …"));
        changeHotkey?.SetEnabled(false);
        // Abmelden, sonst erreicht die aktuelle Kombination dieses Fenster nie.
        app.PauseHotkey();
    }

    private void EndHotkeyCapture()
    {
        capturingHotkey = false;
        var s = Settings.Shared;
        hotkeyCap?.SetText(HotkeyManager.Describe(s.HotkeyModifiers, s.HotkeyKey));
        changeHotkey?.SetEnabled(true);
        app.RegisterHotkeyFromSettings();
        Invalidate();
    }

    protected override void OnKeyDown(KeyEventArgs e)
    {
        if (capturingHotkey)
        {
            e.SuppressKeyPress = true;
            e.Handled = true;

            if (e.KeyCode == Keys.Escape)
            {
                EndHotkeyCapture();
                return;
            }

            uint mods = 0;
            if (e.Control) mods |= HotkeyManager.ModControl;
            if (e.Alt) mods |= HotkeyManager.ModAlt;
            if (e.Shift) mods |= HotkeyManager.ModShift;
            var key = (uint)e.KeyCode;
            // Reine Modifier-Tasten ignorieren; mindestens ein Modifier ist Pflicht,
            // sonst schluckt der Hotkey normale Tastendrücke systemweit.
            if (key is 0x10 or 0x11 or 0x12 || mods == 0) return;

            var s = Settings.Shared;
            s.HotkeyModifiers = mods;
            s.HotkeyKey = key;
            s.Save();
            EndHotkeyCapture();
            return;
        }
        base.OnKeyDown(e);
    }

    // MARK: Layout und Zeichnung

    protected override void OnLayout(LayoutEventArgs e)
    {
        base.OnLayout(e);
        if (!ready || ClientSize.Width <= 0) return;

        var width = ClientSize.Width - PadH * 2;
        var y = ContentTop(width);

        var available = Math.Max(0, ClientSize.Height - FooterHeight - y - 10);
        extras.Location = new Point(PadH, y);
        extras.Size = new Size(width, available);
        LayoutExtras(width);
        // Nur so hoch wie der Inhalt: die Fläche ist deckend und verdeckte sonst die
        // Fußnote des letzten Schritts.
        var content = extras.Controls.Cast<Control>().Select(c => c.Bottom).DefaultIfEmpty(0).Max();
        extras.Height = Math.Min(available, content);

        back.Location = new Point(PadH, ClientSize.Height - FooterHeight + 16);
        next.Location = new Point(ClientSize.Width - PadH - next.Width,
                                  ClientSize.Height - FooterHeight + 14);
    }

    /// <summary>Oberkante der Schritt-Bedienelemente — hängt an der Höhe des
    /// umbrechenden Erklärtextes.</summary>
    private int ContentTop(int width)
    {
        var (_, _, title, text) = Content();
        var y = HeaderHeight + 26 + 44 + 18;                                  // Symbol
        y += TextRenderer.MeasureText(title, Theme.StepTitle).Height + 10;    // Titel
        y += TextRenderer.MeasureText(text, Theme.StepBody,
                                     new Size(width, int.MaxValue),
                                     TextFormatFlags.WordBreak).Height + 22;
        return y;
    }

    private void LayoutExtras(int width)
    {
        switch (step)
        {
            case 1 when micDevice != null && meter != null && micTest != null:
                micDevice.Location = new Point(0, 0);
                micDevice.Width = Math.Min(320, width);
                meter.Location = new Point(0, micDevice.Bottom + 14);
                meter.Width = Math.Min(320, width);
                micTest.Location = new Point(0, meter.Bottom + 16);
                if (micPrivacy != null)
                    micPrivacy.Location = new Point(micTest.Right + 10,
                                                    micTest.Top + (micTest.Height - micPrivacy.Height) / 2);
                break;

            case 2 when hotkeyCap != null && changeHotkey != null && hotkeyMode != null:
                hotkeyCap.Location = new Point(0, 0);
                changeHotkey.Location = new Point(hotkeyCap.Right + 10,
                                                  (hotkeyCap.Height - changeHotkey.Height) / 2);
                hotkeyMode.Location = new Point(0, hotkeyCap.Bottom + 18);
                break;

            case 3 when modelRetry != null:
                modelRetry.Location = new Point(0, 0);
                break;

            case 4 when testField != null:
                testField.Location = new Point(0, 0);
                testField.Width = width;
                break;
        }
    }

    protected override void OnPaint(PaintEventArgs e)
    {
        var g = e.Graphics;
        Theme.Smooth(g);
        using (var bg = new SolidBrush(Theme.Window)) g.FillRectangle(bg, ClientRectangle);

        // Kopf: Wortmarke links, Schritt-Punkte rechts.
        var shoutWidth = Theme.MeasureTight("shout", Theme.Wordmark);
        Theme.DrawTight(g, "shout", Theme.Wordmark, Color.White, new Point(PadH, 18));
        Theme.DrawTight(g, ".", Theme.Wordmark, Theme.Live, new Point(PadH + shoutWidth, 18));
        DrawStepDots(g);

        using (var pen = new Pen(Theme.White(0.06f)))
            g.DrawLine(pen, PadH, HeaderHeight, ClientSize.Width - PadH, HeaderHeight);

        // Symbol, Titel, Erklärung.
        var width = ClientSize.Width - PadH * 2;
        var (icon, color, title, text) = Content();
        var y = HeaderHeight + 26;
        Icons.Draw(g, icon, new RectangleF(PadH, y, 44, 44), color, 40f);
        y += 44 + 18;

        var titleHeight = TextRenderer.MeasureText(title, Theme.StepTitle).Height;
        TextRenderer.DrawText(g, title, Theme.StepTitle, new Rectangle(PadH, y, width, titleHeight),
                              Theme.Gray(0.95), TextFormatFlags.NoPrefix);
        y += titleHeight + 10;

        var textHeight = TextRenderer.MeasureText(text, Theme.StepBody, new Size(width, int.MaxValue),
                                                 TextFormatFlags.WordBreak).Height;
        TextRenderer.DrawText(g, text, Theme.StepBody, new Rectangle(PadH, y, width, textHeight),
                              Theme.Gray(0.62), TextFormatFlags.WordBreak | TextFormatFlags.NoPrefix);

        // Fußnote im Probediktat (wie am Mac).
        if (step == StepCount - 1)
        {
            var hint = Loc.T("Tipp: Aufnahme-Art und Taste kannst du später unter „Aufnahme & Text“ ändern.");
            TextRenderer.DrawText(g, hint, Theme.Help,
                                  new Rectangle(PadH, ClientSize.Height - FooterHeight - 26, width, 22),
                                  Theme.Gray(0.45), TextFormatFlags.NoPrefix);
        }
    }

    /// <summary>Fortschritts-Punkte: der aktuelle Schritt als längere Kapsel.</summary>
    private void DrawStepDots(Graphics g)
    {
        const int dot = 7, gap = 6, activeWidth = 18;
        var total = 0;
        for (var i = 0; i < StepCount; i++) total += (i == step ? activeWidth : dot) + gap;
        var x = ClientSize.Width - PadH - total + gap;
        var y = 28f;
        for (var i = 0; i < StepCount; i++)
        {
            var w = i == step ? activeWidth : dot;
            var color = i == step ? Theme.Live : Theme.White(i < step ? 0.35 : 0.14);
            Theme.DrawCapsule(g, new RectangleF(x, y, w, dot), color);
            x += w + gap;
        }
    }

    private static void OpenUrl(string url)
    {
        try { Process.Start(new ProcessStartInfo(url) { UseShellExecute = true }); }
        catch { /* kein Standard-Handler — dann eben nicht */ }
    }
}

/// <summary>
/// Pegelbalken für die Mikrofon-Probe: eine vertiefte Bahn, gefüllt in der
/// Signalfarbe. Bewusst schlicht — die Wellenform hat die Pille.
/// </summary>
internal sealed class LevelMeter : ThemedControl
{
    private float level;

    public LevelMeter()
    {
        Height = 10;
    }

    public void SetLevel(float value)
    {
        var next = Math.Clamp(value, 0f, 1f);
        if (Math.Abs(next - level) < 0.01f) return;
        level = next;
        Invalidate();
    }

    protected override void OnPaint(PaintEventArgs e)
    {
        var g = e.Graphics;
        Theme.Smooth(g);
        using (var bg = new SolidBrush(BackColor)) g.FillRectangle(bg, ClientRectangle);

        // Etwas heller als die übliche Bahn — auf dem Fensterhintergrund wäre
        // Theme.Track praktisch unsichtbar.
        var track = new RectangleF(0, 0, Width, Height);
        using (var fill = new SolidBrush(Theme.Gray(0.17)))
        using (var path = Theme.Capsule(track))
            g.FillPath(fill, path);

        if (level <= 0.01f) return;
        var filled = new RectangleF(0, 0, Math.Max(Height, Width * level), Height);
        using (var fill = new SolidBrush(Theme.Live))
        using (var path = Theme.Capsule(filled))
            g.FillPath(fill, path);
    }
}

/// <summary>
/// Mehrzeiliges dunkles Eingabefeld — das Gegenstück zu <see cref="ConsoleTextField"/>
/// für das Probediktat.
/// </summary>
internal sealed class ConsoleTextArea : ThemedControl
{
    public TextBox Inner { get; }

    public ConsoleTextArea(int height)
    {
        Inner = new TextBox
        {
            BorderStyle = BorderStyle.None,
            BackColor = Theme.Track,
            ForeColor = Theme.Ink,
            Font = Theme.Body,
            Multiline = true,
            // Keine Bildlaufleiste: die hellgraue Windows-Standardleiste wäre der
            // einzige helle Fleck im dunklen Fenster — der Text rollt beim Tippen
            // ohnehin mit dem Schreibzeiger mit.
            ScrollBars = ScrollBars.None,
            Location = new Point(10, 9),
        };
        Controls.Add(Inner);
        Size = new Size(200, height);
    }

    protected override void OnLayout(LayoutEventArgs e)
    {
        base.OnLayout(e);
        if (Inner == null) return;
        Inner.Width = Math.Max(20, Width - 20);
        Inner.Height = Math.Max(20, Height - 18);
    }

    protected override void OnPaint(PaintEventArgs e)
    {
        var g = e.Graphics;
        Theme.Smooth(g);
        using (var bg = new SolidBrush(BackColor)) g.FillRectangle(bg, ClientRectangle);

        var r = new RectangleF(0.5f, 0.5f, Width - 1, Height - 1);
        using var fill = new SolidBrush(Theme.Track);
        using var path = Theme.Rounded(r, 8);
        using var pen = new Pen(Theme.CardBorder);
        g.FillPath(fill, path);
        g.DrawPath(pen, path);
    }
}
