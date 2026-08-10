using System.Text;

namespace Shout.Core;

/// <summary>
/// Baut aus den Antworten des Sprachmodells ein Protokoll: Zusammenfassung,
/// Kernpunkte, darunter der gegliederte Volltext (Mac: TranscriptMinutes.swift).
///
/// <para>Warum nicht einfach <see cref="LlmFormatter.FormatAsync"/>: Der bereinigt
/// diktierten Text und ist ausdrücklich darauf getrimmt, NICHTS zu kürzen. Auf ein
/// Whisper-Transkript losgelassen — das ohnehin schon interpunktiert ist — kommt
/// fast unverändert die Eingabe heraus. Ein Protokoll ist die andere Aufgabe:
/// verdichten, gliedern, das Wichtigste nach oben holen.</para>
///
/// <para>Das Zerlegen der Modellantwort ist bewusst nachsichtig: Kleine quantisierte
/// Modelle halten sich nicht zuverlässig an ein Ausgabeformat. Was nicht erkannt
/// wird, landet als Text im Protokoll — lieber unstrukturiert als verloren.</para>
/// </summary>
public static class TranscriptMinutes
{
    public sealed class Section
    {
        public string? Title { get; set; }
        public List<string> Points { get; set; } = new();
        public string Text { get; set; } = "";
    }

    /// <summary>Überschriften des Dokuments — als Parameter, damit das
    /// Zusammensetzen ohne Oberfläche testbar bleibt.</summary>
    public readonly record struct Headings(string Summary, string Points, string Body);

    private static readonly string[] TitleMarkers = { "titel:", "überschrift:", "title:" };
    private static readonly string[] PointsMarkers = { "punkte:", "kernpunkte:", "points:" };
    private static readonly string[] TextMarkers = { "text:", "inhalt:", "body:" };

    /// <summary>
    /// Zerlegt eine Modellantwort der Form <c>TITEL: … / PUNKTE: … / TEXT: …</c>.
    /// Fehlt jeder Marker, gilt die ganze Antwort als Text.
    /// </summary>
    public static Section ParseSection(string raw)
    {
        var section = new Section();
        var textLines = new List<string>();
        var part = 0;          // 0 = keiner, 1 = Punkte, 2 = Text
        var sawMarker = false;

        foreach (var line in raw.Split('\n'))
        {
            var trimmed = line.Trim();
            var lowered = trimmed.ToLowerInvariant();

            var marker = TitleMarkers.FirstOrDefault(m => lowered.StartsWith(m, StringComparison.Ordinal));
            if (marker != null)
            {
                var title = trimmed[marker.Length..].Trim();
                section.Title = title.Length == 0 ? null : title;
                part = 0;
                sawMarker = true;
                continue;
            }

            marker = PointsMarkers.FirstOrDefault(m => lowered.StartsWith(m, StringComparison.Ordinal));
            if (marker != null)
            {
                var rest = trimmed[marker.Length..].Trim();
                if (rest.Length > 0) section.Points.Add(rest);
                part = 1;
                sawMarker = true;
                continue;
            }

            marker = TextMarkers.FirstOrDefault(m => lowered.StartsWith(m, StringComparison.Ordinal));
            if (marker != null)
            {
                var rest = trimmed[marker.Length..].Trim();
                if (rest.Length > 0) textLines.Add(rest);
                part = 2;
                sawMarker = true;
                continue;
            }

            if (part == 1)
            {
                var point = StripBullet(trimmed);
                if (point.Length > 0) section.Points.Add(point);
            }
            else
            {
                textLines.Add(line);
            }
        }

        section.Text = string.Join("\n", textLines).Trim();
        if (!sawMarker) section.Title = null;
        return section;
    }

    /// <summary>Entfernt Aufzählungszeichen: „- ", „• ", „* " und „1. ".</summary>
    private static string StripBullet(string line)
    {
        if (line.Length == 0) return line;
        if ("-•*–—".Contains(line[0])) return line[1..].Trim();

        var digits = 0;
        while (digits < line.Length && char.IsDigit(line[digits])) digits++;
        if (digits > 0 && digits < line.Length && line[digits] == '.') return line[(digits + 1)..].Trim();
        return line.Trim();
    }

    /// <summary>
    /// Sammelt die Kernpunkte aller Abschnitte ein und entdoppelt sie (ohne Rücksicht
    /// auf Groß-/Kleinschreibung — Modelle formulieren denselben Punkt gern zweimal
    /// leicht anders angeschrieben).
    /// </summary>
    public static List<string> CollectPoints(IEnumerable<Section> sections)
    {
        var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        var result = new List<string>();
        foreach (var point in sections.SelectMany(s => s.Points))
        {
            var key = point.Trim();
            if (key.Length == 0 || !seen.Add(key)) continue;
            result.Add(point);
        }
        return result;
    }

    public static string Assemble(string summary, IReadOnlyList<string> points,
                                  IReadOnlyList<Section> sections, Headings headings)
    {
        var blocks = new List<string>();

        var cleanSummary = summary.Trim();
        if (cleanSummary.Length > 0)
            blocks.Add($"# {headings.Summary}\n\n{cleanSummary}");
        if (points.Count > 0)
            blocks.Add($"# {headings.Points}\n\n" + string.Join("\n", points.Select(p => $"- {p}")));

        var body = new List<string>();
        foreach (var section in sections)
        {
            var text = section.Text.Trim();
            if (text.Length == 0) continue;
            var title = section.Title?.Trim();
            body.Add(string.IsNullOrEmpty(title) ? text : $"## {title}\n\n{text}");
        }
        if (body.Count > 0)
            blocks.Add($"# {headings.Body}\n\n" + string.Join("\n\n", body));

        return string.Join("\n\n", blocks);
    }
}
