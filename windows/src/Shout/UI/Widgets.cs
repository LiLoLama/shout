using Shout.Core;

namespace Shout.UI;

// Spezialisierte Bausteine für einzelne Seiten — Aufbau und Maße wie in den
// entsprechenden SwiftUI-Ansichten der Mac-App.

/// <summary>Seitenkopf: Titel links, optionaler Knopf rechts (Mac: HStack + Spacer).</summary>
internal sealed class SectionHeader : ThemedControl, IAutoHeight
{
    private readonly string title;
    public Control? Trailing { get; }

    public SectionHeader(string title, Control? trailing = null)
    {
        this.title = title;
        Trailing = trailing;
        if (trailing != null) Controls.Add(trailing);
        ApplyMetrics();
    }

    private void ApplyMetrics() => Height = Scaled(30);

    protected override void OnDpiChangedAfterParent(EventArgs e)
    {
        base.OnDpiChangedAfterParent(e);
        ApplyMetrics();
    }

    public int PreferredHeightFor(int width) => Math.Max(Scaled(24), Trailing?.Height ?? 0);

    protected override void OnLayout(LayoutEventArgs e)
    {
        base.OnLayout(e);
        if (Trailing == null) return;
        Trailing.Location = new Point(Width - Trailing.Width, (Height - Trailing.Height) / 2);
    }

    protected override void OnPaint(PaintEventArgs e)
    {
        var g = e.Graphics;
        Theme.Smooth(g);
        using (var bg = new SolidBrush(BackColor)) g.FillRectangle(bg, ClientRectangle);
        DrawText(g, title, Theme.PageTitle, Theme.Gray(0.92),
                 new Rectangle(0, 0, Width - (Trailing?.Width ?? 0) - Scaled(8), Height),
                 TextFormatFlags.VerticalCenter | TextFormatFlags.NoPrefix);
    }
}

/// <summary>Gesperrtes Gruppen-Label in Großbuchstaben („HEUTE", „GESTERN").</summary>
internal sealed class GroupLabel : ThemedControl, IAutoHeight
{
    private readonly string text;

    public GroupLabel(string text)
    {
        this.text = text.ToUpperInvariant();
        Height = Scaled(18);
    }

    protected override void OnDpiChangedAfterParent(EventArgs e)
    {
        base.OnDpiChangedAfterParent(e);
        Height = Scaled(18);
    }

    public int PreferredHeightFor(int width) => Scaled(18);

    protected override void OnPaint(PaintEventArgs e)
    {
        var g = e.Graphics;
        Theme.Smooth(g);
        using (var bg = new SolidBrush(BackColor)) g.FillRectangle(bg, ClientRectangle);
        Theme.DrawTracked(g, text, Theme.SectionLabel, Theme.Gray(0.45),
                          new PointF(Scaled(4), Scaled(2)), Scaled(0.8f));
    }
}

/// <summary>
/// Verlaufs-Karte: Uhrzeit (Monospace), Diktat-Text und drei Symbol-Knöpfe
/// (einfügen, kopieren, löschen). Klickzonen berechnet die Karte selbst.
/// </summary>
internal sealed class HistoryCard : ThemedControl, IAutoHeight
{
    private readonly DictationHistory.Entry entry;
    private int hoveredAction = -1;
    private int focusedAction = -1;
    private bool showingRaw;

    /// <summary>Hat dieser Eintrag ein Rohtranskript, das sich vom eingefügten Text
    /// unterscheidet? Nur dann gibt es überhaupt etwas anzuzeigen.</summary>
    private bool HasRaw => !string.IsNullOrEmpty(entry.Raw);

    /// <summary>Die Zeile zum Aufklappen zählt als vierte Aktion — so gilt für sie
    /// dieselbe Tastaturbedienung wie für die drei Symbole.</summary>
    private int LastAction => HasRaw ? 3 : 2;

    /// <summary>Höhe wird gebraucht, sobald die Karte neu vermessen werden muss.</summary>
    public event Action? HeightChanged;

    public event Action<DictationHistory.Entry>? InsertRequested;
    public event Action<DictationHistory.Entry>? CopyRequested;
    public event Action<DictationHistory.Entry>? DeleteRequested;

