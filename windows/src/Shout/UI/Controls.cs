using System.Drawing.Drawing2D;

namespace Shout.UI;

// Die Bausteine aus ConsoleUI.swift als eigengezeichnete WinForms-Controls:
// flache Karten, dezente Ränder, Akzent nur über die Signalfarbe. WinForms
// zeichnet nichts davon von Haus aus — jedes Element malt sich selbst.

/// <summary>Elemente, deren Höhe sich aus der verfügbaren Breite ergibt
/// (umbrechende Texte, Karten mit variabel hohen Zeilen).</summary>
internal interface IAutoHeight
{
    int PreferredHeightFor(int width);
}

/// <summary>Basis: doppelt gepuffert, eigengezeichnet, kein Fokus-Rahmen.</summary>
internal abstract class ThemedControl : Control
{
    protected ThemedControl()
    {
        SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.UserPaint
                 | ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw, true);
        SetStyle(ControlStyles.Selectable, false);
        BackColor = Theme.Window;
        ForeColor = Theme.Ink;
    }

    /// <summary>Text scharf über GDI zeichnen (wie native Windows-Oberflächen).</summary>
    protected static void DrawText(Graphics g, string text, Font font, Color color, Rectangle bounds,
                                   TextFormatFlags flags = TextFormatFlags.Left | TextFormatFlags.NoPrefix)
    {
        if (string.IsNullOrEmpty(text)) return;
        TextRenderer.DrawText(g, text, font, bounds, color, flags);
    }

    protected static Size MeasureText(string text, Font font, int maxWidth,
                                      TextFormatFlags flags = TextFormatFlags.WordBreak | TextFormatFlags.NoPrefix)
        => TextRenderer.MeasureText(text, font, new Size(maxWidth, int.MaxValue), flags);
}

// MARK: - Scroll-Bereich

/// <summary>
/// Scrollbereich mit dezentem Overlay-Balken (statt der breiten hellen
/// Windows-Standard-Leiste) — kommt der Optik der Mac-App näher.
/// Inhalte werden in <see cref="Content"/> gelegt; dessen Höhe bestimmt den Lauf.
/// </summary>
internal sealed class ScrollHost : ThemedControl
{
    public Panel Content { get; } = new() { BackColor = Theme.Window, Location = new Point(0, 0) };

    private int offset;
    private const int ThumbWidth = 6;
    private const int ThumbInset = 3;

    public ScrollHost()
    {
        Controls.Add(Content);
    }

    /// <summary>Streifen rechts, den der Inhalt frei lässt, damit der Balken sichtbar
    /// bleibt (Kind-Controls würden ihn sonst überdecken).</summary>
    private const int ScrollGutter = 12;

    private int MaxOffset => Math.Max(0, Content.Height - Height);

    public void ScrollBy(int delta)
    {
        var next = Math.Clamp(offset + delta, 0, MaxOffset);
        if (next == offset) return;
        offset = next;
        Content.Top = -offset;
        Invalidate();
    }

    public void ScrollToTop()
    {
        offset = 0;
        Content.Top = 0;
        Invalidate();
    }

    protected override void OnMouseWheel(MouseEventArgs e)
    {
        ScrollBy(-e.Delta * 5 / 6);   // ~90 px je Rasterschritt
        base.OnMouseWheel(e);
    }

    protected override void OnLayout(LayoutEventArgs e)
    {
        base.OnLayout(e);
        Content.Width = Math.Max(100, Width - ScrollGutter);
        offset = Math.Clamp(offset, 0, MaxOffset);
        Content.Top = -offset;
    }

    protected override void OnPaint(PaintEventArgs e)
    {
        var g = e.Graphics;
        Theme.Smooth(g);
        using (var bg = new SolidBrush(Theme.Window)) g.FillRectangle(bg, ClientRectangle);

        if (MaxOffset <= 0 || Height <= 0) return;

        // Overlay-Balken rechts: Länge im Verhältnis zum Inhalt.
        var trackHeight = Height - ThumbInset * 2;
        var thumbHeight = Math.Max(28, (int)((float)Height / Content.Height * trackHeight));
        var travel = trackHeight - thumbHeight;
        var y = ThumbInset + (MaxOffset > 0 ? (int)((float)offset / MaxOffset * travel) : 0);
        var thumb = new RectangleF(Width - ThumbWidth - ThumbInset, y, ThumbWidth, thumbHeight);
        using var brush = new SolidBrush(Theme.White(0.16));
        using var path = Theme.Capsule(thumb);
        g.FillPath(brush, path);
    }
}

// MARK: - Karte mit Zeilen

/// <summary>Eine Zeile in einer <see cref="ConsolePanel"/>.</summary>
internal sealed class PanelRow
{
    public string Title = "";
    public string? Help;
    /// <summary>Bedienelement rechts (Schalter, Knopf, Dropdown …).</summary>
    public Control? Trailing;
    /// <summary>Führendes Symbol (Listen wie „In der Datei enthalten").</summary>
    public Icons.Kind? Icon { get; init; }
    /// <summary>Zeile nur anzeigen, wenn true (z. B. „Pause bis Stopp" nur bei Auto-Stopp).</summary>
    public Func<bool>? VisibleWhen;

