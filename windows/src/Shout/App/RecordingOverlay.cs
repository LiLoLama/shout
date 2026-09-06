using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;
using Shout.Core;
using Shout.UI;

namespace Shout.App;

/// <summary>
/// Die schwebende Pille — 1:1 die Gestaltung der Mac-App (RecordingIndicator.swift):
/// textlos, mit pegelreaktiver Wellenform. Vier Modi:
///  - Idle       — nur bei „Pille immer anzeigen"; klickbarer Mikrofon-Knopf.
///  - Armed      — erster Tipp im Doppeltipp-Modus erkannt, der zweite wird erwartet.
///  - Recording  — ✕ · Wellenform · ✓
///  - Processing — durchlaufende Sinus-Welle, bis der Text eingefügt ist.
///
/// Umsetzung als Layered Window (<c>UpdateLayeredWindow</c>) statt über eine
/// <c>Region</c>: nur so bekommt die Kapsel weiche Kanten und die durchscheinende
/// „Milchglas"-Fläche. WS_EX_NOACTIVATE hält den Tastaturfokus im Zielfenster —
/// sonst landet der Text hinterher an der falschen Stelle.
/// </summary>
public sealed class RecordingOverlay : Form
{
    public enum Phase { Idle, Armed, Recording, Processing }

    /// <summary>Klick auf den Mikrofon-Knopf der Idle-Pille.</summary>
    public event Action? OnStart;
    /// <summary>Klick auf ✕ — Aufnahme verwerfen.</summary>
    public event Action? OnCancel;
    /// <summary>Klick auf ✓ — Aufnahme beenden und einfügen.</summary>
    public event Action? OnSubmit;

    private Phase phase = Phase.Recording;
    private float level;
    private readonly float[] bars = new float[BarCount];
    private readonly System.Windows.Forms.Timer ticker = new() { Interval = 16 };   // ~60 fps
    private int frame;

    // MARK: Maße (Mac-Werte)

    private const int BarCount = 7;
    private static readonly float[] Weights = { 0.55f, 0.78f, 0.93f, 1.0f, 0.93f, 0.78f, 0.55f };
    private const float BarWidth = 2.8f;
    private const float BarGap = 2.5f;
    private const float MinBar = 2f;
    private const float MaxBar = 20f;
    private const int ButtonSize = 22;
    private const int EdgePadding = 10;
    private const int ScreenMargin = 14;   // Abstand zum Bildschirmrand

    /// <summary>
    /// Skaliert eine in Punkten gedachte Länge auf die Bildschirmauflösung. Ohne das
    /// war die Pille auf einem 200-%-Display halb so groß wie gedacht, und ihre
    /// Knöpfe waren 11 Pixel breite Ziele.
    /// </summary>
    private float S(float value) => value * DeviceDpi / 96f;

    private int Si(float value) => (int)Math.Round(S(value));

    private Size SizeFor(Phase p) => p switch
    {
        Phase.Idle or Phase.Armed => new Size(Si(46), Si(30)),
        Phase.Processing => new Size(Si(84), Si(28)),
        _ => new Size(Si(150), Si(34)),
    };

