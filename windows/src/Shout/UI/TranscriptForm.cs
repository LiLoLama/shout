using Shout.Core;

namespace Shout.UI;

/// <summary>
/// Ergebnisfenster einer Datei-Transkription (Mac: TranscriptWindowView.swift):
/// eine Fassung in voller Fensterbreite, bearbeitbar, mit den Exportwegen darunter.
///
/// <para>Eigenes Fenster statt eines Bereichs auf der Seite: Ein Textfeld von 220
/// Pixeln trägt bei einem einstündigen Transkript nicht — man scrollt darin herum,
/// statt zu lesen.</para>
/// </summary>
internal sealed class TranscriptForm : Form
{
    private const string KeyMinutes = "minutes";
    private const string KeyRaw = "raw";

    private readonly FileTranscriptionJob job;
    private readonly ConsoleSegmented? switcher;
    private readonly TextBox editor;
    private readonly TextBox comparison;
    private readonly ConsoleButton compareButton;
    private readonly Label status;
    private readonly Label header;

    private string active;
    private bool comparing;

    private bool HasBoth => job.MinutesText.Length > 0 && job.RawText.Length > 0;

    public TranscriptForm(FileTranscriptionJob job)
    {
        this.job = job;
        // Ohne Protokoll gibt es nur den Rohtext — dann ist er auch die aktive Fassung.
        active = job.MinutesText.Length > 0 ? KeyMinutes : KeyRaw;

        Text = $"shout. — {job.Name}";
        BackColor = Theme.Window;
        ClientSize = new Size(880, 620);
        MinimumSize = new Size(640, 460);
        StartPosition = FormStartPosition.CenterScreen;
        Icon = AppIcons.Window;

        header = new Label
        {
            AutoSize = false, Height = 24, Dock = DockStyle.Top,
            ForeColor = Theme.Gray(0.55), BackColor = Theme.Window, Font = Theme.Help,
            Padding = new Padding(20, 6, 20, 0),
        };

        editor = MakeTextBox(readOnly: false);
        comparison = MakeTextBox(readOnly: true);
        comparison.Visible = false;

        compareButton = new ConsoleButton(Loc.T("Vergleichen"));
        compareButton.Click2 += () =>
        {
            comparing = !comparing;
            compareButton.Text = comparing ? Loc.T("Vergleich ausblenden") : Loc.T("Vergleichen");
            ApplyFassung();
        };

        if (HasBoth)
        {
            switcher = new ConsoleSegmented(
                new[] { (KeyMinutes, Loc.T("Protokoll")), (KeyRaw, Loc.T("Rohtext")) }, active);
            switcher.Changed += key =>
            {
                // Was der Nutzer geändert hat, gehört in den Auftrag zurück, BEVOR
                // umgeschaltet wird — sonst ist die Bearbeitung weg.
                StoreEdits();
                active = key;
                ApplyFassung();
            };
        }

        status = new Label
        {
            AutoSize = false, Height = 20, Dock = DockStyle.Bottom,
            ForeColor = Theme.Live, BackColor = Theme.Window, Font = Theme.Help,
            Padding = new Padding(20, 2, 20, 0),
        };

        var copy = new ConsoleButton(Loc.T("Kopieren"));
        copy.Click2 += CopyActive;
        var saveText = new ConsoleButton(Loc.T("Als Text sichern …"));
        saveText.Click2 += SaveText;
        var saveSubtitles = new ConsoleButton(Loc.T("Untertitel sichern …"));
        saveSubtitles.Click2 += SaveSubtitles;
        saveSubtitles.Enabled = job.Segments.Count > 0;

        var footnote = new Label
        {
            Text = Loc.T("Untertitel folgen immer dem ursprünglichen Transkript — Änderungen in diesem Fenster wirken sich nicht auf die Zeitmarken aus."),
            AutoSize = false, Height = 34, Dock = DockStyle.Bottom,
            ForeColor = Theme.Gray(0.45), BackColor = Theme.Window, Font = Theme.Help,
            Padding = new Padding(20, 2, 20, 6),
        };

        var buttons = new FlowLayoutPanel
        {
            Dock = DockStyle.Bottom, Height = 44, BackColor = Theme.Window,
            Padding = new Padding(16, 8, 16, 8), WrapContents = false,
        };
        buttons.Controls.AddRange(new Control[] { copy, saveText, saveSubtitles });

        var toolbar = new FlowLayoutPanel
        {
            Dock = DockStyle.Top, Height = 46, BackColor = Theme.Window,
            Padding = new Padding(16, 8, 16, 8), WrapContents = false,
        };
        if (switcher != null)
        {
            toolbar.Controls.Add(switcher);
            toolbar.Controls.Add(compareButton);
        }
        else
        {
            toolbar.Controls.Add(new Label
            {
                Text = Loc.T("Rohtext"), AutoSize = true, Font = Theme.SectionLabel,
                ForeColor = Theme.Gray(0.45), Margin = new Padding(4, 8, 0, 0),
            });
        }

        var split = new TableLayoutPanel
        {
            Dock = DockStyle.Fill, ColumnCount = 2, RowCount = 1, BackColor = Theme.Window,
            Padding = new Padding(14, 6, 14, 6),
        };
        split.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
        split.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 0));
        split.Controls.Add(editor, 0, 0);
        split.Controls.Add(comparison, 1, 0);
        this.split = split;

        Controls.Add(split);
        Controls.Add(toolbar);
        Controls.Add(header);
        Controls.Add(footnote);
        Controls.Add(status);
        Controls.Add(buttons);

        ApplyFassung();
    }

    private readonly TableLayoutPanel split;

    private static TextBox MakeTextBox(bool readOnly) => new()
    {
        Multiline = true, ScrollBars = ScrollBars.Vertical, Dock = DockStyle.Fill,
        BackColor = readOnly ? Theme.Gray(0.09) : Theme.Window,
        ForeColor = readOnly ? Theme.Gray(0.62) : Theme.Gray(0.9),
        BorderStyle = BorderStyle.None, Font = Theme.Body, ReadOnly = readOnly,
        WordWrap = true,
    };

    private string ActiveText => active == KeyMinutes ? job.MinutesText : job.RawText;
    private string OtherText => active == KeyMinutes ? job.RawText : job.MinutesText;
    private string ActiveTitle => active == KeyMinutes ? Loc.T("Protokoll") : Loc.T("Rohtext");

    /// <summary>Übernimmt die Bearbeitung in den Auftrag — vor jedem Umschalten und
    /// vor jedem Export.</summary>
    private void StoreEdits()
    {
        if (active == KeyMinutes) job.MinutesText = editor.Text;
        else job.RawText = editor.Text;
    }

    private void ApplyFassung()
    {
        editor.Text = ActiveText;
        comparison.Text = OtherText;

        var show = comparing && HasBoth;
        comparison.Visible = show;
        split.ColumnStyles[1] = show
            ? new ColumnStyle(SizeType.Percent, 100)
            : new ColumnStyle(SizeType.Absolute, 0);
        split.ColumnStyles[0] = new ColumnStyle(SizeType.Percent, 100);

        var words = ActiveText.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries).Length;
        header.Text = job.Duration > 0
            ? Loc.F("{0} · {1} · {2} Wörter", job.Name, TranscriptLayout.Timecode(job.Duration), words)
            : Loc.F("{0} · {1} Wörter", job.Name, words);
    }

    // MARK: - Export

    private void CopyActive()
    {
        StoreEdits();
        try
        {
            Clipboard.SetText(ActiveText);
            ShowStatus(Loc.F("{0} in die Zwischenablage kopiert.", ActiveTitle));
        }
        catch
        {
            ShowStatus(Loc.T("Die Zwischenablage ist gerade belegt."));
        }
    }

    private void SaveText()
    {
        StoreEdits();
        // Zusatz nur, wenn es zwei Fassungen gibt — sonst überschriebe das zweite
        // Sichern stillschweigend die erste Datei.
        var suffix = HasBoth && active == KeyRaw ? (Loc.IsGerman ? "-roh" : "-raw") : "";
        var name = Path.GetFileNameWithoutExtension(job.Path) + suffix + ".txt";
        Write(ActiveText, name, Loc.T("Textdatei (*.txt)|*.txt"));
    }

    private void SaveSubtitles()
    {
        var name = Path.GetFileNameWithoutExtension(job.Path) + ".srt";
        Write(SubtitleWriter.Srt(job.Segments), name, Loc.T("Untertitel (*.srt)|*.srt"));
    }

    private void Write(string content, string suggestedName, string filter)
    {
        using var dialog = new SaveFileDialog { FileName = suggestedName, Filter = filter };
        if (dialog.ShowDialog() != DialogResult.OK) return;
        try
        {
            File.WriteAllText(dialog.FileName, content);
            ShowStatus(Loc.F("Gesichert: {0}", Path.GetFileName(dialog.FileName)));
        }
        catch (Exception ex)
        {
            ShowStatus(Loc.F("Sichern fehlgeschlagen: {0}", ex.Message));
        }
    }

    private void ShowStatus(string text) => status.Text = text;
}
