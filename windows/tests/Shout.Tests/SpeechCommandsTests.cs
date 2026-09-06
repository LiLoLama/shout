using Shout.Core;
using Xunit;

namespace Shout.Tests;

/// <summary>
/// Sprachbefehle. Geprüft wird die Fassung mit ausdrücklicher Sprache — die
/// Bequemlichkeits-Überladung liest die Einstellungen und damit die Platte.
/// </summary>
public class SpeechCommandsTests
{
    [Fact]
    public void DeutscheMarkerWerdenZuSatzzeichen()
    {
        Assert.Equal("Hallo, wie geht's?",
                     SpeechCommands.Apply("Hallo Komma wie geht's Fragezeichen", "de"));
    }

    [Fact]
    public void NeueZeileUndNeuerAbsatz()
    {
        Assert.Equal("eins\nzwei\n\ndrei",
                     SpeechCommands.Apply("eins neue Zeile zwei neuer Absatz drei", "de"));
    }

    [Fact]
    public void EnglischeMarkerWerdenZuSatzzeichen()
    {
        Assert.Equal("Hello, how are you?",
                     SpeechCommands.Apply("Hello comma how are you question mark", "en"));
    }

    [Fact]
    public void EnglischesNewLineUndFullStop()
    {
        Assert.Equal("one\ntwo.", SpeechCommands.Apply("one new line two full stop", "en"));
    }

    /// <summary>Der Grund für den Lookahead: „Punkt eins" ist ein Aufzählungs-Marker,
    /// auf den der Formatter baut — kein Satzzeichen.</summary>
    [Fact]
    public void AufzaehlungBleibtStehen()
    {
        Assert.Equal("Punkt eins wir fangen an",
                     SpeechCommands.Apply("Punkt eins wir fangen an", "de"));
        Assert.Equal("period one we start",
                     SpeechCommands.Apply("period one we start", "en"));
        // Ohne folgende Zahl ist es sehr wohl ein Satzzeichen.
        Assert.Equal("wir fangen an.", SpeechCommands.Apply("wir fangen an Punkt", "de"));
        Assert.Equal("we start.", SpeechCommands.Apply("we start period", "en"));
    }

    /// <summary>Der Grund für die Lookarounds statt \b: sonst zerfiele
    /// „Punkt-zu-Punkt" zu „.-zu-.".</summary>
    [Fact]
    public void BindestrichSchuetztDasWort()
    {
        Assert.Equal("Punkt-zu-Punkt-Verbindung",
                     SpeechCommands.Apply("Punkt-zu-Punkt-Verbindung", "de"));
    }

    /// <summary>„Punkt" ist im Deutschen ein normales Wort, „comma" im Englischen
    /// nicht — deshalb greift auf Englisch NUR die englische Tabelle.</summary>
    [Fact]
    public void EnglischLaesstDeutscheWoerterInRuhe()
    {
        Assert.Equal("the Punkt stays", SpeechCommands.Apply("the Punkt stays", "en"));
    }

    [Fact]
    public void AutoWendetBeideTabellenAn()
    {
        Assert.Equal("a, b,", SpeechCommands.Apply("a comma b Komma", "auto"));
    }
}
