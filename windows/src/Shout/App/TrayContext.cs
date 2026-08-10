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
    private readonly ToolStripMenuItem settingsMenuItem;
    private readonly ToolStripMenuItem quitMenuItem;
    private readonly SynchronizationContext ui;

    /// <summary>Automatische Aktualisierung (Velopack, gegen die GitHub-Releases).</summary>
    public Updater Updates { get; } = new();

    public TrayContext(bool openSettings = false)
    {
        ui = SynchronizationContext.Current ?? new WindowsFormsSynchronizationContext();

        statusItem = new ToolStripMenuItem(Loc.T("Modell wird geladen …")) { Enabled = false };
        dictateItem = new ToolStripMenuItem(Loc.T("Diktieren"), null, (_, _) => ToggleRecording());
        updateItem = new ToolStripMenuItem(Loc.T("Nach Aktualisierungen suchen …"), null, (_, _) => UpdateMenuClicked());

        var menu = new ContextMenuStrip
        {
            Renderer = new DarkMenuRenderer(),
            BackColor = Theme.Card,
            ForeColor = Theme.Ink,
            Font = Theme.Body,
        };
        settingsMenuItem = new ToolStripMenuItem(Loc.T("Einstellungen …"), null, (_, _) => ShowSettings());
        quitMenuItem = new ToolStripMenuItem(Loc.T("Beenden"), null, (_, _) => ExitThread());

        menu.Items.Add(statusItem);
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add(dictateItem);
        menu.Items.Add(settingsMenuItem);
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add(updateItem);
        menu.Items.Add(quitMenuItem);
        foreach (var item in menu.Items.OfType<ToolStripMenuItem>())
        {
            item.BackColor = Theme.Card;
            item.ForeColor = item == statusItem ? Theme.InkMuted : Theme.Ink;
        }

        tray = new NotifyIcon
        {
            Icon = AppIcons.Tray(recording: false),
            Text = Loc.T("shout. — lokale Diktier-App"),
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
        // Halten-Modus: Drücken startet, Loslassen beendet und fügt ein.
        hotkey.OnPressed += () =>
        {
            if (state == State.Idle) StartRecording();
            else if (state == State.Failed) _ = Task.Run(LoadModelsAsync);   // erneuter Versuch
        };
        hotkey.OnReleased += () => { if (state == State.Recording) StopAndProcess(); };
        RegisterHotkeyFromSettings();

        // Threadpool statt UI-Thread: WhisperFactory.FromPath liest das komplette
        // Modell (bis 1,6 GB) synchron — auf dem UI-Thread stünde die Tray-UI so
        // lange still. Alle UI-Zugriffe darin laufen ohnehin über ui.Post.
        _ = Task.Run(LoadModelsAsync);

        if (Settings.Shared.PersistentPill) overlay.ShowPhase(RecordingOverlay.Phase.Idle);

        // Lauscht auf „shout.exe --settings" eines zweiten Starts.
        messageWindow = new SettingsMessageWindow(ShowSettings);

        // Erststart: Assistent statt Hauptfenster (wie am Mac).
        if (!Settings.Shared.OnboardingDone) ShowOnboarding();
        else if (openSettings) ShowSettings();

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
                            Loc.F("shout. {0} ist aktuell.", Updates.CurrentVersion), ToolTipIcon.Info), null);
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
            Updater.State.Checking => Loc.T("Suche nach Aktualisierungen …"),
            Updater.State.Available => Loc.F("Version {0} laden", Updates.AvailableVersion),
            Updater.State.Downloading => Loc.F("Wird geladen … {0} %", Updates.Progress),
            Updater.State.ReadyToRestart => Loc.F("Neu starten für Version {0}", Updates.AvailableVersion),
            _ => Loc.T("Nach Aktualisierungen suchen …"),
        };
        updateItem.Enabled = Updates.Status is not (Updater.State.Checking or Updater.State.Downloading);

        // Einmalige Meldung, sobald die neue Version bereitliegt.
        if (Updates.Status == Updater.State.ReadyToRestart && !restartNotified)
        {
            restartNotified = true;
            tray.ShowBalloonTip(8000, "shout.",
                Loc.F("Version {0} ist bereit. Über das Tray-Menü neu starten, um sie zu übernehmen.",
                      Updates.AvailableVersion), ToolTipIcon.Info);
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
                ui.Post(_ =>
                {
                    AsrProgress = p is > 0 and < 1 ? p : null;
                    statusItem.Text = AsrProgress is { } value
                        ? Loc.F("Sprachmodell wird geladen … {0} %", (int)(value * 100))
                        : Loc.T("Sprachmodell wird geladen …");
                }, null));
            await transcriber.WarmUpAsync();
            ui.Post(_ => AsrProgress = null, null);
            SetState(State.Idle);
        }
        catch (Exception ex)
        {
            ui.Post(_ => AsrProgress = null, null);
            SetState(State.Failed);
            ui.Post(_ => statusItem.Text = Loc.T("Modell-Fehler — Internet prüfen, dann erneut „Diktieren“ wählen"), null);
            Log($"Modell-Ladefehler: {ex.Message}");
        }

        if (Settings.Shared.FormattingEnabled)
            await formatter.LoadAsync();
    }

    /// <summary>Nach Modellwechsel in den Einstellungen neu laden.</summary>
    public void ReloadModels() => _ = Task.Run(LoadModelsAsync);

    /// <summary>Download-Fortschritt des Transkriptions-Modells (null = kein Download
    /// im Gange) — der Erststart-Assistent zeigt ihn an.</summary>
    public double? AsrProgress { get; private set; }

    /// <summary>Transkriptions-Modell geladen und einsatzbereit?</summary>
    public bool TranscriberReady => transcriber.IsReady;

    /// <summary>Modell-Laden fehlgeschlagen (Assistent bietet „erneut versuchen").</summary>
    public bool ModelFailed => state == State.Failed;

    /// <summary>Ist das KI-Textmodell geladen? Ohne das gibt es kein Sprachprofil
    /// (und das Modell wird nur geladen, wenn die Aufbereitung eingeschaltet ist).</summary>
    public bool FormatterReady => formatter.IsReady;

    /// <summary>Erzeugt „Dein Sprachprofil" aus einer Textprobe des Verlaufs.
    /// null = kein Modell geladen oder Erzeugung fehlgeschlagen.</summary>
    public Task<string?> DescribeVoiceAsync(string sample) => formatter.DescribeVoiceAsync(sample);

    /// <summary>Warteschlange der Datei-Transkriptionen (Seite „Dateien"). Teilt sich
    /// Modelle und Wörterbuch mit dem Diktat; serialisiert wird über die Sperren in
    /// <see cref="Transcriber"/> und <see cref="LlmFormatter"/>.</summary>
    public FileTranscriptionQueue FileQueue => fileQueue ??= new FileTranscriptionQueue(transcriber, formatter, dictionary);
    private FileTranscriptionQueue? fileQueue;

    /// <summary>Aufnahme-Art aus den Einstellungen.</summary>
    private static HotkeyManager.Mode HotkeyMode =>
        Settings.Shared.HotkeyMode == "hold" ? HotkeyManager.Mode.Hold : HotkeyManager.Mode.Toggle;

    /// <summary>
    /// Registriert den eingestellten Hotkey. Ist er belegt (Strg+Alt+Leertaste gehört
    /// z. B. der Claude-App), wird der Reihe nach eine Ausweich-Kombination probiert,
    /// gespeichert und gemeldet — sonst stünde die App ohne Auslöser da und der
    /// Nutzer müsste selbst raten, welche Kombination noch frei ist.
    /// </summary>
    public void RegisterHotkeyFromSettings()
    {
        var s = Settings.Shared;
        if (hotkey.Register(s.HotkeyModifiers, s.HotkeyKey, HotkeyMode))
        {
            UpdateMenu();
            return;
        }

        var blocked = HotkeyManager.Describe(s.HotkeyModifiers, s.HotkeyKey);
        foreach (var (modifiers, key) in HotkeyManager.Fallbacks)
        {
            if (modifiers == s.HotkeyModifiers && key == s.HotkeyKey) continue;
            if (!hotkey.Register(modifiers, key, HotkeyMode)) continue;

            s.HotkeyModifiers = modifiers;
            s.HotkeyKey = key;
            s.Save();
            UpdateMenu();
            settingsForm?.RefreshHotkeyDisplay();
            tray?.ShowBalloonTip(8000, "shout.",
                Loc.F("{0} ist von einem anderen Programm belegt — shout. hört jetzt auf {1}. Ändern kannst du das unter „Aufnahme & Text“.",
                      blocked, HotkeyManager.Describe(modifiers, key)), ToolTipIcon.Info);
            return;
        }

        UpdateMenu();
        tray?.ShowBalloonTip(6000, "shout.",
            Loc.T("Der Hotkey ist bereits belegt — bitte in den Einstellungen ändern."), ToolTipIcon.Warning);
    }

    /// <summary>
    /// Hotkey vorübergehend abmelden, solange in den Einstellungen oder im
    /// Erststart-Assistenten eine neue Kombination aufgenommen wird — ein
    /// registrierter Hotkey erreicht das eigene Fenster nie, die aktuelle
    /// Kombination ließe sich sonst nicht erneut wählen.
    /// </summary>
    public void PauseHotkey() => hotkey.Unregister();

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

    /// <summary>
    /// Oberflächensprache wurde umgestellt. Die Texte stecken in bereits gebauten
    /// Controls, deshalb wird das Tray-Menü neu betextet und das Fenster auf
    /// derselben Seite neu aufgebaut — so wirkt der Wechsel sofort, ohne Neustart.
    /// </summary>
    public void ApplyLanguageChange()
    {
        RetranslateMenu();
        UpdateMenu();
        UpdateStateChanged();

        if (settingsForm is not { IsDisposed: false }) return;
        var openTab = settingsForm.CurrentTab;
        var bounds = settingsForm.Bounds;
        var old = settingsForm;
        settingsForm = new DashboardForm(this, dictionary, history, stats);
        settingsForm.StartPosition = FormStartPosition.Manual;
        settingsForm.Bounds = bounds;
        settingsForm.Show();
        settingsForm.SelectTab(openTab);
        old.Close();
    }

    /// <summary>Beschriftungen der festen Menüpunkte neu setzen.</summary>
    private void RetranslateMenu()
    {
        dictateItem.Text = Loc.T("Diktieren");
        settingsMenuItem.Text = Loc.T("Einstellungen …");
        quitMenuItem.Text = Loc.T("Beenden");
        tray.Text = Loc.T("shout. — lokale Diktier-App");
    }

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
        // Auto-Stopp nur im Umschalt-Modus sinnvoll — im Halten-Modus stoppt das
        // Loslassen (wie am Mac).
        recorder.AutoStopEnabled = s.AutoStopEnabled && HotkeyMode == HotkeyManager.Mode.Toggle;
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
                Loc.F("Aufnahme konnte nicht gestartet werden: {0}", ex.Message), ToolTipIcon.Error);
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
        statusItem.Text = state switch
        {
            State.LoadingModel => statusItem.Text,   // Fortschritt läuft schon
            State.Idle => Loc.F("Bereit — {0}", HotkeyTrigger),
            State.Recording => Loc.T("Ich höre zu …"),
            State.Working => Loc.T("Verarbeite …"),
            State.Failed => statusItem.Text,
            _ => "shout.",
        };
        dictateItem.Text = state == State.Recording ? Loc.T("Aufnahme stoppen") : Loc.T("Diktieren");
        dictateItem.Enabled = state is State.Idle or State.Recording or State.Failed;
        tray.Icon = AppIcons.Tray(recording: state == State.Recording);
        settingsForm?.RefreshStatus();
    }

    private DashboardForm? settingsForm;
    private OnboardingForm? onboardingForm;

    /// <summary>Erststart-Assistent: Mikrofon, Hotkey, Modell, Probediktat.</summary>
    private void ShowOnboarding()
    {
        if (onboardingForm is { IsDisposed: false })
        {
            onboardingForm.Activate();
            return;
        }
        onboardingForm = new OnboardingForm(this);
        onboardingForm.Finished += () =>
        {
            Settings.Shared.OnboardingDone = true;
            Settings.Shared.Save();
            onboardingForm?.Close();
            onboardingForm = null;
            ShowSettings();
        };
        onboardingForm.FormClosed += (_, _) => onboardingForm = null;
        onboardingForm.Show();
        onboardingForm.Activate();
    }

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

    /// <summary>„Strg + Alt + Leertaste halten" bzw. „… drücken" — je nach Aufnahme-Art.</summary>
    public static string HotkeyTrigger
    {
        get
        {
            var s = Settings.Shared;
            var label = HotkeyManager.Describe(s.HotkeyModifiers, s.HotkeyKey);
            return HotkeyMode == HotkeyManager.Mode.Hold
                ? Loc.F("{0} halten", label)
                : Loc.F("{0} drücken", label);
        }
    }

    /// <summary>Beschriftung für die Seitenleiste der Einstellungen. Hier steht nur
    /// die Kombination ohne „drücken"/„halten" — in der schmalen Leiste würde genau
    /// dieses Wort abgeschnitten.</summary>
    public string StatusLine => state switch
    {
        State.LoadingModel => Loc.T("Modell wird geladen …"),
        State.Recording => Loc.T("Ich höre zu …"),
        State.Working => Loc.T("Verarbeite …"),
        State.Failed => Loc.T("Modell-Fehler"),
        _ => Loc.F("Bereit · {0}",
                   HotkeyManager.Describe(Settings.Shared.HotkeyModifiers, Settings.Shared.HotkeyKey)),
    };

    /// <summary>Läuft gerade eine Aufnahme? (Modellwechsel ist dann gesperrt.)</summary>
    public bool IsBusy => state is State.Recording or State.Working;

    // MARK: Icon

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
