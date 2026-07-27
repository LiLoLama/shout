using Shout.App;
using Shout.Core;

namespace Shout.UI;

/// <summary>
/// „Aufnahme & Text" — Aufbau und Texte wie SettingsView.swift der Mac-App.
/// Die Aufnahme-Art (halten/umschalten) fehlt bewusst: der Windows-Hotkey über
/// RegisterHotKey kennt kein Loslassen, hier gilt immer „umschalten".
/// </summary>
internal sealed class RecordingPage : PageBase
{
    protected override int MaxContentWidth => 520;

    private readonly TrayContext app;
    private readonly DashboardForm form;
    private readonly Keycap hotkeyCap;
    private readonly Keycap silenceValue;
    private readonly ConsoleButton changeHotkey;

    public RecordingPage(TrayContext app, DashboardForm form)
    {
        this.app = app;
        this.form = form;
        var s = Settings.Shared;

        // MARK: Aufnahme

        hotkeyCap = new Keycap(HotkeyManager.Describe(s.HotkeyModifiers, s.HotkeyKey));
        changeHotkey = new ConsoleButton("Ändern");
        changeHotkey.Click2 += BeginHotkeyCapture;

        var autoStop = new ConsoleToggle(s.AutoStopEnabled);
        autoStop.Changed += value =>
        {
            s.AutoStopEnabled = value;
            s.Save();
            // „Pause bis Stopp" erscheint/verschwindet — Höhe neu berechnen.
            form.PageHeightChanged();
        };

        silenceValue = new Keycap($"{s.SilenceSeconds:0.0} s");
        var silenceSlider = new ConsoleSlider(0.5, 3.0, 0.1, s.SilenceSeconds, 130);
        silenceSlider.Changed += value =>
        {
            s.SilenceSeconds = value;
            s.Save();
            silenceValue.SetText($"{value:0.0} s");
        };

        var persistentPill = new ConsoleToggle(s.PersistentPill);
        persistentPill.Changed += value =>
        {
            s.PersistentPill = value;
            s.Save();
            app.ApplyPersistentPill();
        };

        var pillPosition = new ConsoleDropdown(170);
        pillPosition.SetItems(PillPositionItems(), s.PillCustom ? "custom" : s.PillAnchor);
        pillPosition.Changed += key =>
        {
            if (key == "custom") return;
            s.PillAnchor = key;
            s.PillCustom = false;
            s.Save();
            pillPosition.SetItems(PillPositionItems(), key);
            app.RepositionPill();
        };

        var recording = new ConsolePanel { Title = "Aufnahme" };
        recording.Add("So startest du", "Drück die Tastenkombination, mit der du diktieren willst.",
                      new Cluster(new Control[] { hotkeyCap, changeHotkey }));
        recording.Add("Von selbst aufhören", "Stoppt automatisch nach kurzer Sprechpause.", autoStop);
        recording.Add(new PanelRow
        {
            Title = "Pause bis Stopp",
            Trailing = new Cluster(new Control[] { silenceSlider, silenceValue }, 12),
            VisibleWhen = () => Settings.Shared.AutoStopEnabled,
        });
        recording.Add("Pille immer anzeigen",
                      "Zeigt die Aufnahme-Pille dauerhaft am Bildschirmrand — per Klick starten, mit ✕/✓ abbrechen oder einfügen.",
                      persistentPill);
        recording.Add("Position der Pille",
                      "Wähle eine Ecke — oder zieh die Pille einfach mit der Maus an eine beliebige Stelle.",
                      pillPosition);
        Push(recording, 0);

        // MARK: Text

        var formatting = new ConsoleToggle(s.FormattingEnabled);
        formatting.Changed += value =>
        {
            s.FormattingEnabled = value;
            s.Save();
            if (value) app.ReloadModels();   // lädt das Formatierungs-Modell nach
        };

        var speechCommands = new ConsoleToggle(s.SpeechCommandsEnabled);
        speechCommands.Changed += value => { s.SpeechCommandsEnabled = value; s.Save(); };

        var clipboard = new ConsoleToggle(s.KeepInClipboard);
        clipboard.Changed += value => { s.KeepInClipboard = value; s.Save(); };

        var text = new ConsolePanel { Title = "Text" };
        text.Add("Text automatisch aufräumen",
                 "Füllwörter raus, Satzzeichen und Aufzählungen setzen. Lädt ein zweites Modell.",
                 formatting);
        text.Add("Sprachbefehle",
                 "‚Komma', ‚Punkt', ‚Fragezeichen', ‚neue Zeile', ‚neuer Absatz' werden zu echten Satzzeichen/Umbrüchen.",
                 speechCommands);
        text.Add("In der Zwischenablage behalten",
                 "Das Diktat bleibt zusätzlich in der Zwischenablage — sonst wird der vorherige Inhalt wiederhergestellt.",
                 clipboard);
        Push(text);

        // MARK: Sprache & Ton

        var language = new ConsoleDropdown(170);
        language.SetItems(new[]
        {
            ("de", "Deutsch"),
            ("en", "English"),
            ("auto", "Automatisch"),
        }, s.Language);
        language.Changed += key => { s.Language = key; s.Save(); };

        var soundCues = new ConsoleToggle(s.SoundCuesEnabled);
        soundCues.Changed += value => { s.SoundCuesEnabled = value; s.Save(); };

        var sound = new ConsolePanel { Title = "Sprache & Ton" };
        sound.Add("Diktier-Sprache",
                  "Sprache der Transkription. „Automatisch“ erkennt sie pro Aufnahme selbst.", language);
        sound.Add("Klang-Signale",
                  "Dezente Töne beim Start der Aufnahme und wenn der Text eingefügt ist.", soundCues);
        Push(sound);

        // MARK: Mikrofon

        var mic = new ConsoleDropdown(220);
        var devices = new List<(string, string)> { ("-1", "Systemstandard") };
        devices.AddRange(AudioRecorder.InputDevices().Select(d => (d.Index.ToString(), d.Name)));
        mic.SetItems(devices, s.InputDeviceIndex.ToString());
        mic.Changed += key =>
        {
            s.InputDeviceIndex = int.TryParse(key, out var index) ? index : -1;
            s.Save();
        };

        var micPanel = new ConsolePanel { Title = "Mikrofon" };
        micPanel.Add("Eingang", null, mic);
        Push(micPanel);
    }

