using Shout.App;
using Shout.Core;

namespace Shout.UI;

/// <summary>
/// „Modelle" — erkennt die Hardware, empfiehlt das passende lokale Modell und
/// lässt frei umschalten; beim Wechsel wird (falls nötig) geladen
/// (Mac: ModelsView.swift).
/// </summary>
internal sealed class ModelsPage : PageBase
{
    protected override int MaxContentWidth => 640;

    private readonly TrayContext app;
    private readonly ModelListPanel asrList;
    private readonly ModelListPanel llmList;
    private readonly TextBlock note = new("", Theme.Small, Theme.Gray(0.8), 0);

    // MARK: Live-Liste von Hugging Face
    private readonly ConsoleButton refreshButton;
    private readonly TextBlock remoteStatus;
    private ModelListPanel? remoteList;
    private bool remoteLoading;
    private bool didFetch;

    public ModelsPage(TrayContext app)
    {
        this.app = app;
        var s = Settings.Shared;

        note.Visible = false;
        Push(new SectionHeader(Loc.T("Modelle")), 0);
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
            Title = Loc.T("Transkription (Sprache → Text)"),
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
            Title = Loc.T("Aufbereitung & Formatierung (KI-Textmodell)"),
            Locked = () => app.IsBusy,
        };
        llmList.Selected += id => SwitchModel(llmList, id, isAsr: false);
        Push(llmList);

        // MARK: Aktuelle Modelle von Hugging Face

        refreshButton = new ConsoleButton(Loc.T("Aktualisieren"), icon: Icons.Kind.Refresh);
        refreshButton.Click2 += () => LoadRemote(force: true);
        // GroupLabel statt SectionHeader: der zeichnet in Theme.PageTitle und
        // stünde als zweiter Seitentitel neben „Modelle".
        Push(new GroupLabel(Loc.T("AKTUELLE MODELLE · HUGGING FACE")));
        Push(new Cluster(new Control[] { refreshButton }), 8);

        remoteStatus = TextBlock.Body(Loc.T("Suche aktuelle Modelle …"));
        Push(remoteStatus, 8);

