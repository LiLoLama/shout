using System.Text.Json.Serialization;
using System.Text.RegularExpressions;

namespace Shout.Core;

/// <summary>
/// Persönliches Wörterbuch — 1:1-Port der Mac-Logik:
///  - terms: Eigennamen/Fachbegriffe (gehen als Bias-Prompt an Whisper und als
///    „exakt so schreiben"-Hinweis an das Formatting-LLM).
///  - corrections: gelernte Paare falsch→richtig, wortgenau (case-insensitive)
///    auf den fertigen Text angewendet.
/// JSON-Feldnamen identisch zum Mac (Backup-kompatibel).
/// </summary>
public sealed class PersonalDictionary
{
    public sealed class Correction
    {
        [JsonPropertyName("wrong")] public string Wrong { get; set; } = "";
        [JsonPropertyName("right")] public string Right { get; set; } = "";
    }

    public sealed class Contents
    {
        [JsonPropertyName("terms")] public List<string> Terms { get; set; } = new();
        [JsonPropertyName("corrections")] public List<Correction> Corrections { get; set; } = new();
    }

    public Contents Data { get; private set; } = new();

    public PersonalDictionary()
    {
        Data = StoreIO.Load<Contents>("dictionary.json") ?? new Contents();
    }

    private void Save() => StoreIO.Save(Data, "dictionary.json");

    // MARK: Begriffe

    public void AddTerm(string term)
    {
        var t = term.Trim();
        if (t.Length == 0) return;
        if (Data.Terms.Any(x => string.Equals(x, t, StringComparison.OrdinalIgnoreCase))) return;
        Data.Terms.Add(t);
        Save();
    }

    public void RemoveTerm(string term)
    {
        Data.Terms.RemoveAll(x => x == term);
        Save();
    }

    // MARK: Korrekturen

    /// <summary>Fügt eine Korrektur hinzu (bzw. ersetzt sie) und hinterlegt die
    /// richtige Schreibweise gleich als Begriff. Reine Casing-Fixes
    /// („github" → „GitHub") sind ausdrücklich erlaubt.</summary>
    public void AddCorrection(string wrong, string right)
    {
        var w = wrong.Trim();
        var r = right.Trim();
        if (w.Length == 0 || r.Length == 0 || w == r) return;
        Data.Corrections.RemoveAll(c => string.Equals(c.Wrong, w, StringComparison.OrdinalIgnoreCase));
        Data.Corrections.Add(new Correction { Wrong = w, Right = r });
        AddTerm(r);
        Save();
    }

    public void RemoveCorrection(Correction correction)
    {
        Data.Corrections.RemoveAll(c => c.Wrong == correction.Wrong && c.Right == correction.Right);
        Save();
    }

    /// <summary>Ersetzt den kompletten Inhalt (für Import).</summary>
    public void ReplaceContents(Contents newContents)
    {
        Data = newContents;
        Save();
    }

    // MARK: Anwendung

    /// <summary>
    /// Ersetzt bekannte Falsch-Schreibungen wortgenau (case-insensitive).
    /// \b nur dort, wo der Begriff mit einem Wortzeichen beginnt/endet — sonst
    /// (z. B. „C#", „.NET") würde \b nie matchen und die Korrektur liefe leer.
    /// </summary>
    public string ApplyCorrections(string text)
    {
        var result = text;
        foreach (var c in Data.Corrections)
        {
            static bool IsWordChar(char? ch) =>
                ch is { } x && (char.IsLetter(x) || char.IsDigit(x) || x == '_');

            var lead = IsWordChar(c.Wrong.FirstOrDefault()) ? "\\b" : "";
            var trail = IsWordChar(c.Wrong.LastOrDefault()) ? "\\b" : "";
            try
            {
                result = Regex.Replace(
                    result,
                    lead + Regex.Escape(c.Wrong) + trail,
                    c.Right.Replace("$", "$$"),   // $ im Ersatz escapen
                    RegexOptions.IgnoreCase);
            }
            catch
            {
                // Eine defekte Korrektur darf den Rest nicht blockieren.
            }
        }
        return result;
    }

    /// <summary>Begriffe als Hinweis-Zeile für den Formatting-Prompt (oder null).</summary>
    public string? TermHint =>
        Data.Terms.Count == 0 ? null : string.Join(", ", Data.Terms);
}
