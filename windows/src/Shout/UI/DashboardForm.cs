using Shout.App;
using Shout.Core;

namespace Shout.UI;

/// <summary>
/// Hauptfenster im Mischpult-Look der Mac-App (DashboardView.swift): links die
/// Graphit-Seitenleiste mit Wortmarke und Navigation, rechts die scrollenden
/// Einstellungs-Panels.
/// </summary>
internal sealed class DashboardForm : Form
{
    internal enum Tab { Aufnahme, Woerterbuch, Verlauf, Statistik, Modelle, Sync, Unterstuetzen }

    private readonly TrayContext app;
    private readonly Sidebar sidebar;
    private readonly ScrollHost host = new();
    private readonly Dictionary<Tab, PageBase> pages = new();
    private Tab current = Tab.Aufnahme;

    private const int SidebarWidth = 224;

    public DashboardForm(TrayContext app, PersonalDictionary dictionary,
                         DictationHistory history, StatsStore stats)
    {
        this.app = app;

        Text = "shout.";
        Icon = AppIcons.Window;   // Logo in Titelleiste, Taskleiste und Alt-Tab
        BackColor = Theme.Window;
        ForeColor = Theme.Ink;
        Font = Theme.Body;
        ClientSize = new Size(920, 660);
        MinimumSize = new Size(800, 600);
        StartPosition = FormStartPosition.CenterScreen;
        KeyPreview = true;   // für die Hotkey-Aufnahme

        sidebar = new Sidebar(app) { Dock = DockStyle.Left, Width = SidebarWidth };
        sidebar.TabSelected += Select;

        host.Dock = DockStyle.Fill;

        pages[Tab.Aufnahme] = new RecordingPage(app, this);
        pages[Tab.Woerterbuch] = new DictionaryPage(dictionary);
        var historyPage = new HistoryPage(history);
        // „Am Cursor einfügen": erst dieses Fenster in den Hintergrund, damit der
        // Text in der zuvor aktiven App landet — sonst fügt er sich hier ein.
        historyPage.InsertRequested += text =>
        {
            var keepInClipboard = Settings.Shared.KeepInClipboard;
            SendToBack();
            var timer = new System.Windows.Forms.Timer { Interval = 220 };
            timer.Tick += (_, _) =>
            {
                timer.Stop();
                timer.Dispose();
                TextInjector.Insert(text, keepInClipboard);
            };
            WindowState = FormWindowState.Minimized;
            timer.Start();
        };
        pages[Tab.Verlauf] = historyPage;
        pages[Tab.Statistik] = new StatisticsPage(app, stats, history, dictionary);
        pages[Tab.Modelle] = new ModelsPage(app);
        pages[Tab.Sync] = new SyncPage(dictionary, history, stats);
        pages[Tab.Unterstuetzen] = new SupportPage(app);

        foreach (var page in pages.Values)
        {
            page.Visible = false;
            page.Width = host.Width;
            host.Content.Controls.Add(page);
        }

        Controls.Add(host);
        Controls.Add(new Divider { Dock = DockStyle.Left, Width = 1 });
        Controls.Add(sidebar);

        // Mausrad soll überall im Inhalt scrollen — auch über Karten hinweg.
        // Beim Schließen wieder abmelden, sonst sammeln sich die Filter an (das
        // Fenster wird bei jedem Sprachwechsel neu aufgebaut).
        wheelFilter = new WheelForwarder(host);
        Application.AddMessageFilter(wheelFilter);

        Select(Tab.Aufnahme);
    }

    private readonly WheelForwarder wheelFilter;

    protected override void OnHandleCreated(EventArgs e)
    {
        base.OnHandleCreated(e);
        DarkTitleBar.Apply(Handle);
    }

    protected override void OnFormClosed(FormClosedEventArgs e)
    {
        Application.RemoveMessageFilter(wheelFilter);
        base.OnFormClosed(e);
    }