    private static (string Key, string Label)[] PillPositionItems()
    {
        var items = new List<(string, string)>
        {
            ("bottomCenter", "Unten Mitte"),
            ("bottomLeft", "Unten links"),
            ("bottomRight", "Unten rechts"),
            ("topCenter", "Oben Mitte"),
            ("topLeft", "Oben links"),
            ("topRight", "Oben rechts"),
        };
        if (Settings.Shared.PillCustom) items.Add(("custom", "Frei verschoben"));
        return items.ToArray();
    }

    // MARK: Hotkey aufnehmen

    private void BeginHotkeyCapture()
    {
        if (form.IsCapturingHotkey) return;
        hotkeyCap.SetText("Taste drücken …");
        changeHotkey.SetEnabled(false);
        form.CaptureHotkey((mods, key) =>
        {
            var s = Settings.Shared;
            s.HotkeyModifiers = mods;
            s.HotkeyKey = key;
            s.Save();
            hotkeyCap.SetText(HotkeyManager.Describe(mods, key));
            changeHotkey.SetEnabled(true);
            app.RegisterHotkeyFromSettings();
            form.PageHeightChanged();
        });
    }

    /// <summary>Escape während der Aufnahme — Anzeige zurücksetzen.</summary>
    public void HotkeyCaptureEnded()
    {
        var s = Settings.Shared;
        hotkeyCap.SetText(HotkeyManager.Describe(s.HotkeyModifiers, s.HotkeyKey));
        changeHotkey.SetEnabled(true);
        form.PageHeightChanged();
    }
}
