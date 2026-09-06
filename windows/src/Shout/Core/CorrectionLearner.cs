namespace Shout.Core;

/// <summary>
/// Vergleicht das eingefügte Diktat mit der vom Nutzer korrigierten Fassung und
/// leitet daraus Wörterbuch-Korrekturen ab (Mac: die Lernlogik hinter
/// CorrectionView/CorrectionWatcher).
///
/// <para>Bewusst nur <b>Wort gegen Wort</b>: Wer einen ganzen Satz umschreibt, meint
/// keine Erkennungskorrektur, sondern formuliert um — daraus eine Ersetzungsregel zu
/// bauen, die künftig in JEDEM Diktat greift, wäre ein sicherer Weg, Text kaputt zu
/// machen. Eingefügte oder gelöschte Wörter werden deshalb übersprungen; gelernt wird
/// nur, was an derselben Stelle steht und sich unterscheidet.</para>
/// </summary>
public static class CorrectionLearner
{
    /// <summary>Trägt die erkannten Paare ins Wörterbuch ein und liefert ihre Anzahl.</summary>
    public static int Learn(string original, string corrected, PersonalDictionary dictionary)
    {
        var pairs = Pairs(original, corrected);
        foreach (var (wrong, right) in pairs) dictionary.AddCorrection(wrong, right);
        return pairs.Count;
    }

    /// <summary>Die gelernten Paare (falsch → richtig), ohne sie zu speichern — so
    /// lässt sich die Regel für sich prüfen.</summary>
    public static List<(string Wrong, string Right)> Pairs(string original, string corrected)
    {
        var before = Words(original);
        var after = Words(corrected);
        var result = new List<(string, string)>();
        var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);

        foreach (var (a, b) in Align(before, after))
        {
            var wrong = Trim(a);
            var right = Trim(b);
            if (wrong.Length == 0 || right.Length == 0) continue;
            if (string.Equals(wrong, right, StringComparison.Ordinal)) continue;
            // Mindestens ein Buchstabe auf beiden Seiten: Zahlen und Satzzeichen
            // ändern sich je nach Kontext, eine feste Regel dafür wäre falsch.
            if (!wrong.Any(char.IsLetter) || !right.Any(char.IsLetter)) continue;
            if (!seen.Add(wrong)) continue;
            result.Add((wrong, right));
        }
        return result;
    }

    private static string[] Words(string text)
        => text.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries);

    /// <summary>Satzzeichen am Rand weg — die setzt die Aufbereitung ohnehin neu,
    /// und „Gerät." → „Gerät" ist keine Erkennungskorrektur.</summary>
    private static string Trim(string word) => word.Trim('.', ',', ';', ':', '!', '?', '"', '\'',
                                                          '(', ')', '[', ']', '„', '“', '”', '…', '-');

    /// <summary>
    /// Stellt die Wörter über die längste gemeinsame Teilfolge gegenüber. Nur wo
    /// GENAU ein Wort gegen genau ein Wort steht, entsteht ein Paar — bei
    /// Einfügungen und Streichungen bleibt die Stelle unberücksichtigt.
    /// </summary>
    private static List<(string, string)> Align(string[] before, string[] after)
    {
        var n = before.Length;
        var m = after.Length;
        // Klassische LCS-Tabelle. Diktate sind einige Dutzend bis wenige Hundert
        // Wörter lang, das ist für O(n·m) völlig unkritisch.
        var lcs = new int[n + 1, m + 1];
        for (var i = n - 1; i >= 0; i--)
            for (var j = m - 1; j >= 0; j--)
                lcs[i, j] = Same(before[i], after[j])
                    ? lcs[i + 1, j + 1] + 1
                    : Math.Max(lcs[i + 1, j], lcs[i, j + 1]);

        var pairs = new List<(string, string)>();
        int x = 0, y = 0;
        while (x < n && y < m)
        {
            if (Same(before[x], after[y])) { x++; y++; continue; }

            // Beide Seiten rücken vor = Ersetzung. Rückt nur eine vor, wurde ein
            // Wort gestrichen oder eingefügt — daraus lässt sich nichts lernen.
            var skipBefore = lcs[x + 1, y];
            var skipAfter = lcs[x, y + 1];
            if (skipBefore == skipAfter)
            {
                pairs.Add((before[x], after[y]));
                x++;
                y++;
            }
            else if (skipBefore > skipAfter) x++;
            else y++;
        }
        return pairs;
    }

    private static bool Same(string a, string b)
        => string.Equals(a, b, StringComparison.Ordinal);
}
