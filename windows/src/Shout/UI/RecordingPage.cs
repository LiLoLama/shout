using Shout.App;
using Shout.Core;

namespace Shout.UI;

/// <summary>
/// „Aufnahme & Text" — Aufbau und Texte wie SettingsView.swift der Mac-App,
/// einschließlich der Aufnahme-Art (halten/umschalten): den Halten-Modus trägt
/// unter Windows ein Tastatur-Hook, siehe <see cref="HotkeyManager"/>.
/// </summary>
internal sealed class RecordingPage : PageBase
{
    protected override int MaxContentWidth => 520;

    private readonly TrayContext app;
    private readonly DashboardForm form;
    private readonly Keycap hotkeyCap;
    private readonly Keycap silenceValue;
    private readonly ConsoleButton changeHotkey;
    private readonly ConsolePanel recording;

    public RecordingPage(TrayContext app, DashboardForm form)
    {
        this.app = app;
        this.form = form;
        var s = Settings.Shared;

        // MARK: Aufnahme

        hotkeyCap = new Keycap(HotkeyManager.Describe(s.HotkeyModifiers, s.HotkeyKey));
        changeHotkey = new ConsoleButton(Loc.T("Ändern"));
        changeHotkey.Click2 += BeginHotkeyCapture;

        // Die Karte steht schon hier, weil der Umschalter unten auf sie zugreift.
        recording = new ConsolePanel { Title = Loc.T("Aufnahme") };
        var card = recording;

        var mode = new ConsoleSegmented(new[]
        {
            ("hold", Loc.T("Halten")),
            ("toggle", Loc.T("Umschalten")),
        }, s.HotkeyMode == "hold" ? "hold" : "toggle");
        mode.Changed += key =>
        {
            s.HotkeyMode = key;
            s.Save();
            // Die Aufnahme-Art entscheidet, WIE der Hotkey registriert wird
            // (RegisterHotKey oder Tastatur-Hook) — also neu registrieren.
            app.RegisterHotkeyFromSettings();
            // Der Hilfetext der Zeile hängt am Modus — Höhe neu rechnen.
            card.Relayout();
            form.PageHeightChanged();
        };

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

        recording.Add(new PanelRow
        {
            Title = Loc.T("Aufnahme-Art"),
            HelpFor = () => Settings.Shared.HotkeyMode == "hold"
                ? Loc.T("Tastenkombination gedrückt halten, beim Loslassen wird eingefügt.")
                : Loc.T("Einmal drücken zum Starten, nochmal zum Stoppen."),
            Trailing = mode,
        });
        recording.Add(Loc.T("So startest du"), Loc.T("Drück die Tastenkombination, mit der du diktieren willst."),
                      new Cluster(new Control[] { hotkeyCap, changeHotkey }));
        recording.Add(Loc.T("Von selbst aufhören"),
                      Loc.T("Stoppt automatisch nach kurzer Sprechpause (im Umschalt-Modus)."), autoStop);
        recording.Add(new PanelRow
        {
            Title = Loc.T("Pause bis Stopp"),
            Trailing = new Cluster(new Control[] { silenceSlider, silenceValue }, 12),
            VisibleWhen = () => Settings.Shared.AutoStopEnabled,
        });
        recording.Add(Loc.T("Pille immer anzeigen"),
                      Loc.T("Zeigt die Aufnahme-Pille dauerhaft am Bildschirmrand — per Klick starten, mit ✕/✓ abbrechen oder einfügen."),
                      persistentPill);
        recording.Add(Loc.T("Position der Pille"),
                      Loc.T("Wähle eine Ecke — oder zieh die Pille einfach mit der Maus an eine beliebige Stelle."),
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

        var text = new ConsolePanel { Title = Loc.T("Text") };
        text.Add(Loc.T("Text automatisch aufräumen"),
                 Loc.T("Füllwörter raus, Satzzeichen und Aufzählungen setzen. Lädt ein zweites Modell."),
                 formatting);
        text.Add(Loc.T("Sprachbefehle"),
                 Loc.T("‚Komma', ‚Punkt', ‚Fragezeichen', ‚neue Zeile', ‚neuer Absatz' werden zu echten Satzzeichen/Umbrüchen."),
                 speechCommands);
        text.Add(Loc.T("In der Zwischenablage behalten"),
                 Loc.T("Das Diktat bleibt zusätzlich in der Zwischenablage — sonst wird der vorherige Inhalt wiederhergestellt."),
                 clipboard);
        Push(text);

        // MARK: Sprache & Ton

        var language = new ConsoleDropdown(170);
        language.SetItems(new[]
        {
            ("de", Loc.T("Deutsch")),
            ("en", Loc.T("English")),
            ("auto", Loc.T("Automatisch")),
        }, s.Language);
        language.Changed += key => { s.Language = key; s.Save(); };

        var soundCues = new ConsoleToggle(s.SoundCuesEnabled);
        soundCues.Changed += value => { s.SoundCuesEnabled = value; s.Save(); };

        // Oberflächensprache. Die Texte stecken schon in den fertig gebauten
        // Controls, daher lässt das Fenster sich nach dem Wechsel neu aufbauen.
        var uiLanguage = new ConsoleDropdown(170);
        uiLanguage.SetItems(Loc.LanguageOptions, s.UiLanguage);
        uiLanguage.Changed += key =>
        {
            s.UiLanguage = key;
            s.Save();
            Loc.Initialize();
            app.ApplyLanguageChange();
        };

        var sound = new ConsolePanel { Title = Loc.T("Sprache & Ton") };
        sound.Add(Loc.T("Diktier-Sprache"),
                  Loc.T("Sprache der Transkription. „Automatisch“ erkennt sie pro Aufnahme selbst."), language);
        sound.Add(Loc.T("Oberfläche"),
                  Loc.T("Sprache der Bedienoberfläche. „Wie das System“ folgt der Windows-Anzeigesprache."),
                  uiLanguage);
        sound.Add(Loc.T("Klang-Signale"),
                  Loc.T("Dezente Töne beim Start der Aufnahme und wenn der Text eingefügt ist."), soundCues);
        Push(sound);

        // MARK: Mikrofon

        var mic = new ConsoleDropdown(220);
        var devices = new List<(string, string)> { ("-1", Loc.T("Systemstandard")) };
        devices.AddRange(AudioRecorder.InputDevices().Select(d => (d.Index.ToString(), d.Name)));
        mic.SetItems(devices, s.InputDeviceIndex.ToString());
        mic.Changed += key =>
        {
            s.InputDeviceIndex = int.TryParse(key, out var index) ? index : -1;
            s.Save();
        };

        var micPanel = new ConsolePanel { Title = Loc.T("Mikrofon") };
        micPanel.Add(Loc.T("Eingang"), null, mic);
        Push(micPanel);
    }

    private static (string Key, string Label)[] PillPositionItems()
    {
        var items = new List<(string, string)>
        {
            ("bottomCenter", Loc.T("Unten Mitte")),
            ("bottomLeft", Loc.T("Unten links")),
            ("bottomRight", Loc.T("Unten rechts")),
            ("topCenter", Loc.T("Oben Mitte")),
            ("topLeft", Loc.T("Oben links")),
            ("topRight", Loc.T("Oben rechts")),
        };
        if (Settings.Shared.PillCustom) items.Add(("custom", Loc.T("Frei verschoben")));
        return items.ToArray();
    }

    // MARK: Hotkey aufnehmen

    private void BeginHotkeyCapture()
    {
        if (form.IsCapturingHotkey) return;
        hotkeyCap.SetText(Loc.T("Taste drücken …"));
        changeHotkey.SetEnabled(false);
        // Solange abmelden: ein registrierter Hotkey (bzw. der Tastatur-Hook des
        // Halten-Modus) erreicht dieses Fenster nie — die aktuelle Kombination
        // ließe sich sonst nicht erneut auswählen.
        app.PauseHotkey();
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

    /// <summary>Zeigt die aktuell gültige Kombination — nach Abbruch der Aufnahme
    /// (Escape) und wenn die App auf eine Ausweich-Kombination gewechselt ist.</summary>
    public void ShowCurrentHotkey()
    {
        var s = Settings.Shared;
        hotkeyCap.SetText(HotkeyManager.Describe(s.HotkeyModifiers, s.HotkeyKey));
        changeHotkey.SetEnabled(true);
        form.PageHeightChanged();
    }
}