    private int Pad => Scaled(14);
    private int TimeWidth => Scaled(48);
    private int ActionSize => Scaled(22);
    private int ActionGap => Scaled(8);
    private int ActionsWidth => ActionSize * 3 + ActionGap * 2;

    public HistoryCard(DictationHistory.Entry entry)
    {
        this.entry = entry;
        // Der Diktat-Text ist der einzige Name, den diese Karte hat.
        MakeInteractive(AccessibleRole.ListItem, entry.Text);
    }

    private int TextWidth(int width) =>
        Math.Max(Scaled(60), width - Pad * 2 - TimeWidth - Scaled(14) - ActionsWidth - Scaled(14));

    private string RawToggleLabel =>
        showingRaw ? Loc.T("Original ausblenden") : Loc.T("Original anzeigen");

    /// <summary>Höhe des Textes plus, wenn aufgeklappt, des Rohtranskripts.</summary>
    private int BodyHeight(int width)
    {
        var height = Math.Max(Scaled(24), MeasureText(entry.Text, Theme.RowTitle, TextWidth(width)).Height);
        if (!HasRaw) return height;
        height += Scaled(6) + MeasureText(RawToggleLabel, Theme.Help, TextWidth(width)).Height;
        if (showingRaw)
            height += Scaled(4) + MeasureText(entry.Raw!, Theme.Help, TextWidth(width)).Height;
        return height;
    }

    public int PreferredHeightFor(int width) => BodyHeight(width) + Pad * 2;

    /// <summary>Fläche der Aufklapp-Zeile — sie sitzt unter dem Text, nicht rechts
    /// bei den Symbolen.</summary>
    private Rectangle RawToggleRect()
    {
        if (!HasRaw) return Rectangle.Empty;
        var textWidth = TextWidth(Width);
        var left = Pad + TimeWidth + Scaled(14);
        var top = Pad + Math.Max(Scaled(24), MeasureText(entry.Text, Theme.RowTitle, textWidth).Height)
                  + Scaled(6);
        var size = MeasureText(RawToggleLabel, Theme.Help, textWidth);
        return new Rectangle(left, top, Math.Min(size.Width + Scaled(4), textWidth), size.Height);
    }

    private void ToggleRaw()
    {
        if (!HasRaw) return;
        showingRaw = !showingRaw;
        Invalidate();
        HeightChanged?.Invoke();
    }

    private Rectangle ActionRect(int index) =>
        new(Width - Pad - ActionsWidth + index * (ActionSize + ActionGap), Pad, ActionSize, ActionSize);

    protected override void OnMouseMove(MouseEventArgs e)
    {
        var hit = -1;
        for (var i = 0; i < 3; i++)
            if (ActionRect(i).Contains(e.Location)) { hit = i; break; }
        if (hit < 0 && HasRaw && RawToggleRect().Contains(e.Location)) hit = 3;
        if (hit != hoveredAction)
        {
            hoveredAction = hit;
            Cursor = hit >= 0 ? Cursors.Hand : Cursors.Default;
            Invalidate();
        }
        base.OnMouseMove(e);
    }

    protected override void OnMouseLeave(EventArgs e)
    {
        hoveredAction = -1;
        Invalidate();
        base.OnMouseLeave(e);
    }

    protected override void OnMouseClick(MouseEventArgs e)
    {
        // Nur die linke Taste: ein Rechtsklick auf den Papierkorb hat sonst denselben
        // Diktat-Eintrag gelöscht wie ein bewusster Klick.
        if (e.Button != MouseButtons.Left)
        {
            base.OnMouseClick(e);
            return;
        }
        for (var i = 0; i < 3; i++)
        {
            if (!ActionRect(i).Contains(e.Location)) continue;
            focusedAction = i;
            Trigger(i);
            base.OnMouseClick(e);
            return;
        }
        if (HasRaw && RawToggleRect().Contains(e.Location))
        {
            focusedAction = 3;
            ToggleRaw();
        }
        base.OnMouseClick(e);
    }

    private void Trigger(int index)
    {
        switch (index)
        {
            case 0: InsertRequested?.Invoke(entry); break;
            case 1: CopyRequested?.Invoke(entry); break;
            case 2: DeleteRequested?.Invoke(entry); break;
            case 3: ToggleRaw(); break;
        }
    }

    protected override void OnGotFocus(EventArgs e)
    {
        if (focusedAction < 0) focusedAction = 0;
        base.OnGotFocus(e);
    }

