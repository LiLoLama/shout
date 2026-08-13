namespace Shout.UI;

/// <summary>
/// Freistehender Textblock (Absätze, Fußnoten, Seitentitel) — bricht um und
/// meldet seine Höhe an das Stapel-Layout der Seite.
/// </summary>
internal sealed class TextBlock : ThemedControl, IAutoHeight
{
    private readonly Font font;
    private readonly Color color;
    private readonly int indent;

    public TextBlock(string text, Font font, Color color, int indent = 0)
    {
        Text = text;
        this.font = font;
        this.color = color;
        this.indent = indent;
    }

    /// <summary>Seitentitel wie am Mac: 15 px, halbfett, nahezu weiß.</summary>
    public static TextBlock Title(string text) => new(text, Theme.PageTitle, Theme.Gray(0.92));

    /// <summary>Erklärender Absatz.</summary>
    public static TextBlock Body(string text) => new(text, Theme.Body, Theme.Gray(0.62));

    /// <summary>Fußnote unter einer Karte.</summary>
    public static TextBlock Footnote(string text) => new(text, Theme.Help, Theme.Gray(0.5), 4);

    /// <summary>Hinweis, der auffallen soll — dieselbe Farbe wie ein gescheiterter
    /// Auftrag, damit die App nur eine Warnfarbe kennt.</summary>
    public static TextBlock Warning(string text)
        => new(text, Theme.Help, Color.FromArgb(242, 179, 51), 4);

    public int PreferredHeightFor(int width)
        => MeasureText(Text, font, Math.Max(40, width - indent)).Height;

    public void SetText(string text)
    {
        Text = text;
        Invalidate();
    }

    protected override void OnPaint(PaintEventArgs e)
    {
        var g = e.Graphics;
        Theme.Smooth(g);
        using (var bg = new SolidBrush(BackColor)) g.FillRectangle(bg, ClientRectangle);
        DrawText(g, Text, font, color, new Rectangle(indent, 0, Math.Max(40, Width - indent), Height),
                 TextFormatFlags.WordBreak | TextFormatFlags.NoPrefix);
    }
}

/// <summary>
/// Waagerechte Reihe gleich breiter Kacheln (Mac: LazyVGrid mit adaptiven Spalten).
/// Bricht auf eine Spalte um, wenn die Kacheln zu schmal würden.
/// </summary>
internal sealed class GridRow : Panel, IAutoHeight
{
    private readonly Control[] cells;
    private readonly int minCellWidth;
    private const int Gap = 12;

    public GridRow(Control[] cells, int minCellWidth = 150)
    {
        this.cells = cells;
        this.minCellWidth = minCellWidth;
        BackColor = Theme.Window;
        foreach (var c in cells) Controls.Add(c);
    }

    private int ColumnsFor(int width)
    {
        var columns = Math.Max(1, (width + Gap) / (minCellWidth + Gap));
        return Math.Min(columns, cells.Length);
    }

    public int PreferredHeightFor(int width)
    {
        var columns = ColumnsFor(width);
        var rows = (int)Math.Ceiling(cells.Length / (double)columns);
        var cellHeight = cells.Length > 0 ? cells[0].Height : 0;
        return rows * cellHeight + (rows - 1) * Gap;
    }

    protected override void OnLayout(LayoutEventArgs e)
    {
        base.OnLayout(e);
        if (cells.Length == 0 || Width <= 0) return;

        var columns = ColumnsFor(Width);
        var cellWidth = (Width - (columns - 1) * Gap) / columns;
        for (var i = 0; i < cells.Length; i++)
        {
            var row = i / columns;
            var column = i % columns;
            cells[i].Location = new Point(column * (cellWidth + Gap), row * (cells[i].Height + Gap));
            cells[i].Width = cellWidth;
        }
    }
}

/// <summary>
/// Basis aller Dashboard-Seiten: mittig gesetzte Spalte (wie die Mac-App:
/// `frame(maxWidth: …)` plus 28 px seitlich, 42 px oben) und ein senkrechter
/// Stapel mit 22 px Abstand. Höhen liefern die Elemente über
/// <see cref="IAutoHeight"/>; feste Höhen bleiben unverändert.
/// </summary>
internal abstract class PageBase : Panel
{
    protected const int PadH = 28;
    protected const int PadTop = 42;
    protected const int PadBottom = 28;
    protected const int Spacing = 22;

    /// <summary>Maximale Spaltenbreite (Mac: 520 für Einstellungen, 640 für Listen).</summary>
    protected virtual int MaxContentWidth => 520;

    private readonly List<(Control Control, int SpacingBefore)> stack = new();

    protected PageBase()
    {
        BackColor = Theme.Window;
    }

    /// <summary>Element unten an den Stapel hängen.</summary>
    protected T Push<T>(T control, int spacingBefore = Spacing) where T : Control
    {
        stack.Add((control, stack.Count == 0 ? 0 : spacingBefore));
        Controls.Add(control);
        return control;
    }

    /// <summary>
    /// Stapel auf die ersten <paramref name="keep"/> Elemente zurücksetzen — für
    /// Seiten, die ihre Liste neu aufbauen (Verlauf). Die entfernten Controls
    /// werden freigegeben.
    /// </summary>
    protected void TrimStack(int keep)
    {
        for (var i = stack.Count - 1; i >= keep; i--)
        {
            Controls.Remove(stack[i].Control);
            stack[i].Control.Dispose();
            stack.RemoveAt(i);
        }
    }

    /// <summary>Wird nach jeder Änderung aufgerufen, die Höhen beeinflusst.</summary>
    public void Relayout()
    {
        PerformLayout();
        Invalidate(true);
    }

    /// <summary>Höhe hat sich geändert — Seite neu setzen und den Scrollbereich nachziehen.</summary>
    protected void NotifyHeightChanged()
    {
        Relayout();
        (FindForm() as DashboardForm)?.PageHeightChanged();
    }

    protected override void OnLayout(LayoutEventArgs e)
    {
        base.OnLayout(e);
        if (Width <= 0) return;

        var columnWidth = Math.Min(MaxContentWidth, Math.Max(200, Width - PadH * 2));
        var left = Math.Max(PadH, (Width - columnWidth) / 2);
        var y = PadTop;

        foreach (var (control, spacingBefore) in stack)
        {
            if (!control.Visible) continue;
            y += spacingBefore;
            control.Left = left;
            control.Width = columnWidth;
            if (control is IAutoHeight auto) control.Height = auto.PreferredHeightFor(columnWidth);
            control.Top = y;
            y += control.Height;
        }
        Height = y + PadBottom;
    }
}
