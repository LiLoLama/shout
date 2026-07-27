using Shout.Core;

namespace Shout.UI;

/// <summary>
/// „Wörterbuch" — Begriffe als Chips, gelernte Korrekturen darunter
/// (Mac: DictionaryView.swift). Der Kontakte-Import der Mac-App entfällt:
/// Windows hat keine vergleichbare lokale Kontakte-Schnittstelle.
/// </summary>
internal sealed class DictionaryPage : PageBase, IRefreshablePage
{
    protected override int MaxContentWidth => 560;

    private readonly PersonalDictionary dictionary;
    private readonly ChipFlow chips = new();
    private readonly CorrectionList corrections = new();
    private readonly TextBlock emptyTerms = TextBlock.Body("Noch keine Begriffe.");
    private readonly TextBlock emptyCorrections = TextBlock.Body(
        "Noch keine Korrekturen — trag eine falsche und die richtige Schreibweise ein.");
    private readonly TextBlock importStatus = new("", Theme.Help, Theme.Live);
    private readonly ConsoleTextField termField;
    private readonly ConsoleTextField wrongField;
    private readonly ConsoleTextField rightField;

    public DictionaryPage(PersonalDictionary dictionary)
    {
        this.dictionary = dictionary;

        // MARK: Begriffe

        termField = new ConsoleTextField("Neuer Begriff (z. B. inthezone)", 240);
        var addTerm = new ConsoleButton("Hinzufügen");
        addTerm.Click2 += AddTerm;
        termField.Inner.KeyDown += (_, e) =>
        {
            if (e.KeyCode != Keys.Enter) return;
            e.SuppressKeyPress = true;
            AddTerm();
        };

        var importFile = new ConsoleButton("Aus Datei (CSV/TXT) …");
        importFile.Click2 += ImportFromFile;

        var termsBox = new ConsoleBox { Title = "Wörter, die shout. richtig schreiben soll" };
        termsBox.Add(new Cluster(new Control[] { termField, addTerm }) { StretchFirst = true }, 0);
        termsBox.Add(new Cluster(new Control[] { importFile, importStatus }));
        termsBox.Add(emptyTerms);
        termsBox.Add(chips);
        chips.Deleted += term =>
        {
            dictionary.RemoveTerm(term);
            Reload();
        };
        Push(termsBox, 0);

        // MARK: Korrekturen

        wrongField = new ConsoleTextField("falsch", 130);
        rightField = new ConsoleTextField("richtig", 130);
        var addCorrection = new ConsoleButton("Hinzufügen");
        addCorrection.Click2 += AddCorrection;
        rightField.Inner.KeyDown += (_, e) =>
        {
            if (e.KeyCode != Keys.Enter) return;
            e.SuppressKeyPress = true;
            AddCorrection();
        };

        var correctionsBox = new ConsoleBox { Title = "Automatisch verbessert" };
        correctionsBox.Add(new Cluster(new Control[]
        {
            wrongField,
            new IconView(Icons.Kind.ArrowRight, Theme.Gray(0.5), 12f, 16),
            rightField,
            addCorrection,
        }, 8), 0);
        correctionsBox.Add(emptyCorrections);
        correctionsBox.Add(corrections);
        corrections.Deleted += correction =>
        {
            dictionary.RemoveCorrection(correction);
            Reload();
        };
        Push(correctionsBox);

        Reload();
    }

    public void Refresh2() => Reload();

    private void Reload()
    {
        var terms = dictionary.Data.Terms;
        chips.SetTerms(terms);
        chips.Visible = terms.Count > 0;
        emptyTerms.Visible = terms.Count == 0;

        var list = dictionary.Data.Corrections;
        corrections.SetItems(list);
        corrections.Visible = list.Count > 0;
        emptyCorrections.Visible = list.Count == 0;

        NotifyHeightChanged();
    }

    private void AddTerm()
    {
        var text = termField.Inner.Text.Trim();
        if (text.Length == 0) return;
        dictionary.AddTerm(text);
        termField.Inner.Clear();
        Reload();
    }

    private void AddCorrection()
    {
        var wrong = wrongField.Inner.Text.Trim();
        var right = rightField.Inner.Text.Trim();
        if (wrong.Length == 0 || right.Length == 0) return;
        dictionary.AddCorrection(wrong, right);
        wrongField.Inner.Clear();
        rightField.Inner.Clear();
        Reload();
    }

    /// <summary>Begriffe aus CSV/TXT übernehmen — jeweils das erste Feld pro Zeile.</summary>
    private void ImportFromFile()
    {
        using var dialog = new OpenFileDialog
        {
            Filter = "Text/CSV (*.csv;*.txt)|*.csv;*.txt|Alle Dateien (*.*)|*.*",
            Title = "Begriffe importieren",
        };
        if (dialog.ShowDialog() != DialogResult.OK) return;

        var before = dictionary.Data.Terms.Count;
        try
        {
            foreach (var line in File.ReadLines(dialog.FileName))
            {
                var field = line.Split(',', 2).FirstOrDefault() ?? line;
                var term = field.Trim(' ', '\t', '"', '\'');
                if (term.Length > 0) dictionary.AddTerm(term);
            }
            importStatus.SetText($"{dictionary.Data.Terms.Count - before} neue Begriffe.");
        }
        catch (Exception ex)
        {
            importStatus.SetText($"Import fehlgeschlagen: {ex.Message}");
        }
        Reload();
    }
}
