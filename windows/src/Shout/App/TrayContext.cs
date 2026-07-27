using System.Media;
using Shout.Core;
using Shout.UI;

namespace Shout.App;

/// <summary>
/// Die eigentliche App: Tray-Icon + globaler Hotkey + Zustandsmaschine
/// Aufnahme → Whisper → Sprachbefehle → optionales LLM → Korrekturen →
/// Einfügen ins aktive Fenster. Das Windows-Pendant zum macOS-AppDelegate.
/// </summary>
public sealed class TrayContext : ApplicationContext
{
    private enum State { LoadingModel, Idle, Recording, Working, Failed }

    private State state = State.LoadingModel;

    private readonly NotifyIcon tray;
    private readonly HotkeyManager hotkey = new();
    private readonly RecordingOverlay overlay = new();

    private readonly AudioRecorder recorder = new();
    private readonly Transcriber transcriber = new();
    private readonly LlmFormatter formatter = new();
    private readonly PersonalDictionary dictionary = new();
    private readonly DictationHistory history = new();
    private readonly StatsStore stats = new();

    private readonly ToolStripMenuItem dictateItem;
    private readonly ToolStripMenuItem statusItem;
    private readonly ToolStripMenuItem updateItem;
    private readonly SynchronizationContext ui;

    /// <summary>Automatische Aktualisierung (Velopack, gegen die GitHub-Releases).</summary>
    public Updater Updates { get; } = new();

    public TrayContext(bool openSettings = false)
    {
        ui = SynchronizationContext.Current ?? new WindowsFormsSynchronizationContext();

        statusItem = new ToolStripMenuItem("Modell wird geladen …") { Enabled = false };
        dictateItem = new ToolStripMenuItem("Diktieren", null, (_, _) => ToggleRecording());
        updateItem = new ToolStripMenuItem("Nach Aktualisierungen suchen …", null, (_, _) => UpdateMenuClicked());

        var menu = new ContextMenuStrip
        {
            Renderer = new DarkMenuRenderer(),
            BackColor = Theme.Card,
            ForeColor = Theme.Ink,
            Font = Theme.Body,
        };
        menu.Items.Add(statusItem);
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add(dictateItem);
        menu.Items.Add(new ToolStripMenuItem("Einstellungen …", null, (_, _) => ShowSettings()));
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add(updateItem);
        menu.Items.Add(new ToolStripMenuItem("Beenden", null, (_, _) => ExitThread()));
        foreach (var item in menu.Items.OfType<ToolStripMenuItem>())
        {
            item.BackColor = Theme.Card;
            item.ForeColor = item == statusItem ? Theme.InkMuted : Theme.Ink;
        }

        tray = new NotifyIcon
        {
            Icon = MakeIcon(idle: true),
            Text = "shout. — lokale Diktier-App",
            ContextMenuStrip = menu,
            Visible = true,
        };
        tray.DoubleClick += (_, _) => ToggleRecording();

        // Die Pille steuert dieselben Aktionen wie am Mac: Klick startet,
        // ✕ verwirft, ✓ fügt ein.
        overlay.OnStart += () => { if (state == State.Idle) StartRecording(); };
        overlay.OnCancel += CancelRecording;
        overlay.OnSubmit += () => { if (state == State.Recording) StopAndProcess(); };

        recorder.OnLevel += level => ui.Post(_ => overlay.SetLevel(level), null);
        recorder.OnSilence += () => ui.Post(_ =>
        {
            if (state == State.Recording) StopAndProcess();
        }, null);

        hotkey.OnHotkey += ToggleRecording;
        RegisterHotkeyFromSettings();

        // Threadpool statt UI-Thread: WhisperFactory.FromPath liest das komplette
        // Modell (bis 1,6 GB) synchron — auf dem UI-Thread stünde die Tray-UI so
        // lange still. Alle UI-Zugriffe darin laufen ohnehin über ui.Post.
        _ = Task.Run(LoadModelsAsync);

        if (Settings.Shared.PersistentPill) overlay.ShowPhase(RecordingOverlay.Phase.Idle);

        // Lauscht auf „shout.exe --settings" eines zweiten Starts.
        messageWindow = new SettingsMessageWindow(ShowSettings);
        if (openSettings) ShowSettings();

        Updates.Changed += () => ui.Post(_ => UpdateStateChanged(), null);
        // Stiller Start-Check wie Sparkle am Mac: sucht und lädt im Hintergrund,
        // meldet sich erst, wenn eine Version bereitliegt.
        if (Updates.IsSupported) _ = Task.Run(Updates.CheckAndDownloadAsync);
    }

