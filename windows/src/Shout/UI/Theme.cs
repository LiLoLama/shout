using System.Drawing.Drawing2D;

namespace Shout.UI;

/// <summary>
/// Farbwelt und Typografie der Mac-App (Theme.swift + ConsoleUI.swift), 1:1 nach
/// Windows übertragen. SwiftUI rechnet in Punkten bei 72 dpi, GDI+ in typo-
/// grafischen Punkten bei 96 dpi — Mac-Größe × 0,75 ergibt dieselbe Optik.
/// </summary>
internal static class Theme
{
    // MARK: Farben (identische Werte wie Theme.swift / ConsoleUI.swift)

    /// „live"-Signalfarbe — Aufnahme, aktive Schalter, Akzente.
    public static readonly Color Live = Color.FromArgb(255, 74, 10);
    /// Fenster-Hintergrund (dunkler als die Karten, damit sie sich abheben).
    public static readonly Color Window = Color.FromArgb(27, 27, 32);
    /// Seitenleiste (noch etwas dunkler als das Fenster).
    public static readonly Color Sidebar = Color.FromArgb(22, 22, 26);
    /// Karten-Fläche, die zusammengehörige Einstellungen bündelt.
    public static readonly Color Card = Color.FromArgb(42, 42, 42);
    /// Vertiefte Flächen: Schalter-Bahnen, Eingabefelder, Tastenkappen.
    public static readonly Color Track = Color.FromArgb(28, 28, 28);
    /// Aktives Feld im Segment-Umschalter.
    public static readonly Color SegActive = Color.FromArgb(69, 69, 69);
    /// Flacher Knopf.
    public static readonly Color Button = Color.FromArgb(56, 56, 56);

    public static readonly Color Ink = Color.FromArgb(240, 240, 240);
    public static readonly Color InkMuted = Color.FromArgb(153, 153, 153);
    public static readonly Color InkFaint = Color.FromArgb(115, 115, 115);

    /// Karten-/Kapsel-Rand: Weiß mit 7 % Deckkraft.
    public static readonly Color CardBorder = Color.FromArgb(18, 255, 255, 255);
    /// Trennlinie innerhalb einer Karte: Weiß mit 6 %.
    public static readonly Color Divider = Color.FromArgb(15, 255, 255, 255);

    /// Weiß mit beliebiger Deckkraft (wie `Color.white.opacity(x)`).
    public static Color White(double opacity) =>
        Color.FromArgb((int)Math.Round(opacity * 255), 255, 255, 255);

    /// Grauwert wie SwiftUIs `Color(white: x)`.
    public static Color Gray(double white)
    {
        var v = (int)Math.Round(white * 255);
        return Color.FromArgb(v, v, v);
    }

    /// Signalfarbe mit Deckkraft (für Badges und aktive Navigationszeilen).
    public static Color LiveAlpha(double opacity) =>
        Color.FromArgb((int)Math.Round(opacity * 255), Live);

    // MARK: Schriften

    private const string Family = "Segoe UI";
    private const string Mono = "Consolas";

    public static readonly Font Wordmark = new(Family, 17.25f, FontStyle.Bold);
    public static readonly Font PageTitle = new(Family, 11.25f, FontStyle.Bold);
    public static readonly Font SectionLabel = new(Family, 8.25f, FontStyle.Bold);
    public static readonly Font RowTitle = new(Family, 10f, FontStyle.Regular);
    public static readonly Font RowTitleStrong = new(Family, 10f, FontStyle.Bold);
    public static readonly Font Body = new(Family, 9.75f, FontStyle.Regular);
    public static readonly Font Help = new(Family, 8.25f, FontStyle.Regular);
    public static readonly Font Small = new(Family, 9f, FontStyle.Regular);
    public static readonly Font Badge = new(Family, 7.5f, FontStyle.Bold);
    public static readonly Font ButtonText = new(Family, 9f, FontStyle.Regular);
    public static readonly Font Metric = new(Family, 21f, FontStyle.Bold);
    public static readonly Font MetricSmall = new(Family, 18f, FontStyle.Bold);
    public static readonly Font InfoValue = new(Family, 12.75f, FontStyle.Regular);
    public static readonly Font Keycap = new(Mono, 9.5f, FontStyle.Regular);
    public static readonly Font MonoSmall = new(Mono, 9f, FontStyle.Regular);

    // MARK: Geometrie

    /// Abgerundetes Rechteck als Pfad (Karten: Radius 12, Felder: 8, Knöpfe: 7).
    public static GraphicsPath Rounded(RectangleF r, float radius)
    {
        var path = new GraphicsPath();
        var d = Math.Min(radius * 2, Math.Min(r.Width, r.Height));
        if (d <= 0)
        {
            path.AddRectangle(r);
            return path;
        }
        path.AddArc(r.X, r.Y, d, d, 180, 90);
        path.AddArc(r.Right - d, r.Y, d, d, 270, 90);
        path.AddArc(r.Right - d, r.Bottom - d, d, d, 0, 90);
        path.AddArc(r.X, r.Bottom - d, d, d, 90, 90);
        path.CloseFigure();
        return path;
    }