    protected override bool IsInputKey(Keys keyData)
        => keyData is Keys.Left or Keys.Right or Keys.Home or Keys.End or Keys.Delete
           || base.IsInputKey(keyData);

    protected override void OnKeyDown(KeyEventArgs e)
    {
        switch (e.KeyCode)
        {
            case Keys.Left: focusedAction = Math.Max(0, focusedAction - 1); Invalidate(); break;
            case Keys.Right: focusedAction = Math.Min(LastAction, focusedAction + 1); Invalidate(); break;
            case Keys.Home: focusedAction = 0; Invalidate(); break;
            case Keys.End: focusedAction = LastAction; Invalidate(); break;
            case Keys.Delete: Trigger(2); break;
            case Keys.Enter:
            case Keys.Space:
                Trigger(Math.Max(0, focusedAction));
                break;
            default:
                base.OnKeyDown(e);
                return;
        }
        e.Handled = true;
        e.SuppressKeyPress = true;
        base.OnKeyDown(e);
    }

    protected override void OnPaint(PaintEventArgs e)
    {
        var g = e.Graphics;
        Theme.Smooth(g);
        using (var bg = new SolidBrush(Theme.Window)) g.FillRectangle(bg, ClientRectangle);
        Theme.DrawCard(g, new RectangleF(0, 0, Width, Height), Scaled(12f));

        DrawText(g, entry.Date.ToLocalTime().ToString("HH:mm"), Theme.MonoSmall, Theme.Gray(0.5),
                 new Rectangle(Pad, Pad, TimeWidth, Scaled(20)), TextFormatFlags.NoPrefix);

        var textWidth = TextWidth(Width);
        var left = Pad + TimeWidth + Scaled(14);
        var textHeight = Math.Max(Scaled(24), MeasureText(entry.Text, Theme.RowTitle, textWidth).Height);
        DrawText(g, entry.Text, Theme.RowTitle, Theme.Gray(0.9),
                 new Rectangle(left, Pad, textWidth, textHeight),
                 TextFormatFlags.WordBreak | TextFormatFlags.NoPrefix);

        if (HasRaw)
        {
            // Das Rohtranskript zeigt, was die Spracherkennung WIRKLICH geliefert
            // hat — ohne das lässt sich fehlender Inhalt nicht der richtigen Stufe
            // zuordnen (Whisper oder Aufbereitung).
            var toggle = RawToggleRect();
            var toggleColor = hoveredAction == 3 ? Theme.Live : Theme.Gray(0.5);
            DrawText(g, RawToggleLabel, Theme.Help, toggleColor, toggle, TextFormatFlags.NoPrefix);
            if (focusedAction == 3)
                DrawFocusRing(g, new RectangleF(toggle.X - 1.5f, toggle.Y - 0.5f,
                                                toggle.Width + 2, toggle.Height + 1), Scaled(4f));
            if (showingRaw)
            {
                var rawTop = toggle.Bottom + Scaled(4);
                DrawText(g, entry.Raw!, Theme.Help, Theme.Gray(0.42),
                         new Rectangle(left, rawTop, textWidth, Height - rawTop - Pad),
                         TextFormatFlags.WordBreak | TextFormatFlags.NoPrefix);
            }
        }

        Icons.Kind[] actions = { Icons.Kind.Insert, Icons.Kind.Copy, Icons.Kind.Trash };
        for (var i = 0; i < actions.Length; i++)
        {
            var r = ActionRect(i);
            var color = i == hoveredAction ? Theme.Live : Theme.Gray(0.5);
            Icons.Draw(g, actions[i], r, color, Scaled(14f));
            if (i == focusedAction)
                DrawFocusRing(g, new RectangleF(r.X + 0.5f, r.Y + 0.5f, r.Width - 1, r.Height - 1), Scaled(6f));
        }
    }
}

/// <summary>Leerer Zustand mit großem Symbol, Titel und Erklärung (mittig).</summary>
internal sealed class EmptyState : ThemedControl, IAutoHeight
{
    private readonly Icons.Kind icon;
    private readonly string title, subtitle;

    public EmptyState(Icons.Kind icon, string title, string subtitle)
    {
        this.icon = icon;
        this.title = title;
        this.subtitle = subtitle;
    }

