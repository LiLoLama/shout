using System.Text.Json.Serialization;
using System.Text.RegularExpressions;

namespace Shout.Core;

/// <summary>
/// Persönliches Wörterbuch — 1:1-Port der Mac-Logik:
///  - terms: Eigennamen/Fachbegriffe (gehen als „exakt so schreiben"-Hinweis an
///    das Formatting-LLM — NICHT mehr als Bias-Prompt an Whisper, der ließ
///    Whisper Audio überspringen; siehe Transcriber.TranscribeAsync).
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

    private readonly object gate = new();

    public Contents Data { get; private set; } = new();

    public PersonalDictionary()
    {
        Data = StoreIO.Load<Contents>("dictionary.json") ?? new Contents();
        Data.Terms ??= new List<string>();
        Data.Corrections ??= new List<Correction>();
    }

    private void SaveLocked() => StoreIO.Save(Data, "dictionary.json");

    /// <summary>Kopie für Export und Anzeige — die Korrekturen werden vom
    /// Threadpool gelesen, während die Oberfläche sie ändert.</summary>
    public Contents Snapshot()
    {
        lock (gate)
            return new Contents
            {
                Terms = new List<string>(Data.Terms),
                Corrections = Data.Corrections
                    .Select(c => new Correction { Wrong = c.Wrong, Right = c.Right }).ToList(),
            };
    }

    // MARK: Begriffe

    public void AddTerm(string term) => AddTerms(new[] { term });

    /// <summary>
    /// Nimmt mehrere Begriffe auf einmal auf. Der CSV/TXT-Import ging vorher Zeile
    /// für Zeile durch <see cref="AddTerm"/> und schrieb dabei die komplette
    /// dictionary.json JE ZEILE — bei tausend Namen tausend Schreibvorgänge.
    /// </summary>
    public void AddTerms(IEnumerable<string> newTerms)
    {
        lock (gate)
        {
            var added = false;
            foreach (var term in newTerms)
            {
                var t = term.Trim();
                if (t.Length == 0) continue;
                if (Data.Terms.Any(x => string.Equals(x, t, StringComparison.OrdinalIgnoreCase))) continue;
                Data.Terms.Add(t);
                added = true;
            }
            if (added) SaveLocked();
        }
    }

    public void RemoveTerm(string term)
    {
        lock (gate)
        {
            Data.Terms.RemoveAll(x => x == term);
            SaveLocked();
        }
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
        lock (gate)
        {
            Data.Corrections.RemoveAll(c => string.Equals(c.Wrong, w, StringComparison.OrdinalIgnoreCase));
            Data.Corrections.Add(new Correction { Wrong = w, Right = r });
            if (!Data.Terms.Any(x => string.Equals(x, r, StringComparison.OrdinalIgnoreCase)))
                Data.Terms.Add(r);
            SaveLocked();
        }
    }

    public void RemoveCorrection(Correction correction)
    {
        lock (gate)
        {
            Data.Corrections.RemoveAll(c => c.Wrong == correction.Wrong && c.Right == correction.Right);
            SaveLocked();
        }
    }

    /// <summary>Ersetzt den kompletten Inhalt (für Import).</summary>
    public void ReplaceContents(Contents newContents)
    {
        lock (gate)
        {
            Data = newContents;
            Data.Terms ??= new List<string>();
            Data.Corrections ??= new List<Correction>();
            SaveLocked();
        }
    }

    // MARK: Anwendung

    /// <summary>
    /// Ersetzt bekannte Falsch-Schreibungen wortgenau (case-insensitive).
    /// \b nur dort, wo der Begriff mit einem Wortzeichen beginnt/endet — sonst
    /// (z. B. „C#", „.NET") würde \b nie matchen und die Korrektur liefe leer.
    /// </summary>
    public string ApplyCorrections(string text)
    {
        List<Correction> corrections;
        lock (gate) corrections = new List<Correction>(Data.Corrections);

        var result = text;
        foreach (var c in corrections)
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
    public string? TermHint
    {
        get
        {
            lock (gate) return Data.Terms.Count == 0 ? null : string.Join(", ", Data.Terms);
        }
    }
}