    // MARK: Aktualisierung

    /// <summary>Klick auf den Menüpunkt — je nach Zustand suchen, laden oder neu starten.</summary>
    private void UpdateMenuClicked()
    {
        switch (Updates.Status)
        {
            case Updater.State.Available:
                _ = Task.Run(Updates.DownloadAsync);
                break;
            case Updater.State.ReadyToRestart:
                Updates.ApplyAndRestart();
                break;
            case Updater.State.Unsupported:
                tray.ShowBalloonTip(6000, "shout.", Updates.StatusText, ToolTipIcon.Info);
                break;
            default:
                _ = Task.Run(async () =>
                {
                    await Updates.CheckAsync();
                    if (Updates.Status == Updater.State.UpToDate)
                        ui.Post(_ => tray.ShowBalloonTip(4000, "shout.",
                            $"shout. {Updates.CurrentVersion} ist aktuell.", ToolTipIcon.Info), null);
                    else if (Updates.Status == Updater.State.Available)
                        await Updates.DownloadAsync();
                });
                break;
        }
    }

    private void UpdateStateChanged()
    {
        updateItem.Text = Updates.Status switch
        {
            Updater.State.Checking => "Suche nach Aktualisierungen …",
            Updater.State.Available => $"Version {Updates.AvailableVersion} laden",
            Updater.State.Downloading => $"Wird geladen … {Updates.Progress} %",
            Updater.State.ReadyToRestart => $"Neu starten für Version {Updates.AvailableVersion}",
            _ => "Nach Aktualisierungen suchen …",
        };
        updateItem.Enabled = Updates.Status is not (Updater.State.Checking or Updater.State.Downloading);

        // Einmalige Meldung, sobald die neue Version bereitliegt.
        if (Updates.Status == Updater.State.ReadyToRestart && !restartNotified)
        {
            restartNotified = true;
            tray.ShowBalloonTip(8000, "shout.",
                $"Version {Updates.AvailableVersion} ist bereit. Über das Tray-Menü neu starten, "
                + "um sie zu übernehmen.", ToolTipIcon.Info);
        }

        settingsForm?.RefreshUpdateState();
    }

    private bool restartNotified;

    private readonly SettingsMessageWindow messageWindow;

    /// <summary>
    /// Unsichtbares Fenster, das die per <c>RegisterWindowMessage</c> registrierte
    /// Nachricht „Einstellungen öffnen" empfängt (gesendet von einer zweiten Instanz).
    /// </summary>
    private sealed class SettingsMessageWindow : NativeWindow, IDisposable
    {
        private readonly Action openSettings;

        public SettingsMessageWindow(Action openSettings)
        {
            this.openSettings = openSettings;
            CreateHandle(new CreateParams());
        }

        protected override void WndProc(ref Message m)
        {
            if (m.Msg == Program.OpenSettingsMessage) openSettings();
            base.WndProc(ref m);
        }

        public void Dispose() => DestroyHandle();
    }

    // MARK: Modelle

    private async Task LoadModelsAsync()
    {
        SetState(State.LoadingModel);
        try
        {
            await transcriber.LoadAsync(p =>
                ui.Post(_ => statusItem.Text = p is > 0 and < 1
                    ? $"Sprachmodell wird geladen … {(int)(p * 100)} %"
                    : "Sprachmodell wird geladen …", null));
            await transcriber.WarmUpAsync();
            SetState(State.Idle);
        }
        catch (Exception ex)
        {
            SetState(State.Failed);
            ui.Post(_ => statusItem.Text = "Modell-Fehler — Internet prüfen, dann erneut „Diktieren“ wählen", null);
            Log($"Modell-Ladefehler: {ex.Message}");
        }

        if (Settings.Shared.FormattingEnabled)
            await formatter.LoadAsync();
    }

