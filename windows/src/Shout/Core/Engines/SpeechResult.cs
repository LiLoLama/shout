namespace Shout.Core;

/// <summary>
/// Ergebnis einer Spracherkennung (Mac: SpeechResult in SpeechEngine.swift).
///
/// <para><see cref="Text"/> und <see cref="Segments"/> sind absichtlich getrennt und
/// NICHT dasselbe: Das Diktat nimmt den einen Weg, die Datei-Transkription den
/// anderen. Bei Anbietern kommt hinzu, dass manche gar keine Zeitmarken liefern —
/// dann gibt es ein Ersatzsegment über die Gesamtlänge, und die .srt wird
/// unbrauchbar, während das Diktat weiter funktioniert.</para>
/// </summary>
public sealed class SpeechResult
{
    public string Text { get; init; } = "";
    public List<TranscriptSegment> Segments { get; init; } = new();

    public static readonly SpeechResult Empty = new();
}
