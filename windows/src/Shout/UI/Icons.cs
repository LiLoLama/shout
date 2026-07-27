using System.Drawing.Drawing2D;

namespace Shout.UI;

/// <summary>
/// Die SF-Symbols der Mac-App als GDI+-Vektoren nachgezeichnet. Bewusst kein
/// Icon-Font (Segoe MDL2 ist je Windows-Version unterschiedlich bestückt —
/// fehlende Glyphen erscheinen als Kästchen) und keine Bild-Assets.
///
/// Jede Methode zeichnet in ein quadratisches Feld; `size` ist die Kantenlänge,
/// die Strichstärke skaliert mit. Zentriert wird über <see cref="Draw"/>.
/// </summary>
internal static class Icons
{
    public enum Kind
    {
        Mic, Book, History, Chart, Chip, Sync, Heart, Check, Close, Trash, Copy,
        Insert, ArrowRight, Sparkle, Warning, Refresh, Plus, Code, Coffee, Lock, LockOpen, Branch,
    }

    /// <summary>Zeichnet das Icon zentriert in <paramref name="box"/>.</summary>
    public static void Draw(Graphics g, Kind kind, RectangleF box, Color color, float size)
    {
        var s = size;
        var x = box.X + (box.Width - s) / 2f;
        var y = box.Y + (box.Height - s) / 2f;
        var r = new RectangleF(x, y, s, s);

        var old = g.SmoothingMode;
        g.SmoothingMode = SmoothingMode.AntiAlias;
        switch (kind)
        {
            case Kind.Mic: Mic(g, r, color); break;
            case Kind.Book: Book(g, r, color); break;
            case Kind.History: History(g, r, color); break;
            case Kind.Chart: Chart(g, r, color); break;
            case Kind.Chip: Chip(g, r, color); break;
            case Kind.Sync: Sync(g, r, color); break;
            case Kind.Heart: Heart(g, r, color); break;
            case Kind.Check: Check(g, r, color); break;
            case Kind.Close: Close(g, r, color); break;
            case Kind.Trash: Trash(g, r, color); break;
            case Kind.Copy: Copy(g, r, color); break;
            case Kind.Insert: Insert(g, r, color); break;
            case Kind.ArrowRight: ArrowRight(g, r, color); break;
            case Kind.Sparkle: Sparkle(g, r, color); break;
            case Kind.Warning: Warning(g, r, color); break;
            case Kind.Refresh: Refresh(g, r, color); break;
            case Kind.Plus: Plus(g, r, color); break;
            case Kind.Code: Code(g, r, color); break;
            case Kind.Coffee: Coffee(g, r, color); break;
            case Kind.Lock: Lock(g, r, color, closed: true); break;
            case Kind.LockOpen: Lock(g, r, color, closed: false); break;
            case Kind.Branch: Branch(g, r, color); break;
        }
        g.SmoothingMode = old;
    }

    private static Pen Stroke(Color c, float size, float weight = 0.11f) =>
        new(c, Math.Max(1.1f, size * weight)) { StartCap = LineCap.Round, EndCap = LineCap.Round, LineJoin = LineJoin.Round };

    // MARK: Einzelne Symbole

    /// mic.fill — Kapsel-Kapsel mit Bügel und Fuß.
    private static void Mic(Graphics g, RectangleF r, Color c)
    {
        using var brush = new SolidBrush(c);
        using var pen = Stroke(c, r.Width, 0.10f);
        var capW = r.Width * 0.34f;
        var capH = r.Height * 0.50f;
        var cap = new RectangleF(r.X + (r.Width - capW) / 2f, r.Y + r.Height * 0.06f, capW, capH);
        using var capsule = Theme.Capsule(cap);
        g.FillPath(brush, capsule);
        // Bügel
        var arc = new RectangleF(r.X + r.Width * 0.20f, r.Y + r.Height * 0.34f, r.Width * 0.60f, r.Height * 0.42f);
        g.DrawArc(pen, arc, 0, 180);
        // Fuß
        var cx = r.X + r.Width / 2f;
        g.DrawLine(pen, cx, r.Y + r.Height * 0.76f, cx, r.Y + r.Height * 0.93f);
    }

