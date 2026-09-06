namespace Shout.Core;

/// <summary>
/// Was für einen Schritt benutzt werden soll. Die Entscheidung steht hier statt in
/// <c>EngineFactory</c>, damit sie prüfbar ist — die Fabrik selbst kennt die
/// konkreten Engines (whisper.cpp, llama.cpp) und liegt deshalb nicht im Testziel.
/// </summary>
public sealed class EngineSelection
{
    /// <summary>Auf diesem Gerät rechnen.</summary>
    public static readonly EngineSelection Local = new();

    public bool IsRemote => Config != null;
    public RemoteConfig? Config { get; }
    public ProviderTemplate? Template { get; }

    private EngineSelection() { }

    private EngineSelection(RemoteConfig config, ProviderTemplate template)
    {
        Config = config;
        Template = template;
    }

    /// <summary>
    /// Woher die Frage „liegt ein Schlüssel vor?" beantwortet wird.
    ///
    /// <para>Als Delegat und nicht als fester Aufruf von <see cref="ProviderKeyStore"/>:
    /// Der hängt an DPAPI und lässt sich nur unter Windows ausführen, weshalb er nicht
    /// mit ins Testziel übersetzt wird. Er meldet sich beim Laden der App selbst hier
    /// an; ohne ihn (also nur im Test) steht hier „kein Schlüssel", und die Tests
    /// reichen ihre eigene Antwort mit.</para>
    /// </summary>
    public static Func<string, bool> KeySource { get; set; } = _ => false;

    /// <summary>Trifft die Wahl aus den Einstellungen dieses Geräts.</summary>
    public static EngineSelection Decide(EnginePurpose purpose, Func<string, bool>? hasKey = null)
        => Decide(purpose,
                  purpose == EnginePurpose.Text
                      ? Settings.Shared.FormatEngine
                      : Settings.Shared.AsrEngine,
                  RemoteConfig.Load(purpose),
                  hasKey);

    /// <summary>
    /// Trifft die Wahl aus Einstellung, gespeicherter Konfiguration und der Frage, ob
    /// ein Schlüssel hinterlegt ist.
    ///
    /// <para><b>Ohne Schlüssel wird lokal gearbeitet, nicht gescheitert.</b> Das ist die
    /// Regel, die einen importierten Sicherungsstand abfängt: Die Konfiguration reist
    /// im Backup mit (sie ist harmlos), der Schlüssel nicht. Auf dem neuen Gerät stünde
    /// sonst „Anbieter" in den Einstellungen, und jedes Diktat liefe in einen 401 —
    /// oder schlimmer, es ginge Text an einen Anbieter, für den der Mensch auf diesem
    /// Gerät nie einen Schlüssel eingetragen hat.</para>
    /// </summary>
    public static EngineSelection Decide(EnginePurpose purpose, string engineSetting,
                                         RemoteConfig? config, Func<string, bool>? hasKey = null)
    {
        if (engineSetting != "remote" || config == null) return Local;

        var template = ProviderCatalog.Template(config.TemplateId);
        if (template == null) return Local;

        var url = purpose == EnginePurpose.Text ? config.ChatUrl : config.AudioUrl;
        if (url == null) return Local;

        if (purpose == EnginePurpose.Audio && !template.CanAudio) return Local;
        if (purpose == EnginePurpose.Text && !template.CanText) return Local;
        if (template.NeedsKey && !(hasKey ?? KeySource)(template.Id)) return Local;

        return new EngineSelection(config, template);
    }
}
