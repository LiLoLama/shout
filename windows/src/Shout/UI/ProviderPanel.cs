using System.Globalization;
using Shout.Core;

namespace Shout.UI;

/// <summary>
/// Der Anbieter-Block auf der Modelle-Seite — einmal für die Aufbereitung, einmal
/// für die Transkription (Mac: ProviderPanel.swift).
///
/// <para>Er lebt hier und nicht in den Einstellungen, weil die Modelle-Seite schon
/// die Frage beantwortet „welches Modell macht welchen Schritt". Die Anbieterwahl
/// ist dieselbe Frage; sie auf zwei Seiten zu verteilen würde eine Entscheidung
/// zerreißen.</para>
/// </summary>
internal sealed class ProviderPanel : Panel, IAutoHeight
{
    private readonly EnginePurpose purpose;
    private readonly Action onChanged;

    private RemoteConfig config;
    private string? maskedKey;
    private List<string> models = new();
    private string? probeText;
    private string? lastError;
    private bool busy;

    private ConsolePanel panel;

    /// <summary>Die Höhe hat sich geändert (Zeile getauscht, Fehler dazugekommen).</summary>
    public event Action? HeightChanged;

    public ProviderPanel(EnginePurpose purpose, Action onChanged)
    {
        this.purpose = purpose;
        this.onChanged = onChanged;
        BackColor = Theme.Window;

        config = RemoteConfig.Load(purpose)
                 ?? new RemoteConfig(ProviderCatalog.Templates(purpose)[0], purpose);
        maskedKey = ProviderKeyStore.Masked(config.TemplateId);

        panel = Build();
        Controls.Add(panel);
    }

    private ProviderTemplate? Template => ProviderCatalog.Template(config.TemplateId);

    /// <summary>Adresse selbst eintragen: bei „Eigener Endpunkt" und bei Anbietern
    /// auf dem eigenen Rechner, wo Host und Port abweichen können.</summary>
    private bool AddressEditable => Template is not { } t || t.BaseUrl.Length == 0 || !t.NeedsKey;

    public int PreferredHeightFor(int width) => panel.PreferredHeightFor(width);

    protected override void OnLayout(LayoutEventArgs e)
    {
        base.OnLayout(e);
        if (Width <= 0) return;
        panel.Left = 0;
        panel.Top = 0;
        panel.Width = Width;
        panel.Height = panel.PreferredHeightFor(Width);
        Height = panel.Height;
    }

    // MARK: - Aufbau

    private ConsolePanel Build()
    {
        var box = new ConsolePanel
        {
            Title = purpose == EnginePurpose.Audio
                ? Loc.T("Anbieter") + " · " + Loc.T("Transkription (Sprache → Text)")
                : Loc.T("Anbieter") + " · " + Loc.T("Aufbereitung & Formatierung (KI-Textmodell)"),
        };

        AddProviderRow(box);
        AddAddressRow(box);
        if (Template?.NeedsKey == true) AddKeyRow(box);
        AddModelRow(box);
        AddProbeRow(box);
        if (Template?.NeedsKey == true) AddCostRow(box);

        if (Template?.Note is { Length: > 0 } note)
            box.Add(new PanelRow { Title = Loc.T("Hinweis"), Help = Loc.T(note) });
        if (lastError is { Length: > 0 } error)
            box.Add(new PanelRow { Title = Loc.T("Fehler"), Help = error });

        return box;
    }

    private void AddProviderRow(ConsolePanel box)
    {
        var picker = new ConsoleDropdown(200);
        picker.SetItems(ProviderCatalog.Templates(purpose).Select(t => (t.Id, t.Name)).ToArray(),
                        config.TemplateId);
        picker.Changed += SwitchTemplate;
        box.Add(new PanelRow
        {
            Title = Loc.T("Anbieter"),
            Help = purpose == EnginePurpose.Audio
                ? Loc.T("Nur Anbieter, die transkribieren können, stehen hier.")
                : null,
            Trailing = picker,
        });
    }

    private void AddAddressRow(ConsolePanel box)
    {
        Control trailing;
        if (AddressEditable)
        {
            var field = new ConsoleTextField("https://…", 260);
            field.Inner.Text = config.BaseUrl;
            // Erst beim Verlassen des Feldes sichern, nicht bei jedem Anschlag:
            // settings.json würde sonst je Buchstabe neu geschrieben.
            field.Inner.Leave += (_, _) => { config.BaseUrl = field.Inner.Text.Trim(); Save(); };
            trailing = field;
        }
        else
        {
            trailing = new Keycap(config.BaseUrl);
        }

        box.Add(new PanelRow
        {
            Title = Loc.T("Adresse"),
            Help = AddressEditable
                ? Loc.T("Die Basis-Adresse. „/chat/completions“ wird selbst angehängt.")
                : null,
            Trailing = trailing,
        });
    }