    /// text.book.closed.fill — geschlossenes Buch mit Rücken.
    private static void Book(Graphics g, RectangleF r, Color c)
    {
        using var brush = new SolidBrush(c);
        var body = new RectangleF(r.X + r.Width * 0.16f, r.Y + r.Height * 0.10f, r.Width * 0.68f, r.Height * 0.80f);
        using var path = Theme.Rounded(body, r.Width * 0.10f);
        g.FillPath(brush, path);
        // Rücken als Aussparung
        using var spine = new SolidBrush(Color.FromArgb(90, 0, 0, 0));
        g.FillRectangle(spine, r.X + r.Width * 0.16f, r.Y + r.Height * 0.10f, r.Width * 0.13f, r.Height * 0.80f);
        // Seiten-Striche
        using var line = new Pen(Color.FromArgb(120, 0, 0, 0), Math.Max(1f, r.Width * 0.06f));
        for (var i = 0; i < 2; i++)
        {
            var y = r.Y + r.Height * (0.36f + i * 0.20f);
            g.DrawLine(line, r.X + r.Width * 0.40f, y, r.X + r.Width * 0.72f, y);
        }
    }

    /// clock.arrow.circlepath — Uhr mit Zeigern.
    private static void History(Graphics g, RectangleF r, Color c)
    {
        using var pen = Stroke(c, r.Width, 0.10f);
        var dial = new RectangleF(r.X + r.Width * 0.10f, r.Y + r.Height * 0.10f, r.Width * 0.80f, r.Height * 0.80f);
        // offener Kreis (Lücke oben rechts, wie das Rücklauf-Symbol)
        g.DrawArc(pen, dial, 300, 320);
        // Rücklauf-Pfeilspitze
        var tipX = dial.Right - dial.Width * 0.14f;
        var tipY = dial.Y + dial.Height * 0.10f;
        g.DrawLine(pen, tipX, tipY, tipX - r.Width * 0.14f, tipY - r.Height * 0.02f);
        g.DrawLine(pen, tipX, tipY, tipX + r.Width * 0.02f, tipY + r.Height * 0.14f);
        // Zeiger
        var cx = dial.X + dial.Width / 2f;
        var cy = dial.Y + dial.Height / 2f;
        g.DrawLine(pen, cx, cy, cx, cy - dial.Height * 0.26f);
        g.DrawLine(pen, cx, cy, cx + dial.Width * 0.20f, cy);
    }

    /// chart.bar.xaxis — drei Balken auf einer Achse.
    private static void Chart(Graphics g, RectangleF r, Color c)
    {
        using var brush = new SolidBrush(c);
        using var pen = Stroke(c, r.Width, 0.10f);
        var baseY = r.Y + r.Height * 0.82f;
        var w = r.Width * 0.17f;
        float[] heights = { 0.30f, 0.52f, 0.40f };
        for (var i = 0; i < 3; i++)
        {
            var h = r.Height * heights[i];
            var x = r.X + r.Width * (0.18f + i * 0.26f);
            var bar = new RectangleF(x, baseY - h, w, h);
            using var path = Theme.Rounded(bar, w * 0.35f);
            g.FillPath(brush, path);
        }
        g.DrawLine(pen, r.X + r.Width * 0.10f, baseY + r.Height * 0.06f, r.Right - r.Width * 0.10f, baseY + r.Height * 0.06f);
    }

