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

        Push(new SectionHeader("Sync & Geräte"), 0);

        var export = new ConsoleButton("Exportieren …");
        export.Click2 += Export;
        var import = new ConsoleButton("Importieren …");
        import.Click2 += Import;

        status.Visible = false;

        var transfer = new ConsoleBox { Title = "Daten übertragen" };
        transfer.Add(TextBlock.Body(
            "shout. speichert alles lokal — keine Cloud. Für ein zweites Gerät exportierst du eine "
            + "Datei, kopierst sie hinüber (USB-Stick, Netzwerk …) und importierst sie dort. Die Datei "
            + "passt auch zur Mac- und iPhone-App."), 0);
        transfer.Add(new Cluster(new Control[] { export, import }), 14);
        transfer.Add(status);
        Push(transfer);

        var contents = new ConsolePanel { Title = "In der Datei enthalten" };
        contents.Add(new PanelRow
        {
            Title = "Wörterbuch", Help = "Begriffe & gelernte Korrekturen", Icon = Icons.Kind.Book,
        });
        contents.Add(new PanelRow
        {
            Title = "Verlauf", Help = "Deine bisherigen Diktate", Icon = Icons.Kind.History,
        });
        contents.Add(new PanelRow
        {
            Title = "Statistiken", Help = "Wörter, Streak, aktive Tage", Icon = Icons.Kind.Chart,
        });
        contents.Add(new PanelRow
        {
            Title = "Einstellungen", Help = "Auto-Stopp, Stille-Dauer, Formatierung", Icon = Icons.Kind.Mic,
        });
        Push(contents);

        Push(TextBlock.Footnote(
            "Beim Import werden die aktuellen Daten auf diesem Gerät ersetzt. Die Datei enthält deinen "
            + "Verlauf im Klartext — behandle sie vertraulich."));
    }

    private void Export()
    {
        using var dialog = new SaveFileDialog
        {
            FileName = "shout-backup.json",
            Filter = "shout-Backup (*.json)|*.json",
        };
        if (dialog.ShowDialog() != DialogResult.OK) return;
        try
        {
            BackupBundle.ExportToFile(dialog.FileName, dictionary, history, stats);
            ShowStatus($"Exportiert nach {Path.GetFileName(dialog.FileName)}.");
        }
        catch (Exception ex)
        {
            ShowStatus($"Export fehlgeschlagen: {ex.Message}");
        }
    }

    private void Import()
    {
        using var dialog = new OpenFileDialog { Filter = "shout-Backup (*.json)|*.json" };
        if (dialog.ShowDialog() != DialogResult.OK) return;
        if (MessageBox.Show(
                "Import ERSETZT Wörterbuch, Verlauf und Statistiken auf diesem Gerät. Fortfahren?",
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

    public SupportPage()
    {
        Push(new SectionHeader("Unterstützen"), 0);

        var donate = new ConsoleButton("Unterstützen", primary: true, icon: Icons.Kind.Coffee);
        donate.Click2 += () => OpenUrl(DonateUrl);
        var source = new ConsoleButton("Quellcode auf GitHub", icon: Icons.Kind.Code);
        source.Click2 += () => OpenUrl(GithubUrl);

        var intro = new ConsoleBox { ContentHeaderHeight = 52 };
        intro.PaintContent = (g, inner) =>
        {
            Icons.Draw(g, Icons.Kind.Heart, new RectangleF(inner.X, inner.Y, 36, 36), Theme.Live, 30f);
            TextRenderer.DrawText(g, "shout. ist Open Source", Theme.PageTitle,
                                  new Rectangle(inner.X + 48, inner.Y + 2, inner.Width - 48, 24),
                                  Theme.Gray(0.95), TextFormatFlags.NoPrefix);
            TextRenderer.DrawText(g, "Kostenlos, quelloffen und komplett lokal.", Theme.Small,
                                  new Rectangle(inner.X + 48, inner.Y + 26, inner.Width - 48, 20),
                                  Theme.Gray(0.58), TextFormatFlags.NoPrefix);
        };
        intro.Add(TextBlock.Body(
            "shout. entsteht in meiner freien Zeit. Wenn dir die App hilft und du die Weiterentwicklung "
            + "unterstützen möchtest, freue ich mich riesig — freiwillig, ohne Verpflichtung."), 0);
        intro.Add(new Cluster(new Control[] { donate, source }), 14);
        Push(intro);

        var points = new ConsolePanel { Title = "Was shout. ausmacht" };
        points.Add(new PanelRow
        {
            Title = "Frei & quelloffen",
            Help = "Der komplette Quellcode ist öffentlich — nutzen, anpassen, weitergeben.",
            Icon = Icons.Kind.LockOpen,
        });
        points.Add(new PanelRow
        {
            Title = "Lokal & privat",
            Help = "Keine Cloud, keine Konten, keine Datenweitergabe. Alles bleibt auf deinem Rechner.",
            Icon = Icons.Kind.Lock,
        });
        points.Add(new PanelRow
        {
            Title = "Aktiv gepflegt",
            Help = "Ich bemühe mich, shout. aktuell zu halten, zu verbessern und zu erweitern.",
            Icon = Icons.Kind.Branch,
        });
        Push(points);

        Push(TextBlock.Footnote(
            "Fehler gefunden oder eine Idee? Auf GitHub freue ich mich über Issues und Pull Requests."));
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
