using Shout.Core;

namespace Shout.UI;

/// <summary>
/// Eine Zeile der Auftragsliste auf der Seite „Dateien" (Mac: JobRow in FilesView.swift):
/// Dateiname, Zustand, bei laufendem Auftrag ein Fortschrittsbalken, rechts „Öffnen"
/// und das Abbrechen-Kreuz.
/// </summary>
internal sealed class FileJobCard : ThemedControl, IAutoHeight
{
    private const int PadH = 15;
    private const int PadV = 12;
    private const int BarHeight = 4;

    private readonly FileTranscriptionJob job;
    private readonly ConsoleButton open;
    private readonly ConsoleButton close;

    public event Action<FileTranscriptionJob>? OpenRequested;
    public event Action<FileTranscriptionJob>? CancelRequested;
    public event Action<FileTranscriptionJob>? RemoveRequested;

    public FileJobCard(FileTranscriptionJob job)
    {
        this.job = job;

        open = new ConsoleButton(Loc.T("Öffnen"));
        open.Click2 += () => OpenRequested?.Invoke(job);
        open.Visible = job.State == FileTranscriptionJob.Phase.Done;
        Controls.Add(open);

        close = new ConsoleButton("", false, Icons.Kind.Close);
        close.Click2 += () =>
        {
            if (job.IsFinished) RemoveRequested?.Invoke(job);
            else CancelRequested?.Invoke(job);
        };
        Controls.Add(close);
    }

    public int PreferredHeightFor(int width)
    {
        var textWidth = Math.Max(60, width - PadH * 2 - TrailingWidth() - 14);
        var h = MeasureText(job.Name, Theme.RowTitle, textWidth).Height;
        h += 3 + MeasureText(Subtitle, Theme.Help, textWidth).Height;
        if (ShowsProgress) h += 8 + BarHeight;
        return Math.Max(h, open.Height) + PadV * 2;
    }

    private int TrailingWidth() => (open.Visible ? open.Width + 8 : 0) + close.Width;

    private bool ShowsProgress =>
        job.State is FileTranscriptionJob.Phase.Transcribing or FileTranscriptionJob.Phase.Minutes;

    /// <summary>Zustand, davor die Länge der Datei, sobald sie bekannt ist (sie steht
    /// erst nach dem Öffnen fest, deshalb nicht schon im Zustand „Wartet").</summary>
    private string Subtitle
    {
        get
        {
            var state = job.State switch
            {
                FileTranscriptionJob.Phase.Queued => Loc.T("Wartet"),
                FileTranscriptionJob.Phase.Transcribing => Loc.T("Wird transkribiert …"),
                FileTranscriptionJob.Phase.Minutes => Loc.T("Protokoll wird erstellt …"),
                FileTranscriptionJob.Phase.Done => Loc.F("Fertig · {0} Wörter", job.WordCount),
                FileTranscriptionJob.Phase.Failed => job.FailureReason ?? Loc.T("Fehlgeschlagen"),
                _ => Loc.T("Abgebrochen"),
            };
            if (job.State == FileTranscriptionJob.Phase.Failed) return state;
            return job.Duration > 0 ? $"{Length(job.Duration)} · {state}" : state;
        }
    }

    private static string Length(double seconds)
    {
        var total = (int)Math.Round(seconds);
        return total >= 3600
            ? $"{total / 3600}:{total % 3600 / 60:D2}:{total % 60:D2}"
            : $"{total / 60}:{total % 60:D2}";
    }

    protected override void OnLayout(LayoutEventArgs e)
    {
        base.OnLayout(e);
        if (Width <= 0) return;
        close.Location = new Point(Width - PadH - close.Width, (Height - close.Height) / 2);
        open.Visible = job.State == FileTranscriptionJob.Phase.Done;
        if (open.Visible)
            open.Location = new Point(close.Left - 8 - open.Width, (Height - open.Height) / 2);
    }

    protected override void OnPaint(PaintEventArgs e)
    {
        var g = e.Graphics;
        Theme.Smooth(g);
        using (var bg = new SolidBrush(Theme.Window)) g.FillRectangle(bg, ClientRectangle);
        Theme.DrawCard(g, new RectangleF(0, 0, Width, Height));

        var textWidth = Math.Max(60, Width - PadH * 2 - TrailingWidth() - 14);
        var y = PadV;

        var titleSize = MeasureText(job.Name, Theme.RowTitle, textWidth);
        DrawText(g, job.Name, Theme.RowTitle, Theme.Gray(0.9),
                 new Rectangle(PadH, y, textWidth, titleSize.Height), TextFormatFlags.NoPrefix);
        y += titleSize.Height + 3;

        var subtitle = Subtitle;
        var subtitleSize = MeasureText(subtitle, Theme.Help, textWidth);
        var subtitleColor = job.State == FileTranscriptionJob.Phase.Failed
            ? Color.FromArgb(242, 179, 51)
            : Theme.Gray(0.55);
        DrawText(g, subtitle, Theme.Help, subtitleColor,
                 new Rectangle(PadH, y, textWidth, subtitleSize.Height),
                 TextFormatFlags.WordBreak | TextFormatFlags.NoPrefix);
        y += subtitleSize.Height;

        if (!ShowsProgress) return;
        y += 8;
        var barWidth = Math.Min(220, textWidth);
        using var track = new SolidBrush(Theme.Gray(0.20));
        g.FillRectangle(track, PadH, y, barWidth, BarHeight);
        using var fill = new SolidBrush(Theme.Live);
        g.FillRectangle(fill, PadH, y, (int)(barWidth * Math.Clamp(job.Progress, 0, 1)), BarHeight);
    }
}