    public bool IsVisible => VisibleWhen?.Invoke() ?? true;
}

/// <summary>
/// Flache Karte, die zusammengehörige Einstellungen bündelt — Abschnitts-Label in
/// Großbuchstaben darüber, darunter die Zeilen mit Trennlinien (ConsolePanel +
/// FieldRow + ConsoleDivider aus der Mac-App in einem Control).
///
/// Die Karte zeichnet Titel, Hilfetexte und Linien selbst; nur die Bedienelemente
/// sind echte Kind-Controls und werden rechts positioniert.
/// </summary>
internal sealed class ConsolePanel : ThemedControl, IAutoHeight
{
    public string? Title { get; init; }
    private readonly List<PanelRow> rows = new();

    private const int LabelHeight = 22;     // Abschnitts-Label + Abstand (9 px Lücke wie am Mac)
    private const int RowPaddingH = 15;
    private const int RowPaddingV = 12;
    private const int IconWidth = 22;
    private const int TrailingGap = 14;

    public void Add(PanelRow row)
    {
        rows.Add(row);
        if (row.Trailing != null)
        {
            row.Trailing.BackColor = Theme.Card;
            Controls.Add(row.Trailing);
        }
    }

    public void Add(string title, string? help, Control? trailing, Func<bool>? visibleWhen = null)
        => Add(new PanelRow { Title = title, Help = help, Trailing = trailing, VisibleWhen = visibleWhen });

    /// <summary>Höhe neu berechnen (nach Sichtbarkeits-Änderungen aufrufen).</summary>
    public void Relayout()
    {
        Height = PreferredHeightFor(Width);
        PerformLayout();
        Invalidate();
    }

    private int TextWidth(PanelRow row, int width)
    {
        var trailingWidth = row.Trailing?.Width ?? 0;
        var iconWidth = row.Icon != null ? IconWidth + 12 : 0;
        return Math.Max(60, width - RowPaddingH * 2 - iconWidth
                            - (trailingWidth > 0 ? trailingWidth + TrailingGap : 0));
    }

    private int RowHeight(PanelRow row, int width)
    {
        var textWidth = TextWidth(row, width);
        var h = MeasureText(row.Title, Theme.RowTitle, textWidth).Height;
        if (!string.IsNullOrEmpty(row.Help))
            h += 3 + MeasureText(row.Help!, Theme.Help, textWidth).Height;
        var content = Math.Max(h, row.Trailing?.Height ?? 0);
        return content + RowPaddingV * 2;
    }

    public int PreferredHeightFor(int width)
    {
        var top = Title != null ? LabelHeight : 0;
        var sum = 0;
        foreach (var row in rows)
            if (row.IsVisible) sum += RowHeight(row, width);
        return top + sum;
    }

    protected override void OnLayout(LayoutEventArgs e)
    {
        base.OnLayout(e);
        var y = Title != null ? LabelHeight : 0;
        foreach (var row in rows)
        {
            if (row.Trailing == null) continue;
            if (!row.IsVisible)
            {
                row.Trailing.Visible = false;
                continue;
            }
            var h = RowHeight(row, Width);
            row.Trailing.Visible = true;
            row.Trailing.Location = new Point(
                Width - RowPaddingH - row.Trailing.Width,
                y + (h - row.Trailing.Height) / 2);
            y += h;
        }
    }

    protected override void OnPaint(PaintEventArgs e)
    {
        var g = e.Graphics;
        Theme.Smooth(g);
        using (var bg = new SolidBrush(Theme.Window)) g.FillRectangle(bg, ClientRectangle);

        var cardTop = 0;
        if (Title != null)
        {
            // Abschnitts-Label: Großbuchstaben, gesperrt, gedämpft — wie am Mac.
            Theme.DrawTracked(g, Title.ToUpperInvariant(), Theme.SectionLabel, Theme.InkFaint,
                              new PointF(4, 0), 0.8f);
            cardTop = LabelHeight;
        }

        var cardHeight = Height - cardTop;
        if (cardHeight <= 0) return;
        Theme.DrawCard(g, new RectangleF(0, cardTop, Width, cardHeight));

        var y = cardTop;
        var first = true;
        foreach (var row in rows)
        {
            if (!row.IsVisible) continue;
            var h = RowHeight(row, Width);

            if (!first)
            {
                using var pen = new Pen(Theme.Divider);
                g.DrawLine(pen, RowPaddingH, y + 0.5f, Width - RowPaddingH, y + 0.5f);
            }
            first = false;

            var textLeft = RowPaddingH;
            if (row.Icon is { } icon)
            {
                Icons.Draw(g, icon, new RectangleF(RowPaddingH, y + h / 2f - 11, IconWidth, 22), Theme.Live, 15f);
                textLeft += IconWidth + 12;
            }

            var textWidth = TextWidth(row, Width);
            var titleSize = MeasureText(row.Title, Theme.RowTitle, textWidth);
            var helpSize = string.IsNullOrEmpty(row.Help)
                ? Size.Empty
                : MeasureText(row.Help!, Theme.Help, textWidth);
            var blockHeight = titleSize.Height + (helpSize.Height > 0 ? 3 + helpSize.Height : 0);
            var textTop = y + (h - blockHeight) / 2;

            DrawText(g, row.Title, Theme.RowTitle, Theme.Ink,
                     new Rectangle(textLeft, textTop, textWidth, titleSize.Height),
                     TextFormatFlags.WordBreak | TextFormatFlags.NoPrefix);
            if (helpSize.Height > 0)
                DrawText(g, row.Help!, Theme.Help, Theme.InkMuted,
                         new Rectangle(textLeft, textTop + titleSize.Height + 3, textWidth, helpSize.Height),
                         TextFormatFlags.WordBreak | TextFormatFlags.NoPrefix);

            y += h;
        }
    }
}

