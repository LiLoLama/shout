namespace Shout.Core;

/// <summary>
/// Grobe Vorauswahl der Transkriptions-Modelle aus einer Anbieter-Liste.
///
/// <para>Die Modell-Liste eines Anbieters enthält alles durcheinander, und aus hundert
/// Chat-Modellen das eine Whisper herauszusuchen ist unnötige Arbeit. <b>Bleibt nichts
/// übrig, wird nicht gefiltert</b> — eine ungefilterte Liste ist besser als eine leere,
/// denn dann hat der Filter die Namensgebung dieses Anbieters nur nicht erkannt.</para>
/// </summary>
public static class AudioModelFilter
{
    private static readonly string[] Hints =
        { "whisper", "transcribe", "voxtral", "scribe", "stt", "asr" };

    public static List<string> Apply(IEnumerable<string> ids)
    {
        var all = ids.ToList();
        var filtered = all
            .Where(id => Hints.Any(hint => id.Contains(hint, StringComparison.OrdinalIgnoreCase)))
            .ToList();
        return filtered.Count == 0 ? all : filtered;
    }
}
