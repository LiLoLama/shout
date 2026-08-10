namespace Shout.Core;

/// <summary>
/// Teilt langen Text in Abschnitte, die einzeln durchs Sprachmodell passen
/// (Mac: TextChunker.swift).
///
/// <para>Die Satzgrenze ist eine Heuristik: „.!?" gefolgt von Leerraum und einem
/// Großbuchstaben, wobei einzelne Buchstaben und bekannte Abkürzungen davor
/// ausgeschlossen sind („z. B.", „Dr."). Sie kann danebenliegen — schlimmstenfalls
/// steht ein Absatzumbruch an einer unschönen Stelle. Am Wortlaut ändert sich nichts.</para>
/// </summary>
public static class TextChunker
{
    private static readonly HashSet<string> Abbreviations = new(StringComparer.OrdinalIgnoreCase)
    {
        "ca", "bzw", "usw", "etc", "vgl", "ggf", "inkl", "evtl", "sog", "bspw",
        "dr", "prof", "nr", "abb", "bzgl", "mr", "mrs", "st", "vs", "approx",
    };

    /// <summary>
    /// Zerlegt den Text. Abschnitte werden so nah wie möglich am Zielmaß
    /// geschnitten, aber nie kürzer als <paramref name="minLength"/> — sonst
    /// zerfiele ein Text mit vielen kurzen Sätzen in lauter Schnipsel.
    /// </summary>
    public static List<string> Chunks(string text, int targetLength = 1500, int minLength = 1000)
    {
        var trimmed = text.Trim();
        var result = new List<string>();
        if (trimmed.Length == 0) return result;
        if (trimmed.Length <= targetLength)
        {
            result.Add(trimmed);
            return result;
        }

        var start = 0;
        while (trimmed.Length - start > targetLength)
        {
            var limit = start + targetLength;
            var floor = start + Math.Min(minLength, targetLength);
            var cut = SentenceBreak(trimmed, limit, floor) ?? limit;
            var piece = trimmed[start..cut].Trim();
            if (piece.Length > 0) result.Add(piece);
            start = cut;
        }
        var tail = trimmed[start..].Trim();
        if (tail.Length > 0) result.Add(tail);
        return result;
    }

    /// <summary>
    /// Letzte Satzgrenze im Bereich [floor, limit). Zurück kommt der Index des
    /// ersten Zeichens des FOLGENDEN Satzes — der Leerraum dazwischen fällt weg.
    /// </summary>
    private static int? SentenceBreak(string text, int limit, int floor)
    {
        for (var i = limit - 1; i > floor; i--)
        {
            if (text[i] != '.' && text[i] != '!' && text[i] != '?') continue;
            if (IsAbbreviation(text, i)) continue;

            var j = i + 1;
            if (j >= text.Length || !char.IsWhiteSpace(text[j])) continue;
            while (j < text.Length && char.IsWhiteSpace(text[j])) j++;
            if (j >= text.Length || !char.IsUpper(text[j])) continue;
            return j;
        }
        return null;
    }

    /// <summary>
    /// Prüft das Wort unmittelbar vor dem Punkt. Ein einzelner Buchstabe („z.", „B.")
    /// oder eine bekannte Abkürzung („Dr.") beendet keinen Satz.
    /// </summary>
    private static bool IsAbbreviation(string text, int period)
    {
        if (text[period] != '.') return false;
        var start = period;
        while (start > 0 && char.IsLetter(text[start - 1])) start--;
        var word = text[start..period];
        return word.Length == 1 || (word.Length > 1 && Abbreviations.Contains(word));
    }
}
