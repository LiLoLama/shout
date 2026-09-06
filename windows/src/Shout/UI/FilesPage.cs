using Shout.App;
using Shout.Core;

namespace Shout.UI;

/// <summary>
/// „Dateien" — fertige Audio- und Videodateien lokal transkribieren
/// (Mac: FilesView.swift).
///
/// <para>Ein Ergebnisbereich auf der Seite selbst fehlt bewusst: Ein Textfeld von
/// 220 Pixeln trägt bei einem einstündigen Transkript nicht. Das Ergebnis lebt in
/// einem eigenen Fenster (<see cref="TranscriptForm"/>); die Seite ist Ablagefläche,
/// Schalter und Warteschlange.</para>
/// </summary>
internal sealed class FilesPage : PageBase, IRefreshablePage
{
    protected override int MaxContentWidth => 640;

    private readonly TrayContext app;
    private readonly FileTranscriptionQueue queue;
    private readonly Dictionary<Guid, TranscriptForm> windows = new();
    private readonly Dictionary<Guid, FileJobCard> cards = new();
    private string structure = "";

    public FilesPage(TrayContext app, FileTranscriptionQueue queue)
    {
        this.app = app;
        this.queue = queue;

        AllowDrop = true;
        DragEnter += OnDragEnter;
        DragDrop += OnDragDrop;

        // Die Warteschlange meldet sich vom Threadpool — auf den UI-Thread wechseln.
        queue.Changed += OnChanged;

        Rebuild();
    }

    protected override void Dispose(bool disposing)
    {
        // Die Warteschlange lebt so lange wie die App, diese Seite nicht — ohne das
        // Abmelden bliebe jede alte Seite über den Delegaten erreichbar.
        if (disposing) queue.Changed -= OnChanged;
        base.Dispose(disposing);
    }

    private void OnChanged()
    {
        if (IsDisposed || !IsHandleCreated) return;
        try { BeginInvoke(new Action(Tick)); } catch (ObjectDisposedException) { }
    }

    /// <summary>
    /// Die Warteschlange meldet sich nach jedem transkribierten Block und bei jedem
    /// Prozentschritt des Protokolls. Neu gebaut wird nur, wenn sich die Liste oder
    /// ein Zustand ändert — sonst wandern die Werte in die vorhandenen Karten, und
    /// „Öffnen" bleibt anklickbar, während nebenan gerechnet wird.
    /// </summary>
    private void Tick()
    {
        if (Signature() != structure) { Rebuild(); return; }
        foreach (var card in cards.Values) card.RefreshFromJob();
    }

    private string Signature()
    {
        var jobs = string.Join(",", Jobs().Select(j => $"{j.Id}:{j.State}"));
        return string.Join("|", app.TranscriberReady, app.FormatterReady, jobs);
    }

    private List<FileTranscriptionJob> Jobs()
        // Nur eingeworfene Dateien — Mitschnitte stehen unter „Meeting".
        => queue.Jobs.Where(j => !MeetingRecorder.IsOwnRecording(j.Path)).ToList();

    public void Refresh2() => Rebuild();

    private void Rebuild()
    {
        structure = Signature();
        cards.Clear();
        TrimStack(0);

        Push(new SectionHeader(Loc.T("Dateien")), 0);

        if (!app.TranscriberReady)
        {
            var hint = new ConsoleBox();
            hint.Add(TextBlock.Body(Loc.T(
                "Zum Transkribieren wird das Sprachmodell gebraucht. Lade es unter „Modelle“ herunter — danach geht es hier weiter.")), 0);
            Push(hint);
            NotifyHeightChanged();
            return;
        }

        PushDropZone();
        PushOptions();
        PushJobs();

        Push(TextBlock.Footnote(Loc.T(
            "Die Datei wird auf diesem Gerät gelesen — nichts wird hochgeladen. Ergebnisse werden nicht automatisch gespeichert und tauchen weder im Verlauf noch in den Statistiken auf.")));
        NotifyHeightChanged();
        EnableDropOnChildren(this);
    }

