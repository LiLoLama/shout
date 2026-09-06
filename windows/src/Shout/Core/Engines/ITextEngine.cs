namespace Shout.Core;

/// <summary>
/// Ein Textmodell, das genau EINE Sache kann: auf eine Anweisung antworten. Ob
/// das lokal über llama.cpp passiert oder über HTTP bei einem selbst gewählten
/// Anbieter, weiß nur die Umsetzung (Mac: TextEngine.swift).
///
/// <para>Der Schnitt sitzt hier, weil <see cref="LlmFormatter"/> ihn schon hatte:
/// Dessen private <c>RespondAsync</c> war bereits die einzige Stelle, an der
/// überhaupt ein Modell gefragt wurde. Alles andere — Prompts, Abschnitte,
/// Antwort-Schutz, Protokoll, Sprachprofil — ist anbieterunabhängig und bleibt im
/// Router. Folge: <see cref="FormattingGuard"/> und <see cref="TextChunker"/>
/// greifen automatisch auch bei Cloud-Modellen.</para>
/// </summary>
public interface ITextEngine : IDisposable
{
    /// <summary>Bereit für <see cref="RespondAsync"/>. Ist das false, fügt der Router
    /// den Rohtext ein — niemals blockieren, das gilt lokal wie extern.</summary>
    bool IsReady { get; }

    /// <summary>Für die Oberfläche, z. B. „Qwen 2.5 (3B)" oder „gpt-5-mini · OpenAI".</summary>
    string DisplayName { get; }

    /// <summary>
    /// Zielgröße der Abschnitte in Zeichen. Das kleine lokale Modell lässt bei
    /// langen Eingaben still Inhalt weg, deshalb wird dort klein geschnitten. Ein
    /// Modell mit großem Kontextfenster darf größere Stücke bekommen — weniger
    /// Aufrufe heißt bei einem Anbieter weniger Latenz und weniger Geld.
    /// </summary>
    int ChunkTargetLength { get; }

    /// <summary>Untergrenze für den Schnitt an Satzgrenzen (siehe <see cref="TextChunker"/>).</summary>
    int ChunkMinLength { get; }

    /// <summary>
    /// Harte Obergrenze für EINEN Aufruf in Sekunden, oder 0 für „keine".
    ///
    /// <para>Die Grenze gehört der Engine, nicht dem Router: Ein großes lokales
    /// Modell auf einem langsamen Rechner darf sich Zeit nehmen — es hängt nicht,
    /// es rechnet. Ein Anbieter dagegen kann wirklich hängen, und dann steht der
    /// Mensch mit dem Finger auf der Taste.</para>
    /// </summary>
    double CallTimeoutSeconds { get; }

    /// <summary>Lädt bzw. verbindet. Wirft nicht: Ein gescheiterter Ladevorgang lässt
    /// <see cref="IsReady"/> auf false stehen, und der Router fügt den Rohtext ein.</summary>
    Task PrepareAsync(Action<double>? onProgress = null, CancellationToken cancel = default);

    /// <summary>„Aufwärmen", damit die erste echte Aufbereitung nicht länger dauert.</summary>
    Task WarmUpAsync(CancellationToken cancel = default);

    /// <summary>Ein Aufruf ans Modell. Wirft bei jedem Fehler; der Router entscheidet,
    /// was das für den Text bedeutet.</summary>
    Task<string> RespondAsync(string system, string user, float temperature,
                              int maxTokens, CancellationToken cancel = default);
}

/// <summary>
/// Ein Spracherkenner — lokal whisper.cpp im eigenen Prozess, extern ein
/// OpenAI-kompatibler <c>/v1/audio/transcriptions</c>-Endpunkt.
///
/// <para>Alles, was nicht die Erkennung selbst ist, bleibt im Router
/// <see cref="Transcriber"/>: die Sprachwahl aus den Einstellungen und der
/// Rückfall aufs lokale Modell. Damit gilt beides für jeden Erkenner.</para>
/// </summary>
public interface ISpeechEngine : IDisposable
{
    bool IsReady { get; }

    /// <summary>Für die Oberfläche, z. B. „Whisper Small" oder „whisper-large-v3 · Groq".</summary>
    string DisplayName { get; }

    /// <summary>Kennung des geladenen Modells — der Router nimmt sie zurück, wenn ein
    /// Wechsel scheitert.</summary>
    string? LoadedModel { get; }

    /// <summary>Lädt bzw. verbindet. Wirft, damit der Aufrufer den Zustand richtig
    /// setzen und gegebenenfalls zurückrollen kann.</summary>
    Task PrepareAsync(Action<double>? onProgress = null, CancellationToken cancel = default);

    /// <summary>„Aufwärmen". Bei einem Anbieter absichtlich wirkungslos: Stille
    /// hochzuladen würde Geld kosten und nichts beschleunigen.</summary>
    Task WarmUpAsync(CancellationToken cancel = default);

    /// <summary><paramref name="language"/> ist ein ISO-Kürzel oder null für
    /// automatische Erkennung.</summary>
    Task<SpeechResult> TranscribeAsync(float[] samples, string? language,
                                       CancellationToken cancel = default);
}
