using Shout.Core;

namespace Shout.UI;

/// <summary>
/// Kleiner Editor für das letzte Diktat (Mac: CorrectionView.swift). Der Nutzer
/// bessert falsch erkannte Wörter aus; beim Übernehmen lernt das Wörterbuch die
/// Korrekturen.
///
/// <para>Warum ein eigenes Fenster und nicht das Zielfeld beobachten: Am Mac hängt
/// dafür ein Bedienungshilfen-Beobachter am fokussierten Textfeld. Unter Windows
/// gäbe es dafür nur UI Automation — das funktioniert je nach Ziel-Programm
/// unterschiedlich gut und gar nicht in Fenstern mit erhöhten Rechten. Hier zu
/// korrigieren wirkt dagegen überall gleich.</para>
/// </summary>
internal sealed class CorrectionForm : Form
{
    private readonly string original;
    private readonly TextBox editor;
    private readonly ConsoleButton apply;

    public CorrectionForm(string original, Action<string> onApply)
    {
        this.original = original;

        Text = Loc.T("Letztes Diktat korrigieren");
        BackColor = Theme.Window;
        ClientSize = new Size(560, 360);
        MinimumSize = new Size(420, 280);
        StartPosition = FormStartPosition.CenterScreen;
        Icon = AppIcons.Window;
        KeyPreview = true;

        var hint = new Label
        {
            Text = Loc.T("Bessere falsch erkannte Wörter aus. shout. lernt die Korrekturen fürs nächste Mal — in jedem Programm."),
            AutoSize = false, Height = 40, Dock = DockStyle.Top,
            ForeColor = Theme.Gray(0.55), BackColor = Theme.Window, Font = Theme.Help,
            Padding = new Padding(20, 10, 20, 0),
        };

        editor = new TextBox
        {
            Multiline = true, ScrollBars = ScrollBars.Vertical, Dock = DockStyle.Fill,
            BackColor = Theme.Window, ForeColor = Theme.Gray(0.9),
            BorderStyle = BorderStyle.None, Font = Theme.Body, WordWrap = true,
            Text = original,
        };
        var editorHost = new Panel
        {
            Dock = DockStyle.Fill, BackColor = Theme.Window, Padding = new Padding(18, 6, 18, 6),
        };
        editorHost.Controls.Add(editor);

        apply = new ConsoleButton(Loc.T("Übernehmen"), primary: true);
        apply.Click2 += Apply;
        apply.SetEnabled(false);

        void Apply()
        {
            if (!apply.IsEnabled) return;
            var corrected = editor.Text.Trim();
            if (corrected.Length > 0 && corrected != original) onApply(corrected);
            Close();
        }

        var cancel = new ConsoleButton(Loc.T("Abbrechen"));
        cancel.Click2 += Close;

        editor.TextChanged += (_, _) => apply.SetEnabled(editor.Text.Trim() != original);
        // Escape schließt, Strg+Eingabe übernimmt — im mehrzeiligen Feld ist die
        // Eingabetaste selbst ein Zeilenumbruch und darf das Fenster nicht schließen.
        KeyDown += (_, e) =>
        {
            if (e.KeyCode == Keys.Escape) { Close(); e.Handled = true; }
            else if (e.Control && e.KeyCode == Keys.Enter) { Apply(); e.Handled = true; }
        };

        var buttons = new FlowLayoutPanel
        {
            Dock = DockStyle.Bottom, Height = 46, BackColor = Theme.Window,
            Padding = new Padding(16, 8, 16, 8), WrapContents = false,
            FlowDirection = FlowDirection.RightToLeft,
        };
        buttons.Controls.Add(apply);
        buttons.Controls.Add(cancel);

        Controls.Add(editorHost);
        Controls.Add(hint);
        Controls.Add(buttons);
    }

    protected override void OnHandleCreated(EventArgs e)
    {
        base.OnHandleCreated(e);
        DarkTitleBar.Apply(Handle);
    }
}