    private void AddKeyRow(ConsolePanel box)
    {
        Control trailing;
        string? help;

        if (maskedKey is { Length: > 0 } shown)
        {
            var replace = new ConsoleButton(Loc.T("Ersetzen"));
            replace.Click2 += () => { maskedKey = null; Rebuild(); };
            var remove = new ConsoleButton(Loc.T("Entfernen"));
            remove.Click2 += () =>
            {
                ProviderKeyStore.Delete(config.TemplateId);
                maskedKey = null;
                Rebuild();
                onChanged();
            };
            trailing = new Cluster(new Control[] { new Keycap(shown), replace, remove });
            help = Loc.T("Der Schlüssel liegt verschlüsselt auf diesem Rechner (DPAPI, an dein Benutzerkonto gebunden) und wandert nie ins Backup.");
        }
        else
        {
            var field = new ConsoleTextField("sk-…", 200);
            // Der Schlüssel steht nicht im Klartext auf dem Bildschirm — jemand
            // schaut immer mal mit, und Bildschirmfotos landen in Fehlerberichten.
            field.Inner.UseSystemPasswordChar = true;
            var save = new ConsoleButton(Loc.T("Speichern"));
            save.Click2 += () => StoreKey(field.Inner.Text);
            trailing = new Cluster(new Control[] { field, save });
            help = Template is { KeyUrl.Length: > 0 } t ? Loc.F("Bekommst du bei: {0}", t.KeyUrl) : null;
        }

        box.Add(new PanelRow { Title = Loc.T("Schlüssel"), Help = help, Trailing = trailing });
    }

    private void AddModelRow(ConsolePanel box)
    {
        var field = new ConsoleTextField("model-id", 190);
        field.Inner.Text = config.Model;
        field.Inner.Leave += (_, _) => { config.Model = field.Inner.Text.Trim(); Save(); };

        Control trailing = field;
        var suggestions = Suggestions();
        if (suggestions.Count > 0)
        {
            var picker = new ConsoleDropdown(150);
            // Ein leerer erster Eintrag: Das Menü ist eine Abkürzung, keine
            // Auswahl — die Kennung im Feld bleibt maßgeblich.
            var items = new List<(string, string)> { ("", Loc.T("Vorschläge …")) };
            items.AddRange(suggestions.Select(id => (id, id)));
            picker.SetItems(items, "");
            picker.Changed += id =>
            {
                if (id.Length == 0) return;
                config.Model = id;
                field.Inner.Text = id;
                Save();
            };
            trailing = new Cluster(new Control[] { field, picker });
        }

        box.Add(new PanelRow
        {
            Title = Loc.T("Modell"),
            Help = Loc.T("Kennung frei eintragbar."),
            Trailing = trailing,
        });
    }

    /// <summary>Erst die geladene Liste, sonst die handverlesenen Vorschläge der
    /// Vorlage.</summary>
    private List<string> Suggestions()
    {
        if (models.Count > 0) return models;
        if (Template is not { } t) return new List<string>();
        return new List<string>(purpose == EnginePurpose.Text ? t.ChatModels : t.AudioModels);
    }

    private void AddProbeRow(ConsolePanel box)
    {
        var load = new ConsoleButton(Loc.T("Modelle laden"));
        load.Click2 += LoadModels;
        var test = new ConsoleButton(Loc.T("Verbindung testen"));
        test.Click2 += Probe;
        load.SetEnabled(!busy);
        test.SetEnabled(!busy);

        box.Add(new PanelRow
        {
            Title = Loc.T("Verbindung"),
            Help = probeText,
            Trailing = new Cluster(new Control[] { load, test }),
        });
    }

    private void AddCostRow(ConsolePanel box)
    {
        var update = new ConsoleButton(Loc.T("Preise aktualisieren"));
        update.Click2 += LoadPrices;
        update.SetEnabled(!busy);

        box.Add(new PanelRow
        {
            Title = Loc.T("Kosten"),
            Help = CostHelp(),
            Trailing = new Cluster(new Control[] { update }),
        });
    }

