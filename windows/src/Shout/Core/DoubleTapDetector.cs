namespace Shout.Core;

/// <summary>
/// Erkennt den Doppeltipp auf dem Diktier-Hotkey (Aufnahme-Art „Doppeltipp") —
/// Port von DoubleTapDetector.swift.
///
/// <para>Reine Zeitlogik ohne Windows-Aufrufe: Die Zeitstempel kommen von außen
/// herein, damit sich das Verhalten in Tests durchspielen lässt. Gemessen wird —
/// wie beim Doppelklick — der Abstand zwischen den beiden <i>Anschlägen</i>; wie
/// lange die Taste dabei gehalten wird, spielt keine Rolle. Das Loslassen
/// interessiert diesen Modus gar nicht, deshalb kennt der Detektor nur
/// <see cref="HandleDown"/>.</para>
/// </summary>
public sealed class DoubleTapDetector
{
    public enum Action
    {
        /// <summary>Erster Tipp erkannt — jetzt wartet der zweite (die Pille zeigt das an).</summary>
        Armed,
        /// <summary>Nichts zu tun (Druck innerhalb der Sperrfrist).</summary>
        Ignored,
        Start,
        Stop,
    }

    /// <summary>Maximaler Abstand zwischen den zwei Anschlägen, in Sekunden. Bewusst
    /// nicht knapper: In dieser Zeit blendet die Pille auf, pulst sichtbar und
    /// wieder weg.</summary>
    public double Window { get; set; } = 0.7;

    /// <summary>Sperrfrist nach dem Start: Ein versehentlicher dritter schneller Tipp
    /// soll die gerade begonnene Aufnahme nicht sofort wieder beenden.</summary>
    public double GuardTime { get; set; } = 0.25;

    private double? lastDown;
    private double? startedAt;

    /// <summary>Verarbeitet einen Tastendruck und sagt, was zu tun ist.</summary>
    public Action HandleDown(double now, bool isRecording)
    {
        if (isRecording)
        {
            if (startedAt is { } started && now - started < GuardTime) return Action.Ignored;
            lastDown = null;
            startedAt = null;
            return Action.Stop;
        }
        if (lastDown is { } last && now - last <= Window)
        {
            lastDown = null;
            startedAt = now;
            return Action.Start;
        }
        // Zu langsam (oder erster Tipp überhaupt) → das ist der neue erste Tipp.
        lastDown = now;
        return Action.Armed;
    }

    /// <summary>Vergisst einen offenen ersten Tipp (z. B. bei Moduswechsel).</summary>
    public void Reset()
    {
        lastDown = null;
        startedAt = null;
    }
}