    private int SubtitleWidth(int width) => Math.Min(Scaled(320), width);

    public int PreferredHeightFor(int width)
        => Scaled(60 + 44 + 12 + 24 + 6)
           + MeasureText(subtitle, Theme.Small, SubtitleWidth(width)).Height;

    protected override void OnPaint(PaintEventArgs e)
    {
        var g = e.Graphics;
        Theme.Smooth(g);
        using (var bg = new SolidBrush(BackColor)) g.FillRectangle(bg, ClientRectangle);

        var y = Scaled(60);
        Icons.Draw(g, icon, new RectangleF(0, y, Width, Scaled(44)), Theme.Gray(0.4), Scaled(40f));
        y += Scaled(44 + 12);
        DrawText(g, title, Theme.PageTitle, Theme.Gray(0.75), new Rectangle(0, y, Width, Scaled(24)),
                 TextFormatFlags.HorizontalCenter | TextFormatFlags.NoPrefix);
        y += Scaled(24 + 6);
        var subWidth = SubtitleWidth(Width);
        DrawText(g, subtitle, Theme.Small, Theme.Gray(0.55),
                 new Rectangle((Width - subWidth) / 2, y, subWidth, Height - y),
                 TextFormatFlags.HorizontalCenter | TextFormatFlags.WordBreak | TextFormatFlags.NoPrefix);
    }
}

/// <summary>Streak-Kennzahlen: große Zahl in der Signalfarbe plus Beschriftung.</summary>
internal sealed class MetricRow : ThemedControl, IAutoHeight
{
    private readonly (string Value, string Label)[] metrics;

    public MetricRow((string Value, string Label)[] metrics)
    {
        this.metrics = metrics;
        Height = Scaled(32);
    }

    protected override void OnDpiChangedAfterParent(EventArgs e)
    {
        base.OnDpiChangedAfterParent(e);
        Height = Scaled(32);
    }

    public int PreferredHeightFor(int width) => Scaled(32);

    protected override void OnPaint(PaintEventArgs e)
    {
        var g = e.Graphics;
        Theme.Smooth(g);
        using (var bg = new SolidBrush(BackColor)) g.FillRectangle(bg, ClientRectangle);

        var x = 0;
        foreach (var (value, label) in metrics)
        {
            // Über den Zeichenkontext messen: ohne ihn misst GDI am Hauptbildschirm
            // und die Beschriftung landet bei 150 % mitten in der Zahl.
            var valueWidth = TextRenderer.MeasureText(g, value, Theme.MetricSmall).Width;
            DrawText(g, value, Theme.MetricSmall, Theme.Live,
                     new Rectangle(x, 0, valueWidth + Scaled(6), Height),
                     TextFormatFlags.VerticalCenter | TextFormatFlags.NoPrefix);
            x += valueWidth + Scaled(2);
            var labelWidth = TextRenderer.MeasureText(g, label, Theme.Small).Width;
            DrawText(g, label, Theme.Small, Theme.Gray(0.6),
                     new Rectangle(x, 0, labelWidth + Scaled(8), Height),
                     TextFormatFlags.VerticalCenter | TextFormatFlags.NoPrefix);
            x += labelWidth + Scaled(20);
        }
    }
}

/// <summary>Aktivitäts-Kalender der letzten 8 Wochen (13-px-Kacheln, 3 px Abstand).</summary>
internal sealed class HeatmapView : ThemedControl, IAutoHeight
{
    private readonly StatsStore stats;
    private int Cell => Scaled(13);
    private int Gap => Scaled(3);
    private const int Weeks = 8;

    public HeatmapView(StatsStore stats)
    {
        this.stats = stats;
        Height = GridHeight;
    }

    private int GridHeight => 7 * Cell + 6 * Gap;

    protected override void OnDpiChangedAfterParent(EventArgs e)
    {
        base.OnDpiChangedAfterParent(e);
        Height = GridHeight;
    }

    public int PreferredHeightFor(int width) => GridHeight;

    /// <summary>Zeilenindex des Tages — die Woche beginnt hier montags.</summary>
    private static int RowFor(DateTime day) => ((int)day.DayOfWeek + 6) % 7;