    /// <summary>Kosten — gemessen, nicht geschätzt: Die Token stehen in jeder
    /// Antwort. Was unbekannt ist, wird gesagt statt erfunden.</summary>
    private string CostHelp()
    {
        var usage = ProviderUsageStore.Shared;
        var (month, unknown) = usage.Cost();
        var lines = new List<string>();

        if (purpose == EnginePurpose.Text
            && usage.Prices.PriceForText(config.Model) is { } textPrice
            && ProviderCosts.Cost(ProviderCosts.TypicalDictation, textPrice) is { } perDictation)
        {
            lines.Add(Loc.F("ca. {0} je Diktat", ProviderCosts.Format(perDictation)));
        }
        else if (purpose == EnginePurpose.Audio
                 && usage.Prices.PriceForAudio(config.Model) is { } audioPrice
                 && ProviderCosts.Cost(60, audioPrice) is { } perMinute)
        {
            lines.Add(Loc.F("ca. {0} je Minute Audio", ProviderCosts.Format(perMinute)));
        }
        else
        {
            lines.Add(Loc.T("Preis dieses Modells unbekannt."));
        }

        lines.Add(Loc.F("Diesen Monat: {0}", ProviderCosts.Format(month))
                  + (unknown ? " " + Loc.T("(ohne die Modelle mit unbekanntem Preis)") : ""));
        lines.Add(Loc.F("Näherung — abgerechnet wird beim Anbieter. Preise: Stand {0}",
                        usage.Prices.Updated.ToLocalTime().ToString("d", CultureInfo.CurrentCulture)));
        return string.Join("\n", lines);
    }

    // MARK: - Aktionen

    private void SwitchTemplate(string id)
    {
        if (ProviderCatalog.Template(id) is not { } template) return;
        config = new RemoteConfig(template, purpose);
        maskedKey = ProviderKeyStore.Masked(id);
        models = new List<string>();
        probeText = null;
        lastError = null;
        Save();
        Rebuild();
    }

    private void Save()
    {
        config.Save(purpose);
        onChanged();
    }

    private void StoreKey(string entered)
    {
        var value = entered.Trim();
        if (value.Length == 0) return;
        if (ProviderKeyStore.Store(config.TemplateId, value))
        {
            maskedKey = KeyMask.Mask(value);
            lastError = null;
            Rebuild();
            onChanged();
        }
        else
        {
            lastError = Loc.T("Der Schlüssel konnte nicht gespeichert werden.");
            Rebuild();
        }
    }

    private void LoadModels()
    {
        if (Template is not { } template || busy) return;
        busy = true;
        Rebuild();

        Run(async () =>
        {
            var ids = await ProviderModels.FetchAsync(
                config, ProviderKeyStore.Read(template.Id), template.NeedsKey);
            models = purpose == EnginePurpose.Audio
                ? AudioModelFilter.Apply(ids)
                : new List<string>(ids);
            lastError = null;
        });
    }

    private void Probe()
    {
        if (Template is not { } template || busy) return;
        busy = true;
        probeText = null;
        Rebuild();

        Run(async () =>
        {
            var result = await ProviderProbe.RunAsync(
                config, ProviderKeyStore.Read(template.Id), template.NeedsKey);

            if (!result.Ok)
            {
                probeText = null;
                lastError = ProviderText.Describe(result.Error!);
                return;
            }

            var seconds = result.Seconds.ToString("0.0", CultureInfo.CurrentCulture);
            probeText = result.ModelListed switch
            {
                true => Loc.F("Verbindung steht · {0} s", seconds),
                false => Loc.F("Verbindung steht, aber „{0}“ steht nicht in der Modell-Liste des Anbieters.",
                               config.Model),
                _ => Loc.F("Verbindung steht · {0} s. Der Anbieter liefert keine Modell-Liste — ob das Modell stimmt, zeigt erst der erste Versuch.",
                           seconds),
            };
            lastError = null;
        });
    }

    private void LoadPrices()
    {
        if (busy) return;
        busy = true;
        Rebuild();

        Run(async () =>
        {
            ProviderUsageStore.Shared.ReplacePrices(await PriceFetch.FetchAsync());
            lastError = null;
        });
    }

    /// <summary>
    /// Führt eine Netz-Aktion aus und baut die Zeilen danach neu. Fehler landen in
    /// der Fehlerzeile, nie als Ausnahme: Ein abgelehnter Schlüssel darf die
    /// Einstellungen nicht schließen.
    ///
    /// <para>Nach dem Rückweg wird geprüft, ob es diese Seite noch gibt — sonst
    /// würfe der Rückruf mitten in eine bereits geschlossene Oberfläche.</para>
    /// </summary>
    private void Run(Func<Task> action)
    {
        _ = Task.Run(async () =>
        {
            string? error = null;
            try
            {
                await action();
            }
            catch (Exception ex)
            {
                error = ProviderText.Describe(ex);
            }

            if (IsDisposed || !IsHandleCreated) return;
            try
            {
                BeginInvoke(() =>
                {
                    busy = false;
                    if (error != null) lastError = error;
                    Rebuild();
                });
            }
            catch (ObjectDisposedException) { }
            catch (InvalidOperationException) { }
        });
    }

    private void Rebuild()
    {
        var old = panel;
        panel = Build();
        Controls.Add(panel);
        Controls.Remove(old);
        old.Dispose();
        PerformLayout();
        HeightChanged?.Invoke();
    }
}
