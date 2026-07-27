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
        Height = 30;
    }

    public int PreferredHeightFor(int width) => Math.Max(24, Trailing?.Height ?? 0);

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
                 new Rectangle(0, 0, Width - (Trailing?.Width ?? 0) - 8, Height),
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
        Height = 18;
    }

    public int PreferredHeightFor(int width) => 18;

    protected override void OnPaint(PaintEventArgs e)
    {
        var g = e.Graphics;
        Theme.Smooth(g);
        using (var bg = new SolidBrush(BackColor)) g.FillRectangle(bg, ClientRectangle);
        Theme.DrawTracked(g, text, Theme.SectionLabel, Theme.Gray(0.45), new PointF(4, 2), 0.8f);
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

    public event Action<DictationHistory.Entry>? InsertRequested;
    public event Action<DictationHistory.Entry>? CopyRequested;
    public event Action<DictationHistory.Entry>? DeleteRequested;

    private const int Pad = 14;
    private const int TimeWidth = 48;
    private const int ActionSize = 22;
    private const int ActionGap = 8;
    private const int ActionsWidth = ActionSize * 3 + ActionGap * 2;

    public HistoryCard(DictationHistory.Entry entry)
    {
        this.entry = entry;
    }

    private int TextWidth(int width) =>
        Math.Max(60, width - Pad * 2 - TimeWidth - 14 - ActionsWidth - 14);

    public int PreferredHeightFor(int width)
        => Math.Max(24, MeasureText(entry.Text, Theme.RowTitle, TextWidth(width)).Height) + Pad * 2;

    private Rectangle ActionRect(int index) =>
        new(Width - Pad - ActionsWidth + index * (ActionSize + ActionGap), Pad, ActionSize, ActionSize);

    protected override void OnMouseMove(MouseEventArgs e)
    {
        var hit = -1;
        for (var i = 0; i < 3; i++)
            if (ActionRect(i).Contains(e.Location)) { hit = i; break; }
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
        if (ActionRect(0).Contains(e.Location)) InsertRequested?.Invoke(entry);
        else if (ActionRect(1).Contains(e.Location)) CopyRequested?.Invoke(entry);
        else if (ActionRect(2).Contains(e.Location)) DeleteRequested?.Invoke(entry);
        base.OnMouseClick(e);
    }

    protected override void OnPaint(PaintEventArgs e)
    {
        var g = e.Graphics;
        Theme.Smooth(g);
        using (var bg = new SolidBrush(Theme.Window)) g.FillRectangle(bg, ClientRectangle);
        Theme.DrawCard(g, new RectangleF(0, 0, Width, Height));

        DrawText(g, entry.Date.ToLocalTime().ToString("HH:mm"), Theme.MonoSmall, Theme.Gray(0.5),
                 new Rectangle(Pad, Pad, TimeWidth, 20), TextFormatFlags.NoPrefix);

        var textWidth = TextWidth(Width);
        DrawText(g, entry.Text, Theme.RowTitle, Theme.Gray(0.9),
                 new Rectangle(Pad + TimeWidth + 14, Pad, textWidth, Height - Pad * 2),
                 TextFormatFlags.WordBreak | TextFormatFlags.NoPrefix);

        Icons.Kind[] actions = { Icons.Kind.Insert, Icons.Kind.Copy, Icons.Kind.Trash };
        for (var i = 0; i < actions.Length; i++)
        {
            var r = ActionRect(i);
            var color = i == hoveredAction ? Theme.Live : Theme.Gray(0.5);
            Icons.Draw(g, actions[i], r, color, 14f);
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

    public int PreferredHeightFor(int width)
        => 60 + 44 + 12 + 24 + 6 + MeasureText(subtitle, Theme.Small, Math.Min(320, width)).Height;

    protected override void OnPaint(PaintEventArgs e)
    {
        var g = e.Graphics;
        Theme.Smooth(g);
        using (var bg = new SolidBrush(BackColor)) g.FillRectangle(bg, ClientRectangle);

        var y = 60;
        Icons.Draw(g, icon, new RectangleF(0, y, Width, 44), Theme.Gray(0.4), 40f);
        y += 44 + 12;
        DrawText(g, title, Theme.PageTitle, Theme.Gray(0.75), new Rectangle(0, y, Width, 24),
                 TextFormatFlags.HorizontalCenter | TextFormatFlags.NoPrefix);
        y += 24 + 6;
        var subWidth = Math.Min(320, Width);
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
        Height = 32;
    }

    public int PreferredHeightFor(int width) => 32;

    protected override void OnPaint(PaintEventArgs e)
    {
        var g = e.Graphics;
        Theme.Smooth(g);
        using (var bg = new SolidBrush(BackColor)) g.FillRectangle(bg, ClientRectangle);

        var x = 0;
        foreach (var (value, label) in metrics)
        {
            var valueWidth = TextRenderer.MeasureText(value, Theme.MetricSmall).Width;
            DrawText(g, value, Theme.MetricSmall, Theme.Live, new Rectangle(x, 0, valueWidth + 6, Height),
                     TextFormatFlags.VerticalCenter | TextFormatFlags.NoPrefix);
            x += valueWidth + 2;
            var labelWidth = TextRenderer.MeasureText(label, Theme.Small).Width;
            DrawText(g, label, Theme.Small, Theme.Gray(0.6), new Rectangle(x, 0, labelWidth + 8, Height),
                     TextFormatFlags.VerticalCenter | TextFormatFlags.NoPrefix);
            x += labelWidth + 20;
        }
    }
}

/// <summary>Aktivitäts-Kalender der letzten 8 Wochen (13-px-Kacheln, 3 px Abstand).</summary>
internal sealed class HeatmapView : ThemedControl, IAutoHeight
{
    private readonly StatsStore stats;
    private const int Cell = 13;
    private const int Gap = 3;
    private const int Weeks = 8;

    public HeatmapView(StatsStore stats)
    {
        this.stats = stats;
        Height = 7 * Cell + 6 * Gap;
    }

    public int PreferredHeightFor(int width) => 7 * Cell + 6 * Gap;

    protected override void OnPaint(PaintEventArgs e)
    {
        var g = e.Graphics;
        Theme.Smooth(g);
        using (var bg = new SolidBrush(BackColor)) g.FillRectangle(bg, ClientRectangle);

        var today = DateTime.Today;
        var start = today.AddDays(-(Weeks * 7 - 1));
        using var active = new SolidBrush(Theme.Live);
        using var inactive = new SolidBrush(Theme.Gray(0.18));

        for (var i = 0; i < Weeks * 7; i++)
        {
            var day = start.AddDays(i);
            var week = i / 7;
            var weekday = i % 7;
            var cell = new RectangleF(week * (Cell + Gap), weekday * (Cell + Gap), Cell, Cell);
            using var path = Theme.Rounded(cell, 3);
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

    public event Action<string>? Selected;
    /// <summary>Auswahl gesperrt (läuft gerade eine Aufnahme oder ein Wechsel).</summary>
    public Func<bool>? Locked { get; set; }

    public string? Title { get; init; }

    private const int LabelHeight = 22;
    private const int RowPadH = 15;
    private const int RowPadV = 12;
    private const int RadioWidth = 28;

    public ModelListPanel(ModelEntry[] entries, string selectedId)
    {
        this.entries = entries;
        this.selectedId = selectedId;
    }

    public void SetSelected(string id)
    {
        selectedId = id;
        Invalidate();
    }

    /// <summary>Ladezustand anzeigen (id = null beendet die Anzeige).</summary>
    public void SetLoading(string? id, double? value)
    {
        loadingId = id;
        progress = value;
        Invalidate();
    }

    private int TextWidth(int width) => Math.Max(60, width - RowPadH * 2 - RadioWidth - 110);

    private int RowHeight(ModelEntry entry, int width)
    {
        var h = MeasureText(entry.Name, Theme.RowTitle, TextWidth(width)).Height;
        h += 2 + MeasureText(Subtitle(entry), Theme.Help, TextWidth(width)).Height;
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
        if (Locked?.Invoke() == true || loadingId != null) return;
        for (var i = 0; i < entries.Length; i++)
        {
            if (!RowRect(i, Width).Contains(e.Location)) continue;
            if (entries[i].Id != selectedId) Selected?.Invoke(entries[i].Id);
            break;
        }
        base.OnMouseClick(e);
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
                              new PointF(4, 0), 0.8f);
            cardTop = LabelHeight;
        }
        Theme.DrawCard(g, new RectangleF(0, cardTop, Width, Height - cardTop));

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
            var circle = new RectangleF(RowPadH, row.Y + row.Height / 2f - 8, 16, 16);
            using (var pen = new Pen(selected ? Theme.Live : Theme.Gray(0.4), 1.6f))
                g.DrawEllipse(pen, circle);
            if (selected)
            {
                using var dot = new SolidBrush(Theme.Live);
                g.FillEllipse(dot, circle.X + 4, circle.Y + 4, 8, 8);
            }

            var textLeft = RowPadH + RadioWidth;
            var textWidth = TextWidth(Width);
            var nameSize = MeasureText(entry.Name, Theme.RowTitle, textWidth);
            var subSize = MeasureText(Subtitle(entry), Theme.Help, textWidth);
            var block = nameSize.Height + 2 + subSize.Height;
            var top = row.Y + (row.Height - block) / 2;

            DrawText(g, entry.Name, Theme.RowTitle, Theme.Gray(0.9),
                     new Rectangle(textLeft, top, textWidth, nameSize.Height), TextFormatFlags.NoPrefix);

            // Abzeichen rechts vom Namen
            var badgeX = textLeft + nameSize.Width + 7;
            if (entry.Recommended) badgeX += DrawBadge(g, Loc.T("Empfohlen"), Theme.Live, badgeX, top, nameSize.Height);
            if (entry.TooBig) DrawBadge(g, Loc.T("Viel RAM nötig"), Theme.Gray(0.55), badgeX, top, nameSize.Height);

            DrawText(g, Subtitle(entry), Theme.Help, Theme.Gray(0.55),
                     new Rectangle(textLeft, top + nameSize.Height + 2, textWidth, subSize.Height),
                     TextFormatFlags.NoPrefix);

            if (loadingId == entry.Id) DrawProgress(g, row);
        }
    }

    private static int DrawBadge(Graphics g, string text, Color color, int x, int y, int lineHeight)
    {
        var width = TextRenderer.MeasureText(text, Theme.Badge).Width + 12;
        var badge = new RectangleF(x, y + (lineHeight - 16) / 2f, width, 16);
        Theme.DrawCapsule(g, badge, Color.FromArgb(46, color));
        DrawText(g, text, Theme.Badge, color, Rectangle.Round(badge),
                 TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.NoPrefix);
        return width + 6;
    }

    /// <summary>Balken mit Prozent während des Downloads, sonst „lädt …".</summary>
    private void DrawProgress(Graphics g, Rectangle row)
    {
        var right = Width - RowPadH;
        var cy = row.Y + row.Height / 2f;

        if (progress is { } p && p > 0.0001 && p < 0.999)
        {
            var barWidth = 66;
            var bar = new RectangleF(right - barWidth - 38, cy - 3, barWidth, 6);
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
                     new Rectangle(right - 34, row.Y, 34, row.Height),
                     TextFormatFlags.VerticalCenter | TextFormatFlags.NoPrefix);
        }
        else
        {
            DrawText(g, Loc.T("lädt …"), Theme.Help, Theme.Live,
                     new Rectangle(right - 60, row.Y, 60, row.Height),
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

    public event Action<PersonalDictionary.Correction>? Deleted;

    private const int RowHeight = 26;

    public void SetItems(IEnumerable<PersonalDictionary.Correction> corrections)
    {
        items.Clear();
        items.AddRange(corrections);
        Invalidate();
    }

    public int PreferredHeightFor(int width) => items.Count * RowHeight;

    private Rectangle TrashRect(int index) => new(Width - 22, index * RowHeight + 4, 18, 18);

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
        for (var i = 0; i < items.Count; i++)
        {
            if (!TrashRect(i).Contains(e.Location)) continue;
            Deleted?.Invoke(items[i]);
            break;
        }
        base.OnMouseClick(e);
    }

    protected override void OnPaint(PaintEventArgs e)
    {
        var g = e.Graphics;
        Theme.Smooth(g);
        using (var bg = new SolidBrush(BackColor)) g.FillRectangle(bg, ClientRectangle);

        for (var i = 0; i < items.Count; i++)
        {
            var y = i * RowHeight;
            var wrongWidth = TextRenderer.MeasureText(items[i].Wrong, Theme.RowTitle).Width;
            DrawText(g, items[i].Wrong, Theme.RowTitle, Theme.Gray(0.55),
                     new Rectangle(0, y, wrongWidth + 6, RowHeight),
                     TextFormatFlags.VerticalCenter | TextFormatFlags.NoPrefix);
            // Durchgestrichen (Mac: .strikethrough())
            using (var pen = new Pen(Theme.Gray(0.55)))
                g.DrawLine(pen, 1, y + RowHeight / 2f, wrongWidth, y + RowHeight / 2f);

            var arrowX = wrongWidth + 8;
            Icons.Draw(g, Icons.Kind.ArrowRight, new RectangleF(arrowX, y, 16, RowHeight), Theme.Gray(0.45), 12f);

            DrawText(g, items[i].Right, Theme.RowTitleStrong, Theme.Live,
                     new Rectangle(arrowX + 22, y, Width - arrowX - 50, RowHeight),
                     TextFormatFlags.VerticalCenter | TextFormatFlags.EndEllipsis | TextFormatFlags.NoPrefix);

            Icons.Draw(g, Icons.Kind.Trash, TrashRect(i),
                       i == hovered ? Theme.Live : Theme.Gray(0.5), 14f);
        }
    }
}