    protected override void OnPaint(PaintEventArgs e)
    {
        var g = e.Graphics;
        Theme.Smooth(g);
        using (var bg = new SolidBrush(BackColor)) g.FillRectangle(bg, ClientRectangle);

        var today = DateTime.Today;
        var first = today.AddDays(-(Weeks * 7 - 1));
        // Am Montag der ersten Woche verankern und jeden Tag in SEINE Wochentagszeile
        // setzen: sonst rutscht das Raster jeden Tag um eine Zeile weiter und die
        // Zeilen bedeuten nichts. Die Felder vor dem ersten Tag bleiben leer.
        var start = first.AddDays(-RowFor(first));
        using var active = new SolidBrush(Theme.Live);
        using var inactive = new SolidBrush(Theme.Gray(0.18));

        for (var day = first; day <= today; day = day.AddDays(1))
        {
            var week = (day - start).Days / 7;
            var cell = new RectangleF(week * (Cell + Gap), RowFor(day) * (Cell + Gap), Cell, Cell);
            using var path = Theme.Rounded(cell, Scaled(3f));
            g.FillPath(stats.IsActive(day) ? active : inactive, path);
        }
    }
}

/// <summary>Ein Eintrag in der Modell-Liste.</summary>
internal sealed class ModelEntry
{
    public required string Id { get; init; }
    public required string Name { get; init; }
    public required string Note { get; init; }
    public required string SizeHint { get; init; }
    public bool Recommended { get; init; }
    public bool TooBig { get; init; }
}

/// <summary>
/// Karte mit Modell-Zeilen: Auswahlkreis, Name mit Abzeichen, Kurzbeschreibung und
/// rechts der Download-Fortschritt (Mac: ModelsView.modelRow).
/// </summary>
internal sealed class ModelListPanel : ThemedControl, IAutoHeight
{
    private readonly ModelEntry[] entries;
    private string selectedId;
    private string? loadingId;
    private double? progress;
    private int hovered = -1;
    private int focused = -1;

    public event Action<string>? Selected;
    /// <summary>Auswahl gesperrt (läuft gerade eine Aufnahme oder ein Wechsel).</summary>
    public Func<bool>? Locked { get; set; }

    public string? Title { get; init; }

    private int LabelHeight => Scaled(22);
    private int RowPadH => Scaled(15);
    private int RowPadV => Scaled(12);
    private int RadioWidth => Scaled(28);

    public ModelListPanel(ModelEntry[] entries, string selectedId)
    {
        this.entries = entries;
        this.selectedId = selectedId;
        MakeInteractive(AccessibleRole.List, NameOf(selectedId));
    }

    private string? NameOf(string id) => entries.FirstOrDefault(entry => entry.Id == id)?.Name;

    public void SetSelected(string id)
    {
        selectedId = id;
        AccessibleDescription = NameOf(id);
        Invalidate();
    }

    /// <summary>Ladezustand anzeigen (id = null beendet die Anzeige).</summary>
    public void SetLoading(string? id, double? value)
    {
        loadingId = id;
        progress = value;
        Invalidate();
    }

    private int TextWidth(int width) => Math.Max(Scaled(60), width - RowPadH * 2 - RadioWidth - Scaled(110));

    private int RowHeight(ModelEntry entry, int width)
    {
        var h = MeasureText(entry.Name, Theme.RowTitle, TextWidth(width)).Height;
        h += Scaled(2) + MeasureText(Subtitle(entry), Theme.Help, TextWidth(width)).Height;
        return h + RowPadV * 2;
    }

    // Die Beschreibungen stehen im Katalog auf Deutsch (statisches Feld) und
    // werden erst hier, beim Anzeigen, übersetzt.
    private static string Subtitle(ModelEntry entry) => $"{entry.SizeHint} · {Loc.T(entry.Note)}";

    public int PreferredHeightFor(int width)
    {
        var total = Title != null ? LabelHeight : 0;
        foreach (var entry in entries) total += RowHeight(entry, width);
        return total;
    }

    private Rectangle RowRect(int index, int width)
    {
        var y = Title != null ? LabelHeight : 0;
        for (var i = 0; i < index; i++) y += RowHeight(entries[i], width);
        return new Rectangle(0, y, width, RowHeight(entries[index], width));
    }

