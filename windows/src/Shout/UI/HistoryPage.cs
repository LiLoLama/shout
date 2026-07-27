using Shout.Core;

namespace Shout.UI;

/// <summary>
/// „Verlauf" — nach Tagen gruppierte Karten mit Einfügen/Kopieren/Löschen
/// (Mac: HistoryView.swift).
/// </summary>
internal sealed class HistoryPage : PageBase, IRefreshablePage
{
    protected override int MaxContentWidth => 640;

    private readonly DictationHistory history;
    private readonly ConsoleButton clearAll;

    public HistoryPage(DictationHistory history)
    {
        this.history = history;

        clearAll = new ConsoleButton(Loc.T("Alle löschen"));
        clearAll.Click2 += () =>
        {
            if (MessageBox.Show(Loc.T("Gesamten Verlauf löschen?"), "shout.",
                    MessageBoxButtons.YesNo, MessageBoxIcon.Question) != DialogResult.Yes) return;
            history.Clear();
            Rebuild();
        };

        Push(new SectionHeader(Loc.T("Verlauf"), clearAll), 0);
        Rebuild();
    }

    public void Refresh2() => Rebuild();

    /// <summary>Baut die Gruppen und Karten neu auf (nach Löschen oder Tab-Wechsel).</summary>
    private void Rebuild()
    {
        TrimStack(1);   // Seitenkopf behalten
        clearAll.Visible = history.Entries.Count > 0;

        if (history.Entries.Count == 0)
        {
            Push(new EmptyState(Icons.Kind.History, Loc.T("Noch keine Diktate"),
                Loc.T("Was du diktierst, erscheint hier — zum Nachlesen und erneut Kopieren.")));
            NotifyHeightChanged();
            return;
        }

        // Nach Tag gruppieren, Reihenfolge des Verlaufs beibehalten (neueste zuerst).
        var groups = new List<(string Label, List<DictationHistory.Entry> Items)>();
        foreach (var entry in history.Entries)
        {
            var label = DayLabel(entry.Date.ToLocalTime().Date);
            if (groups.Count == 0 || groups[^1].Label != label)
                groups.Add((label, new List<DictationHistory.Entry>()));
            groups[^1].Items.Add(entry);
        }

        foreach (var (label, items) in groups)
        {
            Push(new GroupLabel(label), 20);
            foreach (var entry in items)
            {
                var card = new HistoryCard(entry);
                card.InsertRequested += e => InsertRequested?.Invoke(e.Text);
                card.CopyRequested += e =>
                {
                    try { Clipboard.SetText(e.Text); } catch { /* Zwischenablage gesperrt */ }
                };
                card.DeleteRequested += e =>
                {
                    history.Delete(e);
                    Rebuild();
                };
                Push(card, 8);
            }
        }
        NotifyHeightChanged();
    }

    /// <summary>Ein Verlaufs-Eintrag soll am Cursor eingefügt werden.</summary>
    public event Action<string>? InsertRequested;

    private static string DayLabel(DateTime day)
    {
        if (day == DateTime.Today) return Loc.T("Heute");
        if (day == DateTime.Today.AddDays(-1)) return Loc.T("Gestern");
        return day.ToString("d. MMMM yyyy");
    }
}
