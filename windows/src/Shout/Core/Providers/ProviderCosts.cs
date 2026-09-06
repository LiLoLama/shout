using System.Globalization;

namespace Shout.Core;

/// <summary>Rechnet gemessenen Verbrauch in Geld um und formatiert ihn.</summary>
public static class ProviderCosts
{
    /// <summary>Kosten eines Textverbrauchs. null, wenn der Preis unbekannt ist.</summary>
    public static double? Cost(TokenCount tokens, ModelPrice? price)
    {
        if (price == null) return null;
        return tokens.Prompt / 1_000_000.0 * price.Input
             + tokens.Completion / 1_000_000.0 * price.Output;
    }

    public static double? Cost(double seconds, AudioPrice? price)
    {
        if (price == null) return null;
        return seconds / 60 * price.PerMinute;
    }

    /// <summary>
    /// Geldbetrag für die Oberfläche. Bewusst mehr Stellen bei kleinen Beträgen —
    /// „$0,00" für ein Diktat wäre keine Auskunft.
    ///
    /// <para>Fest invariant formatiert: Der Betrag ist in Dollar, und „$0,0042" mit
    /// deutschem Komma sähe nach einem Tippfehler aus. Übersetzt wird die Zeile
    /// drumherum, nicht die Zahl.</para>
    /// </summary>
    public static string Format(double usd)
    {
        if (usd == 0) return "$0";
        if (usd < 0.01) return "$" + usd.ToString("F4", CultureInfo.InvariantCulture);
        if (usd < 1) return "$" + usd.ToString("F3", CultureInfo.InvariantCulture);
        return "$" + usd.ToString("F2", CultureInfo.InvariantCulture);
    }

    /// <summary>Vorab-Schätzung für ein typisches Diktat: rund 700 Zeichen hinein,
    /// ebenso viele heraus, dazu die Systemanweisung. Vier Zeichen je Token ist die
    /// gängige Faustregel für europäische Sprachen.</summary>
    public static TokenCount TypicalDictation => new() { Prompt = 400, Completion = 180 };
}
