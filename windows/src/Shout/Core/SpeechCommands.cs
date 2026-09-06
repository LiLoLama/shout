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
    private const string NotEnumerationDe =
        @"(?!\s+(?:eins|zwei|drei|vier|fünf|sechs|sieben|acht|neun|zehn|\d))";
    private const string NotEnumerationEn =
        @"(?!\s+(?:one|two|three|four|five|six|seven|eight|nine|ten|\d))";

    private const RegexOptions Opts = RegexOptions.IgnoreCase | RegexOptions.Compiled;

    // Reihenfolge: mehrteilige/spezifische Marker zuerst. Groß-/Kleinschreibung egal.
    private static readonly (Regex Pattern, string Replacement)[] German =
    {
        (new Regex(@"\s*" + L + @"neuer\s+absatz" + R + @"\s*", Opts), "\n\n"),
        (new Regex(@"\s*" + L + @"neue\s+zeile" + R + @"\s*", Opts), "\n"),
        (new Regex(@"\s*" + L + "fragezeichen" + R, Opts), "?"),
        (new Regex(@"\s*" + L + "ausrufezeichen" + R, Opts), "!"),
        (new Regex(@"\s*" + L + "doppelpunkt" + R, Opts), ":"),
        (new Regex(@"\s*" + L + "(?:semikolon|strichpunkt)" + R, Opts), ";"),
        (new Regex(@"\s*" + L + "komma" + R, Opts), ","),
        (new Regex(@"\s*" + L + "punkt" + R + NotEnumerationDe, Opts), "."),
    };

    /// <summary>
    /// Dieselben Marker auf Englisch. Sie fehlten bisher, obwohl die englische
    /// Oberfläche sie ausdrücklich verspricht („say ‚comma‘, ‚period‘, ‚new line‘") —
    /// wer auf Englisch diktierte, bekam den Schalter ohne die Funktion.
    /// </summary>
    private static readonly (Regex Pattern, string Replacement)[] English =
    {
        (new Regex(@"\s*" + L + @"new\s+paragraph" + R + @"\s*", Opts), "\n\n"),
        (new Regex(@"\s*" + L + @"new\s+line" + R + @"\s*", Opts), "\n"),
        (new Regex(@"\s*" + L + @"question\s+mark" + R, Opts), "?"),
        (new Regex(@"\s*" + L + @"exclamation\s+(?:mark|point)" + R, Opts), "!"),
        (new Regex(@"\s*" + L + "colon" + R, Opts), ":"),
        (new Regex(@"\s*" + L + "semicolon" + R, Opts), ";"),
        (new Regex(@"\s*" + L + "comma" + R, Opts), ","),
        (new Regex(@"\s*" + L + @"(?:period|full\s+stop)" + R + NotEnumerationEn, Opts), "."),
    };

    /// <summary>Wendet die Befehle der eingestellten Diktier-Sprache an.</summary>
    public static string Apply(string text) => Apply(text, Settings.Shared.Language);

    /// <summary>
    /// Wendet die Befehle an. <paramref name="language"/> ist "de", "en" oder "auto";
    /// bei „auto" gelten beide Tabellen, weil dann auch beide Sprachen kommen können.
    /// Die jeweils andere Sprache anzuwenden ist nicht harmlos: „comma" ist im
    /// Deutschen kein Wort, „Punkt" im Englischen aber sehr wohl.
    /// </summary>
    public static string Apply(string text, string language)
    {
        var result = text;
        if (language != "en")
            foreach (var (pattern, replacement) in German)
                result = pattern.Replace(result, replacement.Replace("$", "$$"));
        if (language != "de")
            foreach (var (pattern, replacement) in English)
                result = pattern.Replace(result, replacement.Replace("$", "$$"));
        return result.Trim();
    }
}