/// <summary>
/// Karte mit gestapeltem, freiem Inhalt (Mac: `ConsolePanel { VStack … }.padding(16)`)
/// — für Wörterbuch, Sync, Unterstützen und die Hardware-Karte. Die Karte stapelt
/// ihre Kind-Controls senkrecht und berechnet daraus ihre Höhe.
/// </summary>
internal sealed class ConsoleBox : ThemedControl, IAutoHeight
{
    public string? Title { get; init; }
    public int Inset { get; init; } = 16;
    /// <summary>Zusätzliche Zeichnung im Innenbereich (z. B. die Hardware-Kopfzeile).</summary>
    public Action<Graphics, Rectangle>? PaintContent { get; set; }
    /// <summary>Freier Platz oben im Innenbereich, den <see cref="PaintContent"/> nutzt.</summary>
    public int ContentHeaderHeight { get; init; }

    private const int LabelHeight = 22;
    private readonly List<(Control Control, int SpacingBefore)> stack = new();

    public int TopOffset => Title != null ? LabelHeight : 0;

    /// <summary>Element in die Karte stapeln (Standardabstand 12 px wie am Mac).</summary>
    public T Add<T>(T control, int spacingBefore = 12) where T : Control
    {
        control.BackColor = Theme.Card;
        stack.Add((control, stack.Count == 0 ? 0 : spacingBefore));
        Controls.Add(control);
        return control;
    }

    private int InnerWidth(int width) => Math.Max(40, width - Inset * 2);

    public int PreferredHeightFor(int width)
    {
        var inner = InnerWidth(width);
        var content = ContentHeaderHeight;
        foreach (var (control, spacing) in stack)
        {
            if (!control.Visible) continue;
            content += spacing;
            content += control is IAutoHeight auto ? auto.PreferredHeightFor(inner) : control.Height;
        }
        return TopOffset + Inset * 2 + content;
    }

    protected override void OnLayout(LayoutEventArgs e)
    {
        base.OnLayout(e);
        if (Width <= 0) return;
        var inner = InnerWidth(Width);
        var y = TopOffset + Inset + ContentHeaderHeight;
        foreach (var (control, spacing) in stack)
        {
            if (!control.Visible) continue;
            y += spacing;
            control.Left = Inset;
            // Cluster und Chips bestimmen ihre Breite selbst; alles andere füllt die Karte.
            if (control is IAutoHeight auto)
            {
                if (control is not Cluster) control.Width = inner;
                control.Height = auto.PreferredHeightFor(control is Cluster ? control.Width : inner);
            }
            control.Top = y;
            y += control.Height;
        }
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
        var cardHeight = Height - cardTop;
        if (cardHeight <= 0) return;
        Theme.DrawCard(g, new RectangleF(0, cardTop, Width, cardHeight));
        PaintContent?.Invoke(g, new Rectangle(Inset, cardTop + Inset,
                                              InnerWidth(Width), Math.Max(0, ContentHeaderHeight)));
    }
}

/// <summary>
/// Mehrere Bedienelemente nebeneinander (Mac: `HStack(spacing: …)`) — etwa
/// Schieberegler + Wertanzeige oder Eingabefeld + Knopf.
/// </summary>
internal sealed class Cluster : ThemedControl, IAutoHeight
{
    private readonly Control[] items;
    private readonly int gap;
    /// <summary>Letztes Element auf die Restbreite strecken (Eingabefeld + Knopf).</summary>
    public bool StretchFirst { get; init; }

    public Cluster(Control[] items, int gap = 10)
    {
        this.items = items;
        this.gap = gap;
        foreach (var item in items) Controls.Add(item);
        Height = items.Length > 0 ? items.Max(i => i.Height) : 0;
        Width = items.Sum(i => i.Width) + Math.Max(0, items.Length - 1) * gap;
    }

    public int PreferredHeightFor(int width) => items.Length > 0 ? items.Max(i => i.Height) : 0;

    /// <summary>Hintergrundfarbe an die Kinder weitergeben — sonst blitzt an ihren
    /// abgerundeten Ecken die Fensterfarbe statt der Kartenfarbe durch.</summary>
    protected override void OnBackColorChanged(EventArgs e)
    {
        base.OnBackColorChanged(e);
        foreach (var item in items) item.BackColor = BackColor;
    }

