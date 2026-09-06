namespace Shout.Core;

/// <summary>
/// Teilt eine lange Aufnahme in Fenster, die einzeln zu einem Transkriptions-Endpunkt
/// passen.
///
/// <para><b>Warum das nötig ist:</b> Die Endpunkte begrenzen die Dateigröße (bei OpenAI
/// 25 MB). WAV mit 16 kHz, Mono, 16 bit sind 32.000 Byte je Sekunde — die Grenze liegt
/// damit bei rund 13 Minuten. Fürs Diktat ist das folgenlos, für die
/// Datei-Transkription nicht: Dort sind Aufnahmen von einer Stunde der Normalfall.</para>
///
/// <para><b>Geschnitten wird an der leisesten Stelle</b> innerhalb der letzten Sekunden
/// des Fensters, nicht stur nach der Uhr. Ein Schnitt in einer Sprechpause kostet
/// nichts; ein Schnitt mitten im Wort kostet das Wort.</para>
///
/// <para><b>Bewusst ohne Überlappung.</b> Eine Überlappung würde die Sekunden am
/// Übergang zweimal transkribieren, und dann müsste eine Heuristik die Doppelung wieder
/// entfernen — die kann echten Inhalt verwerfen, und das ist der eine Fehler, den
/// dieses Programm nicht machen darf. Der Preis: Findet sich im Suchbereich gar keine
/// Pause (durchgehendes Sprechen über zehn Minuten), kann ein einzelnes Wort am
/// Übergang verstümmelt werden. Das ist selten und sichtbar, während stiller
/// Inhaltsverlust weder das eine noch das andere ist.</para>
/// </summary>
public static class AudioWindows
{
    /// <param name="Start">Erster Sample-Index im Gesamtpuffer.</param>
    /// <param name="Length">Anzahl der Samples.</param>
    /// <param name="OffsetSeconds">Zeitversatz des Fensters im Gesamtaudio, in Sekunden.
    /// Die Zeitmarken der Segmente aus diesem Fenster werden darum verschoben.</param>
    public readonly record struct Window(int Start, int Length, double OffsetSeconds)
    {
        /// <summary>Erster Index NACH dem Fenster.</summary>
        public int End => Start + Length;
    }

    /// <summary>Rahmenlänge der Lautstärkemessung: 20 ms, dasselbe Raster, in dem
    /// Whisper seine Zeitmarken setzt.</summary>
    private const double FrameSeconds = 0.02;

    /// <param name="maxSeconds">Höchstlänge eines Fensters. Voreinstellung 10 Minuten —
    /// mit Sicherheitsabstand unter den ~13 Minuten der 25-MB-Grenze.</param>
    /// <param name="searchSeconds">Wie weit vom Fensterende aus nach einer Pause gesucht
    /// wird.</param>
    public static List<Window> Split(float[] samples, int sampleRate = 16_000,
                                     double maxSeconds = 600, double searchSeconds = 15)
    {
        var windows = new List<Window>();
        if (samples.Length == 0) return windows;

        var maxLength = (int)(maxSeconds * sampleRate);
        if (maxLength <= 0 || samples.Length <= maxLength)
        {
            windows.Add(new Window(0, samples.Length, 0));
            return windows;
        }

        var start = 0;
        while (start < samples.Length)
        {
            var rest = samples.Length - start;
            if (rest <= maxLength)
            {
                windows.Add(new Window(start, rest, (double)start / sampleRate));
                break;
            }
            var hardEnd = start + maxLength;
            var searchStart = Math.Max(start + 1, hardEnd - (int)(searchSeconds * sampleRate));
            var cut = QuietestPoint(samples, searchStart, hardEnd, sampleRate);
            windows.Add(new Window(start, cut - start, (double)start / sampleRate));
            start = cut;
        }
        return windows;
    }

    /// <summary>Mitte des leisesten 20-ms-Rahmens im Bereich. Bei Gleichstand gewinnt
    /// der spätere Rahmen — so werden die Fenster nicht unnötig kurz.</summary>
    private static int QuietestPoint(float[] samples, int from, int to, int sampleRate)
    {
        var frame = Math.Max(1, (int)(FrameSeconds * sampleRate));
        if (to - from <= frame) return to;

        var bestEnergy = float.MaxValue;
        var bestIndex = to;

        for (var i = from; i + frame <= to; i += frame)
        {
            var energy = 0f;
            for (var j = i; j < i + frame; j++) energy += samples[j] * samples[j];
            if (energy > bestEnergy) continue;
            bestEnergy = energy;
            bestIndex = i + frame / 2;
        }
        return bestIndex;
    }
}