    /// <summary>Nach Modellwechsel in den Einstellungen neu laden.</summary>
    public void ReloadModels() => _ = Task.Run(LoadModelsAsync);

    public void RegisterHotkeyFromSettings()
    {
        var s = Settings.Shared;
        if (!hotkey.Register(s.HotkeyModifiers, s.HotkeyKey))
            tray?.ShowBalloonTip(4000, "shout.",
                "Der Hotkey ist bereits belegt — bitte in den Einstellungen ändern.", ToolTipIcon.Warning);
        UpdateMenu();
    }

    /// <summary>„Pille immer anzeigen" wurde umgeschaltet.</summary>
    public void ApplyPersistentPill()
    {
        if (Settings.Shared.PersistentPill)
        {
            if (state is State.Idle or State.LoadingModel or State.Failed)
                overlay.ShowPhase(RecordingOverlay.Phase.Idle);
        }
        else if (state != State.Recording && state != State.Working)
        {
            overlay.HideOverlay();
        }
    }

    /// <summary>Position der Pille wurde in den Einstellungen geändert.</summary>
    public void RepositionPill() => overlay.MoveToAnchor();

    // MARK: Aufnahme

    private void ToggleRecording()
    {
        switch (state)
        {
            case State.Idle: StartRecording(); break;
            case State.Recording: StopAndProcess(); break;
            case State.Failed: _ = Task.Run(LoadModelsAsync); break;   // erneuter Versuch
        }
    }

    private void StartRecording()
    {
        var s = Settings.Shared;
        recorder.AutoStopEnabled = s.AutoStopEnabled;
        recorder.SilenceSeconds = s.SilenceSeconds;
        try
        {
            recorder.Start();
            SetState(State.Recording);
            overlay.ShowPhase(RecordingOverlay.Phase.Recording);
            PlayCue(SystemSounds.Exclamation);
        }
        catch (Exception ex)
        {
            SetState(State.Failed);
            FinishPill();
            tray.ShowBalloonTip(4000, "shout.",
                $"Aufnahme konnte nicht gestartet werden: {ex.Message}", ToolTipIcon.Error);
        }
    }

    /// <summary>✕ auf der Pille: Aufnahme verwerfen, nichts einfügen.</summary>
    private void CancelRecording()
    {
        if (state != State.Recording) return;
        _ = recorder.Stop();   // Puffer verwerfen
        SetState(State.Idle);
        FinishPill();
    }

    private void StopAndProcess()
    {
        var samples = recorder.Stop();
        SetState(State.Working);
        overlay.ShowPhase(RecordingOverlay.Phase.Processing);

        // Threadpool: die Inferenz darf nie den UI-Thread blockieren (die
        // Verarbeiten-Welle liefe sonst nicht) — UI-Arbeit geht per ui.Post.
        _ = Task.Run(() => ProcessAsync(samples));
    }

