namespace Shout.Core;

/// <summary>
/// Prüft, ob die Ausgabe der Aufbereitung wirklich eine Formatierung der Eingabe ist
/// (Port von FormattingGuard.swift).
///
/// <para>Hintergrund: Ein Diktat, das wie eine Bitte klingt („Könntest du bitte das
/// suchen und einfügen?"), wird von einem kleinen Modell gelegentlich als Auftrag an
/// sich selbst gelesen. Es antwortet dann („Bitte gib mir den Text, den ich
/// formatieren soll") statt zu formatieren, und diese Antwort landet im Dokument.
/// Gegen die Ursache steht der Prompt (Transkript in Markierungen); das hier ist das
/// Netz dahinter. Die Windows-Fassung hatte bisher nur die Kürzungs-Prüfung.</para>
/// </summary>
public static class FormattingGuard
{
    public enum Verdict
    {
        Ok,
        /// <summary>Die Ausgabe besteht überwiegend aus Wörtern, die nie diktiert
        /// wurden: Das Modell hat geantwortet, statt zu formatieren.</summary>
        Unrelated,
        /// <summary>Inhaltlich passend, aber drastisch gekürzt — Ende verschluckt.</summary>
        Truncated,
    }

    public readonly record struct Result(Verdict Verdict, int InputSharePercent, int InWords, int OutWords)
    {
        public bool IsOk => Verdict == Verdict.Ok;
    }

    /// <summary>
    /// Anteil der AUSGABE-Wörter, die aus dem Diktat stammen müssen.
    ///
    /// <para>Bewusst diese Richtung: Bereinigen darf Wörter WEGLASSEN (Füllwörter, und
    /// bei kurzen Diktaten schnell die Hälfte), aber keine erfinden. „Wie viel der
    /// Ausgabe stammt aus der Eingabe" ist deshalb der belastbare Maßstab, nicht
    /// umgekehrt — Letzteres fällt bei „also äh das ist gut ja wirklich gut" → „Das
    /// ist gut." legitim auf 43 %.</para>
    /// </summary>
    private const double MinInputShare = 0.50;
    /// <summary>Erst ab dieser Wortzahl im Diktat ist der Vergleich aussagekräftig.</summary>
    private const int MinWordsForShare = 5;
    /// <summary>Kürzungs-Prüfung erst ab hier — bei kürzeren Diktaten ist die halbe
    /// Wortzahl schnell erreicht, ohne dass Inhalt fehlt.</summary>
    private const int MinWordsForLength = 30;

    public static Result Check(string input, string output)
    {
        var inTokens = Tokens(input);
        var inWords = WordCount(input);
        var outWords = WordCount(output);
        if (inTokens.Count < MinWordsForShare) return new Result(Verdict.Ok, 100, inWords, outWords);

        var outTokens = Tokens(output);
        if (outTokens.Count == 0) return new Result(Verdict.Unrelated, 0, inWords, outWords);

        var shared = outTokens.Count(t => inTokens.Contains(t));
        var share = shared / (double)outTokens.Count;
        if (share < MinInputShare)
            return new Result(Verdict.Unrelated, (int)Math.Round(share * 100), inWords, outWords);

        // Wortzahlen, nicht Token-Mengen: Wiederholungen zählen hier mit.
        if (inWords >= MinWordsForLength && outWords * 100 < inWords * 55)
            return new Result(Verdict.Truncated, (int)Math.Round(share * 100), inWords, outWords);

        return new Result(Verdict.Ok, (int)Math.Round(share * 100), inWords, outWords);
    }

    /// <summary>Wörter in Kleinschreibung, ohne Satzzeichen — Interpunktion und
    /// Groß-/Kleinschreibung setzt die Aufbereitung ja gerade neu und darf nicht
    /// gegen sie zählen.</summary>
    private static HashSet<string> Tokens(string s)
    {
        var set = new HashSet<string>(StringComparer.Ordinal);
        var current = new System.Text.StringBuilder();
        foreach (var ch in s)
        {
            if (char.IsLetterOrDigit(ch)) current.Append(char.ToLowerInvariant(ch));
            else if (current.Length > 0) { set.Add(current.ToString()); current.Clear(); }
        }
        if (current.Length > 0) set.Add(current.ToString());
        return set;
    }

    private static int WordCount(string s)
        => s.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries).Length;
}