    protected override void OnMouseMove(MouseEventArgs e)
    {
        var hit = -1;
        for (var i = 0; i < entries.Length; i++)
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
        // Ein Rechtsklick darf kein Modell umschalten — das lädt Gigabyte nach.
        if (e.Button != MouseButtons.Left)
        {
            base.OnMouseClick(e);
            return;
        }
        if (Locked?.Invoke() == true || loadingId != null) return;
        for (var i = 0; i < entries.Length; i++)
        {
            if (!RowRect(i, Width).Contains(e.Location)) continue;
            focused = i;
            Choose(i);
            break;
        }
        base.OnMouseClick(e);
    }

    private void Choose(int index)
    {
        if (index < 0 || index >= entries.Length) return;
        if (Locked?.Invoke() == true || loadingId != null) return;
        if (entries[index].Id != selectedId) Selected?.Invoke(entries[index].Id);
    }

    protected override void OnGotFocus(EventArgs e)
    {
        if (focused < 0)
        {
            var current = Array.FindIndex(entries, entry => entry.Id == selectedId);
            focused = Math.Max(0, current);
        }
        base.OnGotFocus(e);
    }

    private void MoveFocus(int index)
    {
        if (entries.Length == 0) return;
        focused = Math.Clamp(index, 0, entries.Length - 1);
        AccessibleDescription = entries[focused].Name;
        Invalidate();
    }

    protected override bool IsInputKey(Keys keyData)
        => keyData is Keys.Up or Keys.Down or Keys.Home or Keys.End || base.IsInputKey(keyData);

    protected override void OnKeyDown(KeyEventArgs e)
    {
        switch (e.KeyCode)
        {
            case Keys.Up: MoveFocus(focused - 1); break;
            case Keys.Down: MoveFocus(focused + 1); break;
            case Keys.Home: MoveFocus(0); break;
            case Keys.End: MoveFocus(entries.Length - 1); break;
            case Keys.Enter:
            case Keys.Space:
                Choose(focused);
                break;
            default:
                base.OnKeyDown(e);
                return;
        }
        e.Handled = true;
        e.SuppressKeyPress = true;
        base.OnKeyDown(e);
    }

    protected override void OnPaint(PaintEventArgs e)
    {
        var g = e.Graphics;
        Theme.Smooth(g);
        using (var bg = new SolidBrush(Theme.Window)) g.FillRectangle(bg, ClientRectangle);

        var cardTop = 0;
        if (Title != null)
        {
            Theme.DrawTracked(g, Title.ToUpperInvariant(), Theme.SectionLabel, Theme.InkFaint,
                              new PointF(Scaled(4), 0), Scaled(0.8f));
            cardTop = LabelHeight;
        }
        Theme.DrawCard(g, new RectangleF(0, cardTop, Width, Height - cardTop), Scaled(12f));

        for (var i = 0; i < entries.Length; i++)
        {
            var entry = entries[i];
            var row = RowRect(i, Width);
            var selected = entry.Id == selectedId;

            if (i > 0)
            {
                using var pen = new Pen(Theme.Divider);
                g.DrawLine(pen, RowPadH, row.Y + 0.5f, Width - RowPadH, row.Y + 0.5f);
            }

            // Auswahlkreis (Mac: largecircle.fill.circle bzw. circle)
            var ring = Scaled(16);
            var circle = new RectangleF(RowPadH, row.Y + row.Height / 2f - ring / 2f, ring, ring);
            using (var pen = new Pen(selected ? Theme.Live : Theme.Gray(0.4), Scaled(1.6f)))
                g.DrawEllipse(pen, circle);
            if (selected)
            {
                using var dot = new SolidBrush(Theme.Live);
                g.FillEllipse(dot, circle.X + ring / 4f, circle.Y + ring / 4f, ring / 2f, ring / 2f);
            }

            var textLeft = RowPadH + RadioWidth;
            var textWidth = TextWidth(Width);
            var nameSize = MeasureText(entry.Name, Theme.RowTitle, textWidth);
            var subSize = MeasureText(Subtitle(entry), Theme.Help, textWidth);
            var block = nameSize.Height + Scaled(2) + subSize.Height;
            var top = row.Y + (row.Height - block) / 2;

            DrawText(g, entry.Name, Theme.RowTitle, Theme.Gray(0.9),
                     new Rectangle(textLeft, top, textWidth, nameSize.Height), TextFormatFlags.NoPrefix);

            // Abzeichen rechts vom Namen
            var badgeX = textLeft + nameSize.Width + Scaled(7);
            if (entry.Recommended) badgeX += DrawBadge(g, Loc.T("Empfohlen"), Theme.Live, badgeX, top, nameSize.Height);
            if (entry.TooBig) DrawBadge(g, Loc.T("Viel RAM nötig"), Theme.Gray(0.55), badgeX, top, nameSize.Height);

            DrawText(g, Subtitle(entry), Theme.Help, Theme.Gray(0.55),
                     new Rectangle(textLeft, top + nameSize.Height + Scaled(2), textWidth, subSize.Height),
                     TextFormatFlags.NoPrefix);

            if (loadingId == entry.Id) DrawProgress(g, row);

            if (i == focused)
                DrawFocusRing(g, new RectangleF(RowPadH / 2f, row.Y + 1.5f,
                                                Width - RowPadH, row.Height - 3), Scaled(8f));
        }
    }

