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

/// <summary>Basis: doppelt gepuffert, eigengezeichnet, Fokus nur wo bedienbar.</summary>
internal abstract class ThemedControl : Control
{
    protected ThemedControl()
    {
        SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.UserPaint
                 | ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw, true);
        // Schmuck-Elemente bleiben aus der Tab-Reihenfolge draußen; bedienbare
        // schalten sich über MakeInteractive wieder frei. TabStop steht sonst auch
        // bei nicht fokussierbaren Controls auf true und täuscht Bedienbarkeit vor.
        SetStyle(ControlStyles.Selectable, false);
        TabStop = false;
        BackColor = Theme.Window;
        ForeColor = Theme.Ink;
    }

    /// <summary>Maß aus dem 96-dpi-Entwurf in Bildschirmpunkte. Ohne die Umrechnung
    /// bleibt bei 150 % alles in 100-%-Größe stehen, während Windows die Schrift
    /// mitwächst — der Text läuft aus Knöpfen und Kapseln heraus.</summary>
    protected int Scaled(int value) => value * DeviceDpi / 96;

    /// <summary>Wie <see cref="Scaled(int)"/>, für Radien und Strichstärken.</summary>
    protected float Scaled(float value) => value * DeviceDpi / 96f;

    /// <summary>
    /// Auflösung des HAUPTBILDSCHIRMS. Sie ist der Maßstab, in dem TextRenderer ohne
    /// Gerätekontext misst — nicht 96 dpi, wie man annehmen möchte. Auf einem Rechner,
    /// dessen Hauptbildschirm selbst auf 150 % steht, wäre eine feste Umrechnung auf
    /// 96 dpi um genau diesen Faktor daneben.
    /// </summary>
    private static readonly int SystemDpi = ReadSystemDpi();

    private static int ReadSystemDpi()
    {
        try
        {
            using var g = Graphics.FromHwnd(IntPtr.Zero);
            return (int)Math.Round(g.DpiY);
        }
        catch
        {
            return 96;
        }
    }

    /// <summary>Textmaß in den Punkten DIESES Fensters. TextRenderer misst ohne
    /// Gerätekontext immer am Hauptbildschirm — auf einem 200-%-Monitor wäre der
    /// Knopf sonst nur halb so breit wie seine Aufschrift.</summary>
    protected Size MeasureScaled(string text, Font font)
    {
        if (IsHandleCreated)
        {
            try
            {
                using var g = CreateGraphics();
                return TextRenderer.MeasureText(g, text, font);
            }
            catch { /* Gerätekontext gerade nicht zu haben — unten weiter */ }
        }
        // Noch ohne Fenster (im Aufbau): am Hauptbildschirm messen und umrechnen.
        // Der Rest holt OnDpiChangedAfterParent nach.
        var size = TextRenderer.MeasureText(text, font);
        return new Size(size.Width * DeviceDpi / SystemDpi, size.Height * DeviceDpi / SystemDpi);
    }

    /// <summary>Element per Tastatur erreichbar machen und ihm einen Namen geben —
    /// ohne das überspringt Tab das ganze Fenster und Screenreader lesen nichts vor.</summary>
    protected void MakeInteractive(AccessibleRole role, string? name = null)
    {
        SetStyle(ControlStyles.Selectable, true);
        TabStop = true;
        AccessibleRole = role;
        if (!string.IsNullOrEmpty(name)) AccessibleName = name;
    }

    /// <summary>Klick holt den Fokus, damit Maus und Tastatur dieselbe Stelle meinen.</summary>
    protected override void OnMouseDown(MouseEventArgs e)
    {
        if (e.Button == MouseButtons.Left && GetStyle(ControlStyles.Selectable) && !Focused) Focus();
        base.OnMouseDown(e);
    }

    protected override void OnGotFocus(EventArgs e)
    {
        base.OnGotFocus(e);
        Invalidate();
        // Liegt das Element in einem Scrollbereich, muss es beim Tabben sichtbar
        // werden — sonst wandert der Fokusrahmen aus dem Fenster heraus, und wer
        // ohne Maus arbeitet, weiß nicht mehr, wo er steht.
        for (Control? parent = Parent; parent != null; parent = parent.Parent)
            if (parent is ScrollHost host)
            {
                host.ScrollIntoView(this);
                break;
            }
    }

    protected override void OnLostFocus(EventArgs e)
    {
        base.OnLostFocus(e);
        Invalidate();
    }

    /// <summary>Fokusrahmen — ohne ihn ist beim Tabben nicht zu erkennen, wo man steht.</summary>
    protected void DrawFocusRing(Graphics g, RectangleF bounds, float radius)
    {
        if (!Focused) return;
        using var pen = new Pen(Theme.White(0.8), Scaled(1f));
        using var path = Theme.Rounded(bounds, radius);
        g.DrawPath(pen, path);
    }

    /// <summary>Text scharf über GDI zeichnen (wie native Windows-Oberflächen).</summary>
    protected static void DrawText(Graphics g, string text, Font font, Color color, Rectangle bounds,
                                   TextFormatFlags flags = TextFormatFlags.Left | TextFormatFlags.NoPrefix)
    {
        if (string.IsNullOrEmpty(text)) return;
        TextRenderer.DrawText(g, text, font, bounds, color, flags);
    }

    /// <summary>
    /// Höhe eines umbrechenden Textes — ebenfalls im Maßstab DIESES Fensters. Davon
    /// hängen die Kartenhöhen ab: Wird zu knapp gemessen, schneidet die Karte ihren
    /// eigenen Hilfetext ab.
    /// </summary>
    protected Size MeasureText(string text, Font font, int maxWidth,
                               TextFormatFlags flags = TextFormatFlags.WordBreak | TextFormatFlags.NoPrefix)
    {
        var proposed = new Size(maxWidth, int.MaxValue);
        if (IsHandleCreated)
        {
            try
            {
                using var g = CreateGraphics();
                return TextRenderer.MeasureText(g, text, font, proposed, flags);
            }
            catch { /* siehe MeasureScaled */ }
        }
        var size = TextRenderer.MeasureText(text, font, proposed, flags);
        return new Size(size.Width * DeviceDpi / SystemDpi, size.Height * DeviceDpi / SystemDpi);
    }
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
    private int ThumbWidth => Scaled(6);
    private int ThumbInset => Scaled(3);

    public ScrollHost()
    {
        Controls.Add(Content);
    }

    /// <summary>Streifen rechts, den der Inhalt frei lässt, damit der Balken sichtbar
    /// bleibt (Kind-Controls würden ihn sonst überdecken).</summary>
    private int ScrollGutter => Scaled(12);

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

    /// <summary>
    /// Holt ein Bedienelement in den sichtbaren Bereich. Ohne das führt Tab zwar
    /// weiter, aber ins Nichts: Der Fokusrahmen steht dann außerhalb des Fensters,
    /// und wer die Maus nicht benutzt, weiß nicht mehr, wo er ist.
    /// </summary>
    public void ScrollIntoView(Control control)
    {
        if (control.IsDisposed || Height <= 0) return;

        // Lage innerhalb des Inhalts aufsummieren — das Element sitzt mehrere
        // Ebenen tief in Karten und Reihen.
        var top = 0;
        for (var c = control; c != null && c != Content; c = c.Parent)
        {
            top += c.Top;
            if (c.Parent == null) return;   // gehört nicht zu diesem Bereich
        }

        var margin = Scaled(12);
        if (top - margin < offset) ScrollBy(top - margin - offset);
        else if (top + control.Height + margin > offset + Height)
            ScrollBy(top + control.Height + margin - offset - Height);
    }

    protected override void OnMouseWheel(MouseEventArgs e)
    {
        ScrollBy(Scaled(-e.Delta * 5 / 6));   // ~90 px je Rasterschritt
        base.OnMouseWheel(e);
    }

    protected override void OnLayout(LayoutEventArgs e)
    {
        base.OnLayout(e);
        Content.Width = Math.Max(Scaled(100), Width - ScrollGutter);
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
        var thumbHeight = Math.Max(Scaled(28), (int)((float)Height / Content.Height * trackHeight));
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
    /// <summary>Hilfetext, der sich mit dem Zustand ändert (z. B. die Aufnahme-Art:
    /// „halten" erklärt sich anders als „umschalten"). Hat Vorrang vor <see cref="Help"/>.</summary>
    public Func<string>? HelpFor;
    /// <summary>Bedienelement rechts (Schalter, Knopf, Dropdown …).</summary>
    public Control? Trailing;
    /// <summary>Führendes Symbol (Listen wie „In der Datei enthalten").</summary>
    public Icons.Kind? Icon { get; init; }
    /// <summary>Zeile nur anzeigen, wenn true (z. B. „Pause bis Stopp" nur bei Auto-Stopp).</summary>
    public Func<bool>? VisibleWhen;

    public bool IsVisible => VisibleWhen?.Invoke() ?? true;

    /// <summary>Der aktuell anzuzeigende Hilfetext.</summary>
    public string? HelpText => HelpFor?.Invoke() ?? Help;
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

    private int LabelHeight => Scaled(22);   // Abschnitts-Label + Abstand (9 px Lücke wie am Mac)
    private int RowPaddingH => Scaled(15);
    private int RowPaddingV => Scaled(12);
    private int IconWidth => Scaled(22);
    private int IconGap => Scaled(12);
    private int TrailingGap => Scaled(14);
    private int HelpGap => Scaled(3);

    public void Add(PanelRow row)
    {
        rows.Add(row);
        if (row.Trailing != null)
        {
            row.Trailing.BackColor = Theme.Card;
            // Ein Schalter trägt keine eigene Aufschrift: ohne den Zeilentitel liest
            // ein Screenreader nur „Kontrollkästchen" vor.
            NameFromRow(row.Trailing, row.Title);
            Controls.Add(row.Trailing);
        }
    }

    private static void NameFromRow(Control trailing, string title)
    {
        // Ein Knopf trägt seine Aufschrift selbst; Schalter, Regler und Dropdowns
        // haben nur die Zeilenüberschrift.
        if (string.IsNullOrEmpty(trailing.Text)) trailing.AccessibleName = title;
        if (trailing is Cluster cluster) cluster.NameInteractive(title);
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
        var iconWidth = row.Icon != null ? IconWidth + IconGap : 0;
        return Math.Max(Scaled(60), width - RowPaddingH * 2 - iconWidth
                            - (trailingWidth > 0 ? trailingWidth + TrailingGap : 0));
    }

    private int RowHeight(PanelRow row, int width)
    {
        var textWidth = TextWidth(row, width);
        var h = MeasureText(row.Title, Theme.RowTitle, textWidth).Height;
        var help = row.HelpText;
        if (!string.IsNullOrEmpty(help))
            h += HelpGap + MeasureText(help, Theme.Help, textWidth).Height;
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
                              new PointF(Scaled(4), 0), Scaled(0.8f));
            cardTop = LabelHeight;
        }

        var cardHeight = Height - cardTop;
        if (cardHeight <= 0) return;
        Theme.DrawCard(g, new RectangleF(0, cardTop, Width, cardHeight), Scaled(12f));

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
                Icons.Draw(g, icon, new RectangleF(RowPaddingH, y + h / 2f - IconWidth / 2f, IconWidth, IconWidth),
                           Theme.Live, Scaled(15f));
                textLeft += IconWidth + IconGap;
            }

            var textWidth = TextWidth(row, Width);
            var help = row.HelpText;
            var titleSize = MeasureText(row.Title, Theme.RowTitle, textWidth);
            var helpSize = string.IsNullOrEmpty(help)
                ? Size.Empty
                : MeasureText(help, Theme.Help, textWidth);
            var blockHeight = titleSize.Height + (helpSize.Height > 0 ? HelpGap + helpSize.Height : 0);
            var textTop = y + (h - blockHeight) / 2;

            DrawText(g, row.Title, Theme.RowTitle, Theme.Ink,
                     new Rectangle(textLeft, textTop, textWidth, titleSize.Height),
                     TextFormatFlags.WordBreak | TextFormatFlags.NoPrefix);
            if (helpSize.Height > 0)
                DrawText(g, help!, Theme.Help, Theme.InkMuted,
                         new Rectangle(textLeft, textTop + titleSize.Height + HelpGap, textWidth, helpSize.Height),
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
    /// <summary>Freier Platz oben im Innenbereich, den <see cref="PaintContent"/> nutzt.
    /// Bleibt ungerechnet: die zeichnenden Seiten setzen dort eigene, feste Maße.</summary>
    public int ContentHeaderHeight { get; init; }

    private int LabelHeight => Scaled(22);
    private int Padding2 => Scaled(Inset);
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

    private int InnerWidth(int width) => Math.Max(Scaled(40), width - Padding2 * 2);

    public int PreferredHeightFor(int width)
    {
        var inner = InnerWidth(width);
        var content = ContentHeaderHeight;
        foreach (var (control, spacing) in stack)
        {
            if (!control.Visible) continue;
            content += Scaled(spacing);
            content += control is IAutoHeight auto ? auto.PreferredHeightFor(inner) : control.Height;
        }
        return TopOffset + Padding2 * 2 + content;
    }

    protected override void OnLayout(LayoutEventArgs e)
    {
        base.OnLayout(e);
        if (Width <= 0) return;
        var inner = InnerWidth(Width);
        var y = TopOffset + Padding2 + ContentHeaderHeight;
        foreach (var (control, spacing) in stack)
        {
            if (!control.Visible) continue;
            y += Scaled(spacing);
            control.Left = Padding2;
            // Ein Cluster ohne Streckung bringt seine eigene Breite mit; alles andere
            // — auch ein gestreckter Cluster — füllt die Karte. Ohne die Breite bliebe
            // ein Chip-Feld 0 px breit und damit unsichtbar.
            if (control is IAutoHeight auto)
            {
                if (control is not Cluster { StretchFirst: false }) control.Width = inner;
                control.Height = auto.PreferredHeightFor(control.Width);
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
                              new PointF(Scaled(4), 0), Scaled(0.8f));
            cardTop = LabelHeight;
        }
        var cardHeight = Height - cardTop;
        if (cardHeight <= 0) return;
        Theme.DrawCard(g, new RectangleF(0, cardTop, Width, cardHeight), Scaled(12f));
        PaintContent?.Invoke(g, new Rectangle(Padding2, cardTop + Padding2,
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
    private readonly int designGap;
    /// <summary>Erstes Element auf die Restbreite strecken (Eingabefeld + Knopf).</summary>
    public bool StretchFirst { get; init; }

    private int Gap => Scaled(designGap);

    public Cluster(Control[] items, int gap = 10)
    {
        this.items = items;
        designGap = gap;
        foreach (var item in items) Controls.Add(item);
        ApplyMetrics();
    }

    private void ApplyMetrics()
    {
        if (items == null || items.Length == 0) return;
        Height = items.Max(i => i.Height);
        // Ein gestreckter Cluster bekommt seine Breite von der Karte — sie hier neu
        // zu setzen würde ihn nach einem Monitorwechsel wieder zusammenziehen.
        if (!StretchFirst) Width = items.Sum(i => i.Width) + (items.Length - 1) * Gap;
    }

    public int PreferredHeightFor(int width) => items.Length > 0 ? items.Max(i => i.Height) : 0;

    /// <summary>Den Namen der Zeile an das eigentliche Bedienelement durchreichen —
    /// ein Schieberegler trägt keine eigene Aufschrift.</summary>
    public void NameInteractive(string title)
    {
        foreach (var item in items)
        {
            if (!item.TabStop || !string.IsNullOrEmpty(item.Text)) continue;
            item.AccessibleName = title;
            return;
        }
    }

    /// <summary>Hintergrundfarbe an die Kinder weitergeben — sonst blitzt an ihren
    /// abgerundeten Ecken die Fensterfarbe statt der Kartenfarbe durch.
    /// Der Basiskonstruktor setzt BackColor bereits, bevor <c>items</c> zugewiesen
    /// ist — daher die Null-Prüfung.</summary>
    protected override void OnBackColorChanged(EventArgs e)
    {
        base.OnBackColorChanged(e);
        if (items == null) return;
        foreach (var item in items) item.BackColor = BackColor;
    }

    protected override void OnDpiChangedAfterParent(EventArgs e)
    {
        base.OnDpiChangedAfterParent(e);
        ApplyMetrics();
    }

    protected override void OnLayout(LayoutEventArgs e)
    {
        base.OnLayout(e);
        if (items == null || items.Length == 0) return;

        if (StretchFirst && Width > 0)
        {
            var others = items.Skip(1).Sum(i => i.Width) + (items.Length - 1) * Gap;
            items[0].Width = Math.Max(Scaled(60), Width - others);
        }

        var x = 0;
        foreach (var item in items)
        {
            item.Location = new Point(x, (Height - item.Height) / 2);
            x += item.Width + Gap;
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
    private readonly int box;

    public IconView(Icons.Kind kind, Color color, float glyphSize, int box)
    {
        this.kind = kind;
        this.color = color;
        this.glyphSize = glyphSize;
        this.box = box;
        ApplyMetrics();
    }

    private void ApplyMetrics() => Size = new Size(Scaled(box), Scaled(box));

    protected override void OnDpiChangedAfterParent(EventArgs e)
    {
        base.OnDpiChangedAfterParent(e);
        ApplyMetrics();
    }

    public int PreferredHeightFor(int width) => Height;

    protected override void OnPaint(PaintEventArgs e)
    {
        var g = e.Graphics;
        Theme.Smooth(g);
        using (var bg = new SolidBrush(BackColor)) g.FillRectangle(bg, ClientRectangle);
        Icons.Draw(g, kind, ClientRectangle, color, Scaled(glyphSize));
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
        ApplyMetrics();
        Cursor = Cursors.Hand;
        MakeInteractive(AccessibleRole.CheckButton);
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

    private void ApplyMetrics() => Size = new Size(Scaled(40), Scaled(22));

    protected override void OnDpiChangedAfterParent(EventArgs e)
    {
        base.OnDpiChangedAfterParent(e);
        ApplyMetrics();
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

    /// <summary>Ein gemeinsamer Weg für Maus und Tastatur.</summary>
    private void Toggle()
    {
        Checked = !on;
        Changed?.Invoke(on);
    }

    protected override void OnMouseClick(MouseEventArgs e)
    {
        // Nur die linke Taste schaltet: ein Rechtsklick soll ein Kontextmenü
        // aufmachen dürfen, ohne die Einstellung zu verstellen.
        if (e.Button == MouseButtons.Left) Toggle();
        base.OnMouseClick(e);
    }

    protected override bool IsInputKey(Keys keyData)
        => keyData is Keys.Space or Keys.Enter || base.IsInputKey(keyData);

    protected override void OnKeyDown(KeyEventArgs e)
    {
        if (e.KeyCode is Keys.Space or Keys.Enter)
        {
            Toggle();
            e.Handled = true;
            e.SuppressKeyPress = true;
        }
        base.OnKeyDown(e);
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

        var inset = Scaled(3);
        var knobSize = Height - inset * 2;
        var travel = Width - knobSize - inset * 2;
        var knobX = inset + travel * animation;
        using (var knob = new SolidBrush(Blend(Theme.Gray(0.62), Color.White, animation)))
            g.FillEllipse(knob, knobX, inset, knobSize, knobSize);

        DrawFocusRing(g, track, Height / 2f);
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
        ApplyMetrics();
        MakeInteractive(AccessibleRole.ComboBox, options.Length > 0 ? options[selected].Label : null);
        AccessibleDescription = options.Length > 0 ? options[selected].Label : null;
    }

    private void ApplyMetrics()
    {
        Height = Scaled(30);
        Width = Measure();
    }

    protected override void OnDpiChangedAfterParent(EventArgs e)
    {
        base.OnDpiChangedAfterParent(e);
        ApplyMetrics();
    }

    public string SelectedKey => options[selected].Key;

    /// <summary>Setzt die Auswahl von außen, OHNE <see cref="Changed"/> zu feuern —
    /// der Aufrufer weiß ja bereits, was er will.</summary>
    public void Select(string key)
    {
        var index = Array.FindIndex(options, o => o.Key == key);
        if (index < 0 || index == selected) return;
        selected = index;
        AccessibleDescription = options[index].Label;
        Invalidate();
    }

    /// <summary>Auswahl aus der Bedienung heraus — meldet die Änderung weiter.</summary>
    private void Choose(int index)
    {
        if (index < 0 || index >= options.Length || index == selected) return;
        selected = index;
        AccessibleDescription = options[index].Label;
        Invalidate();
        Changed?.Invoke(options[index].Key);
    }

    private int Measure()
    {
        var total = Scaled(4);   // 2 px Polsterung je Seite
        foreach (var (_, label) in options)
            total += SegmentWidth(label);
        return total;
    }

    private int SegmentWidth(string label) => MeasureScaled(label, Theme.Body).Width + Scaled(26);

    private RectangleF SegmentRect(int index)
    {
        var x = (float)Scaled(2);
        for (var i = 0; i < index; i++)
            x += SegmentWidth(options[i].Label);
        return new RectangleF(x, Scaled(2), SegmentWidth(options[index].Label), Height - Scaled(4));
    }

    protected override void OnMouseClick(MouseEventArgs e)
    {
        // Rechtsklick darf nicht umschalten (siehe ConsoleToggle).
        if (e.Button != MouseButtons.Left)
        {
            base.OnMouseClick(e);
            return;
        }
        for (var i = 0; i < options.Length; i++)
        {
            if (!SegmentRect(i).Contains(e.Location)) continue;
            Choose(i);
            break;
        }
        base.OnMouseClick(e);
    }

    protected override bool IsInputKey(Keys keyData)
        => keyData is Keys.Left or Keys.Right or Keys.Home or Keys.End || base.IsInputKey(keyData);

    protected override void OnKeyDown(KeyEventArgs e)
    {
        var next = e.KeyCode switch
        {
            Keys.Left => selected - 1,
            Keys.Right => selected + 1,
            Keys.Home => 0,
            Keys.End => options.Length - 1,
            _ => selected,
        };
        if (next != selected && next >= 0 && next < options.Length)
        {
            Choose(next);
            e.Handled = true;
            e.SuppressKeyPress = true;
        }
        base.OnKeyDown(e);
    }

    protected override void OnPaint(PaintEventArgs e)
    {
        var g = e.Graphics;
        Theme.Smooth(g);
        using (var bg = new SolidBrush(BackColor)) g.FillRectangle(bg, ClientRectangle);

        using (var track = new SolidBrush(Theme.Track))
        using (var path = Theme.Rounded(new RectangleF(0, 0, Width, Height), Scaled(8f)))
            g.FillPath(track, path);

        for (var i = 0; i < options.Length; i++)
        {
            var r = SegmentRect(i);
            var active = i == selected;
            if (active)
            {
                using var fill = new SolidBrush(Theme.SegActive);
                using var path = Theme.Rounded(r, Scaled(6f));
                g.FillPath(fill, path);
            }
            DrawText(g, options[i].Label, Theme.Body, active ? Theme.Ink : Theme.InkMuted,
                     Rectangle.Round(r),
                     TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.NoPrefix);
        }

        DrawFocusRing(g, new RectangleF(0.5f, 0.5f, Width - 1, Height - 1), Scaled(8f));
    }
}

// MARK: - Knopf

/// <summary>Flacher Knopf; <see cref="Primary"/> füllt ihn mit der Signalfarbe.</summary>
internal sealed class ConsoleButton : ThemedControl
{
    public bool Primary { get; }
    public Icons.Kind? Icon { get; }
    private readonly int? designWidth;
    private bool hover, pressed;
    private bool enabledLook = true;

    public event Action? Click2;

    public ConsoleButton(string text, bool primary = false, Icons.Kind? icon = null, int? width = null)
    {
        Text = text;
        Primary = primary;
        Icon = icon;
        designWidth = width;
        Cursor = Cursors.Hand;
        ApplyMetrics();
        MakeInteractive(AccessibleRole.PushButton, text);
    }

    private void ApplyMetrics()
    {
        Height = Scaled(Primary ? 32 : 28);
        var textWidth = MeasureScaled(Text, Primary ? Theme.RowTitleStrong : Theme.ButtonText).Width;
        Width = designWidth is { } w
            ? Scaled(w)
            : textWidth + Scaled(Primary ? 32 : 26) + (Icon != null ? Scaled(22) : 0);
    }

    protected override void OnDpiChangedAfterParent(EventArgs e)
    {
        base.OnDpiChangedAfterParent(e);
        ApplyMetrics();
    }

    /// <summary>Optische und funktionale Sperre (WinForms' Enabled graut Kind-Controls
    /// nicht passend ein, deshalb eigene Darstellung).</summary>
    public void SetEnabled(bool value)
    {
        if (enabledLook == value) return;
        enabledLook = value;
        Cursor = value ? Cursors.Hand : Cursors.Default;
        // Ein gesperrter Knopf darf auch beim Tabben nicht erreichbar sein — sonst
        // steht der Fokus auf etwas, das auf keine Taste reagiert.
        TabStop = value;
        Invalidate();
    }

    public bool IsEnabled => enabledLook;

    protected override void OnMouseEnter(EventArgs e) { hover = true; Invalidate(); base.OnMouseEnter(e); }
    protected override void OnMouseLeave(EventArgs e) { hover = false; pressed = false; Invalidate(); base.OnMouseLeave(e); }
    protected override void OnMouseDown(MouseEventArgs e) { pressed = true; Invalidate(); base.OnMouseDown(e); }
    protected override void OnMouseUp(MouseEventArgs e) { pressed = false; Invalidate(); base.OnMouseUp(e); }

    protected override void OnMouseClick(MouseEventArgs e)
    {
        // Nur die linke Taste löst aus — ein Rechtsklick auf „Löschen" hätte sonst
        // dieselbe Wirkung wie ein bewusster Klick.
        if (e.Button == MouseButtons.Left && enabledLook) Click2?.Invoke();
        base.OnMouseClick(e);
    }

    protected override bool IsInputKey(Keys keyData)
        => keyData is Keys.Space or Keys.Enter || base.IsInputKey(keyData);

    protected override void OnKeyDown(KeyEventArgs e)
    {
        if (enabledLook && e.KeyCode is Keys.Space or Keys.Enter)
        {
            pressed = true;
            Invalidate();
            e.Handled = true;
            e.SuppressKeyPress = true;
        }
        base.OnKeyDown(e);
    }

    protected override void OnKeyUp(KeyEventArgs e)
    {
        if (pressed && e.KeyCode is Keys.Space or Keys.Enter)
        {
            pressed = false;
            Invalidate();
            if (enabledLook) Click2?.Invoke();
            e.Handled = true;
        }
        base.OnKeyUp(e);
    }

    protected override void OnPaint(PaintEventArgs e)
    {
        var g = e.Graphics;
        Theme.Smooth(g);
        using (var bg = new SolidBrush(BackColor)) g.FillRectangle(bg, ClientRectangle);

        var r = new RectangleF(0.5f, 0.5f, Width - 1, Height - 1);
        var radius = Scaled(Primary ? 8f : 7f);
        var fillColor = Primary ? Theme.Live : Theme.Button;
        if (!enabledLook) fillColor = Color.FromArgb(Primary ? 110 : 150, fillColor);
        else if (pressed) fillColor = Color.FromArgb(210, fillColor);
        else if (hover && !Primary) fillColor = Theme.Gray(0.27);

        using (var fill = new SolidBrush(fillColor))
        using (var path = Theme.Rounded(r, radius))
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
            Icons.Draw(g, icon, new RectangleF(Scaled(10), 0, Scaled(16), Height), textColor, Scaled(13f));
            textArea = new Rectangle(Scaled(24), 0, Width - Scaled(30), Height);
            DrawText(g, Text, Primary ? Theme.RowTitleStrong : Theme.ButtonText, textColor, textArea,
                     TextFormatFlags.VerticalCenter | TextFormatFlags.NoPrefix);
        }
        else
        {
            DrawText(g, Text, Primary ? Theme.RowTitleStrong : Theme.ButtonText, textColor, textArea,
                     TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.NoPrefix);
        }

        DrawFocusRing(g, r, radius);
    }
}

// MARK: - Tastenkappe

/// <summary>Monospace-Tastenkappe (Hotkey-Anzeige, Zahlenwerte).</summary>
internal sealed class Keycap : ThemedControl
{
    public Keycap(string text)
    {
        Text = text;
        // Nicht bedienbar, aber Screenreader sollen das Kürzel vorlesen können.
        AccessibleRole = AccessibleRole.StaticText;
        AccessibleName = text;
        ApplyMetrics();
    }

    public void SetText(string text)
    {
        Text = text;
        AccessibleName = text;
        ApplyMetrics();
        Invalidate();
    }

    private void ApplyMetrics()
    {
        Height = Scaled(26);
        Width = Math.Max(Scaled(46), MeasureScaled(Text, Theme.Keycap).Width + Scaled(20));
    }

    protected override void OnDpiChangedAfterParent(EventArgs e)
    {
        base.OnDpiChangedAfterParent(e);
        ApplyMetrics();
    }

    protected override void OnPaint(PaintEventArgs e)
    {
        var g = e.Graphics;
        Theme.Smooth(g);
        using (var bg = new SolidBrush(BackColor)) g.FillRectangle(bg, ClientRectangle);

        var r = new RectangleF(0.5f, 0.5f, Width - 1, Height - 1);
        using (var fill = new SolidBrush(Theme.Track))
        using (var path = Theme.Rounded(r, Scaled(6f)))
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
    private readonly int designWidth;
    private string selectedKey = "";
    private bool hover;

    public event Action<string>? Changed;

    public ConsoleDropdown(int width)
    {
        designWidth = width;
        ApplyMetrics();
        Cursor = Cursors.Hand;
        MakeInteractive(AccessibleRole.ComboBox);
    }

    private void ApplyMetrics()
    {
        Width = Scaled(designWidth);
        Height = Scaled(30);
    }

    protected override void OnDpiChangedAfterParent(EventArgs e)
    {
        base.OnDpiChangedAfterParent(e);
        ApplyMetrics();
    }

    public void SetItems(IEnumerable<(string Key, string Label)> newItems, string selected)
    {
        items.Clear();
        items.AddRange(newItems);
        selectedKey = selected;
        AccessibleDescription = SelectedLabel;
        Invalidate();
    }

    public string SelectedKey => selectedKey;

    private string SelectedLabel =>
        items.FirstOrDefault(i => i.Key == selectedKey).Label ?? items.FirstOrDefault().Label ?? "";

    protected override void OnMouseEnter(EventArgs e) { hover = true; Invalidate(); base.OnMouseEnter(e); }
    protected override void OnMouseLeave(EventArgs e) { hover = false; Invalidate(); base.OnMouseLeave(e); }

    protected override void OnMouseClick(MouseEventArgs e)
    {
        // Rechtsklick öffnet nichts: sonst käme das eigene Menü über das des Systems.
        if (e.Button == MouseButtons.Left) OpenMenu();
        base.OnMouseClick(e);
    }

    protected override bool IsInputKey(Keys keyData)
        => keyData is Keys.Space or Keys.Enter || keyData == (Keys.Alt | Keys.Down)
           || base.IsInputKey(keyData);

    protected override void OnKeyDown(KeyEventArgs e)
    {
        if (e.KeyCode is Keys.Space or Keys.Enter || (e.Alt && e.KeyCode == Keys.Down))
        {
            OpenMenu();
            e.Handled = true;
            e.SuppressKeyPress = true;
        }
        base.OnKeyDown(e);
    }

    private void OpenMenu()
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
                AccessibleDescription = SelectedLabel;
                Invalidate();
                Changed?.Invoke(captured);
            };
            menu.Items.Add(item);
        }
        // Nach dem Schließen freigeben — bei jedem Klick ein neues Menü zu behalten
        // wäre ein Leck.
        menu.Closed += (_, _) => menu.BeginInvoke(() => menu.Dispose());
        menu.Show(this, new Point(0, Height + Scaled(2)));
    }

    protected override void OnPaint(PaintEventArgs e)
    {
        var g = e.Graphics;
        Theme.Smooth(g);
        using (var bg = new SolidBrush(BackColor)) g.FillRectangle(bg, ClientRectangle);

        var r = new RectangleF(0.5f, 0.5f, Width - 1, Height - 1);
        var radius = Scaled(8f);
        using (var fill = new SolidBrush(hover ? Theme.Gray(0.15) : Theme.Track))
        using (var path = Theme.Rounded(r, radius))
        using (var pen = new Pen(Theme.CardBorder))
        {
            g.FillPath(fill, path);
            g.DrawPath(pen, path);
        }

        DrawText(g, SelectedLabel, Theme.Body, Theme.Ink,
                 new Rectangle(Scaled(10), 0, Width - Scaled(32), Height),
                 TextFormatFlags.VerticalCenter | TextFormatFlags.EndEllipsis | TextFormatFlags.NoPrefix);

        // Chevron nach unten
        using (var chevron = new Pen(Theme.InkMuted, Scaled(1.6f)) { StartCap = LineCap.Round, EndCap = LineCap.Round })
        {
            var cx = Width - Scaled(15f);
            var cy = Height / 2f;
            var arm = Scaled(4f);
            g.DrawLines(chevron, new[]
            {
                new PointF(cx - arm, cy - Scaled(2f)),
                new PointF(cx, cy + Scaled(2.5f)),
                new PointF(cx + arm, cy - Scaled(2f)),
            });
        }

        DrawFocusRing(g, r, radius);
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

    private readonly int designWidth;

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
            // Der Platzhalter ist die einzige Beschriftung, die das Feld hat.
            AccessibleName = placeholder,
            Location = new Point(Scaled(10), Scaled(8)),
            Width = Math.Max(Scaled(20), Scaled(width) - Scaled(20)),
        };
        Controls.Add(Inner);
        designWidth = width;
        ApplyMetrics();
    }

    private void ApplyMetrics() => Size = new Size(Scaled(designWidth), Scaled(32));

    protected override void OnDpiChangedAfterParent(EventArgs e)
    {
        base.OnDpiChangedAfterParent(e);
        ApplyMetrics();
    }

    protected override void OnLayout(LayoutEventArgs e)
    {
        base.OnLayout(e);
        if (Inner == null) return;
        Inner.Width = Math.Max(Scaled(20), Width - Scaled(20));
        Inner.Location = new Point(Scaled(10), (Height - Inner.Height) / 2);
    }

    protected override void OnPaint(PaintEventArgs e)
    {
        var g = e.Graphics;
        Theme.Smooth(g);
        using (var bg = new SolidBrush(BackColor)) g.FillRectangle(bg, ClientRectangle);

        var r = new RectangleF(0.5f, 0.5f, Width - 1, Height - 1);
        using var fill = new SolidBrush(Theme.Track);
        using var path = Theme.Rounded(r, Scaled(8f));
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
    private readonly int designWidth;
    private double value;
    private bool dragging;

    public event Action<double>? Changed;

    public ConsoleSlider(double min, double max, double step, double initial, int width)
    {
        this.min = min;
        this.max = max;
        this.step = step;
        value = Math.Clamp(initial, min, max);
        designWidth = width;
        ApplyMetrics();
        Cursor = Cursors.Hand;
        MakeInteractive(AccessibleRole.Slider);
    }

    private void ApplyMetrics()
    {
        Width = Scaled(designWidth);
        Height = Scaled(24);
    }

    protected override void OnDpiChangedAfterParent(EventArgs e)
    {
        base.OnDpiChangedAfterParent(e);
        ApplyMetrics();
    }

    public double Value => value;

    private float Knob => Scaled(14f);

    private float Fraction => (float)((value - min) / (max - min));

    protected override void OnMouseDown(MouseEventArgs e)
    {
        // Nur die linke Taste zieht — ein Rechtsklick verstellt sonst den Wert.
        if (e.Button == MouseButtons.Left)
        {
            dragging = true;
            SetFromX(e.X);
        }
        base.OnMouseDown(e);
    }

    protected override void OnMouseUp(MouseEventArgs e) { dragging = false; base.OnMouseUp(e); }

    protected override void OnMouseMove(MouseEventArgs e)
    {
        if (dragging) SetFromX(e.X);
        base.OnMouseMove(e);
    }

    private void SetFromX(int x)
    {
        var knob = Knob;
        var travel = Width - knob;
        var fraction = Math.Clamp((x - knob / 2) / travel, 0, 1);
        SetValue(min + fraction * (max - min));
    }

    /// <summary>Wert auf das Raster runden und melden — für Maus und Tastatur.</summary>
    private void SetValue(double raw)
    {
        var snapped = Math.Clamp(Math.Round(raw / step) * step, min, max);
        if (Math.Abs(snapped - value) < step / 2) return;
        value = snapped;
        Invalidate();
        Changed?.Invoke(value);
    }

    protected override bool IsInputKey(Keys keyData)
        => keyData is Keys.Left or Keys.Right or Keys.Home or Keys.End || base.IsInputKey(keyData);

    protected override void OnKeyDown(KeyEventArgs e)
    {
        switch (e.KeyCode)
        {
            case Keys.Left: SetValue(value - step); break;
            case Keys.Right: SetValue(value + step); break;
            case Keys.Home: SetValue(min); break;
            case Keys.End: SetValue(max); break;
            default: base.OnKeyDown(e); return;
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

        var knob = Knob;
        var cy = Height / 2f;
        var trackRect = new RectangleF(knob / 2, cy - Scaled(2f), Width - knob, Scaled(4f));
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
        using (var knobBrush = new SolidBrush(Color.White))
            g.FillEllipse(knobBrush, knobX, cy - knob / 2, knob, knob);

        DrawFocusRing(g, new RectangleF(0.5f, 0.5f, Width - 1, Height - 1), Height / 2f);
    }
}

// MARK: - Chips (Wörterbuch-Begriffe)

/// <summary>
/// Begriffe als umbrechende Kapsel-„Chips" mit ✕ zum Löschen (Mac: FlowChips).
/// Layout und Klick-Zonen berechnet das Control selbst — bei hundert Begriffen
/// wären hundert Kind-Controls unnötig teuer.
/// </summary>
internal sealed class ChipFlow : ThemedControl, IAutoHeight
{
    private readonly List<string> terms = new();
    private readonly List<(RectangleF Chip, RectangleF Delete, string Term)> layout = new();
    private string? hovered;
    private int focused = -1;
    /// <summary>Breite, für die <see cref="layout"/> gilt (-1 = noch keine).</summary>
    private int layoutWidth = -1;

    public event Action<string>? Deleted;

    public ChipFlow()
    {
        Cursor = Cursors.Default;
        MakeInteractive(AccessibleRole.List);
    }

    public void SetTerms(IEnumerable<string> newTerms)
    {
        terms.Clear();
        terms.AddRange(newTerms);
        focused = Math.Min(focused, terms.Count - 1);
        layoutWidth = -1;
        Rebuild();
        Invalidate();
    }

    private int ChipHeight => Scaled(28);
    private int Gap => Scaled(7);

    private int ChipWidth(string term)
        => MeasureScaled(term, Theme.Body).Width + Scaled(22) + Scaled(16);   // Text + Polsterung + ✕

    /// <summary>
    /// Bricht die Chips für <paramref name="width"/> um und liefert die nötige Höhe.
    /// Höhe und Trefferflächen müssen aus derselben Rechnung kommen — sonst löscht
    /// ein Klick den Begriff daneben.
    /// </summary>
    private int Flow(int width, List<(RectangleF Chip, RectangleF Delete, string Term)>? into)
    {
        into?.Clear();
        if (width <= 0 || terms.Count == 0) return 0;

        var chipHeight = ChipHeight;
        var gap = Gap;
        var close = Scaled(16);
        float x = 0, y = 0;
        foreach (var term in terms)
        {
            var chipWidth = ChipWidth(term);
            if (x + chipWidth > width && x > 0)
            {
                x = 0;
                y += chipHeight + gap;
            }
            if (into != null)
            {
                var chip = new RectangleF(x, y, chipWidth, chipHeight);
                var del = new RectangleF(chip.Right - Scaled(22), y + (chipHeight - close) / 2f, close, close);
                into.Add((chip, del, term));
            }
            x += chipWidth + gap;
        }
        return (int)(y + chipHeight);
    }

    public int PreferredHeightFor(int width) => Flow(width, null);

    /// <summary>Chip-Positionen und eigene Höhe für die aktuelle Breite bestimmen.</summary>
    private void Rebuild()
    {
        layoutWidth = Width;
        Height = Flow(Width, layout);
    }

    protected override void OnLayout(LayoutEventArgs e)
    {
        base.OnLayout(e);
        // Nur bei echter Breitenänderung neu umbrechen: Rebuild setzt Height und
        // löst damit selbst wieder ein Layout aus.
        if (Width == layoutWidth) return;
        Rebuild();
        Invalidate();
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
        // Rechtsklick darf keinen Begriff löschen.
        if (e.Button != MouseButtons.Left)
        {
            base.OnMouseClick(e);
            return;
        }
        for (var i = 0; i < layout.Count; i++)
        {
            if (!layout[i].Delete.Contains(e.Location)) continue;
            focused = i;
            Deleted?.Invoke(layout[i].Term);
            break;
        }
        base.OnMouseClick(e);
    }

    protected override void OnGotFocus(EventArgs e)
    {
        if (focused < 0 && terms.Count > 0) MoveFocus(0);
        base.OnGotFocus(e);
    }

    private void MoveFocus(int index)
    {
        if (terms.Count == 0) return;
        focused = Math.Clamp(index, 0, terms.Count - 1);
        // Der Name wandert mit: sonst liest ein Screenreader immer denselben Begriff.
        AccessibleName = terms[focused];
        Invalidate();
    }

    protected override bool IsInputKey(Keys keyData)
        => keyData is Keys.Left or Keys.Right or Keys.Home or Keys.End or Keys.Delete
           || base.IsInputKey(keyData);

    protected override void OnKeyDown(KeyEventArgs e)
    {
        switch (e.KeyCode)
        {
            case Keys.Left: MoveFocus(focused - 1); break;
            case Keys.Right: MoveFocus(focused + 1); break;
            case Keys.Home: MoveFocus(0); break;
            case Keys.End: MoveFocus(terms.Count - 1); break;
            case Keys.Delete:
            case Keys.Back:
            case Keys.Enter:
            case Keys.Space:
                if (focused >= 0 && focused < terms.Count) Deleted?.Invoke(terms[focused]);
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

        for (var i = 0; i < layout.Count; i++)
        {
            var (chip, del, term) = layout[i];
            Theme.DrawCapsule(g, chip, Theme.Track, Theme.CardBorder);
            DrawText(g, term, Theme.Body, Theme.Gray(0.9),
                     new Rectangle((int)chip.X + Scaled(11), (int)chip.Y,
                                   (int)chip.Width - Scaled(30), ChipHeight),
                     TextFormatFlags.VerticalCenter | TextFormatFlags.NoPrefix);
            Icons.Draw(g, Icons.Kind.Close, del,
                       term == hovered ? Theme.Live : Theme.Gray(0.5), Scaled(9f));
            if (i == focused)
                DrawFocusRing(g, new RectangleF(chip.X + 0.5f, chip.Y + 0.5f, chip.Width - 1, chip.Height - 1),
                              chip.Height / 2f);
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
        ApplyMetrics();
    }

    private void ApplyMetrics() => Height = Scaled(84);

    protected override void OnDpiChangedAfterParent(EventArgs e)
    {
        base.OnDpiChangedAfterParent(e);
        ApplyMetrics();
    }

    protected override void OnPaint(PaintEventArgs e)
    {
        var g = e.Graphics;
        Theme.Smooth(g);
        using (var bg = new SolidBrush(Theme.Window)) g.FillRectangle(bg, ClientRectangle);
        Theme.DrawCard(g, new RectangleF(0, 0, Width, Height), Scaled(12f));

        var pad = Scaled(16);
        DrawText(g, value, Theme.Metric, Theme.Gray(0.95),
                 new Rectangle(pad, Scaled(12), Width - pad * 2, Scaled(38)),
                 TextFormatFlags.NoPrefix | TextFormatFlags.NoClipping);
        DrawText(g, label, Theme.Help, Theme.Gray(0.55),
                 new Rectangle(pad, Scaled(54), Width - pad * 2, Scaled(18)),
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
        ApplyMetrics();
    }

    private void ApplyMetrics() => Height = Scaled(76);

    protected override void OnDpiChangedAfterParent(EventArgs e)
    {
        base.OnDpiChangedAfterParent(e);
        ApplyMetrics();
    }

    protected override void OnPaint(PaintEventArgs e)
    {
        var g = e.Graphics;
        Theme.Smooth(g);
        using (var bg = new SolidBrush(Theme.Window)) g.FillRectangle(bg, ClientRectangle);
        Theme.DrawCard(g, new RectangleF(0, 0, Width, Height), Scaled(12f));

        var pad = Scaled(16);
        Theme.DrawTracked(g, title.ToUpperInvariant(), Theme.SectionLabel, Theme.Gray(0.5),
                          new PointF(pad, Scaled(14)), Scaled(0.4f));
        DrawText(g, value, Theme.InfoValue, Theme.Gray(0.92),
                 new Rectangle(pad, Scaled(36), Width - pad * 2, Scaled(26)),
                 TextFormatFlags.NoPrefix | TextFormatFlags.EndEllipsis);
    }
}