        PushFootnotes();
    }

    /// <summary>Anzahl der festen Stapel-Elemente vor der Live-Liste: Kopf,
    /// Hinweis, Hardware-Karte, die beiden festen Listen, Abschnittslabel,
    /// Aktualisieren-Knopf und Statuszeile. Alles danach baut
    /// <see cref="ShowRemote"/> neu auf.</summary>
    private const int FixedElements = 8;

    private void PushFootnotes()
    {
        Push(TextBlock.Footnote(Loc.T(
            "Live von Hugging Face, ausschließlich Qwen-Modelle — das Chat-Template der Aufbereitung ist darauf abgestimmt, ein fremdes Modell würde still Unsinn liefern.")));
        Push(TextBlock.Footnote(Loc.T(
            "Modelle werden beim ersten Auswählen einmalig von Hugging Face geladen und danach lokal gespeichert. Alles läuft anschließend komplett offline auf deinem Rechner.")));
    }

    /// <summary>Beim ersten Anzeigen der Seite einmal live nachsehen.</summary>
    protected override void OnVisibleChanged(EventArgs e)
    {
        base.OnVisibleChanged(e);
        if (Visible && !didFetch) LoadRemote(force: false);
    }

    /// <summary>
    /// Holt die Live-Liste und hängt sie als eigenes Panel unter die
    /// Statuszeile. Fehler landen als Text in der Statuszeile — eine fehlende
    /// Internet-Verbindung darf die Seite nicht unbrauchbar machen.
    /// </summary>
    private void LoadRemote(bool force)
    {
        if (remoteLoading) return;
        if (didFetch && !force) return;

        didFetch = true;
        remoteLoading = true;
        refreshButton.SetEnabled(false);
        remoteStatus.SetText(Loc.T("Suche aktuelle Modelle …"));
        remoteStatus.Visible = true;
        NotifyHeightChanged();

        _ = Task.Run(async () =>
        {
            List<HuggingFaceModels.Discovered> found;
            string? error = null;
            try
            {
                found = await HuggingFaceModels.FetchLlmAsync();
            }
            catch (Exception ex)
            {
                found = new List<HuggingFaceModels.Discovered>();
                error = ex.Message;
            }

            // Ohne diesen Rückweg bliebe remoteLoading true und der Knopf tot.
            try
            {
                if (IsDisposed || !IsHandleCreated) throw new ObjectDisposedException(nameof(ModelsPage));
                var list = found;
                var err = error;
                BeginInvoke(() => ShowRemote(list, err));
            }
            catch
            {
                remoteLoading = false;
                didFetch = false;
            }
        });
    }

    private void ShowRemote(List<HuggingFaceModels.Discovered> found, string? error)
    {
        remoteLoading = false;
        refreshButton.SetEnabled(true);

        // Der Stapel kennt kein Einfügen: alles hinter der Statuszeile abräumen
        // (TrimStack gibt die Controls frei) und neu aufbauen.
        remoteList = null;
        TrimStack(FixedElements);

        if (error != null)
        {
            remoteStatus.SetText(Loc.F("Keine Verbindung zu Hugging Face. {0}", error));
            remoteStatus.Visible = true;
            PushFootnotes();
            NotifyHeightChanged();
            return;
        }
        if (found.Count == 0)
        {
            remoteStatus.SetText(Loc.T("Keine Modelle gefunden."));
            remoteStatus.Visible = true;
            PushFootnotes();
            NotifyHeightChanged();
            return;
        }

        remoteStatus.Visible = false;
        var ram = Hardware.MemoryGB;

        remoteList = Push(new ModelListPanel(
            found.Select(d => new ModelEntry
            {
                Id = d.Model.Id,
                Name = d.Model.Name,
                Note = Loc.F("Live von Hugging Face · {0}× geladen",
                             HuggingFaceModels.Compact(d.Downloads)),
                SizeHint = d.Model.SizeHint,
                // Bewusst kein „Empfohlen": das empfiehlt schon die feste Liste
                // nach RAM. Das beliebteste Repo ist oft ein Winzmodell.
                TooBig = d.MinRamGB > ram,
            }).ToArray(),
            Settings.Shared.LlmModel)
        {
            Locked = () => app.IsBusy,
        }, 12);

        var list = remoteList;
        list.Selected += id =>
        {
            var model = found.FirstOrDefault(d => d.Model.Id == id)?.Model;
            if (model == null) return;
            // Merken und speichern, BEVOR gewechselt wird: SwitchModel löst das
            // Modell über ModelCatalog.LlmById auf, und dort steht es erst danach.
            ModelCatalog.Remember(model);
            Settings.Shared.Save();
            SwitchModel(list, id, isAsr: false);
        };

        PushFootnotes();
        NotifyHeightChanged();
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
        TextRenderer.DrawText(g, Loc.F("{0} GB Arbeitsspeicher · {1} Kerne", Hardware.MemoryGB, Hardware.Cores),
                              Theme.Small, new Rectangle(inner.X + 46, inner.Y + 22, inner.Width - 46, 20),
                              Theme.Gray(0.58), TextFormatFlags.NoPrefix);

        using (var pen = new Pen(Theme.Divider))
            g.DrawLine(pen, inner.X, inner.Y + 50.5f, inner.Right, inner.Y + 50.5f);

        Icons.Draw(g, Icons.Kind.Sparkle, new RectangleF(inner.X, inner.Y + 62, 16, 18), Theme.Live, 13f);
        TextRenderer.DrawText(g,
            Loc.F("Empfohlen für diesen Rechner: {0} zum Transkribieren, {1} zum Aufbereiten.",
                  asr.Name, llm.Name),
            Theme.Small, new Rectangle(inner.X + 24, inner.Y + 60, inner.Width - 24, 34),
            Theme.Gray(0.7), TextFormatFlags.WordBreak | TextFormatFlags.NoPrefix);
    }

    /// <summary>Modell umschalten: laden (ggf. herunterladen), dann in der App aktivieren.</summary>
    private void SwitchModel(ModelListPanel list, string id, bool isAsr)
    {
        if (app.IsBusy)
        {
            note.SetText(Loc.T("Während einer Aufnahme lässt sich das Modell nicht wechseln."));
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
                    // Feste und Live-Liste steuern DIESELBE Einstellung — die
                    // jeweils andere muss ihre Markierung verlieren.
                    if (!isAsr)
                    {
                        if (!ReferenceEquals(list, llmList)) llmList.SetSelected(id);
                        if (remoteList != null && !ReferenceEquals(list, remoteList))
                            remoteList.SetSelected(id);
                    }
                    list.SetLoading(null, null);
                    app.ReloadModels();
                });
            }
            catch (Exception ex)
            {
                BeginInvoke(() =>
                {
                    list.SetLoading(null, null);
                    note.SetText(Loc.F("Download fehlgeschlagen: {0}", ex.Message));
                    note.Visible = true;
                    NotifyHeightChanged();
                });
            }
        });
    }
}