    private int DrawBadge(Graphics g, string text, Color color, int x, int y, int lineHeight)
    {
        // Am Zeichenkontext messen: bei 150 % wäre die Kapsel sonst zu schmal
        // für ihre Aufschrift.
        var width = TextRenderer.MeasureText(g, text, Theme.Badge).Width + Scaled(12);
        var height = Scaled(16);
        var badge = new RectangleF(x, y + (lineHeight - height) / 2f, width, height);
        Theme.DrawCapsule(g, badge, Color.FromArgb(46, color));
        DrawText(g, text, Theme.Badge, color, Rectangle.Round(badge),
                 TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.NoPrefix);
        return width + Scaled(6);
    }

    /// <summary>Balken mit Prozent während des Downloads, sonst „lädt …".</summary>
    private void DrawProgress(Graphics g, Rectangle row)
    {
        var right = Width - RowPadH;
        var cy = row.Y + row.Height / 2f;

        if (progress is { } p && p > 0.0001 && p < 0.999)
        {
            var barWidth = Scaled(66);
            var bar = new RectangleF(right - barWidth - Scaled(38), cy - Scaled(3f), barWidth, Scaled(6f));
            using (var track = new SolidBrush(Theme.Track))
            using (var path = Theme.Capsule(bar))
                g.FillPath(track, path);
            var filled = new RectangleF(bar.X, bar.Y, (float)(bar.Width * p), bar.Height);
            if (filled.Width > 1)
            {
                using var fill = new SolidBrush(Theme.Live);
                using var path = Theme.Capsule(filled);
                g.FillPath(fill, path);
            }
            DrawText(g, $"{(int)(p * 100)} %", Theme.MonoSmall, Theme.Gray(0.6),
                     new Rectangle(right - Scaled(34), row.Y, Scaled(34), row.Height),
                     TextFormatFlags.VerticalCenter | TextFormatFlags.NoPrefix);
        }
        else
        {
            DrawText(g, Loc.T("lädt …"), Theme.Help, Theme.Live,
                     new Rectangle(right - Scaled(60), row.Y, Scaled(60), row.Height),
                     TextFormatFlags.VerticalCenter | TextFormatFlags.Right | TextFormatFlags.NoPrefix);
        }
    }
}

/// <summary>
/// Liste der gelernten Korrekturen: „falsch" durchgestrichen, Pfeil, „richtig" in
/// der Signalfarbe, rechts der Papierkorb.
/// </summary>
internal sealed class CorrectionList : ThemedControl, IAutoHeight
{
    private readonly List<PersonalDictionary.Correction> items = new();
    private int hovered = -1;
    private int focused = -1;

    public event Action<PersonalDictionary.Correction>? Deleted;

    private int RowHeight => Scaled(26);

    public CorrectionList()
    {
        MakeInteractive(AccessibleRole.List);
    }

    public void SetItems(IEnumerable<PersonalDictionary.Correction> corrections)
    {
        items.Clear();
        items.AddRange(corrections);
        focused = Math.Min(focused, items.Count - 1);
        Describe();
        Invalidate();
    }

    public int PreferredHeightFor(int width) => items.Count * RowHeight;

    private Rectangle TrashRect(int index)
        => new(Width - Scaled(22), index * RowHeight + Scaled(4), Scaled(18), Scaled(18));

