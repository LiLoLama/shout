using Shout.App;
using Shout.Core;

namespace Shout.UI;

/// <summary>
/// Einstellungen als Tab-Fenster: Allgemein, Modelle, Wörterbuch, Verlauf, Daten.
/// Bewusst programmatisches WinForms (kein Designer) — bleibt diff-bar.
/// </summary>
public sealed class SettingsForm : Form
{
    private readonly TrayContext app;
    private readonly PersonalDictionary dictionary;
    private readonly DictationHistory history;
    private readonly StatsStore stats;

    public SettingsForm(TrayContext app, PersonalDictionary dictionary,
                        DictationHistory history, StatsStore stats)
    {
        this.app = app;
        this.dictionary = dictionary;
        this.history = history;
        this.stats = stats;

        Text = "shout. — Einstellungen";
        Size = new Size(560, 560);
        MinimumSize = new Size(480, 440);
        StartPosition = FormStartPosition.CenterScreen;

        var tabs = new TabControl { Dock = DockStyle.Fill };
        tabs.TabPages.Add(BuildGeneralTab());
        tabs.TabPages.Add(BuildModelsTab());
        tabs.TabPages.Add(BuildDictionaryTab());
        tabs.TabPages.Add(BuildHistoryTab());
        tabs.TabPages.Add(BuildDataTab());
        Controls.Add(tabs);
    }

    // MARK: Allgemein