    public RecordingOverlay()
    {
        FormBorderStyle = FormBorderStyle.None;
        ShowInTaskbar = false;
        StartPosition = FormStartPosition.Manual;
        Size = SizeFor(Phase.Recording);
        // Kein WinForms-Hintergrund: gezeichnet wird ausschließlich per UpdateLayeredWindow.
        SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.Opaque, true);
        ticker.Tick += (_, _) => { frame++; Render(); };
    }

    /// <summary>WS_EX_LAYERED (Per-Pixel-Alpha) | NOACTIVATE (kein Fokus-Klau)
    /// | TOOLWINDOW (kein Alt-Tab-Eintrag) | TOPMOST.</summary>
    protected override CreateParams CreateParams
    {
        get
        {
            var cp = base.CreateParams;
            cp.ExStyle |= 0x00080000 | 0x08000000 | 0x00000080 | 0x00000008;
            return cp;
        }
    }

    protected override bool ShowWithoutActivation => true;

    // MARK: Steuerung

    public void ShowPhase(Phase newPhase)
    {
        var changed = phase != newPhase;
        phase = newPhase;
        if (changed || !Visible)
        {
            if (newPhase == Phase.Recording)
            {
                level = 0;
                Array.Clear(bars);
            }
            frame = 0;
            // Größe und Ort in einem Zug setzen: Getrennt zeichnete das OnResize
            // schon ein Bild mit neuer Größe an der alten Ecke — sichtbar als
            // Zucken beim Phasenwechsel.
            placing = true;
            Size = SizeFor(newPhase);
            MoveToAnchor();
            placing = false;
        }
        if (!Visible) Show();

        // Nur bewegte Zustände brauchen den Zeitgeber. Die Idle-Pille ist ein
        // stehendes Bild — sie 60-mal pro Sekunde neu zu bauen (Bitmap, HBITMAP,
        // zwei Gerätekontexte je Bild) lief bei „immer anzeigen" den ganzen Tag.
        if (newPhase is Phase.Recording or Phase.Processing or Phase.Armed) ticker.Start();
        else ticker.Stop();
        Render();
    }

    private bool placing;

    public void HideOverlay()
    {
        ticker.Stop();
        Hide();
    }

    /// <summary>Neuen Eingangspegel (0…1) einspeisen — geglättet wie am Mac.</summary>
    public void SetLevel(float newLevel)
    {
        level = level * 0.5f + newLevel * 0.5f;
    }

    /// <summary>Positioniert die Pille nach der gespeicherten Voreinstellung
    /// (oder dem frei gezogenen Punkt).</summary>
    public void MoveToAnchor()
    {
        var s = Settings.Shared;

        if (s.PillCustom)
        {
            // Der Anteil gilt relativ zum sichtbaren Bereich — so bleibt „unten
            // Mitte" auch dann unten Mitte, wenn ein breiter Monitor abgesteckt
            // wird. Absolut gespeichert klemmte die Position dort an den Rand.
            EnsureFraction(s);
            var host = HostScreen(s).WorkingArea;
            var center = new Point(
                (int)Math.Round(host.Left + s.PillFracX * host.Width),
                (int)Math.Round(host.Top + s.PillFracY * host.Height));
            var x = Math.Clamp(center.X - Width / 2, host.Left, Math.Max(host.Left, host.Right - Width));
            var y = Math.Clamp(center.Y - Height / 2, host.Top, Math.Max(host.Top, host.Bottom - Height));
            Location = new Point(x, y);
            return;
        }

        // Ohne freie Position: auf dem Bildschirm mit dem Mauszeiger ankern.
        var area = Screen.FromPoint(Cursor.Position).WorkingArea;
        var margin = Si(ScreenMargin);
        var left = s.PillAnchor switch
        {
            "bottomLeft" or "topLeft" => area.Left + margin,
            "bottomRight" or "topRight" => area.Right - Width - margin,
            _ => area.Left + (area.Width - Width) / 2,
        };
        var top = s.PillAnchor.StartsWith("top", StringComparison.Ordinal)
            ? area.Top + margin
            : area.Bottom - Height - margin;
        Location = new Point(left, top);
    }

    /// <summary>
    /// Der Bildschirm, auf dem die frei gezogene Position gilt: der gemerkte, solange
    /// er angeschlossen ist — sonst der unter dem Mauszeiger. Vorher richtete sich
    /// die Pille immer nach dem Mauszeiger und sprang damit auf den Schirm, auf dem
    /// man gerade arbeitete, statt dort zu bleiben, wo man sie hingezogen hat.
    /// </summary>
    private static Screen HostScreen(Settings s)
    {
        if (!string.IsNullOrEmpty(s.PillScreen))
            foreach (var screen in Screen.AllScreens)
                if (screen.DeviceName == s.PillScreen)
                    return screen;
        return Screen.FromPoint(Cursor.Position);
    }

    /// <summary>Rechnet eine noch absolut gespeicherte Position einmalig in den
    /// Anteil um.</summary>
    private static void EnsureFraction(Settings s)
    {
        if (s.PillFracX >= 0 && s.PillFracY >= 0) return;
        var host = Screen.FromPoint(new Point(s.PillCustomX, s.PillCustomY)).WorkingArea;
        s.PillFracX = host.Width > 0 ? (s.PillCustomX - host.Left) / (double)host.Width : 0.5;
        s.PillFracY = host.Height > 0 ? (s.PillCustomY - host.Top) / (double)host.Height : 0.95;
        s.Save();
    }

    // MARK: Zeichnen

    /// <summary>Baut das Pillen-Bild und schiebt es als Layered-Window-Inhalt
    /// ins Fenster (32 bpp mit vormultipliziertem Alpha).</summary>
    private void Render()
    {
        if (!Visible || placing || Width <= 0 || Height <= 0) return;

        using var bmp = new Bitmap(Width, Height, PixelFormat.Format32bppArgb);
        using (var g = Graphics.FromImage(bmp))
            PaintPill(g, new RectangleF(0, 0, Width, Height));
        PushLayered(bmp);
    }

    /// <summary>Zeichnet den aktuellen Zustand in einen Grafikkontext.</summary>
    private void PaintPill(Graphics g, RectangleF bounds)
    {
        g.Clear(Color.Transparent);
        Theme.Smooth(g);
        switch (phase)
        {
            case Phase.Idle: DrawIdle(g, bounds, pulsing: false); break;
            case Phase.Armed: DrawIdle(g, bounds, pulsing: true); break;
            case Phase.Recording: DrawRecording(g, bounds); break;
            case Phase.Processing: DrawProcessing(g, bounds); break;
        }
    }

    /// <summary>Die „Milchglas"-Kapsel: dunkle, halbtransparente Fläche mit einem
    /// zarten Lichtverlauf oben und feinem weißen Rand (wie ultraThinMaterial).</summary>
    private static void DrawCapsuleBackground(Graphics g, RectangleF bounds)
    {
        var r = new RectangleF(bounds.X + 0.5f, bounds.Y + 0.5f, bounds.Width - 1, bounds.Height - 1);
        using var path = Theme.Capsule(r);
        using (var fill = new LinearGradientBrush(
                   new PointF(r.X, r.Y), new PointF(r.X, r.Bottom),
                   Color.FromArgb(198, 52, 52, 58), Color.FromArgb(198, 32, 32, 37)))
        {
            g.FillPath(fill, path);
        }
        using var border = new Pen(Theme.White(0.10));
        g.DrawPath(border, path);
    }

    private void DrawIdle(Graphics g, RectangleF bounds, bool pulsing)
    {
        DrawCapsuleBackground(g, bounds);
        // „Gespannt" pulst sichtbar: Ohne diese Rückmeldung wüsste beim Doppeltipp
        // niemand, ob der erste Anschlag angekommen ist.
        var color = Theme.Live;
        if (pulsing)
        {
            var t = (Math.Sin(frame * 0.016 * 6.0) + 1) / 2;
            color = Color.FromArgb((int)Math.Round((0.35 + 0.65 * t) * 255), Theme.Live);
        }
        Icons.Draw(g, Icons.Kind.Mic, bounds, color, S(15f));
    }

    private void DrawRecording(Graphics g, RectangleF bounds)
    {
        DrawCapsuleBackground(g, bounds);

        var cy = bounds.Height / 2f;

        // ✕ links — Kreis mit Weiß-14-%-Füllung, hellgraues Zeichen.
        var cancel = CancelRect();
        using (var bg = new SolidBrush(Theme.White(0.14)))
            g.FillEllipse(bg, cancel);
        Icons.Draw(g, Icons.Kind.Close, cancel, Theme.Gray(0.75), S(9f));

        // ✓ rechts — gefüllter Signalfarben-Kreis, weißes Zeichen.
        var submit = SubmitRect();
        using (var bg = new SolidBrush(Theme.Live))
            g.FillEllipse(bg, submit);
        Icons.Draw(g, Icons.Kind.Check, submit, Color.White, S(11f));

        // Wellenform in der Mitte — Balkenhöhe folgt dem Pegel, je Balken gewichtet.
        using var brush = new SolidBrush(Theme.Live);
        float barWidth = S(BarWidth), barGap = S(BarGap), minBar = S(MinBar), maxBar = S(MaxBar);
        var totalWidth = BarCount * barWidth + (BarCount - 1) * barGap;
        var x = bounds.X + (bounds.Width - totalWidth) / 2f;
        for (var i = 0; i < BarCount; i++)
        {
            var target = minBar + (maxBar - minBar) * Math.Min(1f, level * Weights[i]);
            // Kurze Glättung je Balken (entspricht dem easeOut der Mac-Animation).
            bars[i] += (target - bars[i]) * 0.45f;
            var h = Math.Max(minBar, bars[i]);
            var bar = new RectangleF(x + i * (barWidth + barGap), cy - h / 2f, barWidth, h);
            using var capsule = Theme.Capsule(bar);
            g.FillPath(brush, capsule);
        }
    }

    private void DrawProcessing(Graphics g, RectangleF bounds)
    {
        DrawCapsuleBackground(g, bounds);

        var cy = bounds.Height / 2f;
        float barWidth = S(BarWidth), barGap = S(BarGap), minBar = S(MinBar), maxBar = S(MaxBar);
        var totalWidth = BarCount * barWidth + (BarCount - 1) * barGap;
        var x = bounds.X + (bounds.Width - totalWidth) / 2f;
        // Durchlaufende Welle: identische Parameter wie am Mac (t * 5.5 - i * 0.7).
        var t = frame * 0.016;
        for (var i = 0; i < BarCount; i++)
        {
            var phaseValue = Math.Sin(t * 5.5 - i * 0.7);
            var norm = (float)((phaseValue + 1) / 2);
            var h = minBar + (maxBar * 0.72f - minBar) * norm;
            using var brush = new SolidBrush(Color.FromArgb(
                (int)Math.Round((0.35 + 0.65 * norm) * 255), Theme.Live));
            var bar = new RectangleF(x + i * (barWidth + barGap), cy - h / 2f, barWidth, h);
            using var capsule = Theme.Capsule(bar);
            g.FillPath(brush, capsule);
        }
    }

    private RectangleF CancelRect() =>
        new(S(EdgePadding), (Height - S(ButtonSize)) / 2f, S(ButtonSize), S(ButtonSize));

    private RectangleF SubmitRect() =>
        new(Width - S(EdgePadding) - S(ButtonSize), (Height - S(ButtonSize)) / 2f,
            S(ButtonSize), S(ButtonSize));

    // MARK: Maus — Klick auf die Knöpfe, Ziehen verschiebt die Pille

    private Point dragStartScreen;
    private Point dragStartWindow;
    private bool pointerDown;
    private bool dragged;

    protected override void OnMouseDown(MouseEventArgs e)
    {
        // Fixiert: Klicks bleiben, Ziehen nicht. Sonst rückt ein Klick daneben
        // die Pille ungewollt weg.
        if (e.Button == MouseButtons.Left)
        {
            pointerDown = true;
            dragged = false;
            dragStartScreen = Cursor.Position;
            dragStartWindow = Location;
            Capture = true;
        }
        base.OnMouseDown(e);
    }

    protected override void OnMouseMove(MouseEventArgs e)
    {
        if (pointerDown)
        {
            var now = Cursor.Position;
            var dx = now.X - dragStartScreen.X;
            var dy = now.Y - dragStartScreen.Y;
            if (!dragged && !Settings.Shared.PillLocked && Math.Abs(dx) + Math.Abs(dy) > 3) dragged = true;
            if (dragged) Location = new Point(dragStartWindow.X + dx, dragStartWindow.Y + dy);
        }
        base.OnMouseMove(e);
    }

    protected override void OnMouseUp(MouseEventArgs e)
    {
        if (pointerDown && e.Button == MouseButtons.Left)
        {
            pointerDown = false;
            Capture = false;

            if (dragged)
            {
                // Auf den sichtbaren Bereich klemmen und die Mitte als freie Position sichern.
                var area = Screen.FromRectangle(Bounds).WorkingArea;
                var x = Math.Clamp(Location.X, area.Left, Math.Max(area.Left, area.Right - Width));
                var y = Math.Clamp(Location.Y, area.Top, Math.Max(area.Top, area.Bottom - Height));
                Location = new Point(x, y);

                var s = Settings.Shared;
                s.PillCustom = true;
                s.PillFracX = area.Width > 0 ? (x + Width / 2.0 - area.Left) / area.Width : 0.5;
                s.PillFracY = area.Height > 0 ? (y + Height / 2.0 - area.Top) / area.Height : 0.95;
                // Den Bildschirm mitschreiben, sonst gilt der Anteil beim nächsten Mal
                // für den Schirm unter dem Mauszeiger.
                s.PillScreen = Screen.FromRectangle(Bounds).DeviceName;
                s.Save();
            }
            else
            {
                HandleClick(e.Location);
            }
        }
        base.OnMouseUp(e);
    }

    private void HandleClick(Point at)
    {
        // Nur Klicks IN der Pille zählen. Bei fixierter Pille kann kein Ziehen
        // beginnen, also galt jedes Loslassen als Klick — auch eines 500 Pixel
        // daneben, und der Zweig „Wellenform" fügte dann ungefragt ein.
        if (!ClientRectangle.Contains(at)) return;

        switch (phase)
        {
            case Phase.Idle:
            case Phase.Armed:
                OnStart?.Invoke();
                break;
            case Phase.Recording:
                if (CancelRect().Contains(at)) OnCancel?.Invoke();
                else OnSubmit?.Invoke();   // ✓ und die Wellenform: einfügen
                break;
        }
    }

    // MARK: Layered-Window-Anbindung

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool UpdateLayeredWindow(IntPtr hwnd, IntPtr hdcDst, ref Point pptDst,
        ref Size psize, IntPtr hdcSrc, ref Point pprSrc, int crKey, ref BlendFunction pblend, int dwFlags);

    [DllImport("user32.dll")] private static extern IntPtr GetDC(IntPtr hWnd);
    [DllImport("user32.dll")] private static extern int ReleaseDC(IntPtr hWnd, IntPtr hDC);
    [DllImport("gdi32.dll")] private static extern IntPtr CreateCompatibleDC(IntPtr hDC);
    [DllImport("gdi32.dll")] private static extern bool DeleteDC(IntPtr hdc);
    [DllImport("gdi32.dll")] private static extern IntPtr SelectObject(IntPtr hdc, IntPtr hObject);
    [DllImport("gdi32.dll")] private static extern bool DeleteObject(IntPtr hObject);

    [StructLayout(LayoutKind.Sequential, Pack = 1)]
    private struct BlendFunction
    {
        public byte BlendOp;
        public byte BlendFlags;
        public byte SourceConstantAlpha;
        public byte AlphaFormat;
    }

    private const byte AcSrcOver = 0x00;
    private const byte AcSrcAlpha = 0x01;
    private const int UlwAlpha = 0x00000002;

    /// <summary>Überträgt das gezeichnete Bild samt Alphakanal ins Fenster.</summary>
    private void PushLayered(Bitmap bitmap)
    {
        var screenDc = GetDC(IntPtr.Zero);
        var memDc = CreateCompatibleDC(screenDc);
        var hBitmap = IntPtr.Zero;
        var oldBitmap = IntPtr.Zero;
        try
        {
            hBitmap = bitmap.GetHbitmap(Color.FromArgb(0));
            oldBitmap = SelectObject(memDc, hBitmap);

            var size = new Size(bitmap.Width, bitmap.Height);
            var pointSource = new Point(0, 0);
            var topPos = Location;
            var blend = new BlendFunction
            {
                BlendOp = AcSrcOver,
                BlendFlags = 0,
                // Gesamtdeckkraft 0,95 wie das Mac-Panel.
                SourceConstantAlpha = 242,
                AlphaFormat = AcSrcAlpha,
            };

            if (!UpdateLayeredWindow(Handle, screenDc, ref topPos, ref size,
                                     memDc, ref pointSource, 0, ref blend, UlwAlpha))
                Core.StoreIO.Log($"Pille konnte nicht gezeichnet werden (Fehler {Marshal.GetLastWin32Error()}).");
        }
        finally
        {
            _ = ReleaseDC(IntPtr.Zero, screenDc);
            if (hBitmap != IntPtr.Zero)
            {
                SelectObject(memDc, oldBitmap);
                DeleteObject(hBitmap);
            }
            DeleteDC(memDc);
        }
    }

    protected override void OnResize(EventArgs e)
    {
        base.OnResize(e);
        Render();
    }

    /// <summary>
    /// Der Monitor unter der Pille hat eine andere Skalierung: Maße neu rechnen und
    /// neu setzen. WinForms macht das für ein Layered Window nicht von selbst.
    /// </summary>
    protected override void OnDpiChangedAfterParent(EventArgs e)
    {
        base.OnDpiChangedAfterParent(e);
        placing = true;
        Size = SizeFor(phase);
        MoveToAnchor();
        placing = false;
        Render();
    }

    protected override void Dispose(bool disposing)
    {
        if (disposing) ticker.Dispose();
        base.Dispose(disposing);
    }
}