    protected override void OnLayout(LayoutEventArgs e)
    {
        base.OnLayout(e);
        if (items.Length == 0) return;

        if (StretchFirst && Width > 0)
        {
            var others = items.Skip(1).Sum(i => i.Width) + (items.Length - 1) * gap;
            items[0].Width = Math.Max(60, Width - others);
        }

        var x = 0;
        foreach (var item in items)
        {
            item.Location = new Point(x, (Height - item.Height) / 2);
            x += item.Width + gap;
        }
    }

    protected override void OnPaint(PaintEventArgs e)
    {
        using var bg = new SolidBrush(BackColor);
        e.Graphics.FillRectangle(bg, ClientRectangle);
    }
}

/// <summary>Einzelnes Symbol als eigenständiges Element (z. B. „→" zwischen Feldern).</summary>
internal sealed class IconView : ThemedControl, IAutoHeight
{
    private readonly Icons.Kind kind;
    private readonly Color color;
    private readonly float glyphSize;

    public IconView(Icons.Kind kind, Color color, float glyphSize, int box)
    {
        this.kind = kind;
        this.color = color;
        this.glyphSize = glyphSize;
        Size = new Size(box, box);
    }

    public int PreferredHeightFor(int width) => Height;

    protected override void OnPaint(PaintEventArgs e)
    {
        var g = e.Graphics;
        Theme.Smooth(g);
        using (var bg = new SolidBrush(BackColor)) g.FillRectangle(bg, ClientRectangle);
        Icons.Draw(g, kind, ClientRectangle, color, glyphSize);
    }
}

// MARK: - Schalter

/// <summary>Schiebeschalter wie am Mac: Bahn in der Signalfarbe wenn an, sonst vertieft.</summary>
internal sealed class ConsoleToggle : ThemedControl
{
    private bool on;
    private float animation;   // 0 = aus, 1 = an
    private readonly System.Windows.Forms.Timer timer = new() { Interval = 15 };

    public event Action<bool>? Changed;

    public ConsoleToggle(bool initial)
    {
        on = initial;
        animation = initial ? 1 : 0;
        Size = new Size(40, 22);
        Cursor = Cursors.Hand;
        timer.Tick += (_, _) =>
        {
            var target = on ? 1f : 0f;
            animation += (target - animation) * 0.35f;
            if (Math.Abs(target - animation) < 0.01f)
            {
                animation = target;
                timer.Stop();
            }
            Invalidate();
        };
    }

    public bool Checked
    {
        get => on;
        set
        {
            if (on == value) return;
            on = value;
            timer.Start();
        }
    }

    protected override void OnMouseClick(MouseEventArgs e)
    {
        Checked = !on;
        Changed?.Invoke(on);
        base.OnMouseClick(e);
    }

    protected override void OnPaint(PaintEventArgs e)
    {
        var g = e.Graphics;
        Theme.Smooth(g);
        using (var bg = new SolidBrush(BackColor)) g.FillRectangle(bg, ClientRectangle);

        var track = new RectangleF(0.5f, 0.5f, Width - 1, Height - 1);
        var trackColor = Blend(Theme.Track, Theme.Live, animation);
        using (var fill = new SolidBrush(trackColor))
        using (var path = Theme.Capsule(track))
        {
            g.FillPath(fill, path);
            if (animation < 0.5f)
            {
                using var pen = new Pen(Theme.White(0.08));
                g.DrawPath(pen, path);
            }
        }

        var knobSize = Height - 6;
        var travel = Width - knobSize - 6;
        var knobX = 3 + travel * animation;
        using var knob = new SolidBrush(Blend(Theme.Gray(0.62), Color.White, animation));
        g.FillEllipse(knob, knobX, 3, knobSize, knobSize);
    }

    private static Color Blend(Color a, Color b, float t)
    {
        t = Math.Clamp(t, 0, 1);
        return Color.FromArgb(
            (int)(a.R + (b.R - a.R) * t),
            (int)(a.G + (b.G - a.G) * t),
            (int)(a.B + (b.B - a.B) * t));
    }

    protected override void Dispose(bool disposing)
    {
        if (disposing) timer.Dispose();
        base.Dispose(disposing);
    }
}

// MARK: - Segment-Umschalter

/// <summary>Flacher Segment-Umschalter (aktives Feld dezent heller, kein 3D).</summary>
internal sealed class ConsoleSegmented : ThemedControl
{
    private readonly (string Key, string Label)[] options;
    private int selected;

    public event Action<string>? Changed;

    public ConsoleSegmented((string Key, string Label)[] options, string initial)
    {
        this.options = options;
        selected = Math.Max(0, Array.FindIndex(options, o => o.Key == initial));
        Cursor = Cursors.Hand;
        Height = 30;
        Width = Measure();
    }

    public string SelectedKey => options[selected].Key;

    private int Measure()
    {
        var total = 4;   // 2 px Polsterung je Seite
        foreach (var (_, label) in options)
            total += SegmentWidth(label);
        return total;
    }

    private static int SegmentWidth(string label)
        => TextRenderer.MeasureText(label, Theme.Body).Width + 26;

    private RectangleF SegmentRect(int index)
    {
        var x = 2f;
        for (var i = 0; i < index; i++)
            x += SegmentWidth(options[i].Label);
        return new RectangleF(x, 2, SegmentWidth(options[index].Label), Height - 4);
    }

