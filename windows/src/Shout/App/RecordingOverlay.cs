namespace Shout.App;

/// <summary>
/// Kleine, randlose Pille am unteren Bildschirmrand — zeigt Aufnahme (mit
/// Live-Pegel) und Verarbeitung an. Klick stoppt die Aufnahme. Das Fenster
/// stiehlt der Ziel-App nie den Fokus (WS_EX_NOACTIVATE).
/// </summary>
public sealed class RecordingOverlay : Form
{
    public enum Phase { Recording, Working }

    private Phase phase = Phase.Recording;
    private float level;
    private readonly System.Windows.Forms.Timer repaint = new() { Interval = 50 };

    /// <summary>Klick auf die Pille während der Aufnahme.</summary>
    public event Action? OnClickStop;

    private static readonly Color Accent = Color.FromArgb(255, 74, 10);      // shoutLive
    private static readonly Color Panel = Color.FromArgb(37, 37, 42);        // shoutPanel

    public RecordingOverlay()
    {
        FormBorderStyle = FormBorderStyle.None;
        ShowInTaskbar = false;
        TopMost = true;
        StartPosition = FormStartPosition.Manual;
        BackColor = Panel;
        Size = new Size(180, 40);
        // Abgerundete Pille
        var path = new System.Drawing.Drawing2D.GraphicsPath();
        path.AddArc(0, 0, 40, 40, 90, 180);
        path.AddArc(Width - 40, 0, 40, 40, 270, 180);
        path.CloseFigure();
        Region = new Region(path);

        repaint.Tick += (_, _) => Invalidate();
        Click += (_, _) => { if (phase == Phase.Recording) OnClickStop?.Invoke(); };
        Cursor = Cursors.Hand;
    }

    /// <summary>WS_EX_NOACTIVATE | WS_EX_TOOLWINDOW: kein Fokus-Klau, kein Alt-Tab-Eintrag.</summary>
    protected override CreateParams CreateParams
    {
        get
        {
            var cp = base.CreateParams;
            cp.ExStyle |= 0x08000000 | 0x00000080;
            return cp;
        }
    }

    protected override bool ShowWithoutActivation => true;

    public void ShowPhase(Phase newPhase)
    {
        phase = newPhase;
        var screen = Screen.PrimaryScreen?.WorkingArea ?? new Rectangle(0, 0, 1280, 720);
        Location = new Point(screen.Left + (screen.Width - Width) / 2, screen.Bottom - Height - 24);
        if (!Visible) Show();
        repaint.Start();
        Invalidate();
    }

    public void HideOverlay()
    {
        repaint.Stop();
        Hide();
    }

    public void SetLevel(float newLevel)
    {
        // leichte Glättung wie am Mac
        level = level * 0.5f + newLevel * 0.5f;
    }

    protected override void OnPaint(PaintEventArgs e)
    {
        var g = e.Graphics;
        g.SmoothingMode = System.Drawing.Drawing2D.SmoothingMode.AntiAlias;

        if (phase == Phase.Recording)
        {
            // Pulsierender Punkt + Pegel-Balken + Text
            var dotSize = 10 + (int)(level * 8);
            using var accent = new SolidBrush(Accent);
            g.FillEllipse(accent, 18 - dotSize / 2 + 5, Height / 2 - dotSize / 2, dotSize, dotSize);

            using var font = new Font("Segoe UI", 9.5f, FontStyle.Bold);
            using var white = new SolidBrush(Color.White);
            g.DrawString("Ich höre zu …", font, white, 38, Height / 2 - 9);

            // dezenter Pegel-Balken unten
            using var bar = new SolidBrush(Color.FromArgb(120, Accent));
            g.FillRectangle(bar, 38, Height - 8, (Width - 56) * Math.Min(1, level), 3);
        }
        else
        {
            using var font = new Font("Segoe UI", 9.5f, FontStyle.Bold);
            using var white = new SolidBrush(Color.White);
            g.DrawString("Verarbeite …", font, white, 38, Height / 2 - 9);
            using var accent = new SolidBrush(Accent);
            var t = Environment.TickCount / 150 % 3;
            for (var i = 0; i < 3; i++)
            {
                var size = i == t ? 8 : 5;
                g.FillEllipse(accent, 14 + i * 7 - size / 2 + 3, Height / 2 - size / 2, size, size);
            }
        }
    }
}
