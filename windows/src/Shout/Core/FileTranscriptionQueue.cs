namespace Shout.Core;

/// <summary>
/// Ein Transkriptions-Auftrag: eine Datei, ihr Zustand und ihr Ergebnis
/// (Mac: FileTranscriptionQueue.swift).
///
/// <para>Ergebnisse leben nur zur Laufzeit. Gesichert wird ausschließlich, was der
/// Nutzer über den Sichern-Dialog selbst ablegt — und weder Verlauf noch Statistiken
/// werden angefasst: Die Statistik misst, wie schnell DU diktierst, eine Stunde
/// fremdes Audio würde diesen Wert bedeutungslos machen.</para>
/// </summary>
public sealed class FileTranscriptionJob
{
    public enum Phase { Queued, Transcribing, Minutes, Done, Failed, Cancelled }

    public Guid Id { get; } = Guid.NewGuid();
    public string Path { get; }
    public string Name => System.IO.Path.GetFileName(Path);

    public Phase State { get; set; } = Phase.Queued;
    /// <summary>0…1 innerhalb der laufenden Phase.</summary>
    public double Progress { get; set; }
    public double Duration { get; set; }
    public string? FailureReason { get; set; }

    /// <summary>Rohsegmente mit Zeitmarken — Grundlage der .srt-Datei.</summary>
    public List<TranscriptSegment> Segments { get; set; } = new();
    /// <summary>Rohtranskript mit Zeitmarken je Absatz.</summary>
    public string RawText { get; set; } = "";
    /// <summary>Protokoll; leer, wenn keines erstellt wurde.</summary>
    public string MinutesText { get; set; } = "";

    /// <summary>Nachgereichtes Protokoll: Der Text steht schon, es fehlt nur die
    /// Aufbereitung. Die Datei wird dafür NICHT noch einmal transkribiert.</summary>
    public bool MinutesOnly { get; set; }

    public FileTranscriptionJob(string path) => Path = path;

    public bool IsFinished => State is Phase.Done or Phase.Failed or Phase.Cancelled;

    /// <summary>Kann noch ein Protokoll nachgereicht werden? Nur wenn der Text fertig
    /// ist und keins existiert.</summary>
    public bool CanAddMinutes => State == Phase.Done && MinutesText.Length == 0 && RawText.Length > 0;

    /// <summary>
    /// Eingang fürs Sprachmodell: <b>ohne</b> Zeitmarken — die kosten dort nur Kontext
    /// und tauchten sonst mitten im Protokoll wieder auf.
    /// </summary>
    public string MinutesInput =>
        Segments.Count > 0 ? TranscriptLayout.RawText(Segments, timestamps: false) : RawText;

    /// <summary>Was angezeigt und als .txt gesichert wird.</summary>
    public string DisplayText => MinutesText.Length > 0 ? MinutesText : RawText;

    public int WordCount => DisplayText.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries).Length;

    /// <summary>Bricht den Auftrag ab und verwirft das Teilergebnis. Ein halbes
    /// Transkript anzuzeigen wäre eine Falle: Es sieht aus wie ein fertiges.</summary>
    public void MarkCancelled()
    {
        Segments.Clear();
        RawText = "";
        MinutesText = "";
        State = Phase.Cancelled;
    }
}

/// <summary>
/// Arbeitet Datei-Aufträge nacheinander ab.
///
/// <para>Seriell und nicht parallel, weil ohnehin nur ein Whisper-Modell im Speicher
/// liegt: Zwei Aufträge gleichzeitig würden sich am Sperr-Semaphor des
/// <see cref="Transcriber"/> gegenseitig blockieren und nur die Fortschrittsanzeige
/// unehrlich machen.</para>
/// </summary>
public sealed class FileTranscriptionQueue
{
    private readonly Transcriber transcriber;
    private readonly LlmFormatter formatter;
    private readonly PersonalDictionary dictionary;