    /// Kapsel (voll abgerundet) — Pille, Chips, Badges.
    public static GraphicsPath Capsule(RectangleF r) => Rounded(r, r.Height / 2f);

    /// Füllt eine Karte samt 1-px-Rand (halbe Pixel Einzug, damit der Rand scharf bleibt).
    public static void DrawCard(Graphics g, RectangleF bounds, float radius = 12f)
    {
        var r = new RectangleF(bounds.X + 0.5f, bounds.Y + 0.5f, bounds.Width - 1, bounds.Height - 1);
        using var path = Rounded(r, radius);
        using var fill = new SolidBrush(Card);
        using var pen = new Pen(CardBorder);
        g.FillPath(fill, path);
        g.DrawPath(pen, path);
    }

    /// Gefüllte Kapsel mit Rand (Chips, Badges).
    public static void DrawCapsule(Graphics g, RectangleF bounds, Color fillColor, Color? border = null)
    {
        var r = new RectangleF(bounds.X + 0.5f, bounds.Y + 0.5f, bounds.Width - 1, bounds.Height - 1);
        using var path = Capsule(r);
        using var fill = new SolidBrush(fillColor);
        g.FillPath(fill, path);
        if (border is { } b)
        {
            using var pen = new Pen(b);
            g.DrawPath(pen, path);
        }
    }

    /// Weiche Kanten + gute Textdarstellung auf dunklem Grund.
    public static void Smooth(Graphics g)
    {
        g.SmoothingMode = SmoothingMode.AntiAlias;
        g.TextRenderingHint = System.Drawing.Text.TextRenderingHint.ClearTypeGridFit;
        g.InterpolationMode = InterpolationMode.HighQualityBicubic;
    }

    /// Zeichen exakt ohne seitliche Polsterung messen und zeichnen.
    private const TextFormatFlags Tight = TextFormatFlags.NoPadding | TextFormatFlags.NoPrefix;

    private static readonly Size MaxSize = new(int.MaxValue, int.MaxValue);

    /// Breite eines Zeichens. Ein einzelnes Leerzeichen misst GDI nicht zuverlässig
    /// (DT_CALCRECT schneidet es ab), daher über die Differenz zweier Messungen.
    private static int CharWidth(char ch, Font font)
        => ch != ' '
            ? TextRenderer.MeasureText(ch.ToString(), font, MaxSize, Tight).Width
            : TextRenderer.MeasureText("i i", font, MaxSize, Tight).Width
              - TextRenderer.MeasureText("ii", font, MaxSize, Tight).Width;

    /// Text mit Sperrung (SwiftUIs `.tracking`) — für die Abschnitts-Labels.
    public static void DrawTracked(Graphics g, string text, Font font, Color color, PointF at, float tracking)
    {
        var x = at.X;
        foreach (var ch in text)
        {
            if (ch != ' ')
                TextRenderer.DrawText(g, ch.ToString(), font,
                                      new Point((int)Math.Round(x), (int)at.Y), color, Tight);
            x += CharWidth(ch, font) + tracking;
        }
    }

    /// Breite eines gesperrten Textes (passend zu <see cref="DrawTracked"/>).
    public static float MeasureTracked(string text, Font font, float tracking)
    {
        float w = 0;
        foreach (var ch in text) w += CharWidth(ch, font) + tracking;
        return w;
    }

    /// Breite ohne seitliche Polsterung — für nahtlos aneinandergesetzte Teile
    /// wie die Wortmarke „shout" + „.".
    public static int MeasureTight(string text, Font font)
        => TextRenderer.MeasureText(text, font, MaxSize, Tight).Width;

    /// Text ohne seitliche Polsterung an eine exakte Position zeichnen.
    public static void DrawTight(Graphics g, string text, Font font, Color color, Point at)
        => TextRenderer.DrawText(g, text, font, at, color, Tight);

    /// Einzeiliger Text ohne Umbruch, links ausgerichtet.
    public static readonly StringFormat NoWrap = new(StringFormatFlags.NoWrap)
    {
        Trimming = StringTrimming.EllipsisCharacter,
        LineAlignment = StringAlignment.Near,
    };

    /// Umbrechender Text (Hilfetexte, Absätze).
    public static readonly StringFormat Wrap = new()
    {
        Trimming = StringTrimming.Word,
        LineAlignment = StringAlignment.Near,
    };

    /// Zentrierter Text (Knöpfe, Badges).
    public static readonly StringFormat Centered = new(StringFormatFlags.NoWrap)
    {
        Alignment = StringAlignment.Center,
        LineAlignment = StringAlignment.Center,
    };

    /// Höhe eines umbrechenden Textes bei gegebener Breite.
    public static int MeasureWrapped(Graphics g, string text, Font font, int width)
    {
        if (string.IsNullOrEmpty(text)) return 0;
        return (int)Math.Ceiling(g.MeasureString(text, font, width, Wrap).Height);
    }
}