    private TabPage BuildGeneralTab()
    {
        var page = new TabPage("Allgemein");
        var panel = new TableLayoutPanel
        {
            Dock = DockStyle.Fill, ColumnCount = 2, Padding = new Padding(14), AutoScroll = true,
        };
        panel.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 45));
        panel.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 55));

        var s = Settings.Shared;

        // Hotkey-Recorder: Feld fokussieren, Kombination drücken.
        var hotkeyBox = new TextBox
        {
            ReadOnly = true, Width = 220,
            Text = HotkeyManager.Describe(s.HotkeyModifiers, s.HotkeyKey),
        };
        hotkeyBox.KeyDown += (_, e) =>
        {
            e.SuppressKeyPress = true;
            uint mods = 0;
            if (e.Control) mods |= HotkeyManager.ModControl;
            if (e.Alt) mods |= HotkeyManager.ModAlt;
            if (e.Shift) mods |= HotkeyManager.ModShift;
            var key = (uint)e.KeyCode;
            // Reine Modifier-Tasten ignorieren; mindestens ein Modifier verlangen
            // (sonst schluckt der Hotkey normale Tastendrücke systemweit).
            if (key is 0x10 or 0x11 or 0x12 || mods == 0) return;
            s.HotkeyModifiers = mods;
            s.HotkeyKey = key;
            s.Save();
            hotkeyBox.Text = HotkeyManager.Describe(mods, key);
            app.RegisterHotkeyFromSettings();
        };
        AddRow(panel, "Hotkey (Feld anklicken, Kombination drücken):", hotkeyBox);

        var language = new ComboBox { DropDownStyle = ComboBoxStyle.DropDownList, Width = 220 };
        language.Items.AddRange(new object[] { "Deutsch", "English", "Automatisch" });
        language.SelectedIndex = s.Language switch { "en" => 1, "auto" => 2, _ => 0 };
        language.SelectedIndexChanged += (_, _) =>
        {
            s.Language = language.SelectedIndex switch { 1 => "en", 2 => "auto", _ => "de" };
            s.Save();
        };
        AddRow(panel, "Sprache:", language);

        var autoStop = new CheckBox { Text = "Nach Stille automatisch stoppen", Checked = s.AutoStopEnabled, AutoSize = true };
        var silence = new NumericUpDown
        {
            Minimum = 0.5m, Maximum = 5, DecimalPlaces = 1, Increment = 0.5m,
            Value = (decimal)Math.Clamp(s.SilenceSeconds, 0.5, 5), Width = 70,
        };
        autoStop.CheckedChanged += (_, _) => { s.AutoStopEnabled = autoStop.Checked; s.Save(); };
        silence.ValueChanged += (_, _) => { s.SilenceSeconds = (double)silence.Value; s.Save(); };
        AddRow(panel, "", autoStop);
        AddRow(panel, "Stille-Dauer (Sekunden):", silence);

        var commands = new CheckBox
        {
            Text = "Sprachbefehle (Komma, neue Zeile …)",
            Checked = s.SpeechCommandsEnabled, AutoSize = true,
        };
        commands.CheckedChanged += (_, _) => { s.SpeechCommandsEnabled = commands.Checked; s.Save(); };
        AddRow(panel, "", commands);

        var formatting = new CheckBox
        {
            Text = "KI-Formatierung (lädt ein zweites Modell)",
            Checked = s.FormattingEnabled, AutoSize = true,
        };
        formatting.CheckedChanged += (_, _) =>
        {
            s.FormattingEnabled = formatting.Checked;
            s.Save();
            if (formatting.Checked) app.ReloadModels();
        };
        AddRow(panel, "", formatting);

        var clipboard = new CheckBox
        {
            Text = "Diktat zusätzlich in der Zwischenablage behalten",
            Checked = s.KeepInClipboard, AutoSize = true,
        };
        clipboard.CheckedChanged += (_, _) => { s.KeepInClipboard = clipboard.Checked; s.Save(); };
        AddRow(panel, "", clipboard);

        page.Controls.Add(panel);
        return page;
    }

    // MARK: Modelle

    private TabPage BuildModelsTab()
    {
        var page = new TabPage("Modelle");
        var panel = new FlowLayoutPanel
        {
            Dock = DockStyle.Fill, FlowDirection = FlowDirection.TopDown,
            WrapContents = false, AutoScroll = true, Padding = new Padding(14),
        };

        panel.Controls.Add(new Label
        {
            Text = "Spracherkennung (★ = Empfehlung für diesen Rechner):",
            AutoSize = true, Font = new Font(Font, FontStyle.Bold),
        });
        foreach (var m in ModelCatalog.AsrModels)
            panel.Controls.Add(ModelRow(m, isAsr: true));

        panel.Controls.Add(new Label { Text = " ", AutoSize = true });
        panel.Controls.Add(new Label
        {
            Text = "KI-Formatierung (optional):",
            AutoSize = true, Font = new Font(Font, FontStyle.Bold),
        });
        foreach (var m in ModelCatalog.LlmModels)
            panel.Controls.Add(ModelRow(m, isAsr: false));

        page.Controls.Add(panel);
        return page;
    }

    private Control ModelRow(ModelCatalog.Model model, bool isAsr)
    {
        var s = Settings.Shared;
        var row = new FlowLayoutPanel { AutoSize = true, WrapContents = false, Margin = new Padding(0, 4, 0, 4) };

        var recommended = isAsr
            ? ModelCatalog.RecommendedAsr().Id == model.Id
            : ModelCatalog.RecommendedLlm().Id == model.Id;
        var active = isAsr ? s.AsrModel == model.Id : s.LlmModel == model.Id;

        var star = recommended ? "★ " : "";
        var label = new Label
        {
            Text = $"{star}{model.Name} ({model.SizeHint}) — {model.Note}",
            AutoSize = true, MaximumSize = new Size(330, 0), Margin = new Padding(0, 5, 8, 0),
        };
        row.Controls.Add(label);

        var progress = new ProgressBar { Width = 80, Height = 14, Visible = false, Margin = new Padding(0, 6, 6, 0) };

        var button = new Button { AutoSize = true };
        void Refresh()
        {
            var downloaded = ModelCatalog.IsDownloaded(model);
            active = isAsr ? s.AsrModel == model.Id : s.LlmModel == model.Id;
            button.Text = active ? "Aktiv ✓" : downloaded ? "Aktivieren" : "Laden";
            button.Enabled = !active;
        }
        Refresh();

        button.Click += async (_, _) =>
        {
            button.Enabled = false;
            try
            {
                if (!ModelCatalog.IsDownloaded(model))
                {
                    progress.Visible = true;
                    await ModelDownloader.DownloadAsync(model, p =>
                    {
                        if (p >= 0) BeginInvoke(() => progress.Value = (int)(p * 100));
                    });
                    progress.Visible = false;
                }
                if (isAsr) s.AsrModel = model.Id; else s.LlmModel = model.Id;
                s.Save();
                app.ReloadModels();
            }
            catch (Exception ex)
            {
                progress.Visible = false;
                MessageBox.Show($"Download fehlgeschlagen: {ex.Message}", "shout.",
                    MessageBoxButtons.OK, MessageBoxIcon.Warning);
            }
            Refresh();
        };

        row.Controls.Add(progress);
        row.Controls.Add(button);
        return row;
    }

    // MARK: Wörterbuch

    private TabPage BuildDictionaryTab()
    {
        var page = new TabPage("Wörterbuch");
        // SplitterDistance NICHT im Initializer setzen: der Container hat da noch
        // seine Default-Größe (100 px hoch) und Windows klemmt den Wert still auf
        // ~70 px — erst nach dem Docking-Layout setzen.
        var split = new SplitContainer { Dock = DockStyle.Fill, Orientation = Orientation.Horizontal };
        var splitterPlaced = false;
        split.SizeChanged += (_, _) =>
        {
            if (splitterPlaced || split.Height < 300) return;
            splitterPlaced = true;
            split.SplitterDistance = split.Height / 2;
        };

        // Begriffe
        var termsList = new ListBox { Dock = DockStyle.Fill };
        void RefreshTerms()
        {
            termsList.Items.Clear();
            foreach (var t in dictionary.Data.Terms) termsList.Items.Add(t);
        }
        RefreshTerms();

        var termBox = new TextBox { Width = 200, PlaceholderText = "Eigenname/Fachbegriff" };
        var termAdd = new Button { Text = "Hinzufügen", AutoSize = true };
        termAdd.Click += (_, _) =>
        {
            dictionary.AddTerm(termBox.Text);
            termBox.Clear();
            RefreshTerms();
        };
        var termRemove = new Button { Text = "Entfernen", AutoSize = true };
        termRemove.Click += (_, _) =>
        {
            if (termsList.SelectedItem is string t) { dictionary.RemoveTerm(t); RefreshTerms(); }
        };

        split.Panel1.Controls.Add(termsList);
        split.Panel1.Controls.Add(ToolRow(new Label { Text = "Begriffe:", AutoSize = true, Font = new Font(Font, FontStyle.Bold) },
                                          termBox, termAdd, termRemove));

        // Korrekturen
        var corrList = new ListBox { Dock = DockStyle.Fill };
        void RefreshCorrections()
        {
            corrList.Items.Clear();
            foreach (var c in dictionary.Data.Corrections)
                corrList.Items.Add($"{c.Wrong} → {c.Right}");
        }
        RefreshCorrections();

        var wrongBox = new TextBox { Width = 120, PlaceholderText = "falsch" };
        var rightBox = new TextBox { Width = 120, PlaceholderText = "richtig" };
        var corrAdd = new Button { Text = "Hinzufügen", AutoSize = true };
        corrAdd.Click += (_, _) =>
        {
            dictionary.AddCorrection(wrongBox.Text, rightBox.Text);
            wrongBox.Clear(); rightBox.Clear();
            RefreshCorrections(); RefreshTerms();
        };
        var corrRemove = new Button { Text = "Entfernen", AutoSize = true };
        corrRemove.Click += (_, _) =>
        {
            if (corrList.SelectedIndex >= 0 && corrList.SelectedIndex < dictionary.Data.Corrections.Count)
            {
                dictionary.RemoveCorrection(dictionary.Data.Corrections[corrList.SelectedIndex]);
                RefreshCorrections();
            }
        };

        split.Panel2.Controls.Add(corrList);
        split.Panel2.Controls.Add(ToolRow(new Label { Text = "Korrekturen (falsch → richtig):", AutoSize = true, Font = new Font(Font, FontStyle.Bold) },
                                          wrongBox, rightBox, corrAdd, corrRemove));

        page.Controls.Add(split);
        return page;
    }

    // MARK: Verlauf

    private TabPage BuildHistoryTab()
    {
        var page = new TabPage("Verlauf");
        var list = new ListBox { Dock = DockStyle.Fill, HorizontalScrollbar = true };
        void Refresh()
        {
            list.Items.Clear();
            foreach (var e in history.Entries)
                list.Items.Add($"{e.Date.ToLocalTime():dd.MM. HH:mm}  {Shorten(e.Text)}");
        }
        Refresh();

        var copy = new Button { Text = "Kopieren", AutoSize = true };
        copy.Click += (_, _) =>
        {
            if (list.SelectedIndex >= 0 && list.SelectedIndex < history.Entries.Count)
                Clipboard.SetText(history.Entries[list.SelectedIndex].Text);
        };
        var delete = new Button { Text = "Löschen", AutoSize = true };
        delete.Click += (_, _) =>
        {
            if (list.SelectedIndex >= 0 && list.SelectedIndex < history.Entries.Count)
            {
                history.Delete(history.Entries[list.SelectedIndex]);
                Refresh();
            }
        };
        var clear = new Button { Text = "Alle löschen", AutoSize = true };
        clear.Click += (_, _) =>
        {
            if (MessageBox.Show("Gesamten Verlauf löschen?", "shout.",
                    MessageBoxButtons.YesNo, MessageBoxIcon.Question) == DialogResult.Yes)
            {
                history.Clear();
                Refresh();
            }
        };

        page.Controls.Add(list);
        page.Controls.Add(ToolRow(copy, delete, clear));
        return page;
    }

    // MARK: Daten (Statistik + Backup)

    private TabPage BuildDataTab()
    {
        var page = new TabPage("Daten");
        var panel = new FlowLayoutPanel
        {
            Dock = DockStyle.Fill, FlowDirection = FlowDirection.TopDown,
            WrapContents = false, AutoScroll = true, Padding = new Padding(14),
        };

        panel.Controls.Add(new Label
        {
            Text = $"Statistik: {stats.Data.TotalDictations} Diktate · {stats.Data.TotalWords} Wörter · " +
                   $"Ø {stats.AverageWpm} WPM · Streak {stats.CurrentStreak} Tage",
            AutoSize = true, Margin = new Padding(0, 0, 0, 14),
        });

        panel.Controls.Add(new Label
        {
            Text = "Übertragung zwischen Geräten (Mac, iPhone, Windows) per Backup-Datei.\n" +
                   "Achtung: Import ERSETZT Wörterbuch, Verlauf und Statistiken.",
            AutoSize = true, Margin = new Padding(0, 0, 0, 8),
        });

        var export = new Button { Text = "Exportieren …", AutoSize = true };
        export.Click += (_, _) =>
        {
            using var dialog = new SaveFileDialog
            {
                FileName = "shout-backup.json",
                Filter = "shout-Backup (*.json)|*.json",
            };
            if (dialog.ShowDialog() == DialogResult.OK)
                BackupBundle.ExportToFile(dialog.FileName, dictionary, history, stats);
        };

        var import = new Button { Text = "Importieren …", AutoSize = true };
        import.Click += (_, _) =>
        {
            using var dialog = new OpenFileDialog { Filter = "shout-Backup (*.json)|*.json" };
            if (dialog.ShowDialog() == DialogResult.OK)
            {
                var message = BackupBundle.ImportFromFile(dialog.FileName, dictionary, history, stats);
                MessageBox.Show(message, "shout.", MessageBoxButtons.OK, MessageBoxIcon.Information);
            }
        };

        panel.Controls.Add(ToolRow(export, import));
        page.Controls.Add(panel);
        return page;
    }

    // MARK: Helfer

    private static void AddRow(TableLayoutPanel panel, string label, Control control)
    {
        panel.RowCount++;
        panel.Controls.Add(new Label { Text = label, AutoSize = true, Margin = new Padding(0, 8, 0, 0) });
        panel.Controls.Add(control);
    }

    private static FlowLayoutPanel ToolRow(params Control[] controls)
    {
        var row = new FlowLayoutPanel { Dock = DockStyle.Top, AutoSize = true, Padding = new Padding(6) };
        foreach (var c in controls) { c.Margin = new Padding(2, 4, 6, 2); row.Controls.Add(c); }
        return row;
    }

    private static string Shorten(string text)
    {
        var flat = text.Replace('\n', ' ');
        return flat.Length > 90 ? flat[..90] + "…" : flat;
    }
}