    private readonly List<FileTranscriptionJob> jobs = new();
    private readonly HashSet<Guid> cancelled = new();
    private readonly object gate = new();
    private Task? runner;

    /// <summary>Feuert bei jeder Zustandsänderung — die Seite zeichnet dann neu.
    /// Wird auf dem Threadpool ausgelöst; die Oberfläche muss selbst auf den
    /// UI-Thread wechseln (siehe FilesPage).</summary>
    public event Action? Changed;

    public FileTranscriptionQueue(Transcriber transcriber, LlmFormatter formatter,
                                  PersonalDictionary dictionary)
    {
        this.transcriber = transcriber;
        this.formatter = formatter;
        this.dictionary = dictionary;
    }

    public IReadOnlyList<FileTranscriptionJob> Jobs
    {
        get { lock (gate) return jobs.ToArray(); }
    }

    public bool IsRunning
    {
        get { lock (gate) return runner is { IsCompleted: false }; }
    }

    public bool HasUnfinishedJobs
    {
        get { lock (gate) return jobs.Any(j => !j.IsFinished); }
    }

    public void Add(IEnumerable<string> paths)
    {
        lock (gate)
        {
            foreach (var path in paths) jobs.Add(new FileTranscriptionJob(path));
        }
        Changed?.Invoke();
        StartIfNeeded();
    }

    /// <summary>
    /// Reicht das Protokoll nach — aus dem vorhandenen Text, ohne die Datei noch
    /// einmal zu transkribieren. Wer die Aufbereitung ausgeschaltet hatte, müsste
    /// sonst eine Stunde neu rechnen lassen, obwohl der Text längst dasteht.
    /// </summary>
    public void AddMinutes(FileTranscriptionJob job)
    {
        if (!job.CanAddMinutes || !formatter.IsReady) return;
        job.MinutesOnly = true;
        job.State = FileTranscriptionJob.Phase.Minutes;
        job.Progress = 0;
        Changed?.Invoke();
        StartIfNeeded();
    }

    public void Cancel(FileTranscriptionJob job)
    {
        lock (gate)
        {
            cancelled.Add(job.Id);
            // Wartende Aufträge sofort abräumen; der laufende merkt es beim nächsten Block.
            if (job.State == FileTranscriptionJob.Phase.Queued) job.MarkCancelled();
        }
        Changed?.Invoke();
    }

    public void CancelAll()
    {
        foreach (var job in Jobs.Where(j => !j.IsFinished)) Cancel(job);
    }

    public void Remove(FileTranscriptionJob job)
    {
        Cancel(job);
        lock (gate) jobs.RemoveAll(j => j.Id == job.Id);
        Changed?.Invoke();
    }

    private void StartIfNeeded()
    {
        lock (gate)
        {
            if (runner is { IsCompleted: false }) return;
            runner = Task.Run(RunAsync);
        }
    }

    private async Task RunAsync()
    {
        while (true)
        {
            FileTranscriptionJob? job;
            lock (gate)
                job = jobs.FirstOrDefault(j => j.State == FileTranscriptionJob.Phase.Queued
                                               // Nachgereichtes Protokoll steht schon
                                               // auf „wird erstellt"; die Marke fällt
                                               // beim Abarbeiten, deshalb wird derselbe
                                               // Auftrag nicht zweimal gezogen.
                                               || j.MinutesOnly);
            if (job == null) return;
            await ProcessAsync(job);
        }
    }

    private bool IsCancelled(Guid id)
    {
        lock (gate) return cancelled.Contains(id);
    }