    /// <summary>
    /// Windows meldet Dateien nur an das Control unter dem Zeiger. Ohne diese Zeile
    /// nahm die Seite Dateien ausschließlich an ihrem Rand an — genau NICHT auf der
    /// Fläche, auf der „Dateien hierher ziehen" steht.
    /// </summary>
    private void EnableDropOnChildren(Control parent)
    {
        foreach (Control child in parent.Controls)
        {
            child.AllowDrop = true;
            child.DragEnter -= OnDragEnter;
            child.DragDrop -= OnDragDrop;
            child.DragEnter += OnDragEnter;
            child.DragDrop += OnDragDrop;
            EnableDropOnChildren(child);
        }
    }

    private void PushDropZone()
    {
        var box = new ConsoleBox();
        box.Add(TextBlock.Body(Loc.T("Audio- oder Videodateien hierher ziehen")), 0);
        box.Add(TextBlock.Footnote(Loc.T("MP3, M4A, WAV, MP4, MOV und alles, was Windows abspielen kann")), 4);
        var choose = new ConsoleButton(Loc.T("Auswählen …"));
        choose.Click2 += ChooseFiles;
        box.Add(new Cluster(new Control[] { choose }), 12);
        Push(box);
    }

    private void PushOptions()
    {
        var settings = Settings.Shared;
        var panel = new ConsolePanel { Title = Loc.T("Verarbeitung") };

        var minutes = new ConsoleToggle(settings.FileMinutesEnabled);
        minutes.Changed += on =>
        {
            settings.FileMinutesEnabled = on;
            settings.Save();
        };
        panel.Add(Loc.T("Protokoll erstellen"),
                  app.FormatterReady
                      ? Loc.T("Zusätzlich zum Rohtext ein Protokoll: Zusammenfassung, Kernpunkte und der gegliederte Text. Dauert bei langen Dateien deutlich länger.")
                      : Loc.T("Das Modell zum Aufbereiten ist noch nicht geladen. Sobald es bereit ist, lässt sich der Schalter umlegen — bis dahin kommt das Rohtranskript."),
                  minutes);

        var commands = new ConsoleToggle(settings.FileSpeechCommandsEnabled);
        commands.Changed += on =>
        {
            settings.FileSpeechCommandsEnabled = on;
            settings.Save();
        };
        panel.Add(Loc.T("Sprachbefehle anwenden"),
                  Loc.T("Standardmäßig aus: In einer Aufzeichnung ist „Punkt“ meist ein normales Wort und kein Satzzeichen."),
                  commands);

        Push(panel);
    }

    private void PushJobs()
    {
        var jobs = Jobs();
        if (jobs.Count == 0) return;

        Push(new GroupLabel(Loc.T("Aufträge")), 20);
        foreach (var job in jobs)
        {
            var card = new FileJobCard(job);
            card.OpenRequested += OpenResult;
            card.StartRequested += j => queue.Start(j);
            card.CancelRequested += j => queue.Cancel(j);
            card.RemoveRequested += j =>
            {
                CloseResult(j.Id);
                queue.Remove(j);
            };
            cards[job.Id] = card;
            Push(card, 8);
        }

        if (jobs.Count(j => !j.IsFinished) > 1)
        {
            var cancelAll = new ConsoleButton(Loc.T("Alle abbrechen"));
            cancelAll.Click2 += () => queue.CancelAll();
            Push(new Cluster(new Control[] { cancelAll }), 10);
        }
    }

    // MARK: - Dateien annehmen

    private void ChooseFiles()
    {
        using var dialog = new OpenFileDialog
        {
            Multiselect = true,
            Filter = Loc.T("Audio & Video|*.mp3;*.m4a;*.wav;*.aiff;*.aac;*.flac;*.wma;*.mp4;*.m4v;*.mov;*.avi;*.wmv;*.mkv|Alle Dateien|*.*"),
        };
        if (dialog.ShowDialog() != DialogResult.OK) return;
        queue.Add(dialog.FileNames);
    }

    private void OnDragEnter(object? sender, DragEventArgs e)
    {
        if (e.Data?.GetDataPresent(DataFormats.FileDrop) == true) e.Effect = DragDropEffects.Copy;
    }

    private void OnDragDrop(object? sender, DragEventArgs e)
    {
        if (e.Data?.GetData(DataFormats.FileDrop) is string[] paths && paths.Length > 0)
            queue.Add(paths.Where(File.Exists));
    }

    // MARK: - Ergebnisfenster

    /// <summary>Öffnet das Ergebnisfenster eines Auftrags — oder holt das bestehende
    /// nach vorn. Ohne dieses Verzeichnis öffnete jeder Klick ein weiteres Fenster.</summary>
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
