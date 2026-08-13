using Shout.App;
using Shout.Core;

namespace Shout.UI;

/// <summary>
/// „Meeting" — Besprechungen mitschneiden und daraus ein Transkript machen
/// (Mac: MeetingView.swift).
///
/// <para>Eigene Seite statt eines Kastens auf „Dateien": Aufnehmen ist ein anderer
/// Vorgang als eine vorhandene Datei einzuwerfen. Die Warteschlange ist dieselbe —
/// es gibt nur einen Verarbeitungsweg —, angezeigt werden hier aber ausschließlich
/// die eigenen Mitschnitte.</para>
/// </summary>
internal sealed class MeetingPage : PageBase, IRefreshablePage
{
    protected override int MaxContentWidth => 640;

    private readonly TrayContext app;
    private readonly FileTranscriptionQueue queue;
    private readonly MeetingRecorder recorder;
    private readonly Dictionary<Guid, TranscriptForm> windows = new();

    private string? error;
    private bool legalHintShown;

    public MeetingPage(TrayContext app, FileTranscriptionQueue queue, MeetingRecorder recorder)
    {
        this.app = app;
        this.queue = queue;
        this.recorder = recorder;
        legalHintShown = Settings.Shared.MeetingLegalHintShown;

        // Beide melden sich vom Threadpool — auf den UI-Thread wechseln.
        queue.Changed += OnChanged;
        recorder.Changed += OnChanged;

        if (!recorder.IsRecording) queue.Restore(MeetingRecorder.ExistingRecordings());
        Rebuild();
    }

    private void OnChanged()
    {
        if (IsDisposed || !IsHandleCreated) return;
        try { BeginInvoke(new Action(Rebuild)); } catch (ObjectDisposedException) { }
    }

    public void Refresh2() => Rebuild();

    private void Rebuild()
    {
        TrimStack(0);
        Push(new SectionHeader(Loc.T("Meeting")), 0);

        if (!app.TranscriberReady)
        {
            var hint = new ConsoleBox();
            hint.Add(TextBlock.Body(Loc.T(
                "Zum Transkribieren wird das Sprachmodell gebraucht. Lade es unter „Modelle“ herunter — danach geht es hier weiter.")), 0);
            Push(hint);
            NotifyHeightChanged();
            return;
        }

        if (recorder.IsRecording) PushRunning(); else PushIdle();
        if (!recorder.IsRecording) PushOptions();
        PushRecordings();

        Push(TextBlock.Footnote(Loc.T(
            "Der Mitschnitt bleibt auf diesem Rechner und wird hier transkribiert. Ein Gespräch ohne Einverständnis der anderen mitzuschneiden ist in Deutschland und Österreich strafbar.")));
        NotifyHeightChanged();
    }

    // MARK: - Bühne

    private void PushIdle()
    {
        var box = new ConsoleBox();
        box.Add(TextBlock.Body(Loc.T("Meeting aufnehmen")), 0);
        box.Add(TextBlock.Footnote(error ?? SourceHelp), 4);

        var source = new ConsoleSegmented(new[]
        {
            (MeetingSource.Microphone.ToString(), Loc.T("Mikrofon")),
            (MeetingSource.SystemAudio.ToString(), Loc.T("Systemton")),
            (MeetingSource.Both.ToString(), Loc.T("Beides")),
        }, Settings.Shared.MeetingSource);
        source.Changed += key =>
        {
            Settings.Shared.MeetingSource = key;
            Settings.Shared.Save();
            error = null;
            Rebuild();
        };

        var record = new ConsoleButton(Loc.T("Aufnehmen"));
        record.Click2 += () =>
        {
            error = null;
            if (legalHintShown) { Begin(); return; }
            var answer = MessageBox.Show(
                Loc.T("Ein Gespräch mitzuschneiden ist ohne Einverständnis der anderen Beteiligten in Deutschland und Österreich strafbar. Frag kurz, bevor du aufnimmst."),
                Loc.T("Kurz vorweg"), MessageBoxButtons.OKCancel, MessageBoxIcon.Information);
            if (answer != DialogResult.OK) return;
            legalHintShown = true;
            Settings.Shared.MeetingLegalHintShown = true;
            Settings.Shared.Save();
            Begin();
        };

        box.Add(new Cluster(new Control[] { source, record }), 12);
        Push(box);
    }

