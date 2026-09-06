using Microsoft.Win32;
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
    private readonly SoundCues sounds = new();

    private readonly ToolStripMenuItem dictateItem;
    private readonly ToolStripMenuItem statusItem;
    private readonly ToolStripMenuItem updateItem;
    private readonly ToolStripMenuItem settingsMenuItem;
    private readonly ToolStripMenuItem quitMenuItem;
    private readonly ToolStripMenuItem formattingItem;
    private readonly ToolStripMenuItem pasteLastItem;
    private readonly ToolStripMenuItem correctLastItem;
    private readonly SynchronizationContext ui;

    /// <summary>Das zuletzt eingefügte Diktat — Grundlage für „noch einmal einfügen"
    /// und „korrigieren" (Mac: lastInsertedText).</summary>
    private string lastInsertedText = "";

    /// <summary>Programm, in das eingefügt werden soll. Beim START der Aufnahme
    /// gemerkt: Bis der Text fertig ist, kann ein anderes Fenster vorne sein.</summary>
    private string? targetApp;

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
        quitMenuItem = new ToolStripMenuItem(Loc.T("Beenden"), null, (_, _) => RequestExit());
        formattingItem = new ToolStripMenuItem(Loc.T("Text aufbereiten"), null, (_, _) => ToggleFormatting())
        {
            CheckOnClick = false,
            Checked = Settings.Shared.FormattingEnabled,
        };
        pasteLastItem = new ToolStripMenuItem(Loc.T("Zuletzt Gesprochenes einfügen"), null,
                                              (_, _) => PasteLastDictation());
        correctLastItem = new ToolStripMenuItem(Loc.T("Letztes Diktat korrigieren …"), null,
                                                (_, _) => ShowCorrection());

        menu.Items.Add(statusItem);
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add(dictateItem);
        menu.Items.Add(pasteLastItem);
        menu.Items.Add(correctLastItem);
        menu.Items.Add(formattingItem);
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
        // Doppeltipp: Der erste Tipp „spannt" nur — die Pille zeigt das, sonst wüsste
        // niemand, ob der Tipp angekommen ist. Bleibt der zweite Tipp aus, muss sie
        // von selbst wieder verschwinden, sonst pulst sie bis zum nächsten Diktat.
        hotkey.OnArmed += () =>
        {
            if (state != State.Idle) return;
            overlay.ShowPhase(RecordingOverlay.Phase.Armed);
            armedTimer.Stop();
            armedTimer.Start();
        };
        hotkey.IsRecording = () => state == State.Recording;
        armedTimer.Tick += (_, _) =>
        {
            armedTimer.Stop();
            if (state == State.Idle) FinishPill();
        };
        RegisterHotkeyFromSettings();

        // Der Autostart-Eintrag lebt in der Registry; die Einstellung wird ihm beim
        // Start angeglichen, damit beide Seiten nicht auseinanderlaufen.
        Settings.Shared.StartAtLogin = Autostart.IsEnabled;

        // Abmelden/Herunterfahren: Ein laufender Mitschnitt muss gesichert werden,
        // bevor Windows den Prozess beendet.
        SystemEvents.SessionEnding += OnSessionEnding;

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
        // meldet sich erst, wenn eine Version bereitliegt. Abschaltbar wie dort.
        if (Updates.IsSupported && Settings.Shared.AutoUpdateCheck)
            _ = Task.Run(Updates.CheckAndDownloadAsync);
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

    /// <summary>Blendet die „gespannte" Pille wieder aus, wenn der zweite Tipp
    /// ausbleibt. Etwas länger als das Zeitfenster des Detektors.</summary>
    private readonly System.Windows.Forms.Timer armedTimer = new() { Interval = 900 };

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

    private Task LoadModelsAsync() => LoadModelsAsync(reset: false);

    private async Task LoadModelsAsync(bool reset)
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
                }, null), reset);
            await transcriber.WarmUpAsync();
            ui.Post(_ => AsrProgress = null, null);
            SetState(State.Idle);
        }
        catch (Exception ex)
        {
            ui.Post(_ => AsrProgress = null, null);
            RollBackModelChoice();
            // Läuft noch ein Modell (gescheiterter Wechsel), bleibt die App
            // einsatzbereit — nur die Wahl ist zurückgenommen.
            SetState(transcriber.IsReady ? State.Idle : State.Failed);
            if (!transcriber.IsReady)
                ui.Post(_ => statusItem.Text = Loc.T("Modell-Fehler — Internet prüfen, dann erneut „Diktieren“ wählen"), null);
            StoreIO.Log($"Modell-Ladefehler: {ex.Message}");
        }

        if (Settings.Shared.FormattingEnabled)
        {
            await formatter.LoadAsync(reset: reset);
            // Aufwärmen wie bei der Spracherkennung: Sonst bezahlt das erste Diktat
            // die einmalige Einrichtung des Ausführers mit.
            await formatter.WarmUpAsync();
        }
    }

    /// <summary>
    /// Das Laden ist gescheitert: die Modellwahl auf das zurücksetzen, was noch
    /// geladen ist. Sonst zeigte die Modelle-Seite ein Modell als „aktiv", das gar
    /// nicht läuft, und jeder Neustart liefe erneut in denselben Fehler.
    /// </summary>
    private void RollBackModelChoice()
    {
        var loaded = transcriber.LoadedModel;
        if (string.IsNullOrEmpty(loaded) || Settings.Shared.AsrModel == loaded) return;
        Settings.Shared.AsrModel = loaded;
        Settings.Shared.Save();
        ui.Post(_ => settingsForm?.RefreshStatus(), null);
    }

    /// <summary>
    /// Nach einem Modell- oder Anbieterwechsel neu laden. <paramref name="reset"/>
    /// baut die Engines neu auf — nötig, sobald zwischen „auf diesem Gerät" und
    /// „Anbieter" gewechselt wurde, denn dahinter steckt dann ein anderer Typ.
    /// </summary>
    public void ReloadModels(bool reset = false) => _ = Task.Run(() => LoadModelsAsync(reset));

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

    /// <summary>Womit gerade transkribiert wird — „Whisper Small" oder
    /// „whisper-large-v3 · Groq".</summary>
    public string TranscriberName => transcriber.DisplayName;

    /// <summary>Womit gerade aufbereitet wird.</summary>
    public string FormatterName => formatter.DisplayName;

    /// <summary>Erzeugt „Dein Sprachprofil" aus einer Textprobe des Verlaufs.
    /// null = kein Modell geladen oder Erzeugung fehlgeschlagen.</summary>
    public Task<string?> DescribeVoiceAsync(string sample) => formatter.DescribeVoiceAsync(sample);

    /// <summary>Warteschlange der Datei-Transkriptionen (Seite „Dateien"). Teilt sich
    /// Modelle und Wörterbuch mit dem Diktat; serialisiert wird über die Sperren in
    /// <see cref="Transcriber"/> und <see cref="LlmFormatter"/>.</summary>
    public FileTranscriptionQueue FileQueue => fileQueue ??= new FileTranscriptionQueue(transcriber, formatter, dictionary);

    /// <summary>Mitschnitt einer Besprechung. Gehört dem Tray-Kontext, damit eine
    /// laufende Aufnahme das Schließen des Fensters übersteht.</summary>
    public MeetingRecorder MeetingRecorder { get; } = new();
    private FileTranscriptionQueue? fileQueue;

    /// <summary>Aufnahme-Art aus den Einstellungen.</summary>
    private static HotkeyManager.Mode HotkeyMode => Settings.Shared.HotkeyMode switch
    {
        "hold" => HotkeyManager.Mode.Hold,
        "doubleTap" => HotkeyManager.Mode.DoubleTap,
        _ => HotkeyManager.Mode.Toggle,
    };

    /// <summary>
    /// Registriert den eingestellten Hotkey. Ist er belegt (Strg+Alt+Leertaste gehört
    /// z. B. der Claude-App), wird der Reihe nach eine Ausweich-Kombination probiert,
    /// gespeichert und gemeldet — sonst stünde die App ohne Auslöser da und der
    /// Nutzer müsste selbst raten, welche Kombination noch frei ist.
    /// </summary>
    public void RegisterHotkeyFromSettings()
    {
        var s = Settings.Shared;
        if (hotkey.Register(s.HotkeyModifiers, s.HotkeyKey, HotkeyMode, s.HotkeyModifierOnly))
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
            s.HotkeyModifierOnly = false;
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
        formattingItem.Text = Loc.T("Text aufbereiten");
        pasteLastItem.Text = Loc.T("Zuletzt Gesprochenes einfügen");
        correctLastItem.Text = Loc.T("Letztes Diktat korrigieren …");
        tray.Text = Loc.T("shout. — lokale Diktier-App");
    }

    // MARK: Letztes Diktat

    /// <summary>Fügt das zuletzt eingefügte Diktat noch einmal ein (Mac: ⌃⌘V).</summary>
    private void PasteLastDictation()
    {
        var text = lastInsertedText.Trim();
        if (text.Length == 0) return;
        TextInjector.Insert(text, Settings.Shared.KeepInClipboard);
        sounds.Play(SoundCues.Cue.Done);
    }

    /// <summary>
    /// Öffnet den Korrektur-Editor fürs letzte Diktat. Was der Nutzer ändert, lernt
    /// das Wörterbuch — in shout.s eigenem Fenster, also unabhängig davon, in welchem
    /// Programm der Text gelandet ist.
    /// </summary>
    private void ShowCorrection()
    {
        var text = lastInsertedText.Trim();
        if (text.Length == 0) return;
        if (correctionForm is { IsDisposed: false })
        {
            correctionForm.Activate();
            return;
        }
        correctionForm = new CorrectionForm(text, corrected =>
        {
            var learned = CorrectionLearner.Learn(text, corrected, dictionary);
            lastInsertedText = corrected;
            if (learned > 0) settingsForm?.RefreshDictionary();
        });
        correctionForm.FormClosed += (_, _) => correctionForm = null;
        correctionForm.Show();
        correctionForm.Activate();
    }

    /// <summary>Aufbereitung an/aus aus dem Menü (Mac: ⌘F).</summary>
    private void ToggleFormatting()
    {
        var s = Settings.Shared;
        s.FormattingEnabled = !s.FormattingEnabled;
        s.Save();
        UpdateMenu();
        settingsForm?.RefreshStatus();
        if (s.FormattingEnabled)
            _ = Task.Run(async () => { await formatter.LoadAsync(); await formatter.WarmUpAsync(); });
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
        armedTimer.Stop();
        var s = Settings.Shared;
        // Ziel-Programm JETZT merken: Bis der Text fertig ist, kann längst ein
        // anderes Fenster vorne sein — und daraus entsteht der Register-Hinweis
        // („E-Mail" formell, „Terminal" wörtlich).
        targetApp = ForegroundApp.Current();
        // Auto-Stopp nur im Umschalt-Modus sinnvoll — im Halten-Modus stoppt das
        // Loslassen (wie am Mac).
        recorder.AutoStopEnabled = s.AutoStopEnabled && HotkeyMode == HotkeyManager.Mode.Toggle;
        recorder.SilenceSeconds = s.SilenceSeconds;
        try
        {
            recorder.Start();
            SetState(State.Recording);
            overlay.ShowPhase(RecordingOverlay.Phase.Recording);
            sounds.Play(SoundCues.Cue.Start);
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
        // Hörbare Rückmeldung wie am Mac: Ein Abbruch ohne Ton lässt einen im
        // Zweifel, ob die Aufnahme wirklich weg ist.
        sounds.Play(SoundCues.Cue.Error);
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

            var raw = await transcriber.TranscribeAsync(samples);
            var output = raw.Trim();
            if (output.Length == 0) return;

            if (s.SpeechCommandsEnabled) output = SpeechCommands.Apply(output);
            if (s.FormattingEnabled) output = await formatter.FormatAsync(output, dictionary.TermHint, targetApp);
            output = dictionary.ApplyCorrections(output).Trim();
            if (output.Length == 0) return;

            var final = output;
            ui.Post(_ =>
            {
                TextInjector.Insert(final, s.KeepInClipboard);
                sounds.Play(SoundCues.Cue.Done);
                lastInsertedText = final;
                UpdateMenu();
            }, null);

            // Rohtext mitgeben: Im Verlauf lässt sich so nachsehen, was die
            // Spracherkennung WIRKLICH geliefert hat — unverzichtbar, um fehlenden
            // Inhalt der richtigen Stufe zuzuordnen (Whisper oder Aufbereitung).
            history.Add(final, raw);
            var words = final.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries).Length;
            stats.Record(words, (double)samples.Length / 16_000);
        }
        catch (Exception ex)
        {
            StoreIO.Log($"Verarbeitung fehlgeschlagen: {ex.Message}");
            ui.Post(_ => sounds.Play(SoundCues.Cue.Error), null);
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
        formattingItem.Checked = Settings.Shared.FormattingEnabled;
        pasteLastItem.Enabled = lastInsertedText.Length > 0;
        correctLastItem.Enabled = lastInsertedText.Length > 0;
        tray.Icon = AppIcons.Tray(recording: state == State.Recording);
        settingsForm?.RefreshStatus();
    }

    private DashboardForm? settingsForm;
    private OnboardingForm? onboardingForm;
    private CorrectionForm? correctionForm;

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

    /// <summary>Läuft gerade eine Aufnahme oder eine Datei-Verarbeitung? Dann ist der
    /// Modellwechsel gesperrt — er würde dem laufenden Auftrag das Modell wegziehen.</summary>
    public bool IsBusy => state is State.Recording or State.Working || FileQueueRunning;

    // MARK: Icon

    // MARK: Beenden

    /// <summary>
    /// „Beenden" aus dem Menü. Läuft noch eine Datei-Verarbeitung, wird gefragt —
    /// eine Stunde Transkription still wegzuwerfen, weil jemand aufs Menü geklickt
    /// hat, wäre der teuerste mögliche Klick der App.
    /// </summary>
    private void RequestExit()
    {
        if (FileQueueRunning)
        {
            var answer = MessageBox.Show(
                Loc.T("Es läuft noch eine Datei-Verarbeitung. Beim Beenden geht sie verloren. Trotzdem beenden?"),
                "shout.", MessageBoxButtons.YesNo, MessageBoxIcon.Warning, MessageBoxDefaultButton.Button2);
            if (answer != DialogResult.Yes) return;
        }
        ExitThread();
    }

    private bool FileQueueRunning => fileQueue is { IsRunning: true };

    private void OnSessionEnding(object sender, SessionEndingEventArgs e) => SaveRunningMeeting();

    /// <summary>
    /// Beendet einen laufenden Mitschnitt geordnet und reiht ihn ein. Ohne das war
    /// eine angefangene Besprechung beim Beenden der App verloren: Die WAV-Datei
    /// blieb ohne gültige Kopfdaten liegen, und in der Liste tauchte sie nie auf.
    /// </summary>
    private void SaveRunningMeeting()
    {
        if (!MeetingRecorder.IsRecording) return;
        try
        {
            var path = MeetingRecorder.Stop();
            if (path != null) FileQueue.Restore(new[] { path });
        }
        catch (Exception ex)
        {
            StoreIO.Log($"Mitschnitt beim Beenden nicht gesichert: {ex.Message}");
        }
    }

    protected override void ExitThreadCore()
    {
        SystemEvents.SessionEnding -= OnSessionEnding;
        armedTimer.Dispose();
        SaveRunningMeeting();
        fileQueue?.CancelAll();
        tray.Visible = false;
        tray.Dispose();
        hotkey.Dispose();
        recorder.Dispose();
        MeetingRecorder.Dispose();
        transcriber.Dispose();
        formatter.Dispose();
        sounds.Dispose();
        overlay.Dispose();
        messageWindow.Dispose();
        base.ExitThreadCore();
    }
}
