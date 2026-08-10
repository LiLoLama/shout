using System.Text.RegularExpressions;

namespace Shout.Core;

/// <summary>Ein Abschnitt eines Transkripts mit Zeitmarken in Sekunden ab Dateibeginn.</summary>
public readonly record struct TranscriptSegment(string Text, double Start, double End);

/// <summary>
/// Bringt Whisper-Segmente in eine Form, die man lesen mag (Mac: TranscriptLayout.swift).
///
/// <para>Alles mit Leerzeichen aneinanderzuhängen ergibt bei einer Stunde Audio eine
/// einzige Textwand. Stattdessen eine Zeile je Segment und eine Leerzeile bei einer
/// längeren Sprechpause — die Pausen im Gesprochenen sind die einzige Gliederung,
/// die im Rohmaterial ehrlich vorhanden ist.</para>
/// </summary>
public static class TranscriptLayout
{
    /// <summary>Pause, ab der ein neuer Absatz beginnt.</summary>
    public const double ParagraphGap = 1.5;

    private static readonly Regex SpecialTokens = new(@"<\|.*?\|>", RegexOptions.Compiled);
    private static readonly Regex Spaces = new(@"[ \t]+", RegexOptions.Compiled);

    /// <summary>
    /// Entfernt Steuermarken der Form <c>&lt;|…|&gt;</c>. whisper.cpp gibt sie
    /// normalerweise nicht aus — am Mac tat WhisperKit es sehr wohl, und der Filter
    /// kostet nichts.
    /// </summary>
    public static string StripSpecialTokens(string text)
        => Spaces.Replace(SpecialTokens.Replace(text, " "), " ").Trim();

    /// <summary>
    /// Baut das Rohtranskript: eine Zeile je Segment, Leerzeile bei einer längeren
    /// Sprechpause, auf Wunsch eine Zeitmarke am Anfang jedes Absatzes.
    ///
    /// <para><paramref name="timestamps"/> ist beim Anzeigen an und für den Eingang
    /// ins Sprachmodell aus: Dort kosten die Marken nur Kontext und tauchten sonst
    /// im Protokoll wieder auf.</para>
    /// </summary>
    public static string RawText(IReadOnlyList<TranscriptSegment> segments,
                                 bool timestamps = false,
                                 double paragraphGap = ParagraphGap)
    {
        var lines = new List<string>();
        double? previousEnd = null;

        foreach (var segment in segments)
        {
            var text = StripSpecialTokens(segment.Text);
            if (text.Length == 0) continue;

            // Absatz nur zwischen zwei ECHTEN Zeilen — der Vergleich läuft gegen das
            // letzte übernommene Segment, nicht gegen ein übersprungenes leeres.
            var newParagraph = previousEnd is not { } end || segment.Start - end >= paragraphGap;
            if (newParagraph && previousEnd != null) lines.Add("");
            lines.Add(newParagraph && timestamps ? $"[{Timecode(segment.Start)}] {text}" : text);
            previousEnd = segment.End;
        }
        return string.Join("\n", lines);
    }

    /// <summary>„2:04" bzw. „1:02:05" — kurz genug, um vor jedem Absatz zu stehen.</summary>
    public static string Timecode(double seconds)
    {
        var total = (int)Math.Max(0, seconds);
        return total >= 3600
            ? $"{total / 3600}:{total % 3600 / 60:D2}:{total % 60:D2}"
            : $"{total / 60}:{total % 60:D2}";
    }
}
