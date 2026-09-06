using Shout.Core;
using Xunit;

namespace Shout.Tests;

public class TextChunkerTests
{
    [Fact]
    public void KurzerTextBleibtEinStueck()
    {
        var chunks = TextChunker.Chunks("Ein kurzer Satz.", 1500, 1000);
        Assert.Single(chunks);
        Assert.Equal("Ein kurzer Satz.", chunks[0]);
    }

    [Fact]
    public void LangerTextWirdAnSatzgrenzenGeteilt()
    {
        var satz = "Das ist ein vollständiger Satz mit genügend Länge. ";
        var text = string.Concat(Enumerable.Repeat(satz, 40));
        var chunks = TextChunker.Chunks(text, 300, 200);

        Assert.True(chunks.Count > 1);
        // Kein Abschnitt fängt mitten im Wort an.
        Assert.All(chunks, c => Assert.StartsWith("Das", c, StringComparison.Ordinal));
        // Nichts geht verloren.
        Assert.Equal(text.Replace(" ", "").Trim(), string.Concat(chunks).Replace(" ", ""));
    }

    /// <summary>„z. B." ist kein Satzende — sonst stünde der Schnitt mitten im Beispiel.</summary>
    [Fact]
    public void AbkuerzungBeendetKeinenSatz()
    {
        var text = "Wir nehmen z. B. Das folgende Beispiel her und reden weiter. " +
                   new string('x', 400) + ". Danach Kommt noch etwas.";
        var chunks = TextChunker.Chunks(text, 200, 120);
        Assert.All(chunks, c => Assert.False(c.StartsWith("B.", StringComparison.Ordinal)));
    }

    [Fact]
    public void JoinFormattedSetztLeerzeichen()
    {
        Assert.Equal("Erster Teil. Zweiter Teil.",
                     TextChunker.JoinFormatted(new[] { "Erster Teil.", "Zweiter Teil." }));
    }

    /// <summary>Der Grund für die Sonderbehandlung: Sonst klebte „2. Punkt" hinter
    /// dem Satzende des vorigen Abschnitts in derselben Zeile.</summary>
    [Fact]
    public void JoinFormattedBrichtVorUndNachListen()
    {
        Assert.Equal("Text davor\n1. eins",
                     TextChunker.JoinFormatted(new[] { "Text davor", "1. eins" }));
        Assert.Equal("- eins\nText danach",
                     TextChunker.JoinFormatted(new[] { "- eins", "Text danach" }));
    }

    [Fact]
    public void JoinFormattedIgnoriertLeereTeile()
    {
        Assert.Equal("a b", TextChunker.JoinFormatted(new[] { "a", "  ", "b" }));
        Assert.Equal("", TextChunker.JoinFormatted(Array.Empty<string>()));
    }

    [Theory]
    [InlineData("1. eins", true)]
    [InlineData("2) zwei", true)]
    [InlineData("- drei", true)]
    [InlineData("• vier", true)]
    [InlineData("kein Punkt", false)]
    [InlineData("", false)]
    public void ListenpunkteWerdenErkannt(string line, bool expected)
        => Assert.Equal(expected, TextChunker.IsListItem(line));
}