    /// cpu — Quadrat mit Kern und Beinchen.
    private static void Chip(Graphics g, RectangleF r, Color c)
    {
        using var pen = Stroke(c, r.Width, 0.09f);
        using var brush = new SolidBrush(c);
        var body = new RectangleF(r.X + r.Width * 0.24f, r.Y + r.Height * 0.24f, r.Width * 0.52f, r.Height * 0.52f);
        using var path = Theme.Rounded(body, r.Width * 0.08f);
        g.DrawPath(pen, path);
        var core = new RectangleF(body.X + body.Width * 0.28f, body.Y + body.Height * 0.28f,
                                  body.Width * 0.44f, body.Height * 0.44f);
        using var corePath = Theme.Rounded(core, r.Width * 0.04f);
        g.FillPath(brush, corePath);
        // Beinchen an allen vier Seiten
        for (var i = 0; i < 2; i++)
        {
            var t = 0.40f + i * 0.20f;
            var px = r.X + r.Width * t;
            var py = r.Y + r.Height * t;
            g.DrawLine(pen, px, r.Y + r.Height * 0.10f, px, body.Y);              // oben
            g.DrawLine(pen, px, body.Bottom, px, r.Bottom - r.Height * 0.10f);    // unten
            g.DrawLine(pen, r.X + r.Width * 0.10f, py, body.X, py);               // links
            g.DrawLine(pen, body.Right, py, r.Right - r.Width * 0.10f, py);       // rechts
        }
    }

    /// arrow.triangle.2.circlepath — zwei Kreisbögen mit Pfeilspitzen.
    private static void Sync(Graphics g, RectangleF r, Color c)
    {
        using var pen = Stroke(c, r.Width, 0.10f);
        using var brush = new SolidBrush(c);
        var dial = new RectangleF(r.X + r.Width * 0.12f, r.Y + r.Height * 0.12f, r.Width * 0.76f, r.Height * 0.76f);
        g.DrawArc(pen, dial, 20, 140);
        g.DrawArc(pen, dial, 200, 140);
        var a = r.Width * 0.13f;
        // Spitze rechts unten
        g.FillPolygon(brush, new[]
        {
            new PointF(dial.Right - a * 0.2f, dial.Y + dial.Height * 0.70f),
            new PointF(dial.Right - a * 1.4f, dial.Y + dial.Height * 0.78f),
            new PointF(dial.Right - a * 0.5f, dial.Y + dial.Height * 0.95f),
        });
        // Spitze links oben
        g.FillPolygon(brush, new[]
        {
            new PointF(dial.X + a * 0.2f, dial.Y + dial.Height * 0.30f),
            new PointF(dial.X + a * 1.4f, dial.Y + dial.Height * 0.22f),
            new PointF(dial.X + a * 0.5f, dial.Y + dial.Height * 0.05f),
        });
    }

    /// heart.fill — zwei Bögen plus Spitze.
    private static void Heart(Graphics g, RectangleF r, Color c)
    {
        using var brush = new SolidBrush(c);
        using var path = new GraphicsPath();
        var cx = r.X + r.Width / 2f;
        var top = r.Y + r.Height * 0.26f;
        var bottom = r.Y + r.Height * 0.90f;
        path.AddBezier(cx, bottom, r.X + r.Width * 0.03f, r.Y + r.Height * 0.52f,
                       r.X + r.Width * 0.16f, r.Y + r.Height * 0.06f, cx, top);
        path.AddBezier(cx, top, r.X + r.Width * 0.84f, r.Y + r.Height * 0.06f,
                       r.X + r.Width * 0.97f, r.Y + r.Height * 0.52f, cx, bottom);
        path.CloseFigure();
        g.FillPath(brush, path);
    }

    private static void Check(Graphics g, RectangleF r, Color c)
    {
        using var pen = Stroke(c, r.Width, 0.15f);
        g.DrawLines(pen, new[]
        {
            new PointF(r.X + r.Width * 0.18f, r.Y + r.Height * 0.53f),
            new PointF(r.X + r.Width * 0.41f, r.Y + r.Height * 0.75f),
            new PointF(r.X + r.Width * 0.83f, r.Y + r.Height * 0.27f),
        });
    }

