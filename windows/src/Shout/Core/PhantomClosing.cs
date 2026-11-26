namespace Shout.Core;

/// <summary>
/// Streicht eine Schlussfloskel, die Whisper in der Stille am Ende erfunden hat
/// (Mac: <c>TranscriptPlausibility.withoutPhantomClosing</c>, gleiche Regeln).
///
/// <para>Whisper ist zu großen Teilen auf Video-Untertiteln trainiert, und die enden
/// mit „Vielen Dank fürs Zuschauen" oder „Untertitel im Auftrag des ZDF". Bleibt am
/// Ende der Aufnahme ein stiller Rest, schreibt es dort gern so eine Zeile hin. Am
/// Mac stand am 26.11.2026 in 21 von 300 Diktaten ein nie gesagtes „Vielen Dank."
/// schon im Rohtext.</para>
///
/// <para>Gestrichen wird nur, wenn der letzte Abschnitt allein aus einer bekannten
/// Floskel besteht UND in seinem Zeitraum kaum Sprache im Audio ist. Ein
/// gesprochenes „Vielen Dank" bleibt stehen. Passt das Textende nicht genau zu
/// diesem Abschnitt, bleibt der Text, wie er ist.</para>
/// </summary>
public static class PhantomClosing
{
    /// <summary>Weniger Sprache als das im Floskel-Zeitraum heißt: nicht gesagt.</summary>
    public const double MaxPhantomSpeechSeconds = 0.3;

    private static readonly HashSet<string> KnownClosings = new()
    {
        "vielen dank", "vielen dank fürs zuschauen", "danke fürs zuschauen",
        "vielen dank für ihre aufmerksamkeit", "danke", "danke schön", "dankeschön",
        "bis zum nächsten mal", "tschüss", "thank you", "thanks for watching",
        "thank you for watching",
    };

    public static string Strip(string text, IReadOnlyList<TranscriptSegment> segments,
                               float[] samples, double sampleRate = 16_000)
    {
        if (segments.Count == 0) return text;
        var last = segments[^1];
        var floskel = last.Text.Trim();
        if (floskel.Length == 0 || !IsKnownClosing(floskel)) return text;

        if (SpeechSeconds(samples, last.Start, last.End, sampleRate) >= MaxPhantomSpeechSeconds)
            return text;

        var whole = text.Trim();
        if (!whole.EndsWith(floskel, StringComparison.OrdinalIgnoreCase)) return text;
        return whole[..^floskel.Length].TrimEnd();
    }

    public static bool IsKnownClosing(string text)
    {
        var chars = text.ToLowerInvariant()
                        .Select(c => char.IsPunctuation(c) ? ' ' : c)
                        .ToArray();
        var norm = string.Join(' ', new string(chars)
            .Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries));
        // „Untertitel im Auftrag des ZDF, 2020", „Untertitelung des ZDF" …
        return KnownClosings.Contains(norm) || norm.StartsWith("untertitel", StringComparison.Ordinal);
    }

    /// <summary>Sekunden mit Sprachenergie im Zeitraum — 30-ms-Fenster, Schwelle
    /// 10 % des Spitzenwerts, geklemmt auf 0,004–0,012 (wie das Stille-Trimmen am
    /// Mac). Hinter dem Audioende ist nichts gesprochen.</summary>
    public static double SpeechSeconds(float[] samples, double start, double end,
                                       double sampleRate = 16_000)
    {
        var window = (int)(sampleRate * 0.03);
        if (window <= 0 || samples.Length == 0) return 0;

        float Rms(int from, int to)
        {
            float sum = 0;
            for (var j = from; j < to; j++) sum += samples[j] * samples[j];
            return MathF.Sqrt(sum / (to - from));
        }

        float peak = 0;
        for (var i = 0; i < samples.Length; i += window)
            peak = Math.Max(peak, Rms(i, Math.Min(i + window, samples.Length)));
        var threshold = Math.Min(Math.Max(0.004f, peak * 0.10f), 0.012f);

        var von = Math.Clamp((int)(start * sampleRate), 0, samples.Length);
        var bis = Math.Clamp((int)(end * sampleRate), von, samples.Length);
        var active = 0;
        for (var i = von; i < bis; i += window)
        {
            var stop = Math.Min(i + window, bis);
            if (Rms(i, stop) > threshold) active += stop - i;
        }
        return active / sampleRate;
    }
}
