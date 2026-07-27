using Shout.App;
using Shout.Core;

namespace Shout.UI;

/// <summary>
/// „Modelle" — erkennt die Hardware, empfiehlt das passende lokale Modell und
/// lässt frei umschalten; beim Wechsel wird (falls nötig) geladen
/// (Mac: ModelsView.swift, ohne die Hugging-Face-Live-Liste).
/// </summary>
internal sealed class ModelsPage : PageBase
{
    protected override int MaxContentWidth => 640;

    private readonly TrayContext app;
    private readonly ModelListPanel asrList;
    private readonly ModelListPanel llmList;
    private readonly TextBlock note = new("", Theme.Small, Theme.Gray(0.8), 0);

    public ModelsPage(TrayContext app)
    {
        this.app = app;
        var s = Settings.Shared;

        note.Visible = false;
        Push(new SectionHeader("Modelle"), 0);
        Push(note, 0);

        // MARK: Hardware

        var recommendedAsr = ModelCatalog.RecommendedAsr();
        var recommendedLlm = ModelCatalog.RecommendedLlm();
        var hardware = new ConsoleBox { ContentHeaderHeight = 96 };
        hardware.PaintContent = (g, inner) => PaintHardware(g, inner, recommendedAsr, recommendedLlm);
        Push(hardware);

        // MARK: Transkription

        asrList = new ModelListPanel(
            ModelCatalog.AsrModels.Select(m => new ModelEntry
            {
                Id = m.Id,
                Name = m.Name,
                Note = m.Note,
                SizeHint = m.SizeHint,
                Recommended = m.Id == recommendedAsr.Id,
                TooBig = RequiredRam(m.Id) > Hardware.MemoryGB,
            }).ToArray(),
            s.AsrModel)
        {
            Title = "Transkription (Sprache → Text)",
            Locked = () => app.IsBusy,
        };
        asrList.Selected += id => SwitchModel(asrList, id, isAsr: true);
        Push(asrList);

        // MARK: Aufbereitung

        llmList = new ModelListPanel(
            ModelCatalog.LlmModels.Select(m => new ModelEntry
            {
                Id = m.Id,
                Name = m.Name,
                Note = m.Note,
                SizeHint = m.SizeHint,
                Recommended = m.Id == recommendedLlm.Id,
                TooBig = RequiredRam(m.Id) > Hardware.MemoryGB,
            }).ToArray(),
            s.LlmModel)
        {
            Title = "Aufbereitung & Formatierung (KI-Textmodell)",
            Locked = () => app.IsBusy,
        };
        llmList.Selected += id => SwitchModel(llmList, id, isAsr: false);
        Push(llmList);

        Push(TextBlock.Footnote(
            "Modelle werden beim ersten Auswählen einmalig von Hugging Face geladen und danach lokal "
            + "gespeichert. Alles läuft anschließend komplett offline auf deinem Rechner."));
    }

    /// <summary>Grober RAM-Bedarf je Modell — nur für das Abzeichen „Viel RAM nötig".</summary>
    private static int RequiredRam(string id) => id switch
    {
        "ggml-large-v3-turbo.bin" => 8,
        "qwen2.5-3b-instruct-q4_k_m.gguf" => 16,
        "qwen2.5-1.5b-instruct-q4_k_m.gguf" => 8,
        _ => 0,
    };

    /// <summary>Kopfzeile der Hardware-Karte: Prozessor, Speicher, Empfehlung.</summary>
    private static void PaintHardware(Graphics g, Rectangle inner,
                                      ModelCatalog.Model asr, ModelCatalog.Model llm)
    {
        Icons.Draw(g, Icons.Kind.Chip, new RectangleF(inner.X, inner.Y, 34, 34), Theme.Live, 28f);
        TextRenderer.DrawText(g, Hardware.Chip, Theme.PageTitle,
                              new Rectangle(inner.X + 46, inner.Y, inner.Width - 46, 22),
                              Theme.Gray(0.95), TextFormatFlags.EndEllipsis | TextFormatFlags.NoPrefix);
        TextRenderer.DrawText(g, $"{Hardware.MemoryGB} GB Arbeitsspeicher · {Hardware.Cores} Kerne",
                              Theme.Small, new Rectangle(inner.X + 46, inner.Y + 22, inner.Width - 46, 20),
                              Theme.Gray(0.58), TextFormatFlags.NoPrefix);

        using (var pen = new Pen(Theme.Divider))
            g.DrawLine(pen, inner.X, inner.Y + 50.5f, inner.Right, inner.Y + 50.5f);

        Icons.Draw(g, Icons.Kind.Sparkle, new RectangleF(inner.X, inner.Y + 62, 16, 18), Theme.Live, 13f);
        TextRenderer.DrawText(g,
            $"Empfohlen für diesen Rechner: {asr.Name} zum Transkribieren, {llm.Name} zum Aufbereiten.",
            Theme.Small, new Rectangle(inner.X + 24, inner.Y + 60, inner.Width - 24, 34),
            Theme.Gray(0.7), TextFormatFlags.WordBreak | TextFormatFlags.NoPrefix);
    }

    /// <summary>Modell umschalten: laden (ggf. herunterladen), dann in der App aktivieren.</summary>
    private void SwitchModel(ModelListPanel list, string id, bool isAsr)
    {
        if (app.IsBusy)
        {
            note.SetText("Während einer Aufnahme lässt sich das Modell nicht wechseln.");
            note.Visible = true;
            NotifyHeightChanged();
            return;
        }

        note.Visible = false;
        var model = isAsr ? ModelCatalog.AsrById(id) : ModelCatalog.LlmById(id);
        if (model == null) return;

        list.SetLoading(id, null);
        _ = Task.Run(async () =>
        {
            try
            {
                await ModelDownloader.DownloadAsync(model, p =>
                {
                    if (p >= 0) BeginInvoke(() => list.SetLoading(id, p));
                });
                BeginInvoke(() =>
                {
                    var s = Settings.Shared;
                    if (isAsr) s.AsrModel = id; else s.LlmModel = id;
                    s.Save();
                    list.SetSelected(id);
                    list.SetLoading(null, null);
                    app.ReloadModels();
                });
            }
            catch (Exception ex)
            {
                BeginInvoke(() =>
                {
                    list.SetLoading(null, null);
                    note.SetText($"Download fehlgeschlagen: {ex.Message}");
                    note.Visible = true;
                    NotifyHeightChanged();
                });
            }
        });
    }
}
