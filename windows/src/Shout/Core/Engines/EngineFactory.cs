namespace Shout.Core;

/// <summary>
/// Baut die Engines für <see cref="LlmFormatter"/> und <see cref="Transcriber"/>.
///
/// <para>Diese Datei ist der EINZIGE Ort, der die konkreten Engines kennt. Nur
/// deshalb sind die beiden Router frei von llama.cpp- und whisper.cpp-Bezügen und
/// damit überhaupt prüfbar (Mac: EngineFactory.swift).</para>
///
/// <para>Hier entscheidet sich „auf diesem Gerät" gegen „Anbieter": Die Fabrik liest
/// die Einstellung und gibt die passende Engine zurück. Ein Wechsel zur Laufzeit
/// greift, weil die Router beim Neuladen mit <c>reset</c> erneut fragen.</para>
/// </summary>
public static class EngineFactory
{
    public static ITextEngine Text()
    {
        var wahl = EngineSelection.Decide(EnginePurpose.Text);
        if (wahl is not { Config: { } config, Template: { } template }) return new LocalTextEngine();

        return new RemoteTextEngine(
            config,
            ProviderKeyStore.Read(template.Id),
            template.NeedsKey,
            template.Name,
            onUsage: usage => ProviderUsageStore.Shared.Record(usage, template.Name, config.Model));
    }

    public static ISpeechEngine Speech()
    {
        var wahl = EngineSelection.Decide(EnginePurpose.Audio);
        if (wahl is not { Config: { } config, Template: { } template }) return new LocalSpeechEngine();

        return new RemoteSpeechEngine(
            config,
            ProviderKeyStore.Read(template.Id),
            template.NeedsKey,
            template.Name,
            onSeconds: seconds => ProviderUsageStore.Shared.Record(seconds, template.Name, config.Model));
    }

    /// <summary>
    /// Ersatz-Erkenner, wenn die Erkennung beim Anbieter scheitert: ein lokales
    /// Modell, das NUR aus dem Cache lädt — ein 1,6-GB-Download mitten im Diktat
    /// wäre keine Rettung, sondern eine zweite Panne. Wird ohnehin lokal
    /// gearbeitet, gibt es nichts zum Ausweichen.
    /// </summary>
    public static ISpeechEngine? SpeechFallback()
        => EngineSelection.Decide(EnginePurpose.Audio).IsRemote
            ? new LocalSpeechEngine(allowDownload: false)
            : null;
}