    private async Task ProcessAsync(float[] samples)
    {
        var s = Settings.Shared;
        try
        {
            if (samples.Length == 0) return;

            var raw = await transcriber.TranscribeAsync(samples, dictionary.Data.Terms);
            var output = raw.Trim();
            if (output.Length == 0) return;

            if (s.SpeechCommandsEnabled) output = SpeechCommands.Apply(output);
            if (s.FormattingEnabled) output = await formatter.FormatAsync(output, dictionary.TermHint);
            output = dictionary.ApplyCorrections(output).Trim();
            if (output.Length == 0) return;

            var final = output;
            ui.Post(_ =>
            {
                TextInjector.Insert(final, s.KeepInClipboard);
                PlayCue(SystemSounds.Asterisk);
            }, null);

            history.Add(final);
            var words = final.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries).Length;
            stats.Record(words, (double)samples.Length / 16_000);
        }
        catch (Exception ex)
        {
            Log($"Verarbeitung fehlgeschlagen: {ex.Message}");
            ui.Post(_ => PlayCue(SystemSounds.Hand), null);
        }
        finally
        {
            ui.Post(_ =>
            {
                SetState(transcriber.IsReady ? State.Idle : State.Failed);
                FinishPill();
            }, null);
        }
    }

    /// <summary>Nach Abschluss/Abbruch: Idle-Pille zeigen (wenn dauerhaft) oder ausblenden.</summary>
    private void FinishPill()
    {
        if (Settings.Shared.PersistentPill) overlay.ShowPhase(RecordingOverlay.Phase.Idle);
        else overlay.HideOverlay();
    }

    private static void PlayCue(SystemSound sound)
    {
        if (Settings.Shared.SoundCuesEnabled) sound.Play();
    }

    // MARK: UI-Zustand

    private void SetState(State newState)
    {
        state = newState;
        ui.Post(_ => UpdateMenu(), null);
    }

    private void UpdateMenu()
    {
        var s = Settings.Shared;
        var hotkeyLabel = HotkeyManager.Describe(s.HotkeyModifiers, s.HotkeyKey);
        statusItem.Text = state switch
        {
            State.LoadingModel => statusItem.Text,   // Fortschritt läuft schon
            State.Idle => $"Bereit — {hotkeyLabel}",
            State.Recording => "Ich höre zu …",
            State.Working => "Verarbeite …",
            State.Failed => statusItem.Text,
            _ => "shout.",
        };
        dictateItem.Text = state == State.Recording ? "Aufnahme stoppen" : "Diktieren";
        dictateItem.Enabled = state is State.Idle or State.Recording or State.Failed;
        tray.Icon = MakeIcon(idle: state != State.Recording);
        settingsForm?.RefreshStatus();
    }

    private DashboardForm? settingsForm;

    private void ShowSettings()
    {
        if (settingsForm is { IsDisposed: false })
        {
            if (settingsForm.WindowState == FormWindowState.Minimized)
                settingsForm.WindowState = FormWindowState.Normal;
            settingsForm.Activate();
            return;
        }
        settingsForm = new DashboardForm(this, dictionary, history, stats);
        settingsForm.Show();
    }

    /// <summary>Beschriftung für die Seitenleiste der Einstellungen.</summary>
    public string StatusLine
    {
        get
        {
            var hotkeyLabel = HotkeyManager.Describe(Settings.Shared.HotkeyModifiers, Settings.Shared.HotkeyKey);
            return state switch
            {
                State.LoadingModel => "Modell wird geladen …",
                State.Recording => "Ich höre zu …",
                State.Working => "Verarbeite …",
                State.Failed => "Modell-Fehler",
                _ => $"Bereit · {hotkeyLabel} drücken",
            };
        }
    }

    /// <summary>Läuft gerade eine Aufnahme? (Modellwechsel ist dann gesperrt.)</summary>
    public bool IsBusy => state is State.Recording or State.Working;

    // MARK: Icon

    /// <summary>Zeichnet das Tray-Icon zur Laufzeit: oranger Punkt (Aufnahme:
    /// gefüllt, sonst Ring) — kein Icon-Asset nötig.</summary>
    private static Icon MakeIcon(bool idle)
    {
        using var bmp = new Bitmap(32, 32);
        using var g = Graphics.FromImage(bmp);
        g.SmoothingMode = System.Drawing.Drawing2D.SmoothingMode.AntiAlias;
        var accent = Theme.Live;
        if (idle)
        {
            using var pen = new Pen(accent, 5);
            g.DrawEllipse(pen, 5, 5, 22, 22);
        }
        else
        {
            using var brush = new SolidBrush(accent);
            g.FillEllipse(brush, 3, 3, 26, 26);
        }
        var handle = bmp.GetHicon();
        return Icon.FromHandle(handle);
    }

    private static void Log(string message)
    {
        try
        {
            File.AppendAllText(Path.Combine(StoreIO.DataDirectory, "shout.log"),
                $"{DateTime.Now:yyyy-MM-dd HH:mm:ss} {message}\n");
        }
        catch { }
    }

    protected override void ExitThreadCore()
    {
        tray.Visible = false;
        tray.Dispose();
        hotkey.Dispose();
        recorder.Dispose();
        transcriber.Dispose();
        formatter.Dispose();
        overlay.Dispose();
        messageWindow.Dispose();
        base.ExitThreadCore();
    }
}