    private static void Close(Graphics g, RectangleF r, Color c)
    {
        using var pen = Stroke(c, r.Width, 0.15f);
        g.DrawLine(pen, r.X + r.Width * 0.22f, r.Y + r.Height * 0.22f, r.Right - r.Width * 0.22f, r.Bottom - r.Height * 0.22f);
        g.DrawLine(pen, r.Right - r.Width * 0.22f, r.Y + r.Height * 0.22f, r.X + r.Width * 0.22f, r.Bottom - r.Height * 0.22f);
    }

    private static void Trash(Graphics g, RectangleF r, Color c)
    {
        using var pen = Stroke(c, r.Width, 0.10f);
        var lid = r.Y + r.Height * 0.26f;
        g.DrawLine(pen, r.X + r.Width * 0.14f, lid, r.Right - r.Width * 0.14f, lid);
        g.DrawLine(pen, r.X + r.Width * 0.38f, lid, r.X + r.Width * 0.38f, r.Y + r.Height * 0.14f);
        g.DrawLine(pen, r.X + r.Width * 0.62f, lid, r.X + r.Width * 0.62f, r.Y + r.Height * 0.14f);
        g.DrawLine(pen, r.X + r.Width * 0.38f, r.Y + r.Height * 0.14f, r.X + r.Width * 0.62f, r.Y + r.Height * 0.14f);
        // Korpus
        g.DrawLines(pen, new[]
        {
            new PointF(r.X + r.Width * 0.22f, lid),
            new PointF(r.X + r.Width * 0.28f, r.Bottom - r.Height * 0.10f),
            new PointF(r.Right - r.Width * 0.28f, r.Bottom - r.Height * 0.10f),
            new PointF(r.Right - r.Width * 0.22f, lid),
        });
    }

    private static void Copy(Graphics g, RectangleF r, Color c)
    {
        using var pen = Stroke(c, r.Width, 0.10f);
        var back = new RectangleF(r.X + r.Width * 0.14f, r.Y + r.Height * 0.14f, r.Width * 0.52f, r.Height * 0.52f);
        var front = new RectangleF(r.X + r.Width * 0.34f, r.Y + r.Height * 0.34f, r.Width * 0.52f, r.Height * 0.52f);
        using var p1 = Theme.Rounded(back, r.Width * 0.09f);
        using var p2 = Theme.Rounded(front, r.Width * 0.09f);
        g.DrawPath(pen, p1);
        g.DrawPath(pen, p2);
    }

    /// arrow.down.doc — Pfeil nach unten in ein Feld (am Cursor einfügen).
    private static void Insert(Graphics g, RectangleF r, Color c)
    {
        using var pen = Stroke(c, r.Width, 0.11f);
        using var brush = new SolidBrush(c);
        var cx = r.X + r.Width / 2f;
        g.DrawLine(pen, cx, r.Y + r.Height * 0.10f, cx, r.Y + r.Height * 0.52f);
        g.FillPolygon(brush, new[]
        {
            new PointF(cx, r.Y + r.Height * 0.68f),
            new PointF(cx - r.Width * 0.17f, r.Y + r.Height * 0.44f),
            new PointF(cx + r.Width * 0.17f, r.Y + r.Height * 0.44f),
        });
        g.DrawLines(pen, new[]
        {
            new PointF(r.X + r.Width * 0.16f, r.Y + r.Height * 0.72f),
            new PointF(r.X + r.Width * 0.16f, r.Bottom - r.Height * 0.12f),
            new PointF(r.Right - r.Width * 0.16f, r.Bottom - r.Height * 0.12f),
            new PointF(r.Right - r.Width * 0.16f, r.Y + r.Height * 0.72f),
        });
    }

    private static void ArrowRight(Graphics g, RectangleF r, Color c)
    {
        using var pen = Stroke(c, r.Width, 0.12f);
        var y = r.Y + r.Height / 2f;
        g.DrawLine(pen, r.X + r.Width * 0.16f, y, r.Right - r.Width * 0.22f, y);
        g.DrawLines(pen, new[]
        {
            new PointF(r.Right - r.Width * 0.44f, y - r.Height * 0.22f),
            new PointF(r.Right - r.Width * 0.18f, y),
            new PointF(r.Right - r.Width * 0.44f, y + r.Height * 0.22f),
        });
    }

