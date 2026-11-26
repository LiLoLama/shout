using Shout.Core;
using Xunit;

namespace Shout.Tests;

/// <summary>Gleiche Fälle wie PhantomClosingTests.swift am Mac.</summary>
public class PhantomClosingTests
{
    private const int Rate = 16_000;

    private static float[] Audio(params (bool speech, double seconds)[] parts)
    {
        var output = new List<float>();
        foreach (var (speech, seconds) in parts)
        {
            var n = (int)(seconds * Rate);
            for (var i = 0; i < n; i++)
                output.Add(speech ? 0.2f * MathF.Sin(i * 2 * MathF.PI * 220 / Rate)
                                  : (i % 2 == 0 ? 0.001f : -0.001f));
        }
        return output.ToArray();
    }

    [Fact]
    public void ErfundeneFloskelInDerStilleWirdGestrichen()
    {
        var samples = Audio((true, 8), (false, 2));
        var segments = new List<TranscriptSegment> { new("Kannst du da nochmal schauen?", 0, 8), new("Vielen Dank.", 8.1, 10) };
        Assert.Equal("Kannst du da nochmal schauen?",
                     PhantomClosing.Strip("Kannst du da nochmal schauen? Vielen Dank.", segments, samples));
    }

    [Fact]
    public void FloskelHinterDemAudioendeWirdGestrichen()
    {
        var samples = Audio((true, 6));
        var segments = new List<TranscriptSegment> { new("Das passt so.", 0, 5.9), new("Bis zum nächsten Mal.", 6, 8) };
        Assert.Equal("Das passt so.", PhantomClosing.Strip("Das passt so. Bis zum nächsten Mal.", segments, samples));
    }

    [Fact]
    public void UntertitelZeileWirdGestrichen()
    {
        var samples = Audio((true, 5), (false, 3));
        var segments = new List<TranscriptSegment> { new("Termin ist am Montag.", 0, 5), new("Untertitel im Auftrag des ZDF, 2020", 5.2, 8) };
        Assert.Equal("Termin ist am Montag.",
                     PhantomClosing.Strip("Termin ist am Montag. Untertitel im Auftrag des ZDF, 2020", segments, samples));
    }

    [Fact]
    public void GesprochenesVielenDankBleibt()
    {
        var samples = Audio((true, 8), (false, 0.3), (true, 0.8), (false, 0.5));
        var segments = new List<TranscriptSegment> { new("Kannst du da nochmal schauen?", 0, 8), new("Vielen Dank.", 8.3, 9.2) };
        const string text = "Kannst du da nochmal schauen? Vielen Dank.";
        Assert.Equal(text, PhantomClosing.Strip(text, segments, samples));
    }

    [Fact]
    public void AndererSchlusssatzInDerStilleBleibt()
    {
        var samples = Audio((true, 8), (false, 2));
        var segments = new List<TranscriptSegment> { new("Das ist der Plan.", 0, 8), new("Das ist der Gedanke dahinter.", 8.1, 10) };
        const string text = "Das ist der Plan. Das ist der Gedanke dahinter.";
        Assert.Equal(text, PhantomClosing.Strip(text, segments, samples));
    }

    [Fact]
    public void FloskelImSelbenAbschnittBleibt()
    {
        var samples = Audio((true, 8), (false, 2));
        var segments = new List<TranscriptSegment> { new("Kannst du da nochmal schauen? Vielen Dank.", 0, 10) };
        const string text = "Kannst du da nochmal schauen? Vielen Dank.";
        Assert.Equal(text, PhantomClosing.Strip(text, segments, samples));
    }
}