    private void PushRunning()
    {
        var box = new ConsoleBox();
        box.Add(TextBlock.Title(Clock(recorder.Duration)), 0);
        box.Add(TextBlock.Footnote(recorder.IsPaused
            ? Loc.T("Pausiert")
            : $"{Loc.T("Nimmt auf …")}  ·  {SourceLabel}"), 4);
        box.Add(new LevelBar(recorder.IsPaused ? 0 : recorder.Level), 10);

        if (recorder.NoSignal)
        {
            box.Add(TextBlock.Warning(Loc.T(
                "Es kommt kein Ton an. Prüfe, ob die gewählte Quelle wirklich etwas ausgibt.")), 8);
        }

        var pause = new ConsoleButton(recorder.IsPaused ? Loc.T("Fortsetzen") : Loc.T("Pause"));
        pause.Click2 += () => { if (recorder.IsPaused) recorder.Resume(); else recorder.Pause(); };
        var stop = new ConsoleButton(Loc.T("Stoppen"));
        stop.Click2 += Finish;
        box.Add(new Cluster(new Control[] { pause, stop }), 12);
        box.Add(TextBlock.Footnote(Loc.T("Diktieren geht weiter — Mitschnitt und Diktat stören sich nicht.")), 8);
        Push(box);
    }

    private void PushOptions()
    {
        var settings = Settings.Shared;
        var panel = new ConsolePanel { Title = Loc.T("Verarbeitung") };

        var minutes = new ConsoleToggle(settings.FileMinutesEnabled);
        minutes.Changed += on => { settings.FileMinutesEnabled = on; settings.Save(); };
        panel.Add(Loc.T("Protokoll erstellen"),
                  app.FormatterReady
                      ? Loc.T("Zusätzlich zum Rohtext ein Protokoll: Zusammenfassung, Kernpunkte und der gegliederte Text. Dauert bei langen Dateien deutlich länger.")
                      : Loc.T("Das Modell zum Aufbereiten ist noch nicht geladen. Sobald es bereit ist, lässt sich der Schalter umlegen — bis dahin kommt das Rohtranskript."),
                  minutes);

        var commands = new ConsoleToggle(settings.FileSpeechCommandsEnabled);
        commands.Changed += on => { settings.FileSpeechCommandsEnabled = on; settings.Save(); };
        panel.Add(Loc.T("Sprachbefehle anwenden"),
                  Loc.T("Standardmäßig aus: In einer Aufzeichnung ist „Punkt“ meist ein normales Wort und kein Satzzeichen."),
                  commands);

        Push(panel);
    }

    private void PushRecordings()
    {
        var recordings = queue.Jobs.Where(j => MeetingRecorder.IsOwnRecording(j.Path)).ToList();
        if (recordings.Count == 0) return;

        Push(new GroupLabel(Loc.T("Mitschnitte")), 20);
        foreach (var job in recordings)
        {
            var card = new FileJobCard(job);
            card.OpenRequested += OpenResult;
            card.StartRequested += j => queue.Start(j);
            card.CancelRequested += j => queue.Cancel(j);
            card.RemoveRequested += j => { CloseResult(j.Id); queue.Remove(j); };
            Push(card, 8);
        }
    }

    // MARK: - Steuerung

    private void Begin()
    {
        try
        {
            var source = Enum.TryParse<MeetingSource>(Settings.Shared.MeetingSource, out var s)
                ? s : MeetingSource.Microphone;
            recorder.Start(source);
        }
        catch (Exception ex)
        {
            error = ex.Message;
        }
        Rebuild();
    }

    /// <summary>Stoppt und fragt nach dem Namen — da weiß man noch, worum es ging.
    /// Dieser Weg wird IMMER durchlaufen: Eine Aufnahme, die niemand übernimmt,
    /// wäre verloren.</summary>
    private void Finish()
    {
        var path = recorder.Stop();
        if (path == null) return;
        var suggestion = System.IO.Path.GetFileNameWithoutExtension(path);
        var chosen = NameDialog.Ask(Loc.T("Wie soll die Aufnahme heißen?"), suggestion);
        if (!string.IsNullOrWhiteSpace(chosen)) path = MeetingRecorder.Rename(path, chosen!);
        queue.Add(new[] { path });
        Rebuild();
    }