    /// <summary>Seite von außen anspringen (z. B. „Einstellungen bei Modelle öffnen").</summary>
    internal void SelectTab(Tab tab) => Select(tab);

    /// <summary>Gerade angezeigte Seite — damit ein Neuaufbau (Sprachwechsel) sie behält.</summary>
    internal Tab CurrentTab => current;

    private void Select(Tab tab)
    {
        current = tab;
        sidebar.Active = tab;
        foreach (var (key, entry) in pages)
            entry.Visible = key == tab;

        var page = pages[tab];
        page.Width = host.Content.Width;
        page.Relayout();
        host.Content.Height = page.Height;
        host.ScrollToTop();
        if (page is IRefreshablePage refreshable) refreshable.Refresh2();
    }

    protected override void OnLayout(LayoutEventArgs e)
    {
        base.OnLayout(e);
        if (!pages.TryGetValue(current, out var page) || host.Content.Width <= 0) return;
        page.Width = host.Content.Width;
        page.Relayout();
        host.Content.Height = page.Height;
    }

    /// <summary>Eine Seite hat ihre Höhe geändert (Zeile ein-/ausgeblendet, Liste
    /// aktualisiert) — Scrollbereich nachziehen.</summary>
    public void PageHeightChanged()
    {
        if (!pages.TryGetValue(current, out var page)) return;
        page.Relayout();
        host.Content.Height = page.Height;
        host.Invalidate();
    }

    /// <summary>Statuszeile der Seitenleiste aktualisieren (aus dem TrayContext).</summary>
    public void RefreshStatus()
    {
        if (InvokeRequired)
        {
            BeginInvoke(RefreshStatus);
            return;
        }
        sidebar.Invalidate();
    }

    /// <summary>Aktualisierungs-Abschnitt auf der Unterstützen-Seite nachziehen.</summary>
    public void RefreshUpdateState()
    {
        if (InvokeRequired)
        {
            BeginInvoke(RefreshUpdateState);
            return;
        }
        if (pages.TryGetValue(Tab.Unterstuetzen, out var page) && page is SupportPage support)
            support.RefreshUpdateState();
    }

    /// <summary>Hotkey-Anzeige nachziehen — nötig, wenn die App auf eine
    /// Ausweich-Kombination gewechselt ist, weil die eingestellte belegt war.</summary>
    public void RefreshHotkeyDisplay()
    {
        if (InvokeRequired)
        {
            BeginInvoke(RefreshHotkeyDisplay);
            return;
        }
        (pages[Tab.Aufnahme] as RecordingPage)?.ShowCurrentHotkey();
    }

    // MARK: Hotkey-Aufnahme

    private Action<uint, uint>? hotkeyCapture;

    /// <summary>Nimmt die nächste Tastenkombination auf (mindestens ein Modifier).
    /// Escape bricht ab.</summary>
    public void CaptureHotkey(Action<uint, uint> onCaptured)
    {
        hotkeyCapture = onCaptured;
    }

    public bool IsCapturingHotkey => hotkeyCapture != null;

    protected override void OnKeyDown(KeyEventArgs e)
    {
        if (hotkeyCapture is { } callback)
        {
            e.SuppressKeyPress = true;
            e.Handled = true;

            if (e.KeyCode == Keys.Escape)
            {
                hotkeyCapture = null;
                app.RegisterHotkeyFromSettings();   // während der Aufnahme abgemeldet
                (pages[Tab.Aufnahme] as RecordingPage)?.ShowCurrentHotkey();
                return;
            }

            uint mods = 0;
            if (e.Control) mods |= HotkeyManager.ModControl;
            if (e.Alt) mods |= HotkeyManager.ModAlt;
            if (e.Shift) mods |= HotkeyManager.ModShift;
            var key = (uint)e.KeyCode;
            // Reine Modifier-Tasten ignorieren; mindestens ein Modifier verlangen
            // (sonst schluckt der Hotkey normale Tastendrücke systemweit).
            if (key is 0x10 or 0x11 or 0x12 || mods == 0) return;

            hotkeyCapture = null;
            callback(mods, key);
            return;
        }
        base.OnKeyDown(e);
    }