    protected override void OnMouseClick(MouseEventArgs e)
    {
        for (var i = 0; i < options.Length; i++)
        {
            if (!SegmentRect(i).Contains(e.Location)) continue;
            if (i != selected)
            {
                selected = i;
                Invalidate();
                Changed?.Invoke(options[i].Key);
            }
            break;
        }
        base.OnMouseClick(e);
    }

    protected override void OnPaint(PaintEventArgs e)
    {
        var g = e.Graphics;
        Theme.Smooth(g);
        using (var bg = new SolidBrush(BackColor)) g.FillRectangle(bg, ClientRectangle);

        using (var track = new SolidBrush(Theme.Track))
        using (var path = Theme.Rounded(new RectangleF(0, 0, Width, Height), 8))
            g.FillPath(track, path);

        for (var i = 0; i < options.Length; i++)
        {
            var r = SegmentRect(i);
            var active = i == selected;
            if (active)
            {
                using var fill = new SolidBrush(Theme.SegActive);
                using var path = Theme.Rounded(r, 6);
                g.FillPath(fill, path);
            }
            DrawText(g, options[i].Label, Theme.Body, active ? Theme.Ink : Theme.InkMuted,
                     Rectangle.Round(r),
                     TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.NoPrefix);
        }
    }
}

// MARK: - Knopf

/// <summary>Flacher Knopf; <see cref="Primary"/> füllt ihn mit der Signalfarbe.</summary>
internal sealed class ConsoleButton : ThemedControl
{
    public bool Primary { get; }
    public Icons.Kind? Icon { get; }
    private bool hover, pressed;
    private bool enabledLook = true;

    public event Action? Click2;

    public ConsoleButton(string text, bool primary = false, Icons.Kind? icon = null, int? width = null)
    {
        Text = text;
        Primary = primary;
        Icon = icon;
        Cursor = Cursors.Hand;
        Height = primary ? 32 : 28;
        var textWidth = TextRenderer.MeasureText(text, primary ? Theme.RowTitleStrong : Theme.ButtonText).Width;
        Width = width ?? textWidth + (primary ? 32 : 26) + (icon != null ? 22 : 0);
    }

    /// <summary>Optische und funktionale Sperre (WinForms' Enabled graut Kind-Controls
    /// nicht passend ein, deshalb eigene Darstellung).</summary>
    public void SetEnabled(bool value)
    {
        if (enabledLook == value) return;
        enabledLook = value;
        Cursor = value ? Cursors.Hand : Cursors.Default;
        Invalidate();
    }

    public bool IsEnabled => enabledLook;

    protected override void OnMouseEnter(EventArgs e) { hover = true; Invalidate(); base.OnMouseEnter(e); }
    protected override void OnMouseLeave(EventArgs e) { hover = false; pressed = false; Invalidate(); base.OnMouseLeave(e); }
    protected override void OnMouseDown(MouseEventArgs e) { pressed = true; Invalidate(); base.OnMouseDown(e); }
    protected override void OnMouseUp(MouseEventArgs e) { pressed = false; Invalidate(); base.OnMouseUp(e); }

    protected override void OnMouseClick(MouseEventArgs e)
    {
        if (enabledLook) Click2?.Invoke();
        base.OnMouseClick(e);
    }

    protected override void OnPaint(PaintEventArgs e)
    {
        var g = e.Graphics;
        Theme.Smooth(g);
        using (var bg = new SolidBrush(BackColor)) g.FillRectangle(bg, ClientRectangle);

        var r = new RectangleF(0.5f, 0.5f, Width - 1, Height - 1);
        var fillColor = Primary ? Theme.Live : Theme.Button;
        if (!enabledLook) fillColor = Color.FromArgb(Primary ? 110 : 150, fillColor);
        else if (pressed) fillColor = Color.FromArgb(210, fillColor);
        else if (hover && !Primary) fillColor = Theme.Gray(0.27);

        using (var fill = new SolidBrush(fillColor))
        using (var path = Theme.Rounded(r, Primary ? 8 : 7))
        {
            g.FillPath(fill, path);
            if (!Primary)
            {
                using var pen = new Pen(Theme.White(0.08));
                g.DrawPath(pen, path);
            }
        }

        var textColor = Primary ? Color.White : (enabledLook ? Theme.Ink : Theme.InkFaint);
        var textArea = ClientRectangle;
        if (Icon is { } icon)
        {
            Icons.Draw(g, icon, new RectangleF(10, 0, 16, Height), textColor, 13f);
            textArea = new Rectangle(24, 0, Width - 30, Height);
            DrawText(g, Text, Primary ? Theme.RowTitleStrong : Theme.ButtonText, textColor, textArea,
                     TextFormatFlags.VerticalCenter | TextFormatFlags.NoPrefix);
        }
        else
        {
            DrawText(g, Text, Primary ? Theme.RowTitleStrong : Theme.ButtonText, textColor, textArea,
                     TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.NoPrefix);
        }
    }
}

// MARK: - Tastenkappe