    /// sparkles — ein großer, ein kleiner Vier-Zack-Stern.
    private static void Sparkle(Graphics g, RectangleF r, Color c)
    {
        using var brush = new SolidBrush(c);
        void Star(float cx, float cy, float radius)
        {
            using var path = new GraphicsPath();
            var inner = radius * 0.32f;
            var pts = new PointF[8];
            for (var i = 0; i < 8; i++)
            {
                var angle = -Math.PI / 2 + i * Math.PI / 4;
                var rad = i % 2 == 0 ? radius : inner;
                pts[i] = new PointF(cx + (float)(Math.Cos(angle) * rad), cy + (float)(Math.Sin(angle) * rad));
            }
            path.AddPolygon(pts);
            g.FillPath(brush, path);
        }
        Star(r.X + r.Width * 0.40f, r.Y + r.Height * 0.42f, r.Width * 0.34f);
        Star(r.X + r.Width * 0.78f, r.Y + r.Height * 0.76f, r.Width * 0.17f);
    }

    private static void Warning(Graphics g, RectangleF r, Color c)
    {
        using var brush = new SolidBrush(c);
        using var path = new GraphicsPath();
        path.AddPolygon(new[]
        {
            new PointF(r.X + r.Width / 2f, r.Y + r.Height * 0.10f),
            new PointF(r.Right - r.Width * 0.06f, r.Bottom - r.Height * 0.14f),
            new PointF(r.X + r.Width * 0.06f, r.Bottom - r.Height * 0.14f),
        });
        g.FillPath(brush, path);
        // Ausrufezeichen als Aussparung
        using var dark = new SolidBrush(Color.FromArgb(200, 0, 0, 0));
        var cx = r.X + r.Width / 2f;
        var w = Math.Max(1.2f, r.Width * 0.09f);
        g.FillRectangle(dark, cx - w / 2f, r.Y + r.Height * 0.38f, w, r.Height * 0.28f);
        g.FillEllipse(dark, cx - w / 2f, r.Y + r.Height * 0.72f, w, w);
    }

    private static void Refresh(Graphics g, RectangleF r, Color c)
    {
        using var pen = Stroke(c, r.Width, 0.11f);
        using var brush = new SolidBrush(c);
        var dial = new RectangleF(r.X + r.Width * 0.14f, r.Y + r.Height * 0.14f, r.Width * 0.72f, r.Height * 0.72f);
        g.DrawArc(pen, dial, 60, 280);
        var a = r.Width * 0.15f;
        g.FillPolygon(brush, new[]
        {
            new PointF(dial.Right - a * 0.1f, dial.Y + dial.Height * 0.16f),
            new PointF(dial.Right - a * 1.3f, dial.Y + dial.Height * 0.02f),
            new PointF(dial.Right + a * 0.2f, dial.Y - dial.Height * 0.06f),
        });
    }

    private static void Plus(Graphics g, RectangleF r, Color c)
    {
        using var pen = Stroke(c, r.Width, 0.14f);
        var cx = r.X + r.Width / 2f;
        var cy = r.Y + r.Height / 2f;
        g.DrawLine(pen, cx, r.Y + r.Height * 0.20f, cx, r.Bottom - r.Height * 0.20f);
        g.DrawLine(pen, r.X + r.Width * 0.20f, cy, r.Right - r.Width * 0.20f, cy);
    }

