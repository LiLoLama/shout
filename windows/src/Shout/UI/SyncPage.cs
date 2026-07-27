using Shout.App;
using Shout.Core;

namespace Shout.UI;

/// <summary>
/// „Sync & Geräte" — bewusst ohne Cloud: Daten als Datei exportieren, auf ein
/// anderes Gerät kopieren und dort importieren (Mac: SyncView.swift). Das Format
/// ist mit Mac und iPhone kompatibel.
/// </summary>
internal sealed class SyncPage : PageBase
{
    protected override int MaxContentWidth => 640;

    private readonly PersonalDictionary dictionary;
    private readonly DictationHistory history;
    private readonly StatsStore stats;
    private readonly TextBlock status = new("", Theme.Small, Theme.Live);

    public SyncPage(PersonalDictionary dictionary, DictationHistory history, StatsStore stats)
    {
        this.dictionary = dictionary;
        this.history = history;
        this.stats = stats;

        Push(new SectionHeader(Loc.T("Sync & Geräte")), 0);

        var export = new ConsoleButton(Loc.T("Exportieren …"));
        export.Click2 += Export;
        var import = new ConsoleButton(Loc.T("Importieren …"));
        import.Click2 += Import;

        status.Visible = false;

        var transfer = new ConsoleBox { Title = Loc.T("Daten übertragen") };
        transfer.Add(TextBlock.Body(Loc.T(
            "shout. speichert alles lokal — keine Cloud. Für ein zweites Gerät exportierst du eine Datei, kopierst sie hinüber (USB-Stick, Netzwerk …) und importierst sie dort. Die Datei passt auch zur Mac- und iPhone-App.")), 0);
        transfer.Add(new Cluster(new Control[] { export, import }), 14);
        transfer.Add(status);
        Push(transfer);

        var contents = new ConsolePanel { Title = Loc.T("In der Datei enthalten") };
        contents.Add(new PanelRow
        {
            Title = Loc.T("Wörterbuch"), Help = Loc.T("Begriffe & gelernte Korrekturen"), Icon = Icons.Kind.Book,
        });
        contents.Add(new PanelRow
        {
            Title = Loc.T("Verlauf"), Help = Loc.T("Deine bisherigen Diktate"), Icon = Icons.Kind.History,
        });
        contents.Add(new PanelRow
        {
            Title = Loc.T("Statistiken"), Help = Loc.T("Wörter, Streak, aktive Tage"), Icon = Icons.Kind.Chart,
        });
        contents.Add(new PanelRow
        {
            Title = Loc.T("Einstellungen"), Help = Loc.T("Auto-Stopp, Stille-Dauer, Formatierung"), Icon = Icons.Kind.Mic,
        });
        Push(contents);

        Push(TextBlock.Footnote(Loc.T(
            "Beim Import werden die aktuellen Daten auf diesem Gerät ersetzt. Die Datei enthält deinen Verlauf im Klartext — behandle sie vertraulich.")));
    }

    private void Export()
    {
        using var dialog = new SaveFileDialog
        {
            FileName = "shout-backup.json",
            Filter = Loc.T("shout-Backup (*.json)|*.json"),
        };
        if (dialog.ShowDialog() != DialogResult.OK) return;
        try
        {
            BackupBundle.ExportToFile(dialog.FileName, dictionary, history, stats);
            ShowStatus(Loc.F("Exportiert nach {0}.", Path.GetFileName(dialog.FileName)));
        }
        catch (Exception ex)
        {
            ShowStatus(Loc.F("Export fehlgeschlagen: {0}", ex.Message));
        }
    }

    private void Import()
    {
        using var dialog = new OpenFileDialog { Filter = Loc.T("shout-Backup (*.json)|*.json") };
        if (dialog.ShowDialog() != DialogResult.OK) return;
        if (MessageBox.Show(
                Loc.T("Import ERSETZT Wörterbuch, Verlauf und Statistiken auf diesem Gerät. Fortfahren?"),
                "shout.", MessageBoxButtons.YesNo, MessageBoxIcon.Warning) != DialogResult.Yes) return;

        ShowStatus(BackupBundle.ImportFromFile(dialog.FileName, dictionary, history, stats));
    }

    private void ShowStatus(string message)
    {
        status.SetText(message);
        status.Visible = true;
        NotifyHeightChanged();
    }
}

/// <summary>
/// „Unterstützen" — shout. ist Open Source; wer mag, unterstützt freiwillig
/// (Mac: SupportView.swift).
/// </summary>
internal sealed class SupportPage : PageBase
{
    protected override int MaxContentWidth => 640;

    private const string DonateUrl = "https://ko-fi.com/lilolama";
    private const string GithubUrl = "https://github.com/LiLoLama/shout";

    private readonly Updater updates;
    private readonly TextBlock updateStatus;
    private readonly ConsoleButton updateButton;

