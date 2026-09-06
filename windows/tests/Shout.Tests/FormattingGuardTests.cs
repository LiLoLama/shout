using Shout.Core;
using Xunit;

namespace Shout.Tests;

/// <summary>
/// Das Netz hinter dem Prompt: Ein kleines Modell liest ein Diktat, das wie eine
/// Bitte klingt, gelegentlich als Auftrag an sich selbst und antwortet darauf.
/// </summary>
public class FormattingGuardTests
{
    [Fact]
    public void SaubereFormatierungGehtDurch()
    {
        var input = "also äh wir treffen uns morgen um drei im großen besprechungsraum";
        var output = "Wir treffen uns morgen um drei im großen Besprechungsraum.";
        Assert.True(FormattingGuard.Check(input, output).IsOk);
    }

    [Fact]
    public void AntwortStattFormatierungWirdVerworfen()
    {
        var input = "könntest du bitte die zahlen vom letzten quartal heraussuchen und einfügen";
        var output = "Gerne! Bitte gib mir den Text, den ich für dich formatieren soll.";
        var result = FormattingGuard.Check(input, output);
        Assert.Equal(FormattingGuard.Verdict.Unrelated, result.Verdict);
    }

    [Fact]
    public void VerschlucktesEndeWirdVerworfen()
    {
        var words = Enumerable.Range(0, 60).Select(i => $"wort{i}");
        var input = string.Join(" ", words);
        var output = string.Join(" ", words.Take(20));
        Assert.Equal(FormattingGuard.Verdict.Truncated, FormattingGuard.Check(input, output).Verdict);
    }

    /// <summary>Bei kurzen Diktaten ist die halbe Wortzahl schnell erreicht, ohne
    /// dass Inhalt fehlt — deshalb greift die Kürzungs-Prüfung erst ab 30 Wörtern.</summary>
    [Fact]
    public void KurzesDiktatDarfDeutlichSchrumpfen()
    {
        var result = FormattingGuard.Check("also äh das ist gut ja wirklich gut", "Das ist gut.");
        Assert.True(result.IsOk);
    }

    [Fact]
    public void SehrKurzeEingabeWirdNichtGeprueft()
        => Assert.True(FormattingGuard.Check("ja gut", "Etwas völlig anderes hier.").IsOk);

    [Fact]
    public void LeereAusgabeGiltAlsFremd()
    {
        var result = FormattingGuard.Check("eins zwei drei vier fünf sechs", "");
        Assert.Equal(FormattingGuard.Verdict.Unrelated, result.Verdict);
    }

    /// <summary>Der Listen-Umbau kostet ein paar Prozent, weil „1." und „2." neue
    /// Wörter sind — er darf trotzdem nicht als Fremdtext gelten.</summary>
    [Fact]
    public void ListenUmbauBleibtErlaubt()
    {
        var input = "wir brauchen erstens die zahlen zweitens die präsentation drittens das feedback";
        var output = "Wir brauchen:\n1. die Zahlen\n2. die Präsentation\n3. das Feedback";
        Assert.True(FormattingGuard.Check(input, output).IsOk);
    }
}