/// <summary>Monospace-Tastenkappe (Hotkey-Anzeige, Zahlenwerte).</summary>
internal sealed class Keycap : ThemedControl
{
    public Keycap(string text)
    {
        Text = text;
        Height = 26;
        UpdateWidth();
    }

    public void SetText(string text)
    {
        Text = text;
        UpdateWidth();
        Invalidate();
    }

    private void UpdateWidth()
        => Width = Math.Max(46, TextRenderer.MeasureText(Text, Theme.Keycap).Width + 20);

    protected override void OnPaint(PaintEventArgs e)
    {
        var g = e.Graphics;
        Theme.Smooth(g);
        using (var bg = new SolidBrush(BackColor)) g.FillRectangle(bg, ClientRectangle);

        var r = new RectangleF(0.5f, 0.5f, Width - 1, Height - 1);
        using (var fill = new SolidBrush(Theme.Track))
        using (var path = Theme.Rounded(r, 6))
        using (var pen = new Pen(Theme.White(0.06)))
        {
            g.FillPath(fill, path);
            g.DrawPath(pen, path);
        }
        DrawText(g, Text, Theme.Keycap, Theme.Ink, ClientRectangle,
                 TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.NoPrefix);
    }
}

// MARK: - Dropdown

/// <summary>Auswahlfeld im Mac-Look; öffnet ein dunkel gestaltetes Menü.</summary>
internal sealed class ConsoleDropdown : ThemedControl
{
    private readonly List<(string Key, string Label)> items = new();
    private string selectedKey = "";
    private bool hover;

    public event Action<string>? Changed;

    public ConsoleDropdown(int width)
    {
        Width = width;
        Height = 30;
        Cursor = Cursors.Hand;
    }

    public void SetItems(IEnumerable<(string Key, string Label)> newItems, string selected)
    {
        items.Clear();
        items.AddRange(newItems);
        selectedKey = selected;
        Invalidate();
    }

    public string SelectedKey => selectedKey;

    private string SelectedLabel =>
        items.FirstOrDefault(i => i.Key == selectedKey).Label ?? items.FirstOrDefault().Label ?? "";

    protected override void OnMouseEnter(EventArgs e) { hover = true; Invalidate(); base.OnMouseEnter(e); }
    protected override void OnMouseLeave(EventArgs e) { hover = false; Invalidate(); base.OnMouseLeave(e); }

    protected override void OnMouseClick(MouseEventArgs e)
    {
        var menu = new ContextMenuStrip
        {
            Renderer = new DarkMenuRenderer(),
            BackColor = Theme.Card,
            ForeColor = Theme.Ink,
            ShowImageMargin = false,
            Font = Theme.Body,
        };
        foreach (var (key, label) in items)
        {
            var item = new ToolStripMenuItem(label)
            {
                ForeColor = key == selectedKey ? Theme.Live : Theme.Ink,
                BackColor = Theme.Card,
            };
            var captured = key;
            item.Click += (_, _) =>
            {
                if (captured == selectedKey) return;
                selectedKey = captured;
                Invalidate();
                Changed?.Invoke(captured);
            };
            menu.Items.Add(item);
        }
        // Nach dem Schließen freigeben — bei jedem Klick ein neues Menü zu behalten
        // wäre ein Leck.
        menu.Closed += (_, _) => menu.BeginInvoke(() => menu.Dispose());
        menu.Show(this, new Point(0, Height + 2));
        base.OnMouseClick(e);
    }

    protected override void OnPaint(PaintEventArgs e)
    {
        var g = e.Graphics;
        Theme.Smooth(g);
        using (var bg = new SolidBrush(BackColor)) g.FillRectangle(bg, ClientRectangle);

        var r = new RectangleF(0.5f, 0.5f, Width - 1, Height - 1);
        using (var fill = new SolidBrush(hover ? Theme.Gray(0.15) : Theme.Track))
        using (var path = Theme.Rounded(r, 8))
        using (var pen = new Pen(Theme.CardBorder))
        {
            g.FillPath(fill, path);
            g.DrawPath(pen, path);
        }

        DrawText(g, SelectedLabel, Theme.Body, Theme.Ink,
                 new Rectangle(10, 0, Width - 32, Height),
                 TextFormatFlags.VerticalCenter | TextFormatFlags.EndEllipsis | TextFormatFlags.NoPrefix);

        // Chevron nach unten
        using var chevron = new Pen(Theme.InkMuted, 1.6f) { StartCap = LineCap.Round, EndCap = LineCap.Round };
        var cx = Width - 15f;
        var cy = Height / 2f;
        g.DrawLines(chevron, new[]
        {
            new PointF(cx - 4, cy - 2),
            new PointF(cx, cy + 2.5f),
            new PointF(cx + 4, cy - 2),
        });
    }
}

/// <summary>Dunkles Menü-Aussehen (Windows-Standardmenüs sind hell).</summary>
internal sealed class DarkMenuRenderer : ToolStripProfessionalRenderer
{
    public DarkMenuRenderer() : base(new DarkColors()) { }

    protected override void OnRenderItemText(ToolStripItemTextRenderEventArgs e)
    {
        e.TextColor = e.Item?.Selected == true ? Color.White : e.Item?.ForeColor ?? Theme.Ink;
        base.OnRenderItemText(e);
    }