    /// <summary>Dünne Trennlinie zwischen Seitenleiste und Inhalt.</summary>
    private sealed class Divider : Control
    {
        public Divider() => BackColor = Color.FromArgb(0, 0, 0);
    }

    /// <summary>
    /// Leitet WM_MOUSEWHEEL an den Scrollbereich, egal über welchem Kind-Control
    /// der Zeiger steht (eigengezeichnete Karten nehmen selbst keinen Fokus).
    /// </summary>
    private sealed class WheelForwarder : IMessageFilter
    {
        private const int WmMouseWheel = 0x020A;
        private readonly ScrollHost host;

        public WheelForwarder(ScrollHost host) => this.host = host;

        public bool PreFilterMessage(ref Message m)
        {
            if (m.Msg != WmMouseWheel || host.IsDisposed || !host.Visible) return false;
            var screen = new Point((short)((long)m.LParam & 0xFFFF), (short)((long)m.LParam >> 16));
            if (!host.RectangleToScreen(host.ClientRectangle).Contains(screen)) return false;

            var delta = (short)((long)m.WParam >> 16);
            host.ScrollBy(-delta * 5 / 6);
            return true;
        }
    }
}

/// <summary>Seiten, die beim Anzeigen neu aufgebaut werden wollen (Verlauf, Statistik).</summary>
internal interface IRefreshablePage
{
    void Refresh2();
}

/// <summary>
/// Graphit-Seitenleiste: Wortmarke „shout." mit Open-Source-Abzeichen, Statuszeile
/// und die Navigationszeilen — aktive Zeile in der Signalfarbe hinterlegt.
/// </summary>
internal sealed class Sidebar : ThemedControl
{
    /// <summary>
    /// Die Navigationseinträge. Die Titel stehen hier auf DEUTSCH und werden erst
    /// beim Zeichnen übersetzt: ein statisches Feld wird beim Laden der Klasse
    /// einmalig ausgewertet und würde nach einem Sprachwechsel in der alten
    /// Sprache stehen bleiben.
    /// </summary>
    private static readonly (DashboardForm.Tab Tab, string Title, Icons.Kind Icon)[] Items =
    {
        (DashboardForm.Tab.Aufnahme, "Aufnahme & Text", Icons.Kind.Mic),
        (DashboardForm.Tab.Woerterbuch, "Wörterbuch", Icons.Kind.Book),
        (DashboardForm.Tab.Verlauf, "Verlauf", Icons.Kind.History),
        (DashboardForm.Tab.Statistik, "Statistiken", Icons.Kind.Chart),
        (DashboardForm.Tab.Modelle, "Modelle", Icons.Kind.Chip),
        (DashboardForm.Tab.Sync, "Sync & Geräte", Icons.Kind.Sync),
        (DashboardForm.Tab.Unterstuetzen, "Unterstützen", Icons.Kind.Heart),
    };

    private const int NavTop = 110;
    private const int RowHeight = 32;
    private const int OuterPad = 10;

    private readonly TrayContext app;
    private int hovered = -1;

    public event Action<DashboardForm.Tab>? TabSelected;

    private DashboardForm.Tab active = DashboardForm.Tab.Aufnahme;

    /// <summary>Hervorgehobene Zeile. Setzt zwingend ein Neuzeichnen nach — ohne das
    /// bliebe die alte Zeile markiert, bis irgendetwas anderes die Leiste anstößt
    /// (bei Mausbedienung der Hover-Effekt, sonst nichts).</summary>
    public DashboardForm.Tab Active
    {
        get => active;
        set
        {
            if (active == value) return;
            active = value;
            Invalidate();
        }
    }

    public Sidebar(TrayContext app)
    {
        this.app = app;
        BackColor = Theme.Sidebar;
    }

    private static Rectangle RowRect(int index, int width) =>
        new(OuterPad, NavTop + index * RowHeight, width - OuterPad * 2, RowHeight - 2);

