using System.Text.RegularExpressions;

namespace Shout.Core;

/// <summary>
/// Deterministischer Sprachbefehl-Layer (Dragon-Stil) — 1:1-Port vom Mac:
/// wandelt gesprochene Marker wie „Komma", „Punkt" oder „neue Zeile" in echte
/// Satzzeichen/Umbrüche. Läuft VOR dem optionalen KI-Formatter.
/// </summary>
public static class SpeechCommands
{
    // Grenzen über Lookarounds statt \b: schließt angrenzende Buchstaben, Ziffern
    // UND Bindestriche aus — sonst würde „Punkt-zu-Punkt" zu „.-zu-." zerfallen.
    private const string L = @"(?<![\p{L}\p{N}-])";   // links: kein Wortzeichen/Bindestrich
    private const string R = @"(?![\p{L}\p{N}-])";    // rechts: dito
    // „Punkt eins/zwei/…" ist ein Aufzählungs-Marker, auf den der Formatter baut —
    // dann NICHT durch „." ersetzen.
    private const string NotEnumeration =
        @"(?!\s+(?:eins|zwei|drei|vier|fünf|sechs|sieben|acht|neun|zehn|\d))";

    // Reihenfolge: mehrteilige/spezifische Marker zuerst. Groß-/Kleinschreibung egal.
    private static readonly (Regex Pattern, string Replacement)[] Rules =
    {
        (new Regex(@"\s*" + L + @"neuer\s+absatz" + R + @"\s*", RegexOptions.IgnoreCase | RegexOptions.Compiled), "\n\n"),
        (new Regex(@"\s*" + L + @"neue\s+zeile" + R + @"\s*", RegexOptions.IgnoreCase | RegexOptions.Compiled), "\n"),
        (new Regex(@"\s*" + L + "fragezeichen" + R, RegexOptions.IgnoreCase | RegexOptions.Compiled), "?"),
        (new Regex(@"\s*" + L + "ausrufezeichen" + R, RegexOptions.IgnoreCase | RegexOptions.Compiled), "!"),
        (new Regex(@"\s*" + L + "doppelpunkt" + R, RegexOptions.IgnoreCase | RegexOptions.Compiled), ":"),
        (new Regex(@"\s*" + L + "(?:semikolon|strichpunkt)" + R, RegexOptions.IgnoreCase | RegexOptions.Compiled), ";"),
        (new Regex(@"\s*" + L + "komma" + R, RegexOptions.IgnoreCase | RegexOptions.Compiled), ","),
        (new Regex(@"\s*" + L + "punkt" + R + NotEnumeration, RegexOptions.IgnoreCase | RegexOptions.Compiled), "."),
    };

    public static string Apply(string text)
    {
        var result = text;
        foreach (var (pattern, replacement) in Rules)
            result = pattern.Replace(result, replacement.Replace("$", "$$"));
        return result.Trim();
    }
}