    private sealed class DarkColors : ProfessionalColorTable
    {
        public override Color MenuItemSelected => Theme.LiveAlpha(0.85);
        public override Color MenuItemSelectedGradientBegin => Theme.LiveAlpha(0.85);
        public override Color MenuItemSelectedGradientEnd => Theme.LiveAlpha(0.85);
        public override Color MenuItemBorder => Theme.LiveAlpha(0.85);
        public override Color MenuBorder => Color.FromArgb(70, 70, 76);
        public override Color ToolStripDropDownBackground => Theme.Card;
        public override Color ImageMarginGradientBegin => Theme.Card;
        public override Color ImageMarginGradientMiddle => Theme.Card;
        public override Color ImageMarginGradientEnd => Theme.Card;
        public override Color SeparatorDark => Color.FromArgb(60, 60, 66);
        public override Color SeparatorLight => Color.FromArgb(60, 60, 66);
    }
}

// MARK: - Eingabefeld

/// <summary>Dunkles, abgerundetes Eingabefeld mit Platzhalter.</summary>
internal sealed class ConsoleTextField : ThemedControl
{
    public TextBox Inner { get; }

    public ConsoleTextField(string placeholder, int width)
    {
        // Erst das Eingabefeld anlegen: Size setzt ein Layout in Gang, und das
        // greift bereits auf Inner zu.
        Inner = new TextBox
        {
            BorderStyle = BorderStyle.None,
            BackColor = Theme.Track,
            ForeColor = Theme.Ink,
            Font = Theme.Body,
            PlaceholderText = placeholder,
            Location = new Point(10, 8),
            Width = Math.Max(20, width - 20),
        };
        Controls.Add(Inner);
        Size = new Size(width, 32);
    }

