using Shout.Core;
using Xunit;

namespace Shout.Tests;

public class TranscriptLayoutTests
{
    [Fact]
    public void SteuermarkenWerdenEntfernt()
        => Assert.Equal("Hallo Welt", TranscriptLayout.StripSpecialTokens("<|de|>Hallo  Welt<|endoftext|>"));

    [Fact]
    public void LangePauseErzeugtEinenAbsatz()
    {
        var segments = new List<TranscriptSegment>
        {
            new("Erster Satz.", 0, 2),
            new("Direkt danach.", 2.2, 4),
            new("Nach langer Pause.", 10, 12),
        };
        var text = TranscriptLayout.RawText(segments);
        Assert.Equal("Erster Satz.\nDirekt danach.\n\nNach langer Pause.", text);
    }

    [Fact]
    public void ZeitmarkenNurAmAbsatzanfang()
    {
        var segments = new List<TranscriptSegment>
        {
            new("Eins", 0, 2),
            new("Zwei", 10, 12),
        };
        var text = TranscriptLayout.RawText(segments, timestamps: true);
        Assert.Equal("[0:00] Eins\n\n[0:10] Zwei", text);
    }

    /// <summary>Der Vergleich läuft gegen das letzte ÜBERNOMMENE Segment — ein
    /// übersprungenes leeres darf keinen Absatz auslösen.</summary>
    [Fact]
    public void LeereSegmenteZaehlenNicht()
    {
        var segments = new List<TranscriptSegment>
        {
            new("Eins", 0, 2),
            new("   ", 2.1, 2.2),
            new("Zwei", 2.3, 4),
        };
        Assert.Equal("Eins\nZwei", TranscriptLayout.RawText(segments));
    }

    [Theory]
    [InlineData(0, "0:00")]
    [InlineData(64, "1:04")]
    [InlineData(3725, "1:02:05")]
    public void Zeitcode(double seconds, string expected)
        => Assert.Equal(expected, TranscriptLayout.Timecode(seconds));
}

public class SubtitleWriterTests
{
    [Fact]
    public void SrtHatLueckenloseNummerierung()
    {
        var segments = new List<TranscriptSegment>
        {
            new("Eins", 0, 1),
            new("   ", 1, 2),
            new("Zwei", 2, 3),
        };
        var srt = SubtitleWriter.Srt(segments);
        Assert.Contains("1\n00:00:00,000 --> 00:00:01,000\nEins", srt, StringComparison.Ordinal);
        Assert.Contains("2\n00:00:02,000 --> 00:00:03,000\nZwei", srt, StringComparison.Ordinal);
        Assert.DoesNotContain("3\n", srt, StringComparison.Ordinal);
    }

    /// <summary>Ein Punkt statt des Kommas ist der häufigste Grund, warum eine .srt
    /// stumm bleibt.</summary>
    [Fact]
    public void MillisekundenMitKomma()
        => Assert.Equal("01:02:03,456", SubtitleWriter.Timecode(3723.456));

    [Fact]
    public void NegativeZeitWirdGeklemmt()
        => Assert.Equal("00:00:00,000", SubtitleWriter.Timecode(-5));
}

public class TranscriptMinutesTests
{
    [Fact]
    public void AbschnittWirdZerlegt()
    {
        var section = TranscriptMinutes.ParseSection(
            "TITEL: Kickoff\nPUNKTE:\n- Erster Punkt\n- Zweiter Punkt\nTEXT:\nDer Fließtext.");
        Assert.Equal("Kickoff", section.Title);
        Assert.Equal(new[] { "Erster Punkt", "Zweiter Punkt" }, section.Points);
        Assert.Equal("Der Fließtext.", section.Text);
    }

    /// <summary>Kleine quantisierte Modelle halten sich nicht zuverlässig an ein
    /// Ausgabeformat — was nicht erkannt wird, landet als Text statt verloren zu gehen.</summary>
    [Fact]
    public void OhneMarkerGiltAllesAlsText()
    {
        var section = TranscriptMinutes.ParseSection("Einfach nur ein Absatz.");
        Assert.Null(section.Title);
        Assert.Empty(section.Points);
        Assert.Equal("Einfach nur ein Absatz.", section.Text);
    }

    [Fact]
    public void KernpunkteWerdenEntdoppelt()
    {
        var sections = new[]
        {
            new TranscriptMinutes.Section { Points = { "Termin steht", "Budget offen" } },
            new TranscriptMinutes.Section { Points = { "termin steht", "Team informieren" } },
        };
        var points = TranscriptMinutes.CollectPoints(sections);
        Assert.Equal(new[] { "Termin steht", "Budget offen", "Team informieren" }, points);
    }

    [Fact]
    public void DokumentWirdZusammengesetzt()
    {
        var headings = new TranscriptMinutes.Headings("Zusammenfassung", "Kernpunkte", "Protokoll");
        var sections = new[] { new TranscriptMinutes.Section { Title = "Teil", Text = "Inhalt" } };
        var document = TranscriptMinutes.Assemble("Kurzfassung.", new[] { "Punkt" }, sections, headings);

        Assert.StartsWith("# Zusammenfassung\n\nKurzfassung.", document, StringComparison.Ordinal);
        Assert.Contains("# Kernpunkte\n\n- Punkt", document, StringComparison.Ordinal);
        Assert.Contains("# Protokoll\n\n## Teil\n\nInhalt", document, StringComparison.Ordinal);
    }

    [Fact]
    public void LeeresProtokollBleibtLeer()
    {
        var headings = new TranscriptMinutes.Headings("Z", "K", "P");
        Assert.Equal("", TranscriptMinutes.Assemble("", Array.Empty<string>(),
                                                    Array.Empty<TranscriptMinutes.Section>(), headings));
    }
}
