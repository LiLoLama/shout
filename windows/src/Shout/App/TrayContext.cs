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
    private readonly SynchronizationContext ui;

    public TrayContext()
    {
        ui = SynchronizationContext.Current ?? new WindowsFormsSynchronizationContext();

        statusItem = new ToolStripMenuItem("Modell wird geladen …") { Enabled = false };
        dictateItem = new ToolStripMenuItem("Diktieren", null, (_, _) => ToggleRecording());

        var menu = new ContextMenuStrip();
        menu.Items.Add(statusItem);
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add(dictateItem);
        menu.Items.Add(new ToolStripMenuItem("Einstellungen …", null, (_, _) => ShowSettings()));
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add(new ToolStripMenuItem("Beenden", null, (_, _) => ExitThread()));

        tray = new NotifyIcon
        {
            Icon = MakeIcon(idle: true),
            Text = "shout. — lokale Diktier-App",
            ContextMenuStrip = menu,
            Visible = true,
        };
        tray.DoubleClick += (_, _) => ToggleRecording();

        overlay.OnClickStop += () => { if (state == State.Recording) StopAndProcess(); };
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

    // MARK: Aufnahme

    private void ToggleRecording()
    {
        switch (state)
        {
            case State.Idle: StartRecording(); break;
            case State.Recording: StopAndProcess(); break;
            case State.Failed: _ = LoadModelsAsync(); break;   // erneuter Versuch
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
            SystemSounds.Exclamation.Play();
        }
        catch (Exception ex)
        {
            SetState(State.Failed);
            tray.ShowBalloonTip(4000, "shout.",
                $"Aufnahme konnte nicht gestartet werden: {ex.Message}", ToolTipIcon.Error);
        }
    }

    private void StopAndProcess()
    {
        var samples = recorder.Stop();
        SetState(State.Working);
        overlay.ShowPhase(RecordingOverlay.Phase.Working);

        // Threadpool: die Inferenz darf nie den UI-Thread blockieren (die
        // „Verarbeite …"-Animation liefe sonst nicht) — UI-Arbeit geht per ui.Post.
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
                SystemSounds.Asterisk.Play();
            }, null);

            history.Add(final);
            var words = final.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries).Length;
            stats.Record(words, (double)samples.Length / 16_000);
        }
        catch (Exception ex)
        {
            Log($"Verarbeitung fehlgeschlagen: {ex.Message}");
            ui.Post(_ => SystemSounds.Hand.Play(), null);
        }
        finally
        {
            ui.Post(_ =>
            {
                overlay.HideOverlay();
                SetState(transcriber.IsReady ? State.Idle : State.Failed);
            }, null);
        }
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
    }

    private SettingsForm? settingsForm;

    private void ShowSettings()
    {
        if (settingsForm is { IsDisposed: false })
        {
            settingsForm.Activate();
            return;
        }
        settingsForm = new SettingsForm(this, dictionary, history, stats);
        settingsForm.Show();
    }

    // MARK: Icon

    /// <summary>Zeichnet das Tray-Icon zur Laufzeit: oranger Punkt (Aufnahme:
    /// gefüllt, sonst Ring) — kein Icon-Asset nötig.</summary>
    private static Icon MakeIcon(bool idle)
    {
        using var bmp = new Bitmap(32, 32);
        using var g = Graphics.FromImage(bmp);
        g.SmoothingMode = System.Drawing.Drawing2D.SmoothingMode.AntiAlias;
        var accent = Color.FromArgb(255, 74, 10);
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
        base.ExitThreadCore();
    }
}
