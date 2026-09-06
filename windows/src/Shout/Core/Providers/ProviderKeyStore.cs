using System.Runtime.CompilerServices;
using System.Security.Cryptography;
using System.Text;

namespace Shout.Core;

/// <summary>
/// Verwahrt die API-Schlüssel der Anbieter — DPAPI-verschlüsselt in einer eigenen
/// Datei, nicht in settings.json (die steht im Klartext).
///
/// <para>Drei Festlegungen, die alle einen Grund haben:</para>
/// <list type="number">
/// <item><b>Ein Schlüssel je Anbieter</b>, nicht je Verarbeitungsschritt. Wer OpenAI
/// für Text und Transkription nutzt, trägt ihn einmal ein.</item>
/// <item><b><see cref="DataProtectionScope.CurrentUser"/></b> — Windows leitet den
/// Schlüssel aus der Anmeldung dieses Kontos ab. Die Datei ist damit auf einem anderen
/// Gerät und in einem anderen Konto wertlos; das ist am Mac
/// <c>…WhenUnlockedThisDeviceOnly</c> und passt zur Haltung des Programms: Es gibt hier
/// keine Synchronisierung, und ein Backup enthält den Schlüssel ausdrücklich nicht.</item>
/// <item>Der Wert wird <b>nie vollständig angezeigt</b> (siehe <see cref="KeyMask"/>)
/// und nie protokolliert — auch nicht im Fehlerfall.</item>
/// </list>
/// </summary>
public static class ProviderKeyStore
{
    private const string FileName = "anbieter-schluessel.json";

    /// <summary>Die Einstellungsseite schreibt vom UI-Faden, die Engines lesen vom
    /// Threadpool — und beides geht über dieselbe Datei.</summary>
    private static readonly object Gate = new();

    /// <summary>
    /// Meldet den Speicher bei <see cref="EngineSelection"/> an. Andersherum wäre es
    /// eine feste Abhängigkeit von DPAPI, und die Auswahllogik ließe sich nicht mehr
    /// dort prüfen, wo die Tests laufen.
    /// </summary>
    [ModuleInitializer]
    internal static void Register() => EngineSelection.KeySource = Has;

    // MARK: Lesen und Schreiben

    /// <summary>
    /// Legt den Schlüssel ab. Ein leerer Wert löscht ihn, statt eine unbrauchbare
    /// Hülle zu hinterlassen, auf die <see cref="EngineSelection"/> dann hereinfiele.
    /// Gibt zurück, ob es geklappt hat: Ein stilles Scheitern würde „gespeichert"
    /// anzeigen und beim nächsten Diktat einen 401 ergeben.
    /// </summary>
    public static bool Store(string templateId, string key)
    {
        var value = (key ?? "").Trim();
        if (value.Length == 0)
        {
            Delete(templateId);
            return true;
        }
        try
        {
            var geschuetzt = ProtectedData.Protect(Encoding.UTF8.GetBytes(value), null,
                                                   DataProtectionScope.CurrentUser);
            lock (Gate)
            {
                var map = LoadMap();
                map[templateId] = Convert.ToBase64String(geschuetzt);
                StoreIO.Save(map, FileName);
            }
            return true;
        }
        catch (Exception ex)
        {
            // Nur der Typ der Ausnahme, nie der Wert: Manche Meldungen zitieren die
            // Eingabe, und die stünde dann im Protokoll.
            StoreIO.Log($"Anbieter-Schlüssel konnte nicht gespeichert werden ({ex.GetType().Name})");
            return false;
        }
    }

    /// <summary>
    /// Der Klartext-Schlüssel oder null. Wirft nie: Diese Methode entscheidet an jedem
    /// Aufrufort mit, ob überhaupt extern gearbeitet wird — eine Ausnahme aus einer
    /// beschädigten Datei würde das Diktat abbrechen, statt es lokal zu erledigen.
    /// </summary>
    public static string? Read(string templateId)
    {
        try
        {
            string? verschluesselt;
            lock (Gate) verschluesselt = LoadMap().GetValueOrDefault(templateId);
            if (string.IsNullOrEmpty(verschluesselt)) return null;

            var klar = Encoding.UTF8.GetString(
                ProtectedData.Unprotect(Convert.FromBase64String(verschluesselt), null,
                                        DataProtectionScope.CurrentUser));
            return klar.Length == 0 ? null : klar;
        }
        catch (Exception ex)
        {
            // Der häufigste Fall ist kein Defekt, sondern ein anderes Benutzerkonto
            // oder ein anderes Gerät: Dann ist der Wert nicht zu entschlüsseln, und
            // „kein Schlüssel" ist die richtige Antwort.
            StoreIO.Log($"Anbieter-Schlüssel nicht lesbar ({ex.GetType().Name})");
            return null;
        }
    }

    /// <summary>Löschen ist absichtlich nachsichtig — sonst müsste jede Aufrufstelle
    /// vorher prüfen, ob überhaupt etwas da ist.</summary>
    public static void Delete(string templateId)
    {
        try
        {
            lock (Gate)
            {
                var map = LoadMap();
                if (!map.Remove(templateId)) return;
                StoreIO.Save(map, FileName);
            }
        }
        catch (Exception ex)
        {
            StoreIO.Log($"Anbieter-Schlüssel konnte nicht gelöscht werden ({ex.GetType().Name})");
        }
    }

    public static bool Has(string templateId) => Read(templateId) != null;

    /// <summary>Für die Oberfläche, z. B. <c>sk-…4f2a</c>; null, wenn nichts hinterlegt ist.</summary>
    public static string? Masked(string templateId)
    {
        var key = Read(templateId);
        return key == null ? null : KeyMask.Mask(key);
    }

    private static Dictionary<string, string> LoadMap()
        => StoreIO.Load<Dictionary<string, string>>(FileName) ?? new Dictionary<string, string>();
}
