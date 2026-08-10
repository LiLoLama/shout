using System.Text;

namespace Shout.Core;

/// <summary>
/// Schreibt Transkript-Abschnitte als SubRip-Untertitel (.srt) — Mac: SubtitleWriter.swift.
///
/// <para>Die Untertitel entstehen IMMER aus dem Rohtranskript. Sobald das
/// Sprachmodell Sätze umbaut, passt der Wortlaut nicht mehr zu den Zeitmarken —
/// dann wären die Untertitel schlicht falsch.</para>
/// </summary>
public static class SubtitleWriter
{
    /// <summary>
    /// SRT-Text für die Segmente. Leere Segmente werden übersprungen; die
    /// Nummerierung bleibt trotzdem lückenlos, weil manche Abspieler bei Lücken die
    /// restliche Datei verwerfen.
    /// </summary>
    public static string Srt(IReadOnlyList<TranscriptSegment> segments)
    {
        var sb = new StringBuilder();
        var index = 1;
        foreach (var segment in segments)
        {
            var text = segment.Text.Trim();
            if (text.Length == 0) continue;
            sb.Append(index).Append('\n');
            sb.Append(Timecode(segment.Start)).Append(" --> ")
              .Append(Timecode(Math.Max(segment.End, segment.Start))).Append('\n');
            sb.Append(text).Append("\n\n");
            index++;
        }
        return sb.ToString();
    }

    /// <summary>
    /// „HH:MM:SS,mmm" — Millisekunden mit Komma, wie SubRip es verlangt (ein Punkt
    /// statt des Kommas ist der häufigste Grund, warum eine .srt stumm bleibt).
    /// </summary>
    public static string Timecode(double seconds)
    {
        var totalMs = (int)Math.Round(Math.Max(0, seconds) * 1000);
        var ms = totalMs % 1000;
        var total = totalMs / 1000;
        return $"{total / 3600:D2}:{total % 3600 / 60:D2}:{total % 60:D2},{ms:D3}";
    }
}
