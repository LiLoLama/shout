using Shout.Core;
using Xunit;

namespace Shout.Tests;

public class CorrectionLearnerTests
{
    [Fact]
    public void EinzelnesFalschesWortWirdGelernt()
    {
        var pairs = CorrectionLearner.Pairs("Wir treffen Lilo Lama morgen",
                                            "Wir treffen LiLoLama morgen");
        Assert.Equal(new[] { ("Lilo", "LiLoLama") }, pairs);
    }

    [Fact]
    public void MehrereErsetzungenWerdenGelernt()
    {
        var pairs = CorrectionLearner.Pairs("Das Tool heisst Schaut und laeuft lokal",
                                            "Das Tool heisst shout und läuft lokal");
        Assert.Contains(("Schaut", "shout"), pairs);
        Assert.Contains(("laeuft", "läuft"), pairs);
    }

    /// <summary>Der Grund für die Wort-gegen-Wort-Regel: Wer einen Satz umformuliert,
    /// meint keine Erkennungskorrektur — daraus eine Ersetzungsregel zu bauen, die
    /// künftig in JEDEM Diktat greift, macht Text kaputt.</summary>
    [Fact]
    public void EingefuegteWoerterWerdenNichtGelernt()
    {
        var pairs = CorrectionLearner.Pairs("Wir treffen uns morgen",
                                            "Wir treffen uns dann morgen");
        Assert.Empty(pairs);
    }

    [Fact]
    public void GestricheneWoerterWerdenNichtGelernt()
    {
        var pairs = CorrectionLearner.Pairs("Wir treffen uns also morgen",
                                            "Wir treffen uns morgen");
        Assert.Empty(pairs);
    }

    [Fact]
    public void ReineSatzzeichenAenderungWirdIgnoriert()
    {
        var pairs = CorrectionLearner.Pairs("Wir gehen jetzt heim",
                                            "Wir gehen jetzt heim.");
        Assert.Empty(pairs);
    }

    [Fact]
    public void ZahlenWerdenNichtGelernt()
    {
        var pairs = CorrectionLearner.Pairs("Wir treffen uns um 3",
                                            "Wir treffen uns um 15");
        Assert.Empty(pairs);
    }

    [Fact]
    public void GleicherTextLerntNichts()
        => Assert.Empty(CorrectionLearner.Pairs("Alles gleich hier", "Alles gleich hier"));

    [Fact]
    public void DasselbeFalscheWortNurEinmal()
    {
        var pairs = CorrectionLearner.Pairs("Schaut und Schaut und Schaut",
                                            "shout und shout und shout");
        Assert.Single(pairs);
    }
}