    private string SourceLabel => Settings.Shared.MeetingSource switch
    {
        nameof(MeetingSource.SystemAudio) => Loc.T("Systemton"),
        nameof(MeetingSource.Both) => Loc.T("Beides"),
        _ => Loc.T("Mikrofon"),
    };

    private string SourceHelp => Settings.Shared.MeetingSource switch
    {
        nameof(MeetingSource.SystemAudio) =>
            Loc.T("Nimmt den Ton anderer Programme auf — für Online-Meetings. Deine eigene Stimme ist dann NICHT dabei."),
        nameof(MeetingSource.Both) =>
            Loc.T("Mikrofon und Ton anderer Programme zusammen — für Online-Meetings, bei denen du mitsprichst."),
        _ => Loc.T("Nimmt über das Mikrofon auf — für Besprechungen im Raum."),
    };

    private static string Clock(double seconds)
    {
        var total = (int)seconds;
        return total >= 3600
            ? $"{total / 3600}:{total % 3600 / 60:D2}:{total % 60:D2}"
            : $"{total / 60}:{total % 60:D2}";
    }

    // MARK: - Ergebnisfenster

    private void OpenResult(FileTranscriptionJob job)
    {
        if (windows.TryGetValue(job.Id, out var existing) && !existing.IsDisposed)
        {
            existing.BringToFront();
            existing.Activate();
            return;
        }
        var form = new TranscriptForm(job, queue);
        form.FormClosed += (_, _) => windows.Remove(job.Id);
        windows[job.Id] = form;
        form.Show();
    }

    private void CloseResult(Guid id)
    {
        if (windows.TryGetValue(id, out var form) && !form.IsDisposed) form.Close();
        windows.Remove(id);
    }
}

/// <summary>Schlichter Pegelbalken. Er beantwortet die einzige Frage, die während
/// einer Aufnahme zählt: Kommt überhaupt Ton an?</summary>
internal sealed class LevelBar : ThemedControl, IAutoHeight
{
    private readonly float level;

    public LevelBar(float level)
    {
        this.level = Math.Clamp(level, 0, 1);
        Height = 5;
    }

    public int PreferredHeightFor(int width) => 5;

    protected override void OnPaint(PaintEventArgs e)
    {
        var g = e.Graphics;
        Theme.Smooth(g);
        using var track = new SolidBrush(Theme.Gray(0.18));
        g.FillRectangle(track, 0, 0, Width, Height);
        using var fill = new SolidBrush(Theme.Live);
        g.FillRectangle(fill, 0, 0, (int)(Width * level), Height);
    }
}

/// <summary>
/// Kleiner Abfrage-Dialog für den Namen einer Aufnahme. WinForms bringt keinen mit,
/// und der Name fällt direkt nach dem Stoppen — da weiß man noch, worum es ging.
/// </summary>
internal static class NameDialog
{
    /// <summary>Gibt den eingegebenen Namen zurück, oder <c>null</c> bei Abbruch.</summary>
    public static string? Ask(string title, string suggestion)
    {
        using var form = new Form
        {
            Text = title,
            FormBorderStyle = FormBorderStyle.FixedDialog,
            StartPosition = FormStartPosition.CenterScreen,
            MinimizeBox = false,
            MaximizeBox = false,
            ClientSize = new Size(420, 116),
            BackColor = Theme.Window,
            Icon = AppIcons.Window,
        };
        var box = new TextBox
        {
            Text = suggestion,
            Location = new Point(16, 20),
            Width = 388,
            BackColor = Theme.Gray(0.12),
            ForeColor = Theme.Gray(0.92),
            BorderStyle = BorderStyle.FixedSingle,
            Font = Theme.Body,
        };
        var ok = new Button { Text = Loc.T("Sichern"), DialogResult = DialogResult.OK,
                              Location = new Point(228, 64), Width = 84 };
        var later = new Button { Text = Loc.T("Später"), DialogResult = DialogResult.Cancel,
                                 Location = new Point(320, 64), Width = 84 };
        form.Controls.AddRange(new Control[] { box, ok, later });
        form.AcceptButton = ok;
        form.CancelButton = later;
        box.SelectAll();
        return form.ShowDialog() == DialogResult.OK ? box.Text : null;
    }
}
