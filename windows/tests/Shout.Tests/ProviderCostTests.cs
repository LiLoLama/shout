using System.Globalization;
using System.Text.Json;
using Shout.Core;
using Xunit;

namespace Shout.Tests;

/// <summary>Preistabelle, Kostenformat und die Schlüssel-Verkürzung.</summary>
public class ProviderCostTests
{
    [Fact]
    public void PreisWirdGenauGefunden()
    {
        var preis = PriceTable.Bundled.PriceForText("gpt-5-mini");
        Assert.NotNull(preis);
        Assert.Equal(0.25, preis!.Input);
        Assert.Equal(2.00, preis.Output);
    }

    /// <summary>OpenRouter nennt dasselbe Modell mit Organisationsvorsilbe.</summary>
    [Fact]
    public void PreisWirdAuchOhneVorsilbeGefunden()
    {
        Assert.Equal(0.25, PriceTable.Bundled.PriceForText("openai/gpt-5-mini")!.Input);
        Assert.Equal(0.00185, PriceTable.Bundled.PriceForAudio("openai/whisper-large-v3")!.PerMinute);
    }

    /// <summary>Unbekannt heißt null — es wird keine Zahl erfunden.</summary>
    [Fact]
    public void UnbekanntesModellHatKeinenPreis()
    {
        Assert.Null(PriceTable.Bundled.PriceForText("hausmarke-7b"));
        Assert.Null(PriceTable.Bundled.PriceForAudio("hausmarke-whisper"));
        Assert.Null(PriceTable.Bundled.PriceForText(""));
    }

    /// <summary>Eine abgerufene Tabelle wird gespeichert und beim nächsten Start wieder
    /// gelesen — dabei darf kein Preis verloren gehen.</summary>
    [Fact]
    public void PreistabelleUeberstehtDieDatei()
    {
        var json = JsonSerializer.Serialize(PriceTable.Bundled, StoreIO.JsonOptions);
        var zurueck = JsonSerializer.Deserialize<PriceTable>(json, StoreIO.JsonOptions)!;

        Assert.Equal(PriceTable.BundledUpdated, zurueck.Updated);
        Assert.Equal(0.25, zurueck.PriceForText("gpt-5-mini")!.Input);
        Assert.Equal(0.006, zurueck.PriceForAudio("whisper-1")!.PerMinute);
    }

    [Fact]
    public void KostenRechnenJeMillionUndJeMinute()
    {
        var tokens = new TokenCount { Prompt = 1_000_000, Completion = 500_000 };
        Assert.Equal(0.25 + 1.00, ProviderCosts.Cost(tokens, new ModelPrice(0.25, 2.00))!.Value, 9);
        Assert.Equal(0.006, ProviderCosts.Cost(60.0, new AudioPrice(0.006))!.Value, 9);

        Assert.Null(ProviderCosts.Cost(tokens, null));
        Assert.Null(ProviderCosts.Cost(60.0, null));
    }

    /// <summary>Der Betrag ist in Dollar — auch auf einem deutschen Windows darf da kein
    /// Komma stehen.</summary>
    [Fact]
    public void FormatBleibtInvariant()
    {
        var vorher = CultureInfo.CurrentCulture;
        try
        {
            CultureInfo.CurrentCulture = new CultureInfo("de-DE");

            Assert.Equal("$0", ProviderCosts.Format(0));
            Assert.Equal("$0.0042", ProviderCosts.Format(0.0042));
            Assert.Equal("$0.500", ProviderCosts.Format(0.5));
            Assert.Equal("$12.35", ProviderCosts.Format(12.3456));
        }
        finally
        {
            CultureInfo.CurrentCulture = vorher;
        }
    }

    [Fact]
    public void MonatsschluesselIstInvariant()
    {
        var vorher = CultureInfo.CurrentCulture;
        try
        {
            CultureInfo.CurrentCulture = new CultureInfo("ar-SA");
            Assert.Equal("2026-09", ProviderUsageStore.MonthKey(new DateTime(2026, 9, 6)));
        }
        finally
        {
            CultureInfo.CurrentCulture = vorher;
        }
    }

    [Fact]
    public void ModellKommtAusDemEintragsschluessel()
    {
        var schluessel = ProviderUsageStore.Key("OpenAI", "gpt-5-mini");
        Assert.Equal("gpt-5-mini", ProviderUsageStore.ModelFrom(schluessel));
        Assert.Equal("ohnetrenner", ProviderUsageStore.ModelFrom("ohnetrenner"));
    }

    // MARK: Schlüssel-Verkürzung

    [Theory]
    [InlineData("sk-proj-abcdefgh1234", "sk-…1234")]
    [InlineData("abcdefghijklmno", "…lmno")]
    [InlineData("  sk-proj-abcdefgh1234  ", "sk-…1234")]
    [InlineData("gsk_abcdefgh1234", "gsk_…1234")]
    public void MaskeZeigtVorsilbeUndVierZeichen(string key, string erwartet)
    {
        Assert.Equal(erwartet, KeyMask.Mask(key));
    }

    /// <summary>Bei kurzen Schlüsseln wären vier Zeichen fast der ganze Wert.</summary>
    [Theory]
    [InlineData("sk-abc", "sk-…")]
    [InlineData("kurz", "…")]
    public void KurzeSchluesselZeigenNichts(string key, string erwartet)
    {
        Assert.Equal(erwartet, KeyMask.Mask(key));
    }

    [Fact]
    public void LeererSchluesselErgibtLeereMaske()
    {
        Assert.Equal("", KeyMask.Mask(""));
        Assert.Equal("", KeyMask.Mask("   "));
        Assert.Equal("", KeyMask.Mask(null));
    }

    /// <summary>Ein Trenner tief im Wert ist keine Vorsilbe, sondern Zufall.</summary>
    [Fact]
    public void SpaeterTrennerIstKeineVorsilbe()
    {
        Assert.Equal("…mnop", KeyMask.Mask("abcdefg-hijklmnop"));
    }
}