    protected override void OnMouseMove(MouseEventArgs e)
    {
        var hit = -1;
        for (var i = 0; i < Items.Length; i++)
            if (RowRect(i, Width).Contains(e.Location)) { hit = i; break; }
        if (hit != hovered)
        {
            hovered = hit;
            Cursor = hit >= 0 ? Cursors.Hand : Cursors.Default;
            Invalidate();
        }
        base.OnMouseMove(e);
    }

    protected override void OnMouseLeave(EventArgs e)
    {
        hovered = -1;
        Invalidate();
        base.OnMouseLeave(e);
    }

    protected override void OnMouseClick(MouseEventArgs e)
    {
        for (var i = 0; i < Items.Length; i++)
        {
            if (!RowRect(i, Width).Contains(e.Location)) continue;
            TabSelected?.Invoke(Items[i].Tab);
            break;
        }
        base.OnMouseClick(e);
    }

    protected override void OnPaint(PaintEventArgs e)
    {
        var g = e.Graphics;
        Theme.Smooth(g);
        using (var bg = new SolidBrush(Theme.Sidebar)) g.FillRectangle(bg, ClientRectangle);

        // Wortmarke: „shout" weiß, der Punkt in der Signalfarbe — ohne Polsterung
        // gemessen, damit er direkt anschließt.
        const int left = 18;
        const int top = 40;
        var shoutWidth = Theme.MeasureTight("shout", Theme.Wordmark);
        var dotWidth = Theme.MeasureTight(".", Theme.Wordmark);
        Theme.DrawTight(g, "shout", Theme.Wordmark, Color.White, new Point(left, top));
        Theme.DrawTight(g, ".", Theme.Wordmark, Theme.Live, new Point(left + shoutWidth, top));

        // „Open Source"-Abzeichen
        var badgeText = "Open Source";
        var badgeWidth = TextRenderer.MeasureText(badgeText, Theme.Badge).Width + 14;
        var badge = new RectangleF(left + shoutWidth + dotWidth + 9, top + 9, badgeWidth, 17);
        Theme.DrawCapsule(g, badge, Theme.LiveAlpha(0.20));
        DrawText(g, badgeText, Theme.Badge, Theme.Live, Rectangle.Round(badge),
                 TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.NoPrefix);

        // Statuszeile mit Signal-Punkt
        using (var dot = new SolidBrush(Theme.Live))
            g.FillEllipse(dot, left, top + 42, 6, 6);
        DrawText(g, app.StatusLine, Theme.Help, Theme.Gray(0.55),
                 new Rectangle(left + 12, top + 35, Width - left - 20, 20),
                 TextFormatFlags.VerticalCenter | TextFormatFlags.EndEllipsis | TextFormatFlags.NoPrefix);

        // Navigationszeilen
        for (var i = 0; i < Items.Length; i++)
        {
            var (tab, title, icon) = Items[i];
            var row = RowRect(i, Width);
            var isActive = tab == Active;

            if (isActive)
            {
                using var fill = new SolidBrush(Theme.LiveAlpha(0.18));
                using var path = Theme.Rounded(row, 8);
                g.FillPath(fill, path);
            }
            else if (i == hovered)
            {
                using var fill = new SolidBrush(Theme.White(0.05));
                using var path = Theme.Rounded(row, 8);
                g.FillPath(fill, path);
            }

            var color = isActive ? Color.White : Theme.Gray(0.64);
            Icons.Draw(g, icon, new RectangleF(row.X + 11, row.Y, 20, row.Height), color, 14f);
            DrawText(g, Loc.T(title), isActive ? Theme.RowTitleStrong : Theme.RowTitle, color,
                     new Rectangle(row.X + 41, row.Y, row.Width - 48, row.Height),
                     TextFormatFlags.VerticalCenter | TextFormatFlags.EndEllipsis | TextFormatFlags.NoPrefix);
        }
    }
}