    protected override void OnLayout(LayoutEventArgs e)
    {
        base.OnLayout(e);
        if (Inner == null) return;
        Inner.Width = Math.Max(20, Width - 20);
        Inner.Location = new Point(10, (Height - Inner.Height) / 2);
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

// MARK: - Schieberegler

/// <summary>Schieberegler in der Signalfarbe (Pause bis Stopp).</summary>
internal sealed class ConsoleSlider : ThemedControl
{
    private readonly double min, max, step;
    private double value;
    private bool dragging;

    public event Action<double>? Changed;

    public ConsoleSlider(double min, double max, double step, double initial, int width)
    {
        this.min = min;
        this.max = max;
        this.step = step;
        value = Math.Clamp(initial, min, max);
        Width = width;
        Height = 24;
        Cursor = Cursors.Hand;
    }

    public double Value => value;

    private float Fraction => (float)((value - min) / (max - min));

    protected override void OnMouseDown(MouseEventArgs e) { dragging = true; SetFromX(e.X); base.OnMouseDown(e); }
    protected override void OnMouseUp(MouseEventArgs e) { dragging = false; base.OnMouseUp(e); }
    protected override void OnMouseMove(MouseEventArgs e)
    {
        if (dragging) SetFromX(e.X);
        base.OnMouseMove(e);
    }

    private void SetFromX(int x)
    {
        var knob = 14f;
        var travel = Width - knob;
        var fraction = Math.Clamp((x - knob / 2) / travel, 0, 1);
        var raw = min + fraction * (max - min);
        var snapped = Math.Round(raw / step) * step;
        var next = Math.Clamp(snapped, min, max);
        if (Math.Abs(next - value) < step / 2) return;
        value = next;
        Invalidate();
        Changed?.Invoke(value);
    }

    protected override void OnPaint(PaintEventArgs e)
    {
        var g = e.Graphics;
        Theme.Smooth(g);
        using (var bg = new SolidBrush(BackColor)) g.FillRectangle(bg, ClientRectangle);

        const float knob = 14f;
        var cy = Height / 2f;
        var trackRect = new RectangleF(knob / 2, cy - 2, Width - knob, 4);
        using (var track = new SolidBrush(Theme.Track))
        using (var path = Theme.Capsule(trackRect))
            g.FillPath(track, path);

        var filled = new RectangleF(trackRect.X, trackRect.Y, trackRect.Width * Fraction, trackRect.Height);
        if (filled.Width > 1)
        {
            using var fill = new SolidBrush(Theme.Live);
            using var path = Theme.Capsule(filled);
            g.FillPath(fill, path);
        }

        var knobX = trackRect.X + trackRect.Width * Fraction - knob / 2;
        using var knobBrush = new SolidBrush(Color.White);
        g.FillEllipse(knobBrush, knobX, cy - knob / 2, knob, knob);
    }
}

// MARK: - Chips (Wörterbuch-Begriffe)

/// <summary>
/// Begriffe als umbrechende Kapsel-„Chips" mit ✕ zum Löschen (Mac: FlowChips).
/// Layout und Klick-Zonen berechnet das Control selbst — bei hundert Begriffen
/// wären hundert Kind-Controls unnötig teuer.
/// </summary>
internal sealed class ChipFlow : ThemedControl
{
    private readonly List<string> terms = new();
    private readonly List<(RectangleF Chip, RectangleF Delete, string Term)> layout = new();
    private string? hovered;

    public event Action<string>? Deleted;

    public ChipFlow()
    {
        Cursor = Cursors.Default;
    }

    public void SetTerms(IEnumerable<string> newTerms)
    {
        terms.Clear();
        terms.AddRange(newTerms);
        Rebuild();
        Invalidate();
    }

    private const int ChipHeight = 28;
    private const int Gap = 7;

    /// <summary>Berechnet Chip-Positionen und die eigene Höhe (Umbruch am Rand).</summary>
    private void Rebuild()
    {
        layout.Clear();
        if (Width <= 0) return;
        float x = 0, y = 0;
        foreach (var term in terms)
        {
            var textWidth = TextRenderer.MeasureText(term, Theme.Body).Width;
            var chipWidth = textWidth + 22 + 16;   // Text + Polsterung + ✕
            if (x + chipWidth > Width && x > 0)
            {
                x = 0;
                y += ChipHeight + Gap;
            }
            var chip = new RectangleF(x, y, chipWidth, ChipHeight);
            var del = new RectangleF(chip.Right - 22, y + (ChipHeight - 16) / 2f, 16, 16);
            layout.Add((chip, del, term));
            x += chipWidth + Gap;
        }
        Height = terms.Count == 0 ? 0 : (int)(y + ChipHeight);
    }

    protected override void OnLayout(LayoutEventArgs e)
    {
        base.OnLayout(e);
        Rebuild();
    }

    protected override void OnMouseMove(MouseEventArgs e)
    {
        var hit = layout.FirstOrDefault(l => l.Delete.Contains(e.Location)).Term;
        if (hit != hovered)
        {
            hovered = hit;
            Cursor = hit != null ? Cursors.Hand : Cursors.Default;
            Invalidate();
        }
        base.OnMouseMove(e);
    }

    protected override void OnMouseLeave(EventArgs e)
    {
        hovered = null;
        Invalidate();
        base.OnMouseLeave(e);
    }

    protected override void OnMouseClick(MouseEventArgs e)
    {
        foreach (var (_, del, term) in layout)
        {
            if (!del.Contains(e.Location)) continue;
            Deleted?.Invoke(term);
            break;
        }
        base.OnMouseClick(e);
    }

    protected override void OnPaint(PaintEventArgs e)
    {
        var g = e.Graphics;
        Theme.Smooth(g);
        using (var bg = new SolidBrush(BackColor)) g.FillRectangle(bg, ClientRectangle);

        foreach (var (chip, del, term) in layout)
        {
            Theme.DrawCapsule(g, chip, Theme.Track, Theme.CardBorder);
            DrawText(g, term, Theme.Body, Theme.Gray(0.9),
                     new Rectangle((int)chip.X + 11, (int)chip.Y, (int)chip.Width - 30, ChipHeight),
                     TextFormatFlags.VerticalCenter | TextFormatFlags.NoPrefix);
            Icons.Draw(g, Icons.Kind.Close, del,
                       term == hovered ? Theme.Live : Theme.Gray(0.5), 9f);
        }
    }
}

// MARK: - Statistik-Karten

/// <summary>Kachel mit großer Zahl und Beschriftung.</summary>
internal sealed class StatCard : ThemedControl
{
    private readonly string value, label;

    public StatCard(string value, string label)
    {
        this.value = value;
        this.label = label;
        Height = 84;
    }

    protected override void OnPaint(PaintEventArgs e)
    {
        var g = e.Graphics;
        Theme.Smooth(g);
        using (var bg = new SolidBrush(Theme.Window)) g.FillRectangle(bg, ClientRectangle);
        Theme.DrawCard(g, new RectangleF(0, 0, Width, Height));

        DrawText(g, value, Theme.Metric, Theme.Gray(0.95), new Rectangle(16, 12, Width - 32, 38),
                 TextFormatFlags.NoPrefix | TextFormatFlags.NoClipping);
        DrawText(g, label, Theme.Help, Theme.Gray(0.55), new Rectangle(16, 54, Width - 32, 18),
                 TextFormatFlags.NoPrefix);
    }
}

/// <summary>Kachel mit kleiner Überschrift und Wert (Meistgenutztes Wort …).</summary>
internal sealed class InfoCard : ThemedControl
{
    private readonly string title, value;

    public InfoCard(string title, string value)
    {
        this.title = title;
        this.value = value;
        Height = 76;
    }

    protected override void OnPaint(PaintEventArgs e)
    {
        var g = e.Graphics;
        Theme.Smooth(g);
        using (var bg = new SolidBrush(Theme.Window)) g.FillRectangle(bg, ClientRectangle);
        Theme.DrawCard(g, new RectangleF(0, 0, Width, Height));

        Theme.DrawTracked(g, title.ToUpperInvariant(), Theme.SectionLabel, Theme.Gray(0.5),
                          new PointF(16, 14), 0.4f);
        DrawText(g, value, Theme.InfoValue, Theme.Gray(0.92), new Rectangle(16, 36, Width - 32, 26),
                 TextFormatFlags.NoPrefix | TextFormatFlags.EndEllipsis);
    }
}