    private async Task ProcessAsync(FileTranscriptionJob job)
    {
        if (job.MinutesOnly) { await AddMinutesOnlyAsync(job); return; }
        if (IsCancelled(job.Id)) { job.MarkCancelled(); Changed?.Invoke(); return; }

        var settings = Settings.Shared;
        var useCommands = settings.FileSpeechCommandsEnabled;
        var useMinutes = settings.FileMinutesEnabled;
        var bias = dictionary.Data.Terms;

        job.State = FileTranscriptionJob.Phase.Transcribing;
        job.Progress = 0;
        Changed?.Invoke();

        var collected = new List<TranscriptSegment>();
        using var decoder = new MediaDecoder();
        try
        {
            job.Duration = decoder.Open(job.Path);
            Changed?.Invoke();

            while (decoder.Next() is { } block)
            {
                if (IsCancelled(job.Id)) { job.MarkCancelled(); Changed?.Invoke(); return; }

                var raw = await transcriber.TranscribeSegmentsAsync(block.Samples, bias);
                foreach (var segment in raw)
                {
                    var text = segment.Text.Trim();
                    if (text.Length == 0) continue;
                    // Sprachbefehle und Korrekturen PRO SEGMENT — sonst passt der Text
                    // der .srt nicht mehr zu dem, was im Fenster steht.
                    if (useCommands) text = SpeechCommands.Apply(text);
                    text = dictionary.ApplyCorrections(text);
                    if (text.Length == 0) continue;
                    collected.Add(new TranscriptSegment(text,
                                                        segment.Start + block.StartTime,
                                                        segment.End + block.StartTime));
                }

                job.Segments = new List<TranscriptSegment>(collected);
                job.RawText = TranscriptLayout.RawText(collected, timestamps: true);
                var processed = block.StartTime + (double)block.Samples.Length / MediaDecoder.SampleRate;
                job.Progress = job.Duration > 0 ? Math.Min(1, processed / job.Duration) : 0;
                Changed?.Invoke();
            }
        }
        catch (MediaDecoderException ex)
        {
            job.State = FileTranscriptionJob.Phase.Failed;
            job.FailureReason = ex.Message;
            Changed?.Invoke();
            return;
        }
        catch (Exception ex)
        {
            job.State = FileTranscriptionJob.Phase.Failed;
            job.FailureReason = ex.Message;
            Changed?.Invoke();
            return;
        }

        if (IsCancelled(job.Id)) { job.MarkCancelled(); Changed?.Invoke(); return; }

        if (job.RawText.Length == 0)
        {
            job.State = FileTranscriptionJob.Phase.Done;
            Changed?.Invoke();
            return;
        }

        if (useMinutes && formatter.IsReady)
        {
            await WriteMinutesAsync(job);
            if (IsCancelled(job.Id)) { job.MarkCancelled(); Changed?.Invoke(); return; }
        }

        job.State = FileTranscriptionJob.Phase.Done;
        Changed?.Invoke();
    }

    /// <summary>
    /// Der nachgereichte Weg: nur die Aufbereitung, der Text steht ja schon.
    /// </summary>
    private async Task AddMinutesOnlyAsync(FileTranscriptionJob job)
    {
        job.MinutesOnly = false;
        await WriteMinutesAsync(job);
        // Ein Abbruch verwirft hier NICHTS: Anders als beim ersten Durchlauf ist das
        // Transkript fertig und bleibt es — es fehlt dann nur das Protokoll. Die
        // Marke muss trotzdem weg, sonst liefe ein zweiter Anlauf sofort ins Leere.
        lock (gate) cancelled.Remove(job.Id);
        job.State = FileTranscriptionJob.Phase.Done;
        Changed?.Invoke();
    }

    /// <summary>Erstellt das Protokoll aus dem vorhandenen Text und trägt es ein.</summary>
    private async Task WriteMinutesAsync(FileTranscriptionJob job)
    {
        job.State = FileTranscriptionJob.Phase.Minutes;
        job.Progress = 0;
        Changed?.Invoke();

        var document = await formatter.MinutesAsync(job.MinutesInput, dictionary.TermHint, fraction =>
        {
            job.Progress = fraction;
            Changed?.Invoke();
        });
        if (IsCancelled(job.Id)) return;
        // Nur setzen, wenn wirklich ein Protokoll herauskam. Sonst stünden im
        // Fenster zwei identische Fassungen.
        if (document != null) job.MinutesText = document;
    }
}