    public SupportPage(TrayContext app)
    {
        updates = app.Updates;

        Push(new SectionHeader(Loc.T("Unterstützen")), 0);

        // MARK: Aktualisierung

        updateStatus = new TextBlock(updates.StatusText, Theme.Small, Theme.Gray(0.62));
        updateButton = new ConsoleButton(Loc.T("Nach Aktualisierungen suchen"));
        updateButton.Click2 += UpdateButtonClicked;

        var updatePanel = new ConsoleBox { Title = Loc.T("Aktualisierung") };
        updatePanel.Add(new TextBlock(Loc.F("shout. {0} für Windows", updates.CurrentVersion),
                                      Theme.RowTitle, Theme.Gray(0.9)), 0);
        updatePanel.Add(updateStatus, 6);
        updatePanel.Add(new Cluster(new Control[] { updateButton }), 14);
        Push(updatePanel);

        RefreshUpdateState();

        var donate = new ConsoleButton(Loc.T("Unterstützen"), primary: true, icon: Icons.Kind.Coffee);
        donate.Click2 += () => OpenUrl(DonateUrl);
        var source = new ConsoleButton(Loc.T("Quellcode auf GitHub"), icon: Icons.Kind.Code);
        source.Click2 += () => OpenUrl(GithubUrl);

        var intro = new ConsoleBox { ContentHeaderHeight = 52 };
        intro.PaintContent = (g, inner) =>
        {
            Icons.Draw(g, Icons.Kind.Heart, new RectangleF(inner.X, inner.Y, 36, 36), Theme.Live, 30f);
            TextRenderer.DrawText(g, Loc.T("shout. ist Open Source"), Theme.PageTitle,
                                  new Rectangle(inner.X + 48, inner.Y + 2, inner.Width - 48, 24),
                                  Theme.Gray(0.95), TextFormatFlags.NoPrefix);
            TextRenderer.DrawText(g, Loc.T("Kostenlos, quelloffen und komplett lokal."), Theme.Small,
                                  new Rectangle(inner.X + 48, inner.Y + 26, inner.Width - 48, 20),
                                  Theme.Gray(0.58), TextFormatFlags.NoPrefix);
        };
        intro.Add(TextBlock.Body(Loc.T(
            "shout. entsteht in meiner freien Zeit. Wenn dir die App hilft und du die Weiterentwicklung unterstützen möchtest, freue ich mich riesig — freiwillig, ohne Verpflichtung.")), 0);
        intro.Add(new Cluster(new Control[] { donate, source }), 14);
        Push(intro);

        var points = new ConsolePanel { Title = Loc.T("Was shout. ausmacht") };
        points.Add(new PanelRow
        {
            Title = Loc.T("Frei & quelloffen"),
            Help = Loc.T("Der komplette Quellcode ist öffentlich — nutzen, anpassen, weitergeben."),
            Icon = Icons.Kind.LockOpen,
        });
        points.Add(new PanelRow
        {
            Title = Loc.T("Lokal & privat"),
            Help = Loc.T("Keine Cloud, keine Konten, keine Datenweitergabe. Alles bleibt auf deinem Rechner."),
            Icon = Icons.Kind.Lock,
        });
        points.Add(new PanelRow
        {
            Title = Loc.T("Aktiv gepflegt"),
            Help = Loc.T("Ich bemühe mich, shout. aktuell zu halten, zu verbessern und zu erweitern."),
            Icon = Icons.Kind.Branch,
        });
        Push(points);

        Push(TextBlock.Footnote(
            Loc.T("Fehler gefunden oder eine Idee? Auf GitHub freue ich mich über Issues und Pull Requests.")));
    }

    /// <summary>Je nach Zustand suchen, laden oder neu starten.</summary>
    private void UpdateButtonClicked()
    {
        switch (updates.Status)
        {
            case Updater.State.Available:
                _ = Task.Run(updates.DownloadAsync);
                break;
            case Updater.State.ReadyToRestart:
                updates.ApplyAndRestart();
                break;
            case Updater.State.Unsupported:
                OpenUrl(GithubUrl + "/releases/latest");
                break;
            default:
                _ = Task.Run(async () =>
                {
                    await updates.CheckAsync();
                    if (updates.Status == Updater.State.Available) await updates.DownloadAsync();
                });
                break;
        }
    }

    /// <summary>Statuszeile und Knopfbeschriftung nachziehen (vom TrayContext gerufen).</summary>
    public void RefreshUpdateState()
    {
        updateStatus.SetText(updates.StatusText);
        updateButton.Text = updates.Status switch
        {
            Updater.State.Available => Loc.T("Jetzt laden"),
            Updater.State.ReadyToRestart => Loc.T("Neu starten und übernehmen"),
            Updater.State.Unsupported => Loc.T("Releases auf GitHub öffnen"),
            _ => Loc.T("Nach Aktualisierungen suchen"),
        };
        updateButton.SetEnabled(updates.Status is not (Updater.State.Checking or Updater.State.Downloading));
        NotifyHeightChanged();
    }

    private static void OpenUrl(string url)
    {
        try
        {
            System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo(url)
            {
                UseShellExecute = true,
            });
        }
        catch
        {
            // Kein Standardbrowser gesetzt — dann passiert schlicht nichts.
        }
    }
}