    /// chevron.left.forwardslash.chevron.right — Quellcode.
    private static void Code(Graphics g, RectangleF r, Color c)
    {
        using var pen = Stroke(c, r.Width, 0.12f);
        g.DrawLines(pen, new[]
        {
            new PointF(r.X + r.Width * 0.32f, r.Y + r.Height * 0.26f),
            new PointF(r.X + r.Width * 0.10f, r.Y + r.Height / 2f),
            new PointF(r.X + r.Width * 0.32f, r.Bottom - r.Height * 0.26f),
        });
        g.DrawLines(pen, new[]
        {
            new PointF(r.Right - r.Width * 0.32f, r.Y + r.Height * 0.26f),
            new PointF(r.Right - r.Width * 0.10f, r.Y + r.Height / 2f),
            new PointF(r.Right - r.Width * 0.32f, r.Bottom - r.Height * 0.26f),
        });
        g.DrawLine(pen, r.X + r.Width * 0.58f, r.Y + r.Height * 0.20f, r.X + r.Width * 0.42f, r.Bottom - r.Height * 0.20f);
    }

    /// cup.and.saucer.fill — Unterstützen.
    private static void Coffee(Graphics g, RectangleF r, Color c)
    {
        using var brush = new SolidBrush(c);
        using var pen = Stroke(c, r.Width, 0.10f);
        var cup = new RectangleF(r.X + r.Width * 0.16f, r.Y + r.Height * 0.26f, r.Width * 0.50f, r.Height * 0.42f);
        using var path = new GraphicsPath();
        path.AddArc(cup.X, cup.Y, cup.Width, cup.Height * 1.1f, 0, 180);
        path.AddLine(cup.X, cup.Y, cup.Right, cup.Y);
        path.CloseFigure();
        g.FillPath(brush, path);
        // Henkel
        g.DrawArc(pen, cup.Right - cup.Width * 0.08f, cup.Y + cup.Height * 0.08f,
                  cup.Width * 0.42f, cup.Height * 0.52f, 280, 180);
        // Untertasse
        g.FillRectangle(brush, r.X + r.Width * 0.10f, r.Bottom - r.Height * 0.20f, r.Width * 0.70f, Math.Max(1.4f, r.Height * 0.08f));
    }

    private static void Lock(Graphics g, RectangleF r, Color c, bool closed)
    {
        using var brush = new SolidBrush(c);
        using var pen = Stroke(c, r.Width, 0.10f);
        var body = new RectangleF(r.X + r.Width * 0.20f, r.Y + r.Height * 0.46f, r.Width * 0.60f, r.Height * 0.42f);
        using var path = Theme.Rounded(body, r.Width * 0.10f);
        g.FillPath(brush, path);
        var shackle = closed
            ? new RectangleF(r.X + r.Width * 0.32f, r.Y + r.Height * 0.14f, r.Width * 0.36f, r.Height * 0.40f)
            : new RectangleF(r.X + r.Width * 0.42f, r.Y + r.Height * 0.14f, r.Width * 0.36f, r.Height * 0.40f);
        g.DrawArc(pen, shackle, 180, closed ? 180 : 140);
    }

    /// arrow.triangle.branch — aktiv gepflegt.
    private static void Branch(Graphics g, RectangleF r, Color c)
    {
        using var pen = Stroke(c, r.Width, 0.10f);
        using var brush = new SolidBrush(c);
        var x = r.X + r.Width * 0.28f;
        g.DrawLine(pen, x, r.Y + r.Height * 0.18f, x, r.Bottom - r.Height * 0.18f);
        g.FillEllipse(brush, x - r.Width * 0.09f, r.Y + r.Height * 0.10f, r.Width * 0.18f, r.Width * 0.18f);
        g.FillEllipse(brush, x - r.Width * 0.09f, r.Bottom - r.Height * 0.28f, r.Width * 0.18f, r.Width * 0.18f);
        // Abzweig nach rechts oben
        using var branch = new GraphicsPath();
        branch.AddBezier(x, r.Y + r.Height * 0.62f,
                         r.X + r.Width * 0.58f, r.Y + r.Height * 0.62f,
                         r.X + r.Width * 0.70f, r.Y + r.Height * 0.50f,
                         r.X + r.Width * 0.70f, r.Y + r.Height * 0.30f);
        g.DrawPath(pen, branch);
        g.FillEllipse(brush, r.X + r.Width * 0.61f, r.Y + r.Height * 0.12f, r.Width * 0.18f, r.Width * 0.18f);
    }
}