    protected override void OnMouseMove(MouseEventArgs e)
    {
        var hit = -1;
        for (var i = 0; i < items.Count; i++)
            if (TrashRect(i).Contains(e.Location)) { hit = i; break; }
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
        // Ein Rechtsklick auf den Papierkorb hat bisher die Korrektur gelöscht.
        if (e.Button != MouseButtons.Left)
        {
            base.OnMouseClick(e);
            return;
        }
        for (var i = 0; i < items.Count; i++)
        {
            if (!TrashRect(i).Contains(e.Location)) continue;
            focused = i;
            Deleted?.Invoke(items[i]);
            break;
        }
        base.OnMouseClick(e);
    }

    protected override void OnGotFocus(EventArgs e)
    {
        if (focused < 0 && items.Count > 0) MoveFocus(0);
        base.OnGotFocus(e);
    }

    private void MoveFocus(int index)
    {
        if (items.Count == 0) return;
        focused = Math.Clamp(index, 0, items.Count - 1);
        Describe();
        Invalidate();
    }

    /// <summary>Die Zeile für Screenreader benennen — beide Schreibweisen stehen schon da.</summary>
    private void Describe()
    {
        if (focused < 0 || focused >= items.Count) return;
        AccessibleName = items[focused].Wrong;
        AccessibleDescription = items[focused].Right;
    }

    protected override bool IsInputKey(Keys keyData)
        => keyData is Keys.Up or Keys.Down or Keys.Home or Keys.End or Keys.Delete
           || base.IsInputKey(keyData);

    protected override void OnKeyDown(KeyEventArgs e)
    {
        switch (e.KeyCode)
        {
            case Keys.Up: MoveFocus(focused - 1); break;
            case Keys.Down: MoveFocus(focused + 1); break;
            case Keys.Home: MoveFocus(0); break;
            case Keys.End: MoveFocus(items.Count - 1); break;
            case Keys.Delete:
            case Keys.Back:
            case Keys.Enter:
            case Keys.Space:
                if (focused >= 0 && focused < items.Count) Deleted?.Invoke(items[focused]);
                break;
            default:
                base.OnKeyDown(e);
                return;
        }
        e.Handled = true;
        e.SuppressKeyPress = true;
        base.OnKeyDown(e);
    }

    protected override void OnPaint(PaintEventArgs e)
    {
        var g = e.Graphics;
        Theme.Smooth(g);
        using (var bg = new SolidBrush(BackColor)) g.FillRectangle(bg, ClientRectangle);

        for (var i = 0; i < items.Count; i++)
        {
            var y = i * RowHeight;
            // Am Zeichenkontext messen, sonst sitzen Pfeil und „richtig" bei 150 %
            // im durchgestrichenen Wort.
            var wrongWidth = TextRenderer.MeasureText(g, items[i].Wrong, Theme.RowTitle).Width;
            DrawText(g, items[i].Wrong, Theme.RowTitle, Theme.Gray(0.55),
                     new Rectangle(0, y, wrongWidth + Scaled(6), RowHeight),
                     TextFormatFlags.VerticalCenter | TextFormatFlags.NoPrefix);
            // Durchgestrichen (Mac: .strikethrough())
            using (var pen = new Pen(Theme.Gray(0.55)))
                g.DrawLine(pen, 1, y + RowHeight / 2f, wrongWidth, y + RowHeight / 2f);

            var arrowX = wrongWidth + Scaled(8);
            Icons.Draw(g, Icons.Kind.ArrowRight, new RectangleF(arrowX, y, Scaled(16), RowHeight),
                       Theme.Gray(0.45), Scaled(12f));

            DrawText(g, items[i].Right, Theme.RowTitleStrong, Theme.Live,
                     new Rectangle(arrowX + Scaled(22), y, Width - arrowX - Scaled(50), RowHeight),
                     TextFormatFlags.VerticalCenter | TextFormatFlags.EndEllipsis | TextFormatFlags.NoPrefix);

            Icons.Draw(g, Icons.Kind.Trash, TrashRect(i),
                       i == hovered ? Theme.Live : Theme.Gray(0.5), Scaled(14f));

            if (i == focused)
                DrawFocusRing(g, new RectangleF(0.5f, y + 0.5f, Width - 1, RowHeight - 1), Scaled(6f));
        }
    }
}
