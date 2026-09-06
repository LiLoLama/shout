namespace Shout.Core;

/// <summary>
/// Verkürzt einen API-Schlüssel für die Anzeige.
///
/// <para>Eigene Datei und nicht Teil von <see cref="ProviderKeyStore"/>: Der Speicher
/// hängt an DPAPI und läuft nur unter Windows, die Verkürzung ist reine Textarbeit.
/// Getrennt lässt sie sich dort prüfen, wo die Tests laufen — und geprüft gehört sie,
/// weil ein Fehler hier den Schlüssel auf den Bildschirm schreiben würde.</para>
/// </summary>
public static class KeyMask
{
    /// <summary>
    /// Was in der Oberfläche steht, z. B. <c>sk-…4f2a</c>.
    ///
    /// <para>Die Vorsilbe bleibt sichtbar, weil sie beim Erkennen hilft (welcher
    /// Anbieter) und nichts verrät. Die letzten vier Zeichen zeigen, ob der richtige
    /// Schlüssel hinterlegt ist. Bei kurzen Schlüsseln wären vier Zeichen fast der
    /// ganze Wert — dann wird nichts gezeigt.</para>
    /// </summary>
    public static string Mask(string? key)
    {
        var trimmed = (key ?? "").Trim();
        if (trimmed.Length == 0) return "";

        var separator = trimmed.IndexOfAny(new[] { '-', '_' });
        var prefix = separator >= 0 && separator <= 5 ? trimmed[..(separator + 1)] : "";

        if (trimmed.Length < 12) return prefix + "…";
        return prefix + "…" + trimmed[^4..];
    }
}
